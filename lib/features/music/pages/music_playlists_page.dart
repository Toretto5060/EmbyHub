import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/local_music_provider.dart';
import '../../../providers/local_music_storage_provider.dart';
import '../../../utils/theme_utils.dart';

class MusicPlaylistsPage extends ConsumerStatefulWidget {
  const MusicPlaylistsPage({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<MusicPlaylistsPage> createState() => _MusicPlaylistsPageState();
}

class _MusicPlaylistsPageState extends ConsumerState<MusicPlaylistsPage> {
  /// 默认歌单的图标和颜色配置
  static final Map<String, Map<String, dynamic>> defaultPlaylistConfig = {
    'favorites': {
      'icon': CupertinoIcons.heart_fill,
      'color': CupertinoColors.systemPink,
    },
    'recent': {
      'icon': CupertinoIcons.time,
      'color': CupertinoColors.activeBlue,
    },
    'workout': {
      'icon': CupertinoIcons.flame_fill,
      'color': CupertinoColors.systemOrange,
    },
    'sleep': {
      'icon': CupertinoIcons.moon_fill,
      'color': CupertinoColors.systemPurple,
    },
  };

  /// 获取歌单图标
  IconData _getPlaylistIcon(MusicPlaylist playlist) {
    if (playlist.isDefault && defaultPlaylistConfig.containsKey(playlist.id)) {
      return defaultPlaylistConfig[playlist.id]!['icon'] as IconData;
    }
    return CupertinoIcons.music_note_list;
  }

  /// 获取歌单颜色
  Color _getPlaylistColor(MusicPlaylist playlist) {
    if (playlist.isDefault && defaultPlaylistConfig.containsKey(playlist.id)) {
      return defaultPlaylistConfig[playlist.id]!['color'] as Color;
    }
    return CupertinoColors.activeBlue;
  }

  /// 显示歌单操作菜单（长按）
  void _showPlaylistOptionsDialog(
      BuildContext context, bool isDark, MusicPlaylist playlist) {
    final songCount = playlist.songIds.length;
    final hasSongs = songCount > 0;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 歌单名称标题
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  playlist.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white12 : Colors.black12,
              ),
              // 播放该歌单按钮（仅当有歌曲时显示）
              if (hasSongs)
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _playPlaylist(playlist);
                  },
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.play_fill,
                        size: 20,
                        color: CupertinoColors.activeBlue,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '播放该歌单',
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              // 删除该歌单按钮
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                onPressed: () {
                  Navigator.of(context).pop();
                  _confirmDeletePlaylist(context, isDark, playlist);
                },
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.trash,
                      size: 20,
                      color: CupertinoColors.destructiveRed,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '删除该歌单',
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放歌单
  void _playPlaylist(MusicPlaylist playlist) {
    final storageState = ref.read(localMusicStorageProvider);
    final songs = storageState.songs
        .where((s) => playlist.songIds.contains(s.id))
        .toList();

    if (songs.isNotEmpty) {
      // 设置播放列表并开始播放（不展开全屏播放页面）
      ref.read(localMusicPlayerProvider.notifier).setPlaylist(
            songs,
            startIndex: 0,
          );
    }
  }

  /// 确认删除歌单
  void _confirmDeletePlaylist(
      BuildContext context, bool isDark, MusicPlaylist playlist) {
    final songCount = playlist.songIds.length;

    // 如果歌单有歌曲，显示确认对话框
    if (songCount > 0) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 48,
                  color: CupertinoColors.systemOrange,
                ),
                const SizedBox(height: 16),
                Text(
                  '删除歌单',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '删除「${playlist.name}」将清除该歌单下的所有 $songCount 首歌曲记录，不会删除本地音乐文件。\n\n是否确认删除？',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: CupertinoColors.destructiveRed,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _deletePlaylist(playlist);
                        },
                        child: const Text(
                          '删除',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // 没有歌曲，直接删除
      _deletePlaylist(playlist);
    }
  }

  /// 删除歌单
  Future<void> _deletePlaylist(MusicPlaylist playlist) async {
    final success = await ref
        .read(localMusicStorageProvider.notifier)
        .deletePlaylist(playlist.id);

    if (!success && mounted) {
      // 默认歌单不可删除
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('默认歌单不可删除'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 显示创建歌单对话框
  void _showCreatePlaylistDialog(BuildContext context, bool isDark) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Text(
                '创建新歌单',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // 输入框
              CupertinoTextField(
                controller: textController,
                placeholder: '请输入歌单名称',
                autofocus: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                placeholderStyle: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 20),
              // 按钮行
              Row(
                children: [
                  // 取消按钮
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 创建按钮
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoColors.activeBlue,
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () async {
                        final name = textController.text.trim();
                        if (name.isNotEmpty) {
                          await ref
                              .read(localMusicStorageProvider.notifier)
                              .createPlaylist(name);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      },
                      child: const Text(
                        '创建',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final storageState = ref.watch(localMusicStorageProvider);
    final playlists = storageState.playlists;

    // 顶部安全区域 + 标题栏高度
    final topPadding = MediaQuery.of(context).padding.top + 56;
    // 迷你播放器高度
    const miniPlayerHeight = 72.0;

    return Column(
      children: [
        // 顶部安全区域占位
        SizedBox(height: topPadding),
        // 创建歌单按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _showCreatePlaylistDialog(context, isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.plus,
                    size: 20,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '创建新歌单',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 歌单列表
        Expanded(
          child: storageState.isLoading
              ? const Center(child: CupertinoActivityIndicator())
              : playlists.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: EdgeInsets.only(
                          left: 16, right: 16, bottom: miniPlayerHeight + 8),
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final icon = _getPlaylistIcon(playlist);
                        final color = _getPlaylistColor(playlist);
                        final songCount = playlist.songIds.length;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onLongPress: () {
                              _showPlaylistOptionsDialog(
                                  context, isDark, playlist);
                            },
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                // TODO: 打开歌单详情
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    // 歌单图标
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        icon,
                                        size: 26,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // 歌单信息
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            playlist.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$songCount 首歌曲',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      CupertinoIcons.chevron_right,
                                      size: 18,
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.black26,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.music_note_list,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 24),
            Text(
              '暂无歌单',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方按钮创建新歌单',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black38,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
