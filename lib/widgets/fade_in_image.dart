import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
  static Directory? _cacheDir;
  
  // 初始化缓存目录
  static Future<void> init() async {
    if (_cacheDir == null) {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/image_cache');
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
      print('📁 Image cache directory: ${_cacheDir!.path}');
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
        print('💾 Loading from disk cache: $url');
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        
        // 同时保存到内存缓存
        putToMemory(url, image);
        return image;
      }
    } catch (e) {
      print('❌ Failed to load from disk cache: $e');
    }
    return null;
  }
  
  // 保存到持久化缓存
  static Future<void> saveToDisk(String url, Uint8List bytes) async {
    try {
      await init();
      final file = _getCacheFile(url);
      await file.writeAsBytes(bytes);
      print('💾 Saved to disk cache: $url');
    } catch (e) {
      print('❌ Failed to save to disk cache: $e');
    }
  }
  
  // 获取缓存文件
  static File _getCacheFile(String url) {
    final hash = md5.convert(url.codeUnits).toString();
    return File('${_cacheDir!.path}/$hash');
  }
  
  // 正在加载的图片
  static Future<ui.Image>? getLoading(String url) => _loading[url];
  
  static void putLoading(String url, Future<ui.Image> future) {
    _loading[url] = future;
  }
  
  static void removeLoading(String url) {
    _loading.remove(url);
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
      print('🗑️ All image cache cleared');
    } catch (e) {
      print('❌ Failed to clear disk cache: $e');
    }
  }
}

/// 带淡入效果的图片加载组件
/// 支持占位符、骨架屏加载动画、错误处理、淡入效果和超时控制
class EmbyFadeInImage extends StatefulWidget {
  const EmbyFadeInImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.fadeDuration = const Duration(milliseconds: 500),
    this.timeout = const Duration(seconds: 10),
    this.retries = -1,  // -1 表示无限重试
    this.onImageReady,
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Duration fadeDuration;
  final Duration timeout;
  final int retries;
  final void Function(ui.Image image)? onImageReady;

  @override
  State<EmbyFadeInImage> createState() => _EmbyFadeInImageState();
}

class _EmbyFadeInImageState extends State<EmbyFadeInImage> {
  ui.Image? _image;
  bool _isLoading = true;
  bool _hasError = false;
  int _currentRetry = 0;
  String? _currentUrl;  // 记录当前显示的图片URL

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
    _loadImageWithCache();
  }

  @override
  void didUpdateWidget(EmbyFadeInImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL 变化时重新加载，但先保留旧图片
    if (oldWidget.imageUrl != widget.imageUrl) {
      print('🔄 Image URL changed: ${oldWidget.imageUrl} -> ${widget.imageUrl}');
      _currentUrl = widget.imageUrl;
      // 先保留旧图片，后台加载新图片
      _loadImageWithCache(keepOldImage: true);
    }
  }

  Future<void> _loadImageWithCache({bool keepOldImage = false}) async {
    // ✅ 重置重试计数器（每次加载新URL时）
    _currentRetry = 0;
    
    // 如果不保留旧图片，先显示加载状态
    if (!keepOldImage) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    
    // ✅ 1. 先检查内存缓存
    final memoryCached = _ImageCache.getFromMemory(widget.imageUrl);
    if (memoryCached != null) {
      print('✅ Image from memory cache: ${widget.imageUrl}');
      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _image = memoryCached;
          _isLoading = false;
          _hasError = false;
        });
        widget.onImageReady?.call(memoryCached);
      }
      return;
    }
    
    // ✅ 2. 检查持久化缓存
    final diskCached = await _ImageCache.getFromDisk(widget.imageUrl);
    if (diskCached != null) {
      print('✅ Image from disk cache: ${widget.imageUrl}');
      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _image = diskCached;
          _isLoading = false;
          _hasError = false;
        });
        widget.onImageReady?.call(diskCached);
      }
      return;
    }
    
    // ✅ 3. 检查是否正在加载（避免重复请求）
    final loading = _ImageCache.getLoading(widget.imageUrl);
    if (loading != null) {
      print('⏳ Image already loading: ${widget.imageUrl}');
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
        if (mounted && _currentUrl == widget.imageUrl && e is! _NonRetryableException) {
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
    final loadFuture = _loadImageFromNetwork();
    _ImageCache.putLoading(widget.imageUrl, loadFuture);
    
    try {
      final image = await loadFuture;
      
      // ✅ 保存到内存缓存
      _ImageCache.putToMemory(widget.imageUrl, image);
      _ImageCache.removeLoading(widget.imageUrl);
      
      if (mounted && _currentUrl == widget.imageUrl) {
        setState(() {
          _image = image;
          _isLoading = false;
          _hasError = false;
        });
        widget.onImageReady?.call(image);
      }
    } catch (e) {
      // ✅ 移除 loading 状态
      _ImageCache.removeLoading(widget.imageUrl);
      
      // ✅ 检查是否是不可重试的错误
      if (e is _NonRetryableException) {
        print('🚫 Non-retryable error, showing placeholder: $e');
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
      print('📷 Loading image from network: ${widget.imageUrl} (retry: $_currentRetry)');
      
      // 使用超时控制
      final response = await http
          .get(Uri.parse(widget.imageUrl))
          .timeout(
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
        
        print('✅ Image loaded from network: ${widget.imageUrl}');
        return frame.image;
      } else {
        // ❌ 不可重试的HTTP错误（404, 403, 401等客户端错误）
        if (response.statusCode >= 400 && response.statusCode < 500) {
          print('❌ Image not found or forbidden (${response.statusCode}): ${widget.imageUrl}');
          print('🚫 Will not retry, showing default placeholder');
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
      
      print('❌ Image load failed: ${widget.imageUrl}, error: $e');
      
      // 无限重试机制（仅针对网络错误和服务器错误）
      if (widget.retries == -1 || _currentRetry < widget.retries) {
        _currentRetry++;
        final retryText = widget.retries == -1 
            ? '$_currentRetry/∞' 
            : '$_currentRetry/${widget.retries}';
        print('🔄 Retrying image load ($retryText)');
        
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
    // 如果有图片，直接显示（即使正在加载新图片）
    if (_image != null) {
      return TweenAnimationBuilder<double>(
        key: ValueKey(_image.hashCode),  // 用于触发动画
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: widget.fadeDuration,
        curve: Curves.easeIn,
        builder: (context, value, _) {
          return Opacity(
            opacity: value,
            child: RawImage(
              image: _image,
              fit: widget.fit,
            ),
          );
        },
      );
    }
    
    // 如果加载失败，显示错误占位符
    if (_hasError) {
      return widget.placeholder ??
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

    // 正在加载且没有旧图片，显示骨架屏
    if (_isLoading) {
      return const _ShimmerPlaceholder();
    }

    // 默认占位符
    return const _ShimmerPlaceholder();
  }

  @override
  void dispose() {
    // 不要 dispose 缓存的图片，因为可能被其他 widget 使用
    // _image?.dispose();
    super.dispose();
  }
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
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
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
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 定义明显的颜色对比
        final Color color1 =
            isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
        final Color color2 =
            isDark ? const Color(0xFF48484A) : const Color(0xFFF2F2F7);

        return Container(
          color: Color.lerp(color1, color2, _controller.value),
        );
      },
    );
  }
}
