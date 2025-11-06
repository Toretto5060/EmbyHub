import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/modern_library_page.dart';
import '../settings/settings_page.dart';
import 'bottom_nav_wrapper.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 BottomNavProvider 获取当前标签索引
    final currentIndex = BottomNavProvider.of(context)?.currentIndex ?? 0;

    return IndexedStack(
        index: currentIndex,
        children: const [
          ModernLibraryPage(),
          _PlaceholderPage(title: '收藏/下载'),
          SettingsPage(),
        ],
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
