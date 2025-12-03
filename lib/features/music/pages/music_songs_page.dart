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

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final playerState = ref.watch(localMusicPlayerProvider);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _mockSongs.length,
      itemBuilder: (context, index) {
        final song = _mockSongs[index];
        final isPlaying = playerState.currentSong?.id == song.id;

        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            ref.read(localMusicPlayerProvider.notifier).setPlaylist(
                  _mockSongs,
                  startIndex: index,
                );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isPlaying
                  ? (isDark
                      ? CupertinoColors.activeBlue.withOpacity(0.15)
                      : CupertinoColors.activeBlue.withOpacity(0.08))
                  : Colors.transparent,
            ),
            child: Row(
              children: [
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
                          fontWeight:
                              isPlaying ? FontWeight.w600 : FontWeight.normal,
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
                const SizedBox(width: 8),
                // 更多按钮
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
            ),
          ),
        );
      },
    );
  }
}
