import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../library/modern_library_page.dart';
import '../music/local_music_page.dart';
import '../settings/settings_page.dart';
import 'bottom_nav_wrapper.dart';

/// ✅ 性能优化：使用 StatefulWidget + 动画切换
/// 保持页面状态的同时，添加淡入淡出动画效果
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 BottomNavProvider 获取当前标签索引
    final currentIndex = BottomNavProvider.of(context)?.currentIndex ?? 0;

    // ✅ 当外部索引变化时，触发 PageView 滑动动画
    if (_currentIndex != currentIndex) {
      _currentIndex = currentIndex;
      _pageController.animateToPage(
        currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    // ✅ 使用 PageView.builder 实现左右滑动效果（懒加载）
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(), // ✅ 禁用手势滑动，只通过底部导航切换
      itemCount: 4,
      onPageChanged: (index) {
        // ✅ 同步更新底部导航栏的选中状态
        if (_currentIndex != index) {
          setState(() {
            _currentIndex = index;
          });
          // 通知 BottomNavWrapper 更新选中状态
          final wrapper = BottomNavWrapper.of(context);
          if (wrapper != null) {
            wrapper.switchToTab(index);
          }
        }
      },
      itemBuilder: (context, index) {
        // ✅ 使用 RepaintBoundary 隔离每个页面
        return RepaintBoundary(
          child: _buildPageAtIndex(index),
        );
      },
    );
  }

  Widget _buildPageAtIndex(int index) {
    // 索引顺序：0-媒体库, 1-音乐, 2-收藏/下载, 3-设置
    switch (index) {
      case 0:
        return const ModernLibraryPage();
      case 1:
        return const LocalMusicPage();
      case 2:
        return const _PlaceholderPage(title: '收藏/下载');
      case 3:
        return const SettingsPage();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
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
