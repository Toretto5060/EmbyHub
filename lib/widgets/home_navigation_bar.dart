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
    this.forceBlur,
    super.key,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? trailing;
  final ScrollController? scrollController;
  final bool? forceBlur;

  @override
  Size get preferredSize => const Size.fromHeight(100.0);

  @override
  bool shouldFullyObstruct(BuildContext context) => false;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final baseColor = brightness == Brightness.dark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);

    return AnimatedBuilder(
      animation: scrollController ?? ScrollController(),
      builder: (context, child) {
        final scrollOffset = scrollController?.hasClients == true
            ? scrollController!.offset
            : 0.0;
        final bool blur = forceBlur ?? (scrollOffset > 10);
        final double sigma = blur ? 30 : 0;
        final double backgroundOpacity = blur ? 0.7 : 1.0;
        final Color currentColor =
            brightness == Brightness.dark ? Colors.white : Colors.black87;

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: Container(
              padding: EdgeInsets.only(top: statusBarHeight),
              decoration: BoxDecoration(
                color: baseColor.withOpacity(backgroundOpacity),
              ),
              child: SizedBox(
                height: 44,
                child: NavigationToolbar(
                  leading: leading != null
                      ? Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: _wrapWithColor(leading!, currentColor),
                        )
                      : null,
                  middle: title != null
                      ? _wrapWithColor(title!, currentColor)
                      : null,
                  trailing: trailing != null
                      ? Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: _wrapWithColor(trailing!, currentColor),
                        )
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

  Widget _wrapWithColor(Widget child, Color color) {
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
