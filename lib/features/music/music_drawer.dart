import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_provider.dart';
import '../../providers/local_music_provider.dart';
import '../../providers/local_music_storage_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/theme_utils.dart';

class MusicDrawer extends ConsumerWidget {
  const MusicDrawer({
    required this.onExit,
    required this.onClose,
    super.key,
  });

  final VoidCallback onExit;
  final VoidCallback onClose;

  /// 上一次检测到的用户ID（用于检测账号切换）
  static String? _lastUserId;

  /// 检查服务器是否有音乐媒体库
  void _checkServerMusicLibrary(WidgetRef ref) {
    // 获取认证状态
    final authAsync = ref.watch(authStateProvider);
    final auth = authAsync.value;

    // 检测账号切换：如果用户ID变化，重置为本地模式
    final currentUserId = auth?.userId;
    if (_lastUserId != null && _lastUserId != currentUserId) {
      // 账号切换了，重置为本地模式
      Future.microtask(() {
        // 切换存储到本地模式（会停止播放并恢复本地歌曲列表）
        ref.read(localMusicStorageProvider.notifier).switchToLocalMode();
        ref.read(serverMusicLibraryProvider.notifier).state =
            const ServerMusicLibrary();
      });
    }
    _lastUserId = currentUserId;

    // 未登录或未连接服务器
    if (auth == null || !auth.isLoggedIn) {
      // 更新为不可用状态，并重置为本地模式
      final currentState = ref.read(serverMusicLibraryProvider);
      final currentMode = ref.read(musicSourceModeProvider);
      if (currentState.isAvailable || currentMode == MusicSourceMode.server) {
        // 使用 Future.microtask 避免在 build 期间修改状态
        Future.microtask(() {
          ref.read(serverMusicLibraryProvider.notifier).state =
              const ServerMusicLibrary();
          // 切换存储到本地模式（会停止播放并恢复本地歌曲列表）
          ref.read(localMusicStorageProvider.notifier).switchToLocalMode();
        });
      }
      return;
    }

    // 获取媒体库列表
    final viewsAsync = ref.watch(viewsProvider);
    viewsAsync.whenData((views) {
      // 查找 music 类型的媒体库
      final musicLibrary =
          views.where((v) => v.collectionType == 'music').firstOrNull;

      final newState = musicLibrary != null
          ? ServerMusicLibrary(
              isAvailable: true,
              libraryId: musicLibrary.id,
              libraryName: musicLibrary.name,
            )
          : const ServerMusicLibrary();

      // 仅当状态变化时更新
      final currentState = ref.read(serverMusicLibraryProvider);
      if (currentState.isAvailable != newState.isAvailable ||
          currentState.libraryId != newState.libraryId) {
        // 使用 Future.microtask 避免在 build 期间修改状态
        Future.microtask(() {
          ref.read(serverMusicLibraryProvider.notifier).state = newState;
          // 如果服务器没有音乐媒体库，也重置为本地模式
          if (!newState.isAvailable) {
            ref.read(localMusicStorageProvider.notifier).switchToLocalMode();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);
    final currentNav = ref.watch(currentMusicNavProvider);
    final musicSourceMode = ref.watch(musicSourceModeProvider);

    // 检查服务器连接状态和音乐媒体库
    _checkServerMusicLibrary(ref);

    // 页面背景色
    final pageBackgroundColor =
        isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F8F8);
    // 区域背景色（卡片色）
    final sectionBackgroundColor =
        isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Container(
      color: pageBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // 顶部操作栏区域
              _buildHeader(context, isDark, ref, musicSourceMode,
                  sectionBackgroundColor),
              const SizedBox(height: 16),
              // 浏览区域
              _buildBrowseSection(
                  context, ref, currentNav, isDark, sectionBackgroundColor),
              const SizedBox(height: 16),
              // 管理区域
              _buildManageSection(
                  context, ref, currentNav, isDark, sectionBackgroundColor),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建毛玻璃区域容器
  Widget _buildGlassContainer({
    required bool isDark,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: child,
        ),
      ),
    );
  }

  /// 构建浏览区域
  Widget _buildBrowseSection(BuildContext context, WidgetRef ref,
      MusicNavItem currentNav, bool isDark, Color backgroundColor) {
    return _buildGlassContainer(
      isDark: isDark,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.double_music_note,
            label: '歌曲',
            item: MusicNavItem.songs,
            isSelected: currentNav == MusicNavItem.songs,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.square_stack,
            label: '专辑',
            item: MusicNavItem.albums,
            isSelected: currentNav == MusicNavItem.albums,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.person_2,
            label: '艺术家',
            item: MusicNavItem.artists,
            isSelected: currentNav == MusicNavItem.artists,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.folder,
            label: '文件夹',
            item: MusicNavItem.folders,
            isSelected: currentNav == MusicNavItem.folders,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.music_note_list,
            label: '歌单',
            item: MusicNavItem.playlists,
            isSelected: currentNav == MusicNavItem.playlists,
            isDark: isDark,
            isLast: true,
          ),
        ],
      ),
    );
  }

  /// 构建管理区域
  Widget _buildManageSection(BuildContext context, WidgetRef ref,
      MusicNavItem currentNav, bool isDark, Color backgroundColor) {
    return _buildGlassContainer(
      isDark: isDark,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.search,
            label: '扫描音乐',
            item: MusicNavItem.scan,
            isSelected: currentNav == MusicNavItem.scan,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.music_albums,
            label: '音乐库',
            item: MusicNavItem.library,
            isSelected: currentNav == MusicNavItem.library,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.chart_bar,
            label: '统计',
            item: MusicNavItem.stats,
            isSelected: currentNav == MusicNavItem.stats,
            isDark: isDark,
          ),
          _buildNavItem(
            context: context,
            ref: ref,
            icon: CupertinoIcons.gear,
            label: '设置',
            item: MusicNavItem.settings,
            isSelected: currentNav == MusicNavItem.settings,
            isDark: isDark,
            isLast: true,
          ),
        ],
      ),
    );
  }

  void _onNavItemTap(BuildContext context, WidgetRef ref, MusicNavItem item) {
    ref.read(currentMusicNavProvider.notifier).state = item;
    onClose();
  }

  Widget _buildHeader(BuildContext context, bool isDark, WidgetRef ref,
      MusicSourceMode musicSourceMode, Color backgroundColor) {
    // 检查服务器是否有音乐媒体库
    final serverMusicLibrary = ref.watch(serverMusicLibraryProvider);
    final hasServerMusicLibrary = serverMusicLibrary.isAvailable;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 退出按钮 - 只显示图标
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 32,
                onPressed: onExit,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    CupertinoIcons.square_arrow_left,
                    size: 16,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              // 切换本地/媒体库按钮 - 仅在服务器有音乐媒体库时显示
              if (hasServerMusicLibrary)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 32,
                  onPressed: () {
                    // 切换音乐来源模式
                    final currentMode = ref.read(musicSourceModeProvider);
                    final storageNotifier =
                        ref.read(localMusicStorageProvider.notifier);

                    if (currentMode == MusicSourceMode.local) {
                      // 切换到服务器模式
                      final libraryId = serverMusicLibrary.libraryId;
                      if (libraryId != null) {
                        storageNotifier.switchToServerMode(libraryId);
                      }
                    } else {
                      // 切换到本地模式
                      storageNotifier.switchToLocalMode();
                    }
                    onClose();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      musicSourceMode == MusicSourceMode.local
                          ? CupertinoIcons.device_phone_portrait
                          : CupertinoIcons.globe,
                      size: 16,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                )
              else
                // 占位，保持布局对齐
                const SizedBox(width: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required WidgetRef ref,
    required IconData icon,
    required String label,
    required MusicNavItem item,
    required bool isSelected,
    required bool isDark,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        bottom: isLast ? 0 : 2,
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => _onNavItemTap(context, ref, item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? CupertinoColors.activeBlue.withOpacity(0.2)
                    : CupertinoColors.activeBlue.withOpacity(0.1))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: isSelected
                    ? CupertinoColors.activeBlue
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? CupertinoColors.activeBlue
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
