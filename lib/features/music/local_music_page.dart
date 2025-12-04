import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../providers/local_music_storage_provider.dart';
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

/// 音乐页面 ScrollController Provider - 用于共享滚动状态以实现毛玻璃效果
final musicScrollControllerProvider =
    Provider<ScrollController?>((ref) => null);

/// 音乐页面滚动进度 Provider - 用于控制毛玻璃效果
final musicScrollProgressProvider = StateProvider<double>((ref) => 0.0);

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

  // 滚动控制器 - 用于毛玻璃效果
  final ScrollController _scrollController = ScrollController();
  double _blurProgress = 0.0;
  static const double _blurStart = 10.0;
  static const double _blurEnd = 200.0;

  // 是否已经检查过初始展开状态
  bool _hasCheckedInitialExpand = false;

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
      reverseCurve: Curves.easeOut, // 使用更平滑的曲线，避免开始时太慢
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _playerAnimationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    double newProgress;
    if (offset <= _blurStart) {
      newProgress = 0.0;
    } else {
      final totalRange =
          (_blurEnd - _blurStart).abs().clamp(1.0, double.infinity);
      final effective = (offset - _blurStart).clamp(0.0, totalRange);
      newProgress = (effective / totalRange).clamp(0.0, 1.0);
    }
    if ((newProgress - _blurProgress).abs() > 0.001) {
      setState(() {
        _blurProgress = newProgress;
      });
      // 更新 Provider 以便子组件可以访问
      ref.read(musicScrollProgressProvider.notifier).state = newProgress;
    }
  }

  /// 获取当前页面的 ScrollController
  ScrollController get currentScrollController => _scrollController;

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _expandPlayer() {
    // 只有当有歌曲时才展开播放器
    final currentSong = ref.read(localMusicPlayerProvider).currentSong;
    if (currentSong == null) return;

    setState(() {
      _isPlayerExpanded = true;
      _hasCheckedInitialExpand = true;
    });
    ref.read(musicPlayerExpandedProvider.notifier).state = true;
    // 正常播放展开动画
    _playerAnimationController.forward(from: 0);
  }

  void _collapsePlayer() {
    _collapsePlayerWithOffset(0);
  }

  void _collapsePlayerWithOffset(double dragOffset) {
    // 立即更新状态，防止重复触发
    if (!_isPlayerExpanded) return;

    ref.read(musicPlayerExpandedProvider.notifier).state = false;

    // 计算动画起始值：根据拖拽偏移量计算当前位置对应的动画值
    final screenHeight = MediaQuery.of(context).size.height;
    final startValue = 1.0 - (dragOffset / screenHeight);

    // 根据剩余距离计算动画时长，让动画更跟手
    // 剩余距离越小，动画时长越短
    final remainingDistance = screenHeight - dragOffset;
    final duration =
        (remainingDistance / screenHeight * 250).clamp(100, 250).toInt();
    _playerAnimationController.duration = Duration(milliseconds: duration);

    // 从当前位置开始动画
    _playerAnimationController.value = startValue.clamp(0.0, 1.0);
    _playerAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isPlayerExpanded = false;
        });
        // 恢复默认动画时长
        _playerAnimationController.duration = const Duration(milliseconds: 350);
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
        return MusicSongsPage(scrollController: _scrollController);
      case MusicNavItem.albums:
        return MusicAlbumsPage(scrollController: _scrollController);
      case MusicNavItem.artists:
        return MusicArtistsPage(scrollController: _scrollController);
      case MusicNavItem.folders:
        return MusicFoldersPage(scrollController: _scrollController);
      case MusicNavItem.playlists:
        return MusicPlaylistsPage(scrollController: _scrollController);
      case MusicNavItem.scan:
        return MusicScanPage(scrollController: _scrollController);
      case MusicNavItem.library:
        return MusicLibraryPage(scrollController: _scrollController);
      case MusicNavItem.stats:
        return MusicStatsPage(scrollController: _scrollController);
      case MusicNavItem.settings:
        return MusicSettingsPage(scrollController: _scrollController);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final currentNav = ref.watch(currentMusicNavProvider);
    final currentSong = ref.watch(localMusicPlayerProvider).currentSong;

    // ✅ 检查静态标记（在第一帧就可以访问，不依赖 Provider）
    final shouldInitialExpand = InitialExpandMarker.shouldExpand;

    // 监听折叠播放页面的请求
    ref.listen<int>(collapsePlayerTriggerProvider, (previous, next) {
      if (_isPlayerExpanded && previous != next) {
        _collapsePlayer();
      }
    });

    // 监听展开播放页面的请求（仅当不是初始展开时）
    ref.listen<int>(expandPlayerTriggerProvider, (previous, next) {
      if (!_isPlayerExpanded && previous != next && _hasCheckedInitialExpand) {
        _expandPlayer();
      }
    });

    // ✅ 初始展开逻辑：如果需要初始展开，直接显示全屏播放器
    if (shouldInitialExpand && !_isPlayerExpanded) {
      if (currentSong != null) {
        // 歌曲已加载，更新状态并显示播放器
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isPlayerExpanded) {
            // 清除静态标记
            InitialExpandMarker.clear();
            setState(() {
              _isPlayerExpanded = true;
              _hasCheckedInitialExpand = true;
            });
            ref.read(musicPlayerExpandedProvider.notifier).state = true;
            _playerAnimationController.value = 1.0;
          }
        });

        // 直接渲染全屏播放页面
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor:
              isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F8F8),
          body: MusicPlayerPage(
            onCollapseWithOffset: _collapsePlayerWithOffset,
          ),
        );
      } else {
        // 歌曲还没加载，显示空白页面等待（避免显示歌曲列表）
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor:
              isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F8F8),
          body: const SizedBox.shrink(),
        );
      }
    }

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
          // 主内容区域（内容从顶部开始，顶部栏浮动在上方）
          Positioned.fill(
            child: _buildContentPage(currentNav),
          ),
          // 顶部导航栏（浮动，带毛玻璃效果）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context, isDark, currentNav),
          ),
          // 底部迷你播放器（始终显示，全屏播放器覆盖其上）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MusicMiniPlayer(
              onTap: _expandPlayer,
            ),
          ),
          // 全屏播放页面（覆盖在迷你播放器上方）
          if (_isPlayerExpanded || _playerAnimationController.isAnimating)
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
                      onCollapseWithOffset: _collapsePlayerWithOffset,
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
    final topPadding = MediaQuery.of(context).padding.top;
    final backgroundColor =
        isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F8F8);

    return ClipRect(
      child: BackdropFilter(
        filter: _blurProgress > 0
            ? ui.ImageFilter.blur(
                sigmaX: 20 * _blurProgress,
                sigmaY: 20 * _blurProgress,
              )
            : ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          padding: EdgeInsets.only(top: topPadding),
          decoration: BoxDecoration(
            color: _blurProgress > 0
                ? backgroundColor.withOpacity(0.7 * _blurProgress)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              SizedBox(
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
              // 工具栏（仅歌曲页面显示）
              if (currentNav == MusicNavItem.songs)
                _buildSongsToolbar(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建歌曲页面的工具栏
  Widget _buildSongsToolbar(BuildContext context, bool isDark) {
    final storageState = ref.watch(localMusicStorageProvider);
    final songs = storageState.songs;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 左侧：随机播放按钮 + 歌曲数量
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 36,
            onPressed: songs.isNotEmpty
                ? () {
                    final shuffledSongs = List<LocalSong>.from(songs)
                      ..shuffle();
                    ref
                        .read(localMusicPlayerProvider.notifier)
                        .setPlaylist(shuffledSongs);
                  }
                : null,
            child: Icon(
              CupertinoIcons.shuffle,
              size: 20,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 8),
          // 歌曲数量（只显示数字）
          Text(
            '${songs.length}',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const Spacer(),
          // 右侧：排序按钮 + 多选按钮（暂时简化）
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 36,
            onPressed: () {
              // TODO: 显示排序选项
            },
            child: Icon(
              CupertinoIcons.sort_down,
              size: 20,
              color: iconColor,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 36,
            onPressed: () {
              // TODO: 切换多选模式
            },
            child: Icon(
              CupertinoIcons.list_bullet,
              size: 20,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}
