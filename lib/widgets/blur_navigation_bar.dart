import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 带动态毛玻璃效果的导航栏 - 根据滚动位置显示/隐藏模糊效果
class BlurNavigationBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const BlurNavigationBar({
    this.leading,
    this.middle,
    this.trailing,
    this.scrollController,
    super.key,
  });

  final Widget? leading;
  final Widget? middle;
  final Widget? trailing;
  final ScrollController? scrollController;

  @override
  Size get preferredSize {
    // 返回一个较大的固定高度，实际高度在 build 中动态计算
    return const Size.fromHeight(100.0);
  }

  @override
  bool shouldFullyObstruct(BuildContext context) => false;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: scrollController ?? ScrollController(),
      builder: (context, child) {
        // 计算滚动偏移量，超过 10px 时显示毛玻璃效果
        final scrollOffset = scrollController?.hasClients == true
            ? scrollController!.offset
            : 0.0;
        final showBlur = scrollOffset > 10;

        return ClipRect(
          child: BackdropFilter(
            filter: showBlur
                ? ImageFilter.blur(sigmaX: 30, sigmaY: 30)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              // 从屏幕顶部开始，包含状态栏高度
              padding: EdgeInsets.only(top: statusBarHeight),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E).withOpacity(0)
                    : const Color(0xFFF2F2F7).withOpacity(0),
              ),
              child: SizedBox(
                height: 44,
                child: NavigationToolbar(
                  leading: leading != null
                      ? Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: _wrapWithColorTransition(
                              leading!, showBlur, isDark),
                        )
                      : null,
                  middle: middle != null
                      ? _wrapWithColorTransition(middle!, showBlur, isDark)
                      : null,
                  trailing: trailing != null
                      ? _wrapWithColorTransition(trailing!, showBlur, isDark)
                      : null,
                  middleSpacing: 16,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 为子组件包裹颜色过渡效果
  Widget _wrapWithColorTransition(Widget child, bool showBlur, bool isDark) {
    // 滑动时：白色
    // 未滑动时：根据深浅模式显示原色
    final color =
        showBlur ? Colors.white : (isDark ? Colors.white : Colors.black87);

    return DefaultTextStyle(
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w400, // 更细的字体
      ),
      child: IconTheme(
        data: IconThemeData(
          color: color,
          size: 28, // 稍小的图标尺寸，让箭头看起来更细
        ),
        child: child,
      ),
    );
  }
}

/// 创建带毛玻璃效果的返回按钮
Widget buildBlurBackButton(BuildContext context) {
  // 使用 Builder 来获取正确的 IconTheme 颜色
  return Builder(
    builder: (context) {
      final color = IconTheme.of(context).color ?? CupertinoColors.activeBlue;
      return CupertinoNavigationBarBackButton(
        color: color,
        onPressed: () => context.pop(),
      );
    },
  );
}

/// 创建带样式的标题
Widget buildNavTitle(String title, BuildContext context) {
  return Text(
    title,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w400, // 更细的字体
    ),
  );
}
