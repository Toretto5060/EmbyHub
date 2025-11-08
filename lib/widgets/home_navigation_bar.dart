import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 首页专用的顶部导航栏 - 带动态毛玻璃效果
class HomeNavigationBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const HomeNavigationBar({
    this.leading,
    this.title,
    this.trailing,
    this.scrollController,
    super.key,
  });

  final Widget? leading;
  final Widget? title;
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
              padding: EdgeInsets.only(top: statusBarHeight),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E).withOpacity(0)
                    : const Color(0xFFF2F2F7).withOpacity(0),
              ),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (leading != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _wrapWithColor(leading!, isDark),
                          ),
                        if (title != null)
                          _wrapWithColor(title!, isDark),
                      ],
                    ),
                    if (trailing != null)
                      Positioned(
                        right: 16,
                        child: _wrapWithColor(trailing!, isDark),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _wrapWithColor(Widget child, bool isDark) {
    final color = isDark ? Colors.white : Colors.black87;

    return DefaultTextStyle(
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
      ),
      child: IconTheme(
        data: IconThemeData(
          color: color,
          size: 28,
        ),
        child: child,
      ),
    );
  }
}

/// 创建首页标题
Widget buildHomeTitle(String title) {
  return Text(
    title,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
    ),
  );
}
