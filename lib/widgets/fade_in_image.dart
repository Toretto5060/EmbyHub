import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 带淡入效果的图片加载组件
/// 支持占位符、骨架屏加载动画、错误处理和淡入效果
class EmbyFadeInImage extends StatelessWidget {
  const EmbyFadeInImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.fadeDuration = const Duration(milliseconds: 500),
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: fit,
      // 使用 frameBuilder 实现淡入效果
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // 所有图片都使用淡入效果
        if (frame == null) {
          return const _ShimmerPlaceholder();
        }
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: fadeDuration,
          curve: Curves.easeIn,
          builder: (context, value, _) {
            return Opacity(
              opacity: value,
              child: child,
            );
          },
        );
      },
      // 加载失败显示错误占位符
      errorBuilder: (context, error, stackTrace) {
        return placeholder ??
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
      },
    );
  }
}

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
