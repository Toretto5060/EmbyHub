import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../library/modern_library_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final location = GoRouterState.of(context).uri.path;
    
    // 根据当前路径判断是否显示首页标签内容还是子页面
    final showTabContent = location == '/';
    
    return PopScope(
      canPop: true, // 首页允许退出 APP
      child: Stack(
        children: [
          // 主内容区域
          if (showTabContent)
            // 显示标签页内容（媒体库/收藏/设置）
            IndexedStack(
              index: _index,
              children: const [
                ModernLibraryPage(),
                _PlaceholderPage(title: '收藏/下载'),
                SettingsPage(),
              ],
            )
          else
            // 显示子页面（通过 go_router 导航的页面）
            widget.child,
          // 自定义毛玻璃导航栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                        : const Color(0xFFF2F2F7).withValues(alpha: 0.85),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.15),
                        width: 0.3,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 60,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTabItem(
                            icon: CupertinoIcons.square_grid_2x2,
                            label: '媒体库',
                            index: 0,
                            isActive: _index == 0,
                          ),
                          _buildTabItem(
                            icon: CupertinoIcons.heart,
                            label: '收藏/下载',
                            index: 1,
                            isActive: _index == 1,
                          ),
                          _buildTabItem(
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
    );
  }

  Widget _buildTabItem({
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

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));

    return CupertinoPageScaffold(
      child: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: const Center(child: Text('开发中…')),
        ),
      ),
    );
  }
}
