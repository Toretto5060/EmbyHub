import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// ✅ 播放器控制状态数据类
class PlayerControlsState {
  const PlayerControlsState({
    required this.isInPipMode,
    required this.ready,
    required this.showControls,
    required this.isBuffering,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.bufferPosition,
    required this.isDraggingProgress,
    required this.draggingPosition,
    required this.videoTitle,
    required this.videoFit,
    required this.showVideoFitHint,
    required this.speed,
    required this.showSpeedList,
    required this.speedOptions,
    required this.expectedBitrateKbps,
    required this.currentSpeedKbps,
    required this.qualityLabel,
    required this.audioStreams,
    required this.subtitleStreams,
    required this.selectedAudioStreamIndex,
    required this.selectedSubtitleStreamIndex,
    required this.controlsAnimation,
    required this.speedListScrollController,
    required this.player,
    required this.onToggleVideoFit,
    required this.onEnterPip,
    required this.onToggleOrientation,
    required this.onPlayPause,
    required this.onIncreaseSpeed,
    required this.onDecreaseSpeed,
    required this.onChangeSpeed,
    required this.onScrollToSelectedSpeed,
    required this.onShowAudioSelectionMenu,
    required this.onShowSubtitleSelectionMenu,
    required this.onDragStart,
    required this.onDragging,
    required this.onDragEnd,
    required this.onResetHideControlsTimer,
    required this.onCancelHideControlsTimer,
    required this.onSetState,
    required this.onShowSpeedListChanged,
    required this.getVideoFitIcon,
    required this.getVideoFitName,
    required this.formatTime,
    required this.formatBitrate,
    required this.canIncreaseSpeed,
    required this.canDecreaseSpeed,
  });

  final bool isInPipMode;
  final bool ready;
  final bool showControls;
  final bool isBuffering;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration bufferPosition;
  final bool isDraggingProgress;
  final Duration? draggingPosition;
  final String videoTitle;
  final BoxFit videoFit;
  final bool showVideoFitHint;
  final double speed;
  final bool showSpeedList;
  final List<double> speedOptions;
  final double? expectedBitrateKbps;
  final double? currentSpeedKbps;
  final String? qualityLabel;
  final List<Map<String, dynamic>> audioStreams;
  final List<Map<String, dynamic>> subtitleStreams;
  final int? selectedAudioStreamIndex;
  final int? selectedSubtitleStreamIndex;
  final Animation<double> controlsAnimation;
  final ScrollController speedListScrollController;
  final Player player;
  final VoidCallback onToggleVideoFit;
  final VoidCallback onEnterPip;
  final VoidCallback onToggleOrientation;
  final VoidCallback onPlayPause;
  final VoidCallback onIncreaseSpeed;
  final VoidCallback onDecreaseSpeed;
  final Future<void> Function(double) onChangeSpeed;
  final VoidCallback onScrollToSelectedSpeed;
  final ValueChanged<BuildContext> onShowAudioSelectionMenu;
  final ValueChanged<BuildContext> onShowSubtitleSelectionMenu;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDragging;
  final ValueChanged<Duration> onDragEnd;
  final VoidCallback onResetHideControlsTimer;
  final VoidCallback onCancelHideControlsTimer;
  final ValueChanged<VoidCallback> onSetState;
  final ValueChanged<bool> onShowSpeedListChanged;
  final IconData Function() getVideoFitIcon;
  final String Function() getVideoFitName;
  final String Function(Duration) formatTime;
  final String Function(double?) formatBitrate;
  final bool canIncreaseSpeed;
  final bool canDecreaseSpeed;
}

/// ✅ 播放器 UI 控制层
/// 负责所有 UI 控制相关的组件和逻辑
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    required this.state,
    super.key,
  });

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ✅ 顶部控制栏（淡入淡出动画）- 固定高度，不随状态栏变化
        // PiP 模式下隐藏
        if (!state.isInPipMode) _TopControlsBar(state: state, context: context),

        // ✅ 拖动进度条时的时间预览（与顶部工具条水平对齐）
        // PiP 模式下隐藏
        if (!state.isInPipMode &&
            state.isDraggingProgress &&
            state.draggingPosition != null)
          _DraggingTimePreview(state: state),

        // ✅ 视频裁切模式提示（tooltip样式，显示在按钮下方）
        // PiP 模式下隐藏
        if (!state.isInPipMode && state.showVideoFitHint)
          _VideoFitHint(state: state, context: context),

        // ✅ 中间播放/暂停按钮（仅在显示控制栏时）
        // PiP 模式下隐藏，缓冲时也隐藏
        if (!state.isInPipMode &&
            state.ready &&
            state.showControls &&
            !state.isBuffering)
          _PlayPauseButton(state: state),

        // ✅ 右侧速度控制（仅在显示控制栏时）
        // PiP 模式下隐藏，一进来就显示
        if (!state.isInPipMode && state.showControls)
          _SpeedControl(state: state, context: context),

        // ✅ 底部控制栏（淡入淡出动画）
        // PiP 模式下隐藏
        if (!state.isInPipMode) _BottomControlsBar(state: state),

        // ✅ 加载/缓冲指示器（不阻挡点击）
        // 显示条件：未准备好 或 正在缓冲 或 还未开始播放（position为0）
        if (!state.ready ||
            state.isBuffering ||
            (state.ready && state.position == Duration.zero))
          _LoadingIndicator(state: state),

        // ✅ 速度档位列表（显示在左侧，放在最后确保在最上层）
        if (!state.isInPipMode && state.showSpeedList && state.showControls)
          _SpeedList(state: state, context: context),
      ],
    );
  }
}

/// ✅ 顶部控制栏
class _TopControlsBar extends StatelessWidget {
  const _TopControlsBar({required this.state, required this.context});

  final PlayerControlsState state;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state.controlsAnimation,
      builder: (context, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: state.controlsAnimation.value,
            child: IgnorePointer(
              ignoring: !state.showControls,
              child: Container(
                // ✅ 使用固定高度，确保状态栏显示时按钮在状态栏下方
                padding: const EdgeInsets.only(
                  top: 40, // 固定高度，足够容纳状态栏
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                decoration: const BoxDecoration(),
                child: Row(
                  children: [
                    _buildIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    // ✅ 显示视频标题
                    Expanded(
                      child: Text(
                        state.videoTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ✅ 右侧按钮组（带毛玻璃背景）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? [
                                      Colors.grey.shade900
                                          .withValues(alpha: 0.6),
                                      Colors.grey.shade800
                                          .withValues(alpha: 0.4),
                                    ]
                                  : [
                                      Colors.white.withValues(alpha: 0.2),
                                      Colors.white.withValues(alpha: 0.1),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ✅ 视频画面裁切模式切换按钮（带动画）
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                minSize: 0,
                                onPressed: () {
                                  state.onToggleVideoFit();
                                  state.onResetHideControlsTimer();
                                },
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, animation) {
                                    return RotationTransition(
                                      turns: animation,
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Icon(
                                    state.getVideoFitIcon(),
                                    key: ValueKey<BoxFit>(state.videoFit),
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                              // ✅ 小窗按钮
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                minSize: 0,
                                onPressed: () {
                                  state.onEnterPip();
                                  state.onResetHideControlsTimer();
                                },
                                child: const Icon(
                                  Icons.picture_in_picture_alt_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              // ✅ 横竖屏切换
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                minSize: 0,
                                onPressed: () {
                                  state.onToggleOrientation();
                                  state.onResetHideControlsTimer();
                                },
                                child: const Icon(
                                  Icons.screen_rotation_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 24,
    bool showBackground = false,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: showBackground
            ? BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 3,
                ),
              )
            : null,
        child: Icon(
          icon,
          color: Colors.white,
          size: size,
        ),
      ),
    );
  }
}

/// ✅ 拖动进度条时的时间预览
class _DraggingTimePreview extends StatelessWidget {
  const _DraggingTimePreview({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40, // 与顶部工具条水平对齐
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: Theme.of(context).brightness == Brightness.dark
                          ? [
                              Colors.grey.shade900.withValues(alpha: 0.6),
                              Colors.grey.shade800.withValues(alpha: 0.4),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.2),
                              Colors.white.withValues(alpha: 0.1),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${state.formatTime(state.draggingPosition!)} / ${state.formatTime(state.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ 视频裁切模式提示
class _VideoFitHint extends StatelessWidget {
  const _VideoFitHint({required this.state, required this.context});

  final PlayerControlsState state;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 90, // 在顶部按钮下方，紧贴按钮组
      right: 85, // 对齐裁剪按钮位置
      child: AnimatedOpacity(
        opacity: state.showVideoFitHint ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ 箭头（三角形）
            CustomPaint(
              size: const Size(12, 6),
              painter: _TooltipArrowPainter(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            // ✅ Tooltip内容
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: Theme.of(context).brightness == Brightness.dark
                          ? [
                              Colors.grey.shade900.withValues(alpha: 0.6),
                              Colors.grey.shade800.withValues(alpha: 0.4),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.2),
                              Colors.white.withValues(alpha: 0.1),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    state.getVideoFitName(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ 中间播放/暂停按钮
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: state.controlsAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: state.controlsAnimation.value * 0.9,
            child: GestureDetector(
              onTap: state.onPlayPause,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  state.isPlaying
                      ? Icons.pause_circle_rounded
                      : Icons.play_circle_rounded,
                  key: ValueKey<bool>(state.isPlaying),
                  color: Colors.white,
                  size: 80,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ✅ 右侧速度控制
class _SpeedControl extends StatelessWidget {
  const _SpeedControl({required this.state, required this.context});

  final PlayerControlsState state;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 24,
      top: 0,
      bottom: 0,
      child: AnimatedBuilder(
        animation: state.controlsAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: state.controlsAnimation.value,
            child: IgnorePointer(
              ignoring: !state.showControls,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? [
                                  Colors.grey.shade900.withValues(alpha: 0.6),
                                  Colors.grey.shade800.withValues(alpha: 0.4),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.2),
                                  Colors.white.withValues(alpha: 0.1),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ✅ 加速按钮
                          CupertinoButton(
                            padding: const EdgeInsets.all(12),
                            onPressed: () {
                              if (state.canIncreaseSpeed) {
                                state.onIncreaseSpeed();
                                // ✅ 关闭倍速列表
                                if (state.showSpeedList) {
                                  state.onShowSpeedListChanged(false);
                                }
                                state.onResetHideControlsTimer();
                              }
                            },
                            child: Icon(
                              Icons.add_rounded,
                              color: state.canIncreaseSpeed
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                              size: 24,
                            ),
                          ),
                          // ✅ 速度值
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            onPressed: () {
                              final willShow = !state.showSpeedList;
                              state.onShowSpeedListChanged(willShow);
                              if (willShow) {
                                // ✅ 显示列表时，取消自动隐藏计时器
                                state.onCancelHideControlsTimer();
                                // ✅ 滚动到选中项
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  state.onScrollToSelectedSpeed();
                                });
                              } else {
                                // ✅ 隐藏列表时，重新启动自动隐藏计时器
                                state.onResetHideControlsTimer();
                              }
                            },
                            child: SizedBox(
                              width: 30, // ✅ 固定宽度，避免文字变化导致宽度变化
                              child: Text(
                                '${state.speed.toStringAsFixed(1)}x',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          // ✅ 减速按钮
                          CupertinoButton(
                            padding: const EdgeInsets.all(12),
                            onPressed: () {
                              if (state.canDecreaseSpeed) {
                                state.onDecreaseSpeed();
                                // ✅ 关闭倍速列表
                                if (state.showSpeedList) {
                                  state.onShowSpeedListChanged(false);
                                }
                                state.onResetHideControlsTimer();
                              }
                            },
                            child: Icon(
                              Icons.remove_rounded,
                              color: state.canDecreaseSpeed
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                              size: 24,
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
        },
      ),
    );
  }
}

/// ✅ 底部控制栏
class _BottomControlsBar extends StatelessWidget {
  const _BottomControlsBar({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state.controlsAnimation,
      builder: (context, child) {
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: state.controlsAnimation.value,
            child: IgnorePointer(
              ignoring: !state.showControls,
              child: _Controls(
                position: state.position,
                duration: state.duration,
                bufferPosition: state.bufferPosition,
                isPlaying: state.isPlaying,
                isDragging: state.isDraggingProgress,
                draggingPosition: state.draggingPosition,
                audioStreams: state.audioStreams,
                subtitleStreams: state.subtitleStreams,
                selectedAudioIndex: state.selectedAudioStreamIndex,
                selectedSubtitleIndex: state.selectedSubtitleStreamIndex,
                onAudioTap: state.onShowAudioSelectionMenu,
                onSubtitleTap: state.onShowSubtitleSelectionMenu,
                onDragStart: state.onDragStart,
                onDragging: state.onDragging,
                onDragEnd: state.onDragEnd,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ✅ 加载/缓冲指示器
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(
                    color: Colors.white,
                    radius: 16,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    !state.ready
                        ? '加载中...'
                        : state.isBuffering
                            ? '缓冲中...'
                            : '准备中...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (state.expectedBitrateKbps != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.formatBitrate(state.currentSpeedKbps),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (state.qualityLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '分辨率: ${state.qualityLabel}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ 速度档位列表
class _SpeedList extends StatelessWidget {
  const _SpeedList({required this.state, required this.context});

  final PlayerControlsState state;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 90,
      top: 10,
      bottom: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 220, // ✅ 设置最大高度
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [
                            Colors.grey.shade900.withValues(alpha: 0.7),
                            Colors.grey.shade800.withValues(alpha: 0.5),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.25),
                            Colors.white.withValues(alpha: 0.15),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  controller: state.speedListScrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.speedOptions.map((speed) {
                      final isSelected = speed == state.speed;
                      return CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        onPressed: () async {
                          await state.onChangeSpeed(speed);
                          state.onShowSpeedListChanged(false);
                          state.onResetHideControlsTimer();
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              '${speed.toStringAsFixed(1)}x',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ 底部控制栏组件
class _Controls extends StatefulWidget {
  const _Controls({
    required this.position,
    required this.duration,
    required this.bufferPosition,
    required this.isPlaying,
    required this.isDragging,
    this.draggingPosition,
    required this.audioStreams,
    required this.subtitleStreams,
    this.selectedAudioIndex,
    this.selectedSubtitleIndex,
    required this.onAudioTap,
    required this.onSubtitleTap,
    required this.onDragStart,
    required this.onDragging,
    required this.onDragEnd,
  });
  final Duration position;
  final Duration duration;
  final Duration bufferPosition;
  final bool isPlaying;
  final bool isDragging;
  final Duration? draggingPosition;
  final List<Map<String, dynamic>> audioStreams;
  final List<Map<String, dynamic>> subtitleStreams;
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final ValueChanged<BuildContext> onAudioTap;
  final ValueChanged<BuildContext> onSubtitleTap;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDragging;
  final ValueChanged<Duration> onDragEnd;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls>
    with SingleTickerProviderStateMixin {
  late AnimationController _thumbAnimationController;
  late Animation<double> _thumbAnimation;
  BuildContext? _subtitleAnchorContext;

  @override
  void initState() {
    super.initState();
    _thumbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _thumbAnimation = Tween<double>(
      begin: 6.0,
      end: 9.0,
    ).animate(CurvedAnimation(
      parent: _thumbAnimationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didUpdateWidget(_Controls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDragging != oldWidget.isDragging) {
      if (widget.isDragging) {
        _thumbAnimationController.forward();
      } else {
        _thumbAnimationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _thumbAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = widget.duration.inSeconds.clamp(1, 1 << 30);
    final displayPosition = widget.isDragging && widget.draggingPosition != null
        ? widget.draggingPosition!
        : widget.position;
    final rawValue = displayPosition.inSeconds / totalSeconds;
    final sliderValue =
        rawValue.isNaN ? 0.0 : rawValue.clamp(0.0, 1.0).toDouble();

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    ? [
                        Colors.grey.shade900.withValues(alpha: 0.6),
                        Colors.grey.shade800.withValues(alpha: 0.4),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.1),
                      ],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 65,
                  child: Text(
                    _fmt(widget.position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const Text(
                  ' · ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(
                  width: 65,
                  child: Text(
                    _fmt(widget.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _thumbAnimation,
                    builder: (context, child) {
                      final bufferValue =
                          widget.bufferPosition.inSeconds / totalSeconds;
                      final bufferSliderValue = bufferValue.isNaN
                          ? 0.0
                          : bufferValue.clamp(0.0, 1.0).toDouble();

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final playedWidth = width * sliderValue;
                          final bufferedWidth = width * bufferSliderValue;

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              if (bufferedWidth > playedWidth)
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        margin: EdgeInsets.only(
                                            left: (width - 48) * sliderValue),
                                        width: (width - 48) *
                                            (bufferSliderValue - sliderValue),
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.5),
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(1.5),
                                            bottomRight: Radius.circular(1.5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: RoundSliderThumbShape(
                                    enabledThumbRadius: _thumbAnimation.value,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor:
                                      Colors.white.withValues(alpha: 0.3),
                                  thumbColor: Colors.white,
                                  overlayColor:
                                      Colors.white.withValues(alpha: 0.15),
                                ),
                                child: Slider(
                                  value: sliderValue,
                                  onChangeStart: (v) {
                                    widget.onDragStart();
                                  },
                                  onChanged: (v) {
                                    final target = Duration(
                                        seconds: (v * totalSeconds).round());
                                    widget.onDragging(target);
                                  },
                                  onChangeEnd: (v) {
                                    final target = Duration(
                                        seconds: (v * totalSeconds).round());
                                    widget.onDragEnd(target);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.subtitleStreams.isNotEmpty)
                  Builder(
                    builder: (btnContext) {
                      _subtitleAnchorContext = btnContext;
                      return CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: () => widget.onSubtitleTap(btnContext),
                        child: const Icon(
                          Icons.subtitles_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      );
                    },
                  ),
                if (widget.audioStreams.isNotEmpty)
                  Builder(
                    builder: (btnContext) {
                      return CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: () => widget
                            .onAudioTap(_subtitleAnchorContext ?? btnContext),
                        child: const Icon(
                          Icons.audiotrack_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

/// ✅ Tooltip箭头绘制器
class _TooltipArrowPainter extends CustomPainter {
  final Color color;

  _TooltipArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    // 绘制向上的三角形箭头
    path.moveTo(size.width / 2, 0); // 顶点（中间）
    path.lineTo(0, size.height); // 左下角
    path.lineTo(size.width, size.height); // 右下角
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
