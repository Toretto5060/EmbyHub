import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/modern_library_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        height: 65,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.square_grid_2x2), label: '媒体库'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.heart), label: '收藏/下载'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.settings), label: '设置'),
        ],
      ),
      controller: CupertinoTabController(initialIndex: _index),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return const ModernLibraryPage();
          case 1:
            return const _PlaceholderPage(title: '收藏/下载');
          case 2:
          default:
            return const SettingsPage();
        }
      },
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: const Color(0x00000000),
        border: null,
      ),
      child: SafeArea(
        top: false,
        child: const Center(child: Text('开发中…')),
      ),
    );
  }
}
