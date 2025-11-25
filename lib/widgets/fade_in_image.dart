import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/theme_utils.dart';
import 'package:visibility_detector/visibility_detector.dart';

const bool _kImageCacheLogging = false;

void _log(String message) {
  if (_kImageCacheLogging) {}
}

// ✅ 不可重试的异常（如404等客户端错误）
class _NonRetryableException implements Exception {
  final String message;
  _NonRetryableException(this.message);

  @override
  String toString() => 'NonRetryableException: $message';
}

// ✅ 全局图片缓存（内存缓存 + 持久化缓存）
class _ImageCache {
  static final _memoryCache = <String, ui.Image>{};
  static final _loading = <String, Future<ui.Image>>{};
  static final Queue<_PendingRequest> _pendingRequests =
      Queue<_PendingRequest>();
  static bool _isProcessingQueue = false;
  static Directory? _cacheDir;

  // 初始化缓存目录
  static Future<void> init() async {
    if (_cacheDir == null) {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/image_cache');
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
      _log('📁 Image cache directory: ${_cacheDir!.path}');
    }
  }

  // 从内存缓存获取
  static ui.Image? getFromMemory(String url) => _memoryCache[url];

  // 保存到内存缓存
  static void putToMemory(String url, ui.Image image) {
    _memoryCache[url] = image;
  }

  // 从持久化缓存获取
  static Future<ui.Image?> getFromDisk(String url) async {
    try {
      await init();
      final file = _getCacheFile(url);
      if (await file.exists()) {
        _log('💾 Loading from disk cache: $url');
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;

        // 同时保存到内存缓存
        putToMemory(url, image);
        return image;
      }
    } catch (e) {
      _log('❌ Failed to load from disk cache: $e');
    }
    return null;
  }

  // 保存到持久化缓存
  static Future<void> saveToDisk(String url, Uint8List bytes) async {
    try {
      await init();
      final file = _getCacheFile(url);
      await file.writeAsBytes(bytes);
      _log('💾 Saved to disk cache: $url');
    } catch (e) {
      _log('❌ Failed to save to disk cache: $e');
    }
  }

  // 获取缓存文件
  static File _getCacheFile(String url) {
    final hash = md5.convert(url.codeUnits).toString();
    return File('${_cacheDir!.path}/$hash');
  }

  // 正在加载的图片
  static Future<ui.Image>? getLoading(String url) => _loading[url];

  static Future<ui.Image> enqueueNetworkLoad(
      String url, Future<ui.Image> Function() loader) {
    final existing = _loading[url];
    if (existing != null) {
      return existing;
    }
    final completer = Completer<ui.Image>();
    _loading[url] = completer.future;
    _pendingRequests.add(_PendingRequest(url, loader, completer));
    _processQueue();
    return completer.future;
  }

  static void _processQueue() {
    if (_isProcessingQueue) {
      return;
    }
    if (_pendingRequests.isEmpty) {
      return;
    }
    _isProcessingQueue = true;
    final request = _pendingRequests.removeFirst();
    request.loader().then((image) {
      if (!request.completer.isCompleted) {
        request.completer.complete(image);
      }
    }).catchError((error, stack) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error, stack);
      }
    }).whenComplete(() {
      _loading.remove(request.url);
      _isProcessingQueue = false;
      if (_pendingRequests.isNotEmpty) {
        _processQueue();
      }
    });
  }

  // 清空所有缓存
  // ignore: unused_element
  static Future<void> clear() async {
    // 清空内存缓存
    for (var image in _memoryCache.values) {
      image.dispose();
    }
    _memoryCache.clear();
    _loading.clear();

    // 清空持久化缓存
    try {
      await init();
      if (_cacheDir!.existsSync()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      _log('🗑️ All image cache cleared');
    } catch (e) {
      _log('❌ Failed to clear disk cache: $e');
    }
  }
}

/// 带淡入效果的图片加载组件
/// 支持占位符、骨架屏加载动画、错误处理、淡入效果和超时控制
/// 支持可视范围内批量加载，可视范围外懒加载
class EmbyFadeInImage extends StatefulWidget {
  const EmbyFadeInImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.fadeDuration = const Duration(milliseconds: 500),
    this.timeout = const Duration(seconds: 10),
    this.retries = -1, // -1 表示无限重试
    this.onImageReady,
    this.enableLazyLoad = true, // 是否启用懒加载
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Duration fadeDuration;
  final Duration timeout;
  final int retries;
  final void Function(ui.Image image)? onImageReady;
  final bool enableLazyLoad;

  @override
  State<EmbyFadeInImage> createState() => _EmbyFadeInImageState();
}

class _EmbyFadeInImageState extends State<EmbyFadeInImage> {
  ui.Image? _image;
  bool _isLoading = false;
  bool _hasError = false;
  int _currentRetry = 0;
  String? _currentUrl; // 记录当前显示的图片URL
  bool _isVisible = false; // 是否在可视范围内
  bool _hasStartedLoading = false; // 是否已经开始加载过
  bool _shouldFadeIn = false; // 是否需要淡入效果（仅网络加载的图片需要）

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
    
    // ✅ 优先检查内存缓存（同步操作，立即显示，无需淡入）
    final memoryCached = _ImageCache.getFromMemory(widget.imageUrl);
    if (memoryCached != null) {
      _log('✅ Image from memory cache (initState): ${widget.imageUrl}');
      _image = memoryCached;
      _shouldFadeIn = false; // 缓存图片不需要淡入
      _hasStartedLoading = true;
      widget.onImageReady?.call(memoryCached);
      return;
    }
    
    // 如果禁用懒加载，立即加载（包括检查磁盘缓存和网络加载）
    if (!widget.enableLazyLoad) {
      _loadImageWithCache();
    } else {
      // 启用懒加载时，异步检查磁盘缓存（不阻塞UI）
      _checkDiskCacheAsync();
    }
  }
  
  /// 异步检查磁盘缓存，如果有则立即显示（无需淡入）
  Future<void> _checkDiskCacheAsync() async {
    final diskCached = await _ImageCache.getFromDisk(widget.imageUrl);
    if (diskCached != null && mounted && _currentUrl == widget.imageUrl) {
      _log('✅ Image from disk cache (async): ${widget.imageUrl}');
      setState(() {
        _image = diskCached;
        _shouldFadeIn = false; // 缓存图片不需要淡入
        _isLoading = false;
        _hasError = false;
      });
      _hasStartedLoading = true;
      widget.onImageReady?.call(diskCached);
    }
  }

  @override
  void didUpdateWidget(EmbyFadeInImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL 变化时重新加载，但先保留旧图片
    if (oldWidget.imageUrl != widget.imageUrl) {
      _log('🔄 Image URL changed: ${oldWidget.imageUrl} -> ${widget.imageUrl}');
      _currentUrl = widget.imageUrl;
      _hasStartedLoading = false;
      
      // ✅ 优先检查内存缓存（同步操作，立即显示，无需淡入）
      final memoryCached = _ImageCache.getFromMemory(widget.imageUrl);
      if (memoryCached != null) {
        _log('✅ Image from memory cache (didUpdate): ${widget.imageUrl}');
        setState(() {
          _image = memoryCached;
          _shouldFadeIn = false; // 缓存图片不需要淡入
          _isLoading = false;
          _hasError = false;
        });
        _hasStartedLoading = true;
        widget.onImageReady?.call(memoryCached);
        return;
      }
      
      // 如果已经可见或禁用懒加载，立即加载
      if (_isVisible || !widget.enableLazyLoad) {
        _loadImageWithCache(keepOldImage: true);
      } else {
        // 启用懒加载且不可见时，异步检查磁盘缓存
        _checkDiskCacheAsync();
      }
    }
  }

  /// 当组件进入或离开可视范围时调用
  void _onVisibilityChanged(VisibilityInfo info) {
    final wasVisible = _isVisible;
    _isVisible = info.visibleFraction > 0;

    // 从不可见变为可见，且还未开始加载
    if (!wasVisible && _isVisible && !_hasStartedLoading) {
      _log('👁️ Image became visible, start loading: ${widget.imageUrl}');
      _loadImageWithCache();
    }
  }

  Future<void> _loadImageWithCache({bool keepOldImage = false}) async {
    // 标记已经开始加载
    _hasStartedLoading = true;

    // ✅ 重置重试计数器（每次加载新URL时）
    _currentRetry = 0;

    // ✅ 1. 先检查内存缓存（无需淡入）
    final memoryCached = _ImageCache.getFromMemory(widget.imageUrl);
    if (memoryCached != null) {
      _log('✅ Image from memory cache: ${widget.imageUrl}');
      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _image = memoryCached;
          _shouldFadeIn = false; // 缓存图片不需要淡入
          _isLoading = false;
          _hasError = false;
        });
        widget.onImageReady?.call(memoryCached);
      }
      return;
    }

    // ✅ 2. 检查持久化缓存（无需淡入）
    final diskCached = await _ImageCache.getFromDisk(widget.imageUrl);
    if (diskCached != null) {
      _log('✅ Image from disk cache: ${widget.imageUrl}');
      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _image = diskCached;
          _shouldFadeIn = false; // 缓存图片不需要淡入
          _isLoading = false;
          _hasError = false;
        });
        widget.onImageReady?.call(diskCached);
      }
      return;
    }

    // 缓存未命中，需要从网络加载，显示加载状态
    if (!keepOldImage && mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    // ✅ 3. 检查是否正在加载（避免重复请求）
    final loading = _ImageCache.getLoading(widget.imageUrl);
    if (loading != null) {
      _log('⏳ Image already loading: ${widget.imageUrl}');
      try {
        final image = await loading;
        if (mounted && _currentUrl == widget.imageUrl) {
          setState(() {
            _image = image;
            _isLoading = false;
            _hasError = false;
          });
          widget.onImageReady?.call(image);
        }
      } catch (e) {
        // 加载失败，如果不是不可重试的错误，则重新尝试
        if (mounted &&
            _currentUrl == widget.imageUrl &&
            e is! _NonRetryableException) {
          _loadImage();
        } else {
          // 不可重试的错误，直接显示错误占位符
          if (mounted && _currentUrl == widget.imageUrl) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          }
        }
      }
      return;
    }

    // ✅ 4. 缓存未命中，从网络加载
    _loadImage();
  }

  Future<void> _loadImage() async {
    // 如果没有旧图片，才显示加载状态
    if (_image == null) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    // 创建加载 Future 并放入正在加载的队列
    final loadFuture = _ImageCache.enqueueNetworkLoad(
      widget.imageUrl,
      _loadImageFromNetwork,
    );

    try {
      final image = await loadFuture;

      // ✅ 保存到内存缓存
      _ImageCache.putToMemory(widget.imageUrl, image);

      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _image = image;
          _shouldFadeIn = true; // 网络加载的图片需要淡入效果
          _isLoading = false;
          _hasError = false;
        });
        widget.onImageReady?.call(image);
      }
    } catch (e) {
      // ✅ 检查是否是不可重试的错误
      if (e is _NonRetryableException) {
        _log('🚫 Non-retryable error, showing placeholder: $e');
      }

      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<ui.Image> _loadImageFromNetwork() async {
    try {
      _log(
          '📷 Loading image from network: ${widget.imageUrl} (retry: $_currentRetry)');

      // 使用超时控制
      final response = await http.get(Uri.parse(widget.imageUrl)).timeout(
        widget.timeout,
        onTimeout: () {
          throw TimeoutException('图片加载超时（${widget.timeout.inSeconds}秒）');
        },
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // ✅ 先保存到持久化缓存
        await _ImageCache.saveToDisk(widget.imageUrl, bytes);

        // 解码图片
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();

        _log('✅ Image loaded from network: ${widget.imageUrl}');
        return frame.image;
      } else {
        // ❌ 不可重试的HTTP错误（404, 403, 401等客户端错误）
        if (response.statusCode >= 400 && response.statusCode < 500) {
          _log(
              '❌ Image not found or forbidden (${response.statusCode}): ${widget.imageUrl}');
          _log('🚫 Will not retry, showing default placeholder');
          throw _NonRetryableException('HTTP ${response.statusCode}');
        }

        // 5xx 服务器错误可以重试
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      // ✅ 如果是不可重试的错误，直接抛出
      if (e is _NonRetryableException) {
        rethrow;
      }

      _log('❌ Image load failed: ${widget.imageUrl}, error: $e');

      // 无限重试机制（仅针对网络错误和服务器错误）
      if (widget.retries == -1 || _currentRetry < widget.retries) {
        _currentRetry++;
        final retryText = widget.retries == -1
            ? '$_currentRetry/∞'
            : '$_currentRetry/${widget.retries}';
        _log('🔄 Retrying image load ($retryText)');

        // 重试间隔：最长5秒
        final delay = (_currentRetry * 500).clamp(500, 5000);
        await Future.delayed(Duration(milliseconds: delay));

        // 递归重试
        return _loadImageFromNetwork();
      } else {
        rethrow;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    // 如果有图片，根据是否需要淡入效果来显示
    if (_image != null) {
      final imageWidget = RawImage(
        image: _image,
        fit: widget.fit,
      );
      
      // 如果需要淡入效果（网络加载的图片）
      if (_shouldFadeIn) {
        child = AnimatedOpacity(
          opacity: 1.0,
          duration: widget.fadeDuration,
          curve: Curves.easeIn,
          child: imageWidget,
          onEnd: () {
            // 动画结束后重置标志，避免下次更新时再次淡入
            if (mounted) {
              setState(() {
                _shouldFadeIn = false;
              });
            }
          },
        );
      } else {
        // 缓存图片直接显示，无需动画
        child = imageWidget;
      }
    }
    // 如果加载失败，显示错误占位符
    else if (_hasError) {
      child = widget.placeholder ??
          Container(
            color: CupertinoColors.systemGrey6,
            child: const Center(
              child: Icon(
                CupertinoIcons.photo,
                size: 32,
                color: CupertinoColors.systemGrey3,
              ),
            ),
          );
    }
    // 正在加载且没有旧图片，显示呼吸占位图
    else if (_isLoading) {
      child = const _ShimmerPlaceholder();
    }
    // 默认透明占位符（未开始加载）
    else {
      child = Container(color: Colors.transparent);
    }

    // 如果启用懒加载，使用 VisibilityDetector 包裹
    if (widget.enableLazyLoad) {
      return VisibilityDetector(
        key: Key('image_${widget.imageUrl}'),
        onVisibilityChanged: _onVisibilityChanged,
        child: child,
      );
    }

    return child;
  }

  @override
  void dispose() {
    // 不要 dispose 缓存的图片，因为可能被其他 widget 使用
    // _image?.dispose();
    super.dispose();
  }
}

class _PendingRequest {
  _PendingRequest(this.url, this.loader, this.completer);
  final String url;
  final Future<ui.Image> Function() loader;
  final Completer<ui.Image> completer;
}

/*
// ❌ 旧版本：使用 Image.network（无超时控制）
class EmbyFadeInImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: fit,
*/

/// 骨架屏占位符（闪烁动画）
class _ShimmerPlaceholder extends ConsumerStatefulWidget {
  const _ShimmerPlaceholder();

  @override
  ConsumerState<_ShimmerPlaceholder> createState() =>
      _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends ConsumerState<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 深色模式：使用更明显的灰色渐变
        // 浅色模式：浅灰色的呼吸动画
        final Color color1 =
            isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8);
        final Color color2 =
            isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF5F5F5);

        return Container(
          color: Color.lerp(color1, color2, _controller.value),
        );
      },
    );
  }
}

/// ✅ 公共方法：从内存缓存获取图片
/// 用于在导航到播放器页面时传递已缓存的图片对象，实现立即显示
ui.Image? getCachedImage(String url) {
  return _ImageCache.getFromMemory(url);
}