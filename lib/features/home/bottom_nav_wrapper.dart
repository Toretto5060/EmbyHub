import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../utils/platform_utils.dart';

// InheritedWidget 用于向下传递当前选中的标签索引
class BottomNavProvider extends InheritedWidget {
  const BottomNavProvider({
    required this.currentIndex,
    required super.child,
    super.key,
  });

  final int currentIndex;

  static BottomNavProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BottomNavProvider>();
  }

  @override
  bool updateShouldNotify(BottomNavProvider oldWidget) {
    return currentIndex != oldWidget.currentIndex;
  }
}

class BottomNavWrapper extends StatefulWidget {
  const BottomNavWrapper({required this.child, super.key});

  final Widget child;

  @override
  State<BottomNavWrapper> createState() => _BottomNavWrapperState();

  static _BottomNavWrapperState? of(BuildContext context) {
    return context.findAncestorStateOfType<_BottomNavWrapperState>();
  }
}

class _BottomNavWrapperState extends State<BottomNavWrapper> {
  int _index = 0;

  int get currentIndex => _index;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final navBarHeight = 65.0;
    final bottomNavHeight =
        navBarHeight + MediaQuery.of(context).padding.bottom;
    final location = GoRouterState.of(context).uri.path;
    final isHomePage = location == '/';  // 判断是否在首页

    return PopScope(
      canPop: false,  // 拦截返回事件
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          // 如果在首页，将应用移到后台
          if (isHomePage) {
            print('📱 首页返回：移到后台');
            await PlatformUtils.moveToBackground();
          } else {
            // 如果在子页面，返回上一页
            print('📱 子页面返回：返回上一页');
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          }
        }
      },
      child: Scaffold(
        body: Stack(
        children: [
          // 内容区域 - 延伸到屏幕最底部，底部留出导航栏空间
          Positioned.fill(
            bottom: bottomNavHeight,
            child: BottomNavProvider(
              currentIndex: _index,
              child: widget.child,
            ),
          ),
          // 底部导航栏 - 悬浮在内容上方
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 40),
                child: Container(
                  height: bottomNavHeight,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1C1C1E).withOpacity(0)
                        : const Color(0xFFF2F2F7).withOpacity(0),
                    // 上阴影效果 - 向上投影，增强层次感
                    // boxShadow: [
                    //   BoxShadow(
                    //     color: isDark
                    //         ? Colors.black.withOpacity(0.1)
                    //         : Colors.black.withOpacity(0.1),
                    //     offset: const Offset(0, -2),  // 向上投影 2px
                    //     blurRadius: 8,                 // 模糊半径 8px
                    //     spreadRadius: 0,
                    //   ),
                    // ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: navBarHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTabItem(
                            context: context,
                            icon: CupertinoIcons.square_grid_2x2,
                            label: '媒体库',
                            index: 0,
                            isActive: _index == 0,
                          ),
                          _buildTabItem(
                            context: context,
                            icon: CupertinoIcons.heart,
                            label: '收藏/下载',
                            index: 1,
                            isActive: _index == 1,
                          ),
                          _buildTabItem(
                            context: context,
                            icon: CupertinoIcons.settings,
                            label: '设置',
                            index: 2,
                            isActive: _index == 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    required bool isActive,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // 如果不在首页，先返回首页
          if (GoRouterState.of(context).uri.path != '/') {
            context.go('/');
          }
          setState(() => _index = index);
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.inactiveGray,
            ),
            const SizedBox(height: 2),
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? CupertinoColors.activeBlue
                    : CupertinoColors.inactiveGray,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
