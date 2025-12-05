import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/theme_utils.dart';
import '../../widgets/default_album_cover.dart';

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
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    // 专辑封面
                    AlbumCoverImage(
                      albumArt: hasCurrentSong ? currentSong.albumArt : null,
                      size: 48,
                      iconSize: 24,
                      borderRadius: BorderRadius.circular(8),
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
                    // 播放队列按钮 - 展开播放器并显示播放列表
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 44,
                      onPressed: hasCurrentSong
                          ? () {
                              // 触发展开播放器并显示播放列表
                              ref
                                  .read(
                                      expandToPlaylistTriggerProvider.notifier)
                                  .state++;
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
}
