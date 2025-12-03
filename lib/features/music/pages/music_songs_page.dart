import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/local_music_provider.dart';
import '../../../providers/local_music_storage_provider.dart';
import '../../../utils/theme_utils.dart';

/// 封面图片缓存
final Map<String, ImageProvider> _albumArtCache = {};

/// 滚动文字组件 - 当文字超出宽度时自动滚动
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  ScrollController? _scrollController;
  bool _needsScroll = false;
  bool _isScrolling = false;
  bool _measured = false;
  double _scrollDistance = 0;

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _reset();
    }
  }

  void _reset() {
    _isScrolling = false;
    _needsScroll = false;
    _measured = false;
    _scrollController?.dispose();
    _scrollController = null;
    if (mounted) setState(() {});
  }

  void _onTextLayout(double textWidth, double maxWidth) {
    if (_measured) return;
    _measured = true;

    // 文字宽度超过可用宽度 5 像素以上才滚动
    if (textWidth > maxWidth + 5) {
      _scrollDistance = textWidth - maxWidth + 20;
      _needsScroll = true;
      _scrollController = ScrollController();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScrolling();
      });
    }
  }

  void _startScrolling() async {
    if (!mounted || !_needsScroll || _isScrolling) return;
    _isScrolling = true;

    await Future.delayed(const Duration(seconds: 1));

    while (mounted && _needsScroll && _isScrolling) {
      if (_scrollController == null || !_scrollController!.hasClients) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      await _scrollController!.animateTo(
        _scrollDistance,
        duration: Duration(milliseconds: (_scrollDistance * 30).toInt()),
        curve: Curves.linear,
      );

      if (!mounted || !_needsScroll) break;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_needsScroll) break;

      if (_scrollController != null && _scrollController!.hasClients) {
        await _scrollController!.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }

      if (!mounted || !_needsScroll) break;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 已确定需要滚动
    if (_needsScroll) {
      return SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
        ),
      );
    }

    // 使用自定义的测量组件
    return _TextMeasurer(
      text: widget.text,
      style: widget.style,
      onMeasured: _onTextLayout,
    );
  }
}

/// 测量文字是否溢出的组件
class _TextMeasurer extends StatelessWidget {
  const _TextMeasurer({
    required this.text,
    required this.style,
    required this.onMeasured,
  });

  final String text;
  final TextStyle style;
  final void Function(double textWidth, double maxWidth) onMeasured;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // 计算文字实际宽度
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final textWidth = textPainter.width;

        // 在布局后回调
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onMeasured(textWidth, maxWidth);
        });

        return Text(
          text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

class MusicSongsPage extends ConsumerStatefulWidget {
  const MusicSongsPage({super.key});

  @override
  ConsumerState<MusicSongsPage> createState() => _MusicSongsPageState();
}

class _MusicSongsPageState extends ConsumerState<MusicSongsPage> {
  bool _isMultiSelectMode = false;
  final Set<String> _selectedSongIds = {};

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 获取缓存的封面图片
  ImageProvider? _getCachedAlbumArt(String? path) {
    if (path == null) return null;

    if (_albumArtCache.containsKey(path)) {
      return _albumArtCache[path];
    }

    final file = File(path);
    if (file.existsSync()) {
      final provider = FileImage(file);
      _albumArtCache[path] = provider;
      return provider;
    }

    return null;
  }

  /// 构建专辑封面组件
  Widget _buildAlbumArt(LocalSong song, bool isPlaying, bool isDark) {
    final albumArtProvider = _getCachedAlbumArt(song.albumArt);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: albumArtProvider != null
          ? Image(
              image: albumArtProvider,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              gaplessPlayback: true, // 防止滚动时闪烁
              errorBuilder: (context, error, stackTrace) {
                return _buildDefaultMusicIcon(isPlaying, isDark);
              },
            )
          : _buildDefaultMusicIcon(isPlaying, isDark),
    );
  }

  /// 构建默认音乐图标
  Widget _buildDefaultMusicIcon(bool isPlaying, bool isDark) {
    return Center(
      child: Icon(
        CupertinoIcons.double_music_note,
        size: 24,
        color: isPlaying
            ? CupertinoColors.activeBlue
            : (isDark ? Colors.white38 : Colors.black26),
      ),
    );
  }

  void _shufflePlay(List<LocalSong> songs) {
    if (songs.isEmpty) return;
    // 随机打乱歌曲顺序
    final shuffledSongs = List<LocalSong>.from(songs)..shuffle();
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
  void _playSelectedSongs(List<LocalSong> songs) {
    if (_selectedSongIds.isEmpty) return;

    // 获取选中的歌曲，保持原始顺序
    final selectedSongs =
        songs.where((song) => _selectedSongIds.contains(song.id)).toList();

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

    final playlists = ref.read(localMusicStorageProvider).playlists;

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
          // 现有歌单列表（排除最近播放）
          ...playlists
              .where((p) => p.id != 'recent')
              .map((playlist) => CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.pop(context);
                      _onAddToPlaylist(playlist.id, playlist.name);
                    },
                    child: Text(playlist.name),
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
  Future<void> _onAddToPlaylist(String playlistId, String playlistName) async {
    await ref
        .read(localMusicStorageProvider.notifier)
        .addSongsToPlaylist(playlistId, _selectedSongIds.toList());
    // 退出多选模式
    setState(() {
      _isMultiSelectMode = false;
      _selectedSongIds.clear();
    });
  }

  // 创建新歌单并添加歌曲
  Future<void> _onCreatePlaylistAndAdd(String playlistName) async {
    final newPlaylist = await ref
        .read(localMusicStorageProvider.notifier)
        .createPlaylist(playlistName);
    await ref
        .read(localMusicStorageProvider.notifier)
        .addSongsToPlaylist(newPlaylist.id, _selectedSongIds.toList());
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

  // 跳转到扫描页面
  void _goToScanPage() {
    ref.read(currentMusicNavProvider.notifier).state = MusicNavItem.scan;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final playerState = ref.watch(localMusicPlayerProvider);
    final storageState = ref.watch(localMusicStorageProvider);
    final musicSourceMode = ref.watch(musicSourceModeProvider);

    final songs = storageState.songs;

    // 加载中状态
    if (storageState.isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(),
      );
    }

    // 空状态
    if (songs.isEmpty) {
      return _buildEmptyState(context, isDark, musicSourceMode);
    }

    return Column(
      children: [
        // 顶部操作栏
        _buildToolbar(context, isDark, songs),
        // 歌曲列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              top: 8,
              bottom: _isMultiSelectMode ? 72 : 8, // 多选模式时底部留出操作栏空间
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
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
                          songs,
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
                      // 专辑封面
                      _buildAlbumArt(song, isPlaying, isDark),
                      const SizedBox(width: 12),
                      // 歌曲信息
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 歌曲标题 - 播放中且超出宽度时滚动显示
                              if (isPlaying)
                                _MarqueeText(
                                  text: song.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.activeBlue,
                                  ),
                                )
                              else
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  // 音质标签
                                  if (song.bitrate != null &&
                                      song.bitrate! > 96) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: song.bitrate! > 256
                                            ? CupertinoColors.activeBlue
                                                .withOpacity(0.15)
                                            : CupertinoColors.activeGreen
                                                .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        song.bitrate! > 256 ? 'SQ' : 'HQ',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: song.bitrate! > 256
                                              ? CupertinoColors.activeBlue
                                              : CupertinoColors.activeGreen,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  // 艺术家和专辑 - 播放中且超出宽度时滚动显示
                                  Expanded(
                                    child: isPlaying
                                        ? _MarqueeText(
                                            text: song.album != null &&
                                                    song.album!.isNotEmpty
                                                ? '${song.artist} · ${song.album}'
                                                : song.artist,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                            ),
                                          )
                                        : Text(
                                            song.album != null &&
                                                    song.album!.isNotEmpty
                                                ? '${song.artist} · ${song.album}'
                                                : song.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 时长
                      SizedBox(
                        width: 45,
                        child: Text(
                          _formatDuration(song.duration),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
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
        if (_isMultiSelectMode)
          _buildMultiSelectActionBar(context, isDark, songs),
      ],
    );
  }

  // 空状态显示
  Widget _buildEmptyState(
      BuildContext context, bool isDark, MusicSourceMode sourceMode) {
    final isServerMode = sourceMode == MusicSourceMode.server;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.double_music_note,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 24),
            Text(
              '暂无播放列表',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            if (isServerMode)
              Text(
                '快去服务器添加音乐文件吧',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black38,
                ),
                textAlign: TextAlign.center,
              )
            else
              Column(
                children: [
                  Text(
                    '当前为本地播放，快去扫描吧',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black38,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    color: CupertinoColors.activeBlue,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: _goToScanPage,
                    child: const Text(
                      '扫描音乐',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // 多选模式底部操作栏
  Widget _buildMultiSelectActionBar(
      BuildContext context, bool isDark, List<LocalSong> songs) {
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
                onPressed:
                    hasSelection ? () => _playSelectedSongs(songs) : null,
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

  Widget _buildToolbar(
      BuildContext context, bool isDark, List<LocalSong> songs) {
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
            onPressed: () => _shufflePlay(songs),
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
