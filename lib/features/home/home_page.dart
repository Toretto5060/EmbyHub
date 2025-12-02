import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../library/modern_library_page.dart';
import '../settings/settings_page.dart';
import 'bottom_nav_wrapper.dart';

/// ✅ 性能优化：使用 StatefulWidget + AutomaticKeepAliveClientMixin
/// 保持页面状态的同时，只构建当前显示的页面
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ✅ 缓存已构建的页面，避免重复构建
  final Map<int, Widget> _cachedPages = {};

  @override
  Widget build(BuildContext context) {
    // 使用 BottomNavProvider 获取当前标签索引
    final currentIndex = BottomNavProvider.of(context)?.currentIndex ?? 0;

    // ✅ 懒加载：只构建当前需要显示的页面
    if (!_cachedPages.containsKey(currentIndex)) {
      _cachedPages[currentIndex] = _buildPage(currentIndex);
    }

    // ✅ 使用 IndexedStack 保持页面状态，但只构建已访问过的页面
    return IndexedStack(
      index: currentIndex,
      children: [
        _cachedPages[0] ?? const SizedBox.shrink(),
        _cachedPages[1] ?? const SizedBox.shrink(),
        _cachedPages[2] ?? const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const ModernLibraryPage();
      case 1:
        return const _PlaceholderPage(title: '收藏/下载');
      case 2:
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
