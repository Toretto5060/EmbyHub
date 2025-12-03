import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/platform_utils.dart';
import '../../utils/status_bar_manager.dart';
import '../../utils/theme_utils.dart';
import '../settings/settings_page.dart';

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

class BottomNavWrapper extends ConsumerStatefulWidget {
  const BottomNavWrapper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BottomNavWrapper> createState() => _BottomNavWrapperState();

  static _BottomNavWrapperState? of(BuildContext context) {
    return context.findAncestorStateOfType<_BottomNavWrapperState>();
  }
}

class _BottomNavWrapperState extends ConsumerState<BottomNavWrapper>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _showBottomNav = true;
  late AnimationController _navAnimationController;
  late Animation<Offset> _navSlideAnimation;

  int get currentIndex => _index;
  bool get showBottomNav => _showBottomNav;

  @override
  void initState() {
    super.initState();
    _navAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _navSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1), // 向下滑出
    ).animate(CurvedAnimation(
      parent: _navAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _navAnimationController.dispose();
    super.dispose();
  }

  // ✅ 切换到指定的 tab
  void switchToTab(int index) {
    if (_index != index) {
      setState(() {
        _index = index;
      });
    }
  }

  // ✅ 控制底部导航栏显示/隐藏（带动画）
  void setBottomNavVisible(bool visible) {
    if (visible) {
      // 显示：先设置状态，再播放动画（从下往上）
      setState(() {
        _showBottomNav = true;
      });
      _navAnimationController.reverse();
    } else {
      // 隐藏：先播放动画（从上往下），再设置状态
      _navAnimationController.forward().then((_) {
        setState(() {
          _showBottomNav = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final navBarHeight = 65.0;
    final bottomNavHeight =
        navBarHeight + MediaQuery.of(context).padding.bottom;
    final location = GoRouterState.of(context).uri.path;
    final isHomePage = location == '/'; // 判断是否在首页

    // ✅ 使用 adaptiveToTheme() 根据用户选择的主题模式自适应状态栏样式
    // 而不是使用 adaptive() 根据系统平台亮度自适应
    return StatusBarStyleScope.adaptiveToTheme(
      child: PopScope(
        canPop: false, // 拦截返回事件
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (!didPop) {
            // 如果在首页，将应用移到后台
            if (isHomePage) {
              await PlatformUtils.moveToBackground();
            } else {
              // 如果在子页面，返回上一页
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
              // ✅ 内容区域 - 使用 AnimatedPositioned 平滑过渡底部间距
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: 0,
                left: 0,
                right: 0,
                bottom: _showBottomNav ? bottomNavHeight : 0,
                child: RepaintBoundary(
                  child: BottomNavProvider(
                    currentIndex: _index,
                    child: widget.child,
                  ),
                ),
              ),
              // ✅ 底部导航栏 - 使用 RepaintBoundary 隔离重绘（带动画）
              if (_showBottomNav || _navAnimationController.isAnimating)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _navSlideAnimation,
                    child: RepaintBoundary(
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Container(
                            height: bottomNavHeight,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1C1C1E).withOpacity(0)
                                  : const Color(0xFFF2F2F7).withOpacity(0),
                            ),
                            child: SafeArea(
                              top: false,
                              child: SizedBox(
                                height: navBarHeight,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
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
                                      icon: CupertinoIcons.music_note_2,
                                      label: '音乐',
                                      index: 1,
                                      isActive: _index == 1,
                                      hideNavOnTap: true,
                                    ),
                                    _buildTabItem(
                                      context: context,
                                      icon: CupertinoIcons.heart,
                                      label: '收藏/下载',
                                      index: 2,
                                      isActive: _index == 2,
                                    ),
                                    _buildTabItem(
                                      context: context,
                                      icon: CupertinoIcons.settings,
                                      label: '设置',
                                      index: 3,
                                      isActive: _index == 3,
                                    ),
                                  ],
                                ),
                              ),
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
      ),
    );
  }

  Widget _buildTabItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    required bool isActive,
    bool hideNavOnTap = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // 如果不在首页，先返回首页
          if (GoRouterState.of(context).uri.path != '/') {
            context.go('/');
          }
          setState(() => _index = index);

          // ✅ 如果切换到设置页面（index == 3），触发缓存刷新
          if (index == 3) {
            ref.read(cacheRefreshTriggerProvider.notifier).state++;
          }

          // ✅ 如果是音乐tab，隐藏底部导航栏并设置音乐页面可见状态
          if (hideNavOnTap) {
            setBottomNavVisible(false);
            ref.read(musicPageVisibleProvider.notifier).state = true;
          }
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

// ✅ 退出音乐页面，恢复底部导航栏
  void exitMusicPage() {
    ref.read(musicPageVisibleProvider.notifier).state = false;

    // 1. 先显示底部导航栏并播放上滑动画
    setState(() {
      _showBottomNav = true;
    });
    _navAnimationController.value = 1.0; // 设置到隐藏状态
    _navAnimationController.reverse().then((_) {
      // 2. 底部导航栏动画结束后，再切换页面（带动画）
      if (mounted) {
        setState(() {
          _index = 0;
        });
      }
    });
  }
}
