import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/theme_utils.dart';

class MusicPlayerPage extends ConsumerStatefulWidget {
  const MusicPlayerPage({
    required this.onCollapseWithOffset,
    super.key,
  });

  /// 折叠回调，参数为当前拖拽偏移量
  final void Function(double dragOffset) onCollapseWithOffset;

  @override
  ConsumerState<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends ConsumerState<MusicPlayerPage> {
  double _dragOffset = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final playerState = ref.watch(localMusicPlayerProvider);
    final currentSong = playerState.currentSong;

    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dy;
          if (_dragOffset < 0) _dragOffset = 0;
        });
      },
      onVerticalDragEnd: (details) {
        // 如果下拉超过 150 或速度足够快，则折叠
        if (_dragOffset > 150 ||
            (details.primaryVelocity != null &&
                details.primaryVelocity! > 500)) {
          // 传递当前拖拽偏移量，让动画从当前位置开始
          widget.onCollapseWithOffset(_dragOffset);
          // 不重置 _dragOffset，让父组件控制
        } else {
          // 未触发折叠，恢复到顶部
          setState(() {
            _dragOffset = 0;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        // 侧滑返回
        if (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 500) {
          widget.onCollapseWithOffset(_dragOffset);
        }
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xFF1A1A2E),
                      const Color(0xFF0A0A0A),
                    ]
                  : [
                      const Color(0xFFE8E8F0),
                      const Color(0xFFF8F8F8),
                    ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // 顶部拖动指示器和关闭按钮
                _buildHeader(context, isDark),
                // 专辑封面
                Expanded(
                  flex: 4,
                  child: _buildAlbumArt(context, isDark, currentSong),
                ),
                // 歌曲信息
                _buildSongInfo(context, isDark, currentSong),
                // 进度条
                _buildProgressBar(context, isDark, playerState),
                // 控制按钮
                _buildControls(context, isDark, playerState),
                // 底部额外操作
                _buildBottomActions(context, isDark),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 拖动指示器
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 下拉关闭按钮
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 40,
                onPressed: () => widget.onCollapseWithOffset(0),
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 28,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              // 标题
              Text(
                '正在播放',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              // 更多选项
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 40,
                onPressed: () {
                  // TODO: 显示更多选项
                },
                child: Icon(
                  CupertinoIcons.ellipsis,
                  size: 24,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, bool isDark, LocalSong song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: song.albumArt != null
                  ? Image.network(
                      song.albumArt!,
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Icon(
                        CupertinoIcons.music_note,
                        size: 80,
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context, bool isDark, LocalSong song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        children: [
          Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: CupertinoColors.activeBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
      BuildContext context, bool isDark, LocalMusicPlayerState playerState) {
    final position = playerState.position;
    final duration = playerState.duration.inMilliseconds > 0
        ? playerState.duration
        : const Duration(minutes: 3, seconds: 30);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // 进度条
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: CupertinoColors.activeBlue,
              inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
              thumbColor: CupertinoColors.activeBlue,
              overlayColor: CupertinoColors.activeBlue.withOpacity(0.2),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (value) {
                // TODO: 跳转到指定位置
              },
            ),
          ),
          // 时间显示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
      BuildContext context, bool isDark, LocalMusicPlayerState playerState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 随机播放
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 切换随机播放
            },
            child: Icon(
              CupertinoIcons.shuffle,
              size: 24,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 上一首
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 56,
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).playPrevious();
            },
            child: Icon(
              CupertinoIcons.backward_fill,
              size: 36,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 播放/暂停
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 72,
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).togglePlayPause();
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.activeBlue.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                playerState.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                size: 36,
                color: Colors.white,
              ),
            ),
          ),
          // 下一首
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 56,
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).playNext();
            },
            child: Icon(
              CupertinoIcons.forward_fill,
              size: 36,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 循环播放
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 切换循环模式
            },
            child: Icon(
              CupertinoIcons.repeat,
              size: 24,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 喜欢
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 添加到喜欢
            },
            child: Icon(
              CupertinoIcons.heart,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 歌词
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 显示歌词
            },
            child: Icon(
              CupertinoIcons.text_quote,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 播放队列
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 显示播放队列
            },
            child: Icon(
              CupertinoIcons.list_bullet,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 音效
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 显示音效设置
            },
            child: Icon(
              CupertinoIcons.waveform,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
