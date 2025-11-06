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
                          child: leading,
                        )
                      : null,
                  middle: middle,
                  trailing: trailing,
                  middleSpacing: 16,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 创建带毛玻璃效果的返回按钮
Widget buildBlurBackButton(BuildContext context) {
  final brightness = MediaQuery.of(context).platformBrightness;
  final isDark = brightness == Brightness.dark;

  return CupertinoNavigationBarBackButton(
    color: isDark ? Colors.white : Colors.black87,
    onPressed: () => context.pop(),
  );
}

/// 创建带样式的标题
Widget buildNavTitle(String title, BuildContext context) {
  final brightness = MediaQuery.of(context).platformBrightness;
  final isDark = brightness == Brightness.dark;

  return Text(
    title,
    style: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white : Colors.black87,
    ),
  );
}
