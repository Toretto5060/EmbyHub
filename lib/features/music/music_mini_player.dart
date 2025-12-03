import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/theme_utils.dart';

class MusicMiniPlayer extends ConsumerWidget {
  const MusicMiniPlayer({
    required this.onTap,
    super.key,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);
    final playerState = ref.watch(localMusicPlayerProvider);
    final currentSong = playerState.currentSong;
    final hasCurrentSong = currentSong != null;

    return GestureDetector(
      onTap: hasCurrentSong ? onTap : null,
      onVerticalDragEnd: hasCurrentSong
          ? (details) {
              // 上滑展开播放页面
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < -300) {
                onTap();
              }
            }
          : null,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A1A1A).withOpacity(0.7)
                  : Colors.white.withOpacity(0.7),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black12,
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    // 专辑封面
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: hasCurrentSong &&
                              currentSong.albumArt != null &&
                              File(currentSong.albumArt!).existsSync()
                          ? Image.file(
                              File(currentSong.albumArt!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  CupertinoIcons.double_music_note,
                                  size: 24,
                                  color:
                                      isDark ? Colors.white38 : Colors.black26,
                                );
                              },
                            )
                          : Icon(
                              CupertinoIcons.double_music_note,
                              size: 24,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                    ),
                    const SizedBox(width: 12),
                    // 歌曲信息
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasCurrentSong ? currentSong.title : '未在播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: hasCurrentSong
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white38 : Colors.black38),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasCurrentSong ? currentSong.artist : '点击歌曲开始播放',
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
                    // 播放/暂停按钮
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 44,
                      onPressed: hasCurrentSong
                          ? () {
                              ref
                                  .read(localMusicPlayerProvider.notifier)
                                  .togglePlayPause();
                            }
                          : null,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: hasCurrentSong
                              ? CupertinoColors.activeBlue.withOpacity(0.1)
                              : (isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.05)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          playerState.isPlaying
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          size: 22,
                          color: hasCurrentSong
                              ? CupertinoColors.activeBlue
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 播放队列按钮
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 44,
                      onPressed: hasCurrentSong
                          ? () {
                              _showPlayQueue(context, ref, isDark);
                            }
                          : null,
                      child: Icon(
                        CupertinoIcons.list_bullet,
                        size: 24,
                        color: hasCurrentSong
                            ? (isDark ? Colors.white54 : Colors.black45)
                            : (isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPlayQueue(BuildContext context, WidgetRef ref, bool isDark) {
    final playerState = ref.read(localMusicPlayerProvider);

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                  Text(
                    '播放队列',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${playerState.playlist.length} 首歌曲',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            // 播放列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: playerState.playlist.length,
                itemBuilder: (context, index) {
                  final song = playerState.playlist[index];
                  final isCurrentSong = playerState.currentIndex == index;

                  return CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      ref.read(localMusicPlayerProvider.notifier).setPlaylist(
                            playerState.playlist,
                            startIndex: index,
                          );
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      color: isCurrentSong
                          ? CupertinoColors.activeBlue.withOpacity(0.1)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          // 播放指示器
                          SizedBox(
                            width: 24,
                            child: isCurrentSong
                                ? Icon(
                                    playerState.isPlaying
                                        ? CupertinoIcons.waveform
                                        : CupertinoIcons.pause_fill,
                                    size: 16,
                                    color: CupertinoColors.activeBlue,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
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
                                    fontSize: 15,
                                    fontWeight: isCurrentSong
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isCurrentSong
                                        ? CupertinoColors.activeBlue
                                        : (isDark
                                            ? Colors.white
                                            : Colors.black87),
                                  ),
                                ),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
