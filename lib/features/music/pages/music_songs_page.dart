import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/local_music_provider.dart';
import '../../../utils/theme_utils.dart';

class MusicSongsPage extends ConsumerStatefulWidget {
  const MusicSongsPage({super.key});

  @override
  ConsumerState<MusicSongsPage> createState() => _MusicSongsPageState();
}

class _MusicSongsPageState extends ConsumerState<MusicSongsPage> {
  bool _isMultiSelectMode = false;
  final Set<String> _selectedSongIds = {};

  // 模拟歌曲数据
  final List<LocalSong> _mockSongs = [
    const LocalSong(
      id: '1',
      title: '示例歌曲 1',
      artist: '艺术家 A',
      album: '专辑一',
      duration: Duration(minutes: 3, seconds: 45),
    ),
    const LocalSong(
      id: '2',
      title: '示例歌曲 2',
      artist: '艺术家 B',
      album: '专辑二',
      duration: Duration(minutes: 4, seconds: 20),
    ),
    const LocalSong(
      id: '3',
      title: '示例歌曲 3',
      artist: '艺术家 A',
      album: '专辑一',
      duration: Duration(minutes: 2, seconds: 58),
    ),
    const LocalSong(
      id: '4',
      title: '示例歌曲 4',
      artist: '艺术家 C',
      album: '专辑三',
      duration: Duration(minutes: 5, seconds: 12),
    ),
    const LocalSong(
      id: '5',
      title: '示例歌曲 5',
      artist: '艺术家 B',
      album: '专辑二',
      duration: Duration(minutes: 3, seconds: 33),
    ),
  ];

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _shufflePlay() {
    if (_mockSongs.isEmpty) return;
    // 随机打乱歌曲顺序
    final shuffledSongs = List<LocalSong>.from(_mockSongs)..shuffle();
    ref.read(localMusicPlayerProvider.notifier).setPlaylist(shuffledSongs);
    ref.read(expandPlayerTriggerProvider.notifier).state++;
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedSongIds.clear();
      }
    });
  }

  void _toggleSongSelection(String songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  // 播放选中的歌曲队列
  void _playSelectedSongs() {
    if (_selectedSongIds.isEmpty) return;

    // 获取选中的歌曲，保持原始顺序
    final selectedSongs =
        _mockSongs.where((song) => _selectedSongIds.contains(song.id)).toList();

    // 设置播放列表并开始播放
    ref.read(localMusicPlayerProvider.notifier).setPlaylist(selectedSongs);
    ref.read(expandPlayerTriggerProvider.notifier).state++;

    // 退出多选模式
    setState(() {
      _isMultiSelectMode = false;
      _selectedSongIds.clear();
    });
  }

  // 显示添加到歌单的弹窗
  void _showAddToPlaylistDialog(BuildContext context, bool isDark) {
    if (_selectedSongIds.isEmpty) return;

    // 模拟歌单数据
    final mockPlaylists = [
      {'id': '1', 'name': '我喜欢的音乐'},
      {'id': '2', 'name': '运动歌单'},
      {'id': '3', 'name': '睡前音乐'},
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('添加 ${_selectedSongIds.length} 首歌曲到歌单'),
        actions: [
          // 新建歌单按钮
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showCreatePlaylistDialog(context, isDark);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.add_circled,
                  size: 20,
                  color: CupertinoColors.activeBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  '新建歌单',
                  style: TextStyle(color: CupertinoColors.activeBlue),
                ),
              ],
            ),
          ),
          // 现有歌单列表
          ...mockPlaylists.map((playlist) => CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: 添加到歌单
                  _onAddToPlaylist(playlist['id']!, playlist['name']!);
                },
                child: Text(playlist['name']!),
              )),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  // 显示新建歌单对话框
  void _showCreatePlaylistDialog(BuildContext context, bool isDark) {
    final textController = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('新建歌单'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: textController,
            placeholder: '请输入歌单名称',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                // TODO: 创建歌单并添加歌曲
                _onCreatePlaylistAndAdd(name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  // 添加到现有歌单
  void _onAddToPlaylist(String playlistId, String playlistName) {
    // TODO: 实现添加到歌单的逻辑
    // 退出多选模式
    setState(() {
      _isMultiSelectMode = false;
      _selectedSongIds.clear();
    });
  }

  // 创建新歌单并添加歌曲
  void _onCreatePlaylistAndAdd(String playlistName) {
    // TODO: 实现创建歌单并添加歌曲的逻辑
    // 退出多选模式
    setState(() {
      _isMultiSelectMode = false;
      _selectedSongIds.clear();
    });
  }

  void _showSortOptions(BuildContext context, bool isDark) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('排序方式'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 按标题排序
            },
            child: const Text('按标题'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 按艺术家排序
            },
            child: const Text('按艺术家'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 按专辑排序
            },
            child: const Text('按专辑'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 按添加时间排序
            },
            child: const Text('按添加时间'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final playerState = ref.watch(localMusicPlayerProvider);

    return Column(
      children: [
        // 顶部操作栏
        _buildToolbar(context, isDark),
        // 歌曲列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              top: 8,
              bottom: _isMultiSelectMode ? 72 : 8, // 多选模式时底部留出操作栏空间
            ),
            itemCount: _mockSongs.length,
            itemBuilder: (context, index) {
              final song = _mockSongs[index];
              final isPlaying = playerState.currentSong?.id == song.id;
              final isSelected = _selectedSongIds.contains(song.id);

              return CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  if (_isMultiSelectMode) {
                    // 多选模式：切换选中状态
                    _toggleSongSelection(song.id);
                  } else {
                    // 正常模式：播放歌曲
                    ref.read(localMusicPlayerProvider.notifier).setPlaylist(
                          _mockSongs,
                          startIndex: index,
                        );
                    ref.read(expandPlayerTriggerProvider.notifier).state++;
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? (isDark
                            ? CupertinoColors.activeBlue.withOpacity(0.15)
                            : CupertinoColors.activeBlue.withOpacity(0.08))
                        : (isSelected && _isMultiSelectMode
                            ? (isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.black.withOpacity(0.03))
                            : Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      // 多选模式下显示选择框
                      if (_isMultiSelectMode) ...[
                        Icon(
                          isSelected
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 22,
                          color: isSelected
                              ? CupertinoColors.activeBlue
                              : (isDark ? Colors.white38 : Colors.black26),
                        ),
                        const SizedBox(width: 12),
                      ],
                      // 专辑封面占位
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white10
                              : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          CupertinoIcons.music_note,
                          size: 24,
                          color: isPlaying
                              ? CupertinoColors.activeBlue
                              : (isDark ? Colors.white38 : Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 歌曲信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isPlaying
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isPlaying
                                    ? CupertinoColors.activeBlue
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${song.artist} · ${song.album ?? '未知专辑'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 时长
                      Text(
                        _formatDuration(song.duration),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      // 非多选模式下显示更多按钮
                      if (!_isMultiSelectMode) ...[
                        const SizedBox(width: 8),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 32,
                          onPressed: () {
                            // TODO: 显示更多选项
                          },
                          child: Icon(
                            CupertinoIcons.ellipsis,
                            size: 20,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // 多选模式下的底部操作栏
        if (_isMultiSelectMode) _buildMultiSelectActionBar(context, isDark),
      ],
    );
  }

  // 多选模式底部操作栏
  Widget _buildMultiSelectActionBar(BuildContext context, bool isDark) {
    final hasSelection = _selectedSongIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 添加到歌单按钮
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: hasSelection
                    ? (isDark ? Colors.white12 : Colors.black.withOpacity(0.05))
                    : (isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.02)),
                borderRadius: BorderRadius.circular(10),
                onPressed: hasSelection
                    ? () => _showAddToPlaylistDialog(context, isDark)
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.music_note_list,
                      size: 18,
                      color: hasSelection
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.white38 : Colors.black26),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '添加到歌单',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: hasSelection
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white38 : Colors.black26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 播放选中按钮
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: hasSelection
                    ? CupertinoColors.activeBlue
                    : CupertinoColors.activeBlue.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                onPressed: hasSelection ? _playSelectedSongs : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.play_fill,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '播放 (${_selectedSongIds.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool isDark) {
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final activeColor = CupertinoColors.activeBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 左侧：随机播放按钮 + 歌曲数量
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 36,
            onPressed: _shufflePlay,
            child: Icon(
              CupertinoIcons.shuffle,
              size: 20,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 8),
          // 歌曲数量（只显示数字）
          Text(
            '${_mockSongs.length}',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const Spacer(),
          // 右侧：排序按钮 + 多选按钮
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 36,
            onPressed: () => _showSortOptions(context, isDark),
            child: Icon(
              CupertinoIcons.sort_down,
              size: 20,
              color: iconColor,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 36,
            onPressed: _toggleMultiSelectMode,
            child: Icon(
              CupertinoIcons.list_bullet,
              size: 20,
              color: _isMultiSelectMode ? activeColor : iconColor,
            ),
          ),
        ],
      ),
    );
  }
}
