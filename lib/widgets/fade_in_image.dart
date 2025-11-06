import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ✅ 全局图片缓存
class _ImageCache {
  static final _cache = <String, ui.Image>{};
  static final _loading = <String, Future<ui.Image>>{};
  
  static ui.Image? get(String url) => _cache[url];
  
  static void put(String url, ui.Image image) {
    _cache[url] = image;
  }
  
  static Future<ui.Image>? getLoading(String url) => _loading[url];
  
  static void putLoading(String url, Future<ui.Image> future) {
    _loading[url] = future;
  }
  
  static void removeLoading(String url) {
    _loading.remove(url);
  }
  
  static void clear() {
    for (var image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _loading.clear();
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
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Duration fadeDuration;
  final Duration timeout;
  final int retries;

  @override
  State<EmbyFadeInImage> createState() => _EmbyFadeInImageState();
}

class _EmbyFadeInImageState extends State<EmbyFadeInImage> {
  ui.Image? _image;
  bool _isLoading = true;
  bool _hasError = false;
  int _currentRetry = 0;

  @override
  void initState() {
    super.initState();
    _loadImageWithCache();
  }

  @override
  void didUpdateWidget(EmbyFadeInImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有 URL 变化时才重新加载
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImageWithCache();
    }
  }

  Future<void> _loadImageWithCache() async {
    // ✅ 先检查缓存
    final cached = _ImageCache.get(widget.imageUrl);
    if (cached != null) {
      print('✅ Image from cache: ${widget.imageUrl}');
      if (mounted) {
        setState(() {
          _image = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }
    
    // ✅ 检查是否正在加载（避免重复请求）
    final loading = _ImageCache.getLoading(widget.imageUrl);
    if (loading != null) {
      print('⏳ Image already loading: ${widget.imageUrl}');
      try {
        final image = await loading;
        if (mounted) {
          setState(() {
            _image = image;
            _isLoading = false;
            _hasError = false;
          });
        }
      } catch (e) {
        // 加载失败，重新尝试
        _loadImage();
      }
      return;
    }
    
    // 缓存未命中，开始加载
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    // 创建加载 Future 并放入正在加载的队列
    final loadFuture = _loadImageFromNetwork();
    _ImageCache.putLoading(widget.imageUrl, loadFuture);
    
    try {
      final image = await loadFuture;
      
      // ✅ 保存到缓存
      _ImageCache.put(widget.imageUrl, image);
      _ImageCache.removeLoading(widget.imageUrl);
      
      if (mounted) {
        setState(() {
          _image = image;
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      _ImageCache.removeLoading(widget.imageUrl);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<ui.Image> _loadImageFromNetwork() async {
    try {
      print('📷 Loading image: ${widget.imageUrl} (retry: $_currentRetry)');
      
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
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        
        print('✅ Image loaded: ${widget.imageUrl}');
        return frame.image;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Image load failed: ${widget.imageUrl}, error: $e');
      
      // 无限重试机制
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

    if (_isLoading || _image == null) {
      return const _ShimmerPlaceholder();
    }

    return TweenAnimationBuilder<double>(
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
