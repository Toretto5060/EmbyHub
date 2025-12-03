import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/theme_utils.dart';
import '../home/bottom_nav_wrapper.dart';
import 'music_drawer.dart';
import 'music_mini_player.dart';
import 'music_player_page.dart';
import 'pages/music_albums_page.dart';
import 'pages/music_artists_page.dart';
import 'pages/music_folders_page.dart';
import 'pages/music_library_page.dart';
import 'pages/music_playlists_page.dart';
import 'pages/music_scan_page.dart';
import 'pages/music_settings_page.dart';
import 'pages/music_songs_page.dart';
import 'pages/music_stats_page.dart';

class LocalMusicPage extends ConsumerStatefulWidget {
  const LocalMusicPage({super.key});

  @override
  ConsumerState<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends ConsumerState<LocalMusicPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // 播放页面展开状态
  bool _isPlayerExpanded = false;
  late AnimationController _playerAnimationController;
  late Animation<double> _playerAnimation;

  @override
  void initState() {
    super.initState();
    _playerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _playerAnimation = CurvedAnimation(
      parent: _playerAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _playerAnimationController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _expandPlayer() {
    setState(() {
      _isPlayerExpanded = true;
    });
    ref.read(musicPlayerExpandedProvider.notifier).state = true;
    _playerAnimationController.forward();
  }

  void _collapsePlayer() {
    // 立即更新状态，防止重复触发
    if (!_isPlayerExpanded) return;

    ref.read(musicPlayerExpandedProvider.notifier).state = false;
    _playerAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isPlayerExpanded = false;
        });
      }
    });
  }

  String _getNavTitle(MusicNavItem item) {
    switch (item) {
      case MusicNavItem.songs:
        return '歌曲';
      case MusicNavItem.albums:
        return '专辑';
      case MusicNavItem.artists:
        return '艺术家';
      case MusicNavItem.folders:
        return '文件夹';
      case MusicNavItem.playlists:
        return '歌单';
      case MusicNavItem.scan:
        return '扫描音乐';
      case MusicNavItem.library:
        return '音乐库';
      case MusicNavItem.stats:
        return '统计';
      case MusicNavItem.settings:
        return '设置';
    }
  }

  Widget _buildContentPage(MusicNavItem item) {
    switch (item) {
      case MusicNavItem.songs:
        return const MusicSongsPage();
      case MusicNavItem.albums:
        return const MusicAlbumsPage();
      case MusicNavItem.artists:
        return const MusicArtistsPage();
      case MusicNavItem.folders:
        return const MusicFoldersPage();
      case MusicNavItem.playlists:
        return const MusicPlaylistsPage();
      case MusicNavItem.scan:
        return const MusicScanPage();
      case MusicNavItem.library:
        return const MusicLibraryPage();
      case MusicNavItem.stats:
        return const MusicStatsPage();
      case MusicNavItem.settings:
        return const MusicSettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final currentNav = ref.watch(currentMusicNavProvider);
    final miniPlayerHeight = 72.0;

    // 监听折叠播放页面的请求
    ref.listen<int>(collapsePlayerTriggerProvider, (previous, next) {
      if (_isPlayerExpanded && previous != next) {
        _collapsePlayer();
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor:
          isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F8F8),
      onDrawerChanged: (isOpened) {
        // 更新抽屉状态
        ref.read(musicDrawerOpenProvider.notifier).state = isOpened;
      },
      drawer: MusicDrawer(
        onExit: () {
          Navigator.of(context).pop();
          // 退出音乐页面
          final wrapper = BottomNavWrapper.of(context);
          wrapper?.exitMusicPage();
        },
      ),
      body: Stack(
        children: [
          // 主内容区域
          Column(
            children: [
              // 顶部导航栏
              _buildTopBar(context, isDark, currentNav),
              // 内容区域
              Expanded(
                child: _buildContentPage(currentNav),
              ),
              // 底部迷你播放器占位
              SizedBox(height: miniPlayerHeight),
            ],
          ),
          // 底部迷你播放器（始终显示）
          if (!_isPlayerExpanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MusicMiniPlayer(
                onTap: _expandPlayer,
              ),
            ),
          // 全屏播放页面
          if (_isPlayerExpanded)
            AnimatedBuilder(
              animation: _playerAnimation,
              builder: (context, child) {
                return Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      MediaQuery.of(context).size.height *
                          (1 - _playerAnimation.value),
                    ),
                    child: MusicPlayerPage(
                      onCollapse: _collapsePlayer,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
      BuildContext context, bool isDark, MusicNavItem currentNav) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F8F8),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            // 左侧菜单按钮
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onPressed: _openDrawer,
              child: Icon(
                CupertinoIcons.bars,
                color: isDark ? Colors.white : Colors.black87,
                size: 24,
              ),
            ),
            // 中间标题
            Expanded(
              child: Center(
                child: Text(
                  _getNavTitle(currentNav),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
            // 右侧占位（保持对称）
            const SizedBox(width: 56),
          ],
        ),
      ),
    );
  }
}
