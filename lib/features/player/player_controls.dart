import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// ✅ 播放器控制状态数据类
class PlayerControlsState {
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
  final VoidCallback onToggleControls;
  final IconData Function() getVideoFitIcon;
  final String Function() getVideoFitName;
  final String Function(Duration) formatTime;
  final String Function(double?) formatBitrate;
  final bool canIncreaseSpeed;
  final bool canDecreaseSpeed;
  final bool isLocked;
  final VoidCallback onToggleLock;
  final VoidCallback onRewind; // ✅ 快退10秒
  final VoidCallback onForward; // ✅ 快进20秒
  final bool isLongPressingForward; // ✅ 是否正在长按快进
  final bool isLongPressingRewind; // ✅ 是否正在长按快退
  final Offset? longPressPosition; // ✅ 长按位置（用于显示水波纹）
  final DateTime? longPressStartTime; // ✅ 长按开始时间（用于显示按住时长）
  final bool isAdjustingBrightness; // ✅ 是否正在调整亮度
  final bool isAdjustingVolume; // ✅ 是否正在调整音量
  final double? currentBrightness; // ✅ 当前亮度（0.0-1.0）
  final double? currentVolume; // ✅ 当前音量（0.0-100.0）

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
    required this.onToggleControls,
    required this.getVideoFitIcon,
    required this.getVideoFitName,
    required this.formatTime,
    required this.formatBitrate,
    required this.canIncreaseSpeed,
    required this.canDecreaseSpeed,
    required this.isLocked,
    required this.onToggleLock,
    required this.onRewind,
    required this.onForward,
    this.isLongPressingForward = false,
    this.isLongPressingRewind = false,
    this.longPressPosition,
    this.longPressStartTime,
    this.isAdjustingBrightness = false,
    this.isAdjustingVolume = false,
    this.currentBrightness,
    this.currentVolume,
  });
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
        // ✅ 空白区域点击检测层（最底层，当控制层显示时，用于隐藏控制层）
        // 使用 translucent 允许事件穿透到按钮，按钮会用 AbsorbPointer 吸收事件
        // 锁定状态下不响应点击隐藏
        if (!state.isInPipMode &&
            state.showControls &&
            !state.showSpeedList &&
            !state.isLocked)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // ✅ 点击空白区域隐藏控制层
                state.onToggleControls();
              },
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),

        // ✅ 锁定按钮（中间左侧，仅在显示控制层时显示）
        // PiP 模式下隐藏
        // 锁定时也会跟随控制栏自动隐藏，点击屏幕可以重新显示控制栏（只显示锁定按钮）
        if (!state.isInPipMode && state.showControls) _LockButton(state: state),

        // ✅ 顶部控制栏（淡入淡出动画）- 固定高度，不随状态栏变化
        // PiP 模式下隐藏，锁定状态下隐藏
        if (!state.isInPipMode && !state.isLocked)
          _TopControlsBar(state: state, context: context),

        // ✅ 拖动进度条时的时间预览（与顶部工具条水平对齐）
        // 长按快进/快退时也显示
        // 不受锁定状态影响，PiP 模式下隐藏
        if (!state.isInPipMode &&
            ((state.isDraggingProgress && state.draggingPosition != null) ||
                (state.isLongPressingForward || state.isLongPressingRewind)))
          _DraggingTimePreview(
            state: state,
            isLongPressing:
                state.isLongPressingForward || state.isLongPressingRewind,
          ),

        // ✅ 视频裁切模式提示（tooltip样式，显示在按钮下方）
        // PiP 模式下隐藏，锁定状态下隐藏
        if (!state.isInPipMode && !state.isLocked && state.showVideoFitHint)
          _VideoFitHint(state: state, context: context),

        // ✅ 快退和快进按钮（一进来就显示，缓冲时也显示）
        // PiP 模式下隐藏，锁定状态下隐藏
        if (!state.isInPipMode && state.showControls && !state.isLocked)
          _SeekButtons(state: state),

        // ✅ 中间播放/暂停按钮（一进来就显示，缓冲时也显示）
        // PiP 模式下隐藏，锁定状态下隐藏
        if (!state.isInPipMode && state.showControls && !state.isLocked)
          _PlayPauseButton(state: state),

        // ✅ 加载指示器（当播放/暂停按钮不显示时，在按钮位置显示 loading）
        // 不受锁定状态影响，PiP 模式下隐藏
        if (!state.isInPipMode &&
            !state.showControls &&
            (!state.ready ||
                state.isBuffering ||
                (state.ready && state.position == Duration.zero)))
          _LoadingIndicator(state: state),

        // ✅ 右侧速度控制（仅在显示控制栏时）
        // PiP 模式下隐藏，锁定状态下隐藏
        if (!state.isInPipMode && state.showControls && !state.isLocked)
          _SpeedControl(state: state, context: context),

        // ✅ 底部控制栏（淡入淡出动画）
        // PiP 模式下隐藏，锁定状态下隐藏
        if (!state.isInPipMode && !state.isLocked)
          _BottomControlsBar(state: state),

        // ✅ 缓冲信息（显示在播放/暂停按钮下方，放在最后确保在最上层，不被字幕遮挡）
        // 不受控制栏显示/隐藏影响，不受锁定状态影响，只要在加载/缓冲时就显示
        // PiP 模式下隐藏
        if (!state.isInPipMode &&
            (!state.ready ||
                state.isBuffering ||
                (state.ready && state.position == Duration.zero)))
          _BufferingInfo(state: state, context: context),

        // ✅ 水波纹效果（长按快进/快退时显示）
        if ((state.isLongPressingForward || state.isLongPressingRewind) &&
            state.longPressPosition != null)
          _RippleEffect(
            position: state.longPressPosition!,
            isRewind: state.isLongPressingRewind,
            startTime: state.longPressStartTime,
          ),

        // ✅ 速度档位列表（显示在左侧，放在最后确保在最上层）
        // 锁定状态下隐藏
        if (!state.isInPipMode &&
            state.showSpeedList &&
            state.showControls &&
            !state.isLocked)
          _SpeedList(state: state, context: context),

        // ✅ 亮度/音量调整提示（显示在屏幕中间，不受锁定影响）
        if (state.isAdjustingBrightness && state.currentBrightness != null)
          _BrightnessIndicator(brightness: state.currentBrightness!),
        if (state.isAdjustingVolume && state.currentVolume != null)
          _VolumeIndicator(volume: state.currentVolume!),
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
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1), // ✅ 从顶部滑下来
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: state.controlsAnimation,
              curve: Curves.easeOut,
            )),
            child: FadeTransition(
              opacity: state.controlsAnimation,
              child: IgnorePointer(
                ignoring: !state.showControls,
                child: Container(
                  // ✅ 顶部距离与底部控制条保持一致（都是20）
                  padding: const EdgeInsets.only(
                    top: 20, // ✅ 与底部控制条的bottom: 20保持一致
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
  const _DraggingTimePreview({
    required this.state,
    this.isLongPressing = false,
  });

  final PlayerControlsState state;
  final bool isLongPressing; // ✅ 是否是长按快进/快退

  @override
  Widget build(BuildContext context) {
    // ✅ 获取要显示的位置
    // 长按快进/快退时，位置会实时更新，直接使用当前位置
    // 拖动进度条时，使用拖动位置
    final displayPosition =
        isLongPressing ? state.position : state.draggingPosition!;

    return Positioned(
      top: 20, // ✅ 与顶部工具条对齐（top: 20）
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
                    '${state.formatTime(displayPosition)} / ${state.formatTime(state.duration)}',
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

/// ✅ 锁定按钮（中间左侧）
class _LockButton extends StatelessWidget {
  const _LockButton({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 48, // ✅ 往右移动，从 24 改为 48
      top: 0,
      bottom: 0,
      child: AnimatedBuilder(
        animation: state.controlsAnimation,
        builder: (context, child) {
          // ✅ 锁定状态下，不显示滑入动画，直接显示
          if (state.isLocked && !state.showControls) {
            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
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
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: CupertinoButton(
                      padding: const EdgeInsets.all(12),
                      onPressed: () {
                        state.onToggleLock();
                        state.onResetHideControlsTimer();
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
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
                          state.isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          key: ValueKey<bool>(state.isLocked),
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          // ✅ 非锁定状态，跟随控制栏动画
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0), // ✅ 从左侧滑进来
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: state.controlsAnimation,
              curve: Curves.easeOut,
            )),
            child: FadeTransition(
              opacity: state.controlsAnimation,
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
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(12),
                        onPressed: () {
                          state.onToggleLock();
                          state.onResetHideControlsTimer();
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
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
                            state.isLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            key: ValueKey<bool>(state.isLocked),
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
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

/// ✅ 快退和快进按钮（左右两侧）
class _SeekButtons extends StatelessWidget {
  const _SeekButtons({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: state.controlsAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: state.controlsAnimation.value * 0.9,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✅ 快退10秒按钮（左侧）
                _SeekButton(
                  icon: Icons.replay_rounded,
                  label: '10',
                  onPressed: state.onRewind,
                  animation: state.controlsAnimation,
                  isRewind: true, // ✅ 标识是快退按钮
                ),
                const SizedBox(width: 24),
                // ✅ 占位空间（播放/暂停按钮的位置）
                const SizedBox(width: 80),
                const SizedBox(width: 24),
                // ✅ 快进20秒按钮（右侧）
                _SeekButton(
                  icon: Icons.replay_rounded, // ✅ 使用 replay 图标，通过 Transform 翻转
                  label: '20',
                  onPressed: state.onForward,
                  animation: state.controlsAnimation,
                  isRewind: false, // ✅ 标识是快进按钮
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ✅ 中间播放/暂停按钮（包含缓冲指示器）
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    final isBuffering = !state.ready ||
        state.isBuffering ||
        (state.ready && state.position == Duration.zero);

    return Center(
      child: AnimatedBuilder(
        animation: state.controlsAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: state.controlsAnimation.value * 0.9,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // ✅ 播放/暂停按钮和环绕的缓冲指示器（固定在中心，位置不变）
                SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // ✅ 缓冲指示器（环绕播放/暂停按钮，紧贴按钮）
                      if (isBuffering)
                        SizedBox(
                          width: 90,
                          height: 90,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      // ✅ 播放/暂停按钮（始终在中心，位置不变）
                      GestureDetector(
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
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ✅ 加载指示器（显示在播放/暂停按钮位置，当按钮不显示时）
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.state});

  final PlayerControlsState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CupertinoActivityIndicator(
        radius: 20,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
  }
}

/// ✅ 缓冲信息（显示在播放/暂停按钮下方）
class _BufferingInfo extends StatelessWidget {
  const _BufferingInfo({required this.state, required this.context});

  final PlayerControlsState state;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: Offset(0, 90 / 2 + 36), // 按钮半径 + 间距
        child: ClipRRect(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    !state.ready
                        ? '加载中...'
                        : state.isBuffering
                            ? '缓冲中...'
                            : '准备中...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (state.expectedBitrateKbps != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      state.formatBitrate(state.currentSpeedKbps),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
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

/// ✅ 快退/快进按钮
class _SeekButton extends StatelessWidget {
  const _SeekButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.animation,
    required this.isRewind,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Animation<double> animation;
  final bool isRewind; // ✅ 是否是快退按钮

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
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
              borderRadius: BorderRadius.circular(28),
            ),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              onPressed: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ 快退时，数字在左侧
                  if (isRewind)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // ✅ 图标（快进时水平翻转）
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..scale(isRewind ? 1.0 : -1.0, 1.0), // ✅ 快进时水平翻转
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  // ✅ 快进时，数字在右侧
                  if (!isRewind)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0), // ✅ 从右侧滑进来
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: state.controlsAnimation,
              curve: Curves.easeOut,
            )),
            child: FadeTransition(
              opacity: state.controlsAnimation,
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
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1), // ✅ 从底部滑上来
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: state.controlsAnimation,
              curve: Curves.easeOut,
            )),
            child: FadeTransition(
              opacity: state.controlsAnimation,
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
          ),
        );
      },
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

/// ✅ 长按快进/快退UI效果（根据图片实现）
class _RippleEffect extends StatefulWidget {
  const _RippleEffect({
    required this.position,
    required this.isRewind,
    this.startTime,
  });

  final Offset position;
  final bool isRewind;
  final DateTime? startTime;

  @override
  State<_RippleEffect> createState() => _RippleEffectState();
}

class _RippleEffectState extends State<_RippleEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // ✅ 三个三角形循环动画，每个三角形亮起需要 400ms，总共 1200ms 一个循环
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // ✅ 定时更新按住时长显示
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // ✅ 计算快进/快退的秒数（按住时长 × 3倍速）
  int _getSeekedSeconds() {
    if (widget.startTime == null) return 0;
    final elapsed = DateTime.now().difference(widget.startTime!);
    // ✅ 3倍速：每1秒实际时间，视频快进/快退3秒
    return (elapsed.inMilliseconds * 3 / 1000).round();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // ✅ 快退时显示在左侧，快进时显示在右侧
    final isRightSide = !widget.isRewind;

    // ✅ 半圆半径：屏幕高度的一半（让半圆覆盖整个屏幕高度）
    final double radius = screenSize.height / 1.8;
    // ✅ 半圆中心位置（屏幕边缘，垂直居中）
    final double centerX =
        isRightSide ? screenSize.width * 0.76 : -screenSize.width * 0.5;
    final double centerY = screenSize.height / 11;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // ✅ 半圆背景（包含三角形和文字）
            Positioned(
              left: isRightSide ? centerX - radius : centerX,
              top: centerY - radius,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // ✅ 计算 CustomPaint 的偏移量
                  final paintOffsetX = isRightSide ? centerX - radius : centerX;
                  return CustomPaint(
                    size: Size(screenSize.width, screenSize.width / 1.1),
                    painter: _SemicirclePainter(
                      isRightSide: isRightSide,
                      animationValue: _controller.value,
                      seekedSeconds: _getSeekedSeconds(),
                      screenWidth: screenSize.width,
                      paintOffsetX: paintOffsetX,
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

/// ✅ 半圆绘制器（包含三个三角形的循环动画和文字）
class _SemicirclePainter extends CustomPainter {
  final bool isRightSide;
  final double animationValue;
  final int seekedSeconds; // ✅ 快进/快退的秒数
  final double screenWidth;
  final double paintOffsetX;

  _SemicirclePainter({
    required this.isRightSide,
    required this.animationValue,
    required this.seekedSeconds,
    required this.screenWidth,
    required this.paintOffsetX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ✅ 半透明白色背景
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // ✅ 绘制半圆
    final path = Path();
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    if (isRightSide) {
      // ✅ 开口朝右的半圆（左侧是直线，右侧是圆弧）
      // 从左上角开始，画直线到左下角，然后画圆弧从右上到右下
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      // 使用addArc：从顶部（90度）顺时针画180度到底部（270度）
      path.addArc(rect, 0.5 * 3.14159, 3.14159);
      path.close();
    } else {
      // ✅ 开口朝左的半圆（右侧是直线，左侧是圆弧）
      // 从右上角开始，画直线到右下角，然后画圆弧从左下到左上
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      // 使用addArc：从顶部（90度）逆时针画180度到底部（270度）
      path.addArc(rect, 0.5 * 3.14159, -3.14159);
      path.close();
    }

    canvas.drawPath(path, paint);

    // ✅ 绘制三个三角形（循环亮起）
    final centerY = size.height / 2;
    const triangleSize = 16.0;
    // ✅ 间距小于三角形宽度，让每个三角形压住前一个的角
    const triangleSpacing = triangleSize * 0.7; // 8.0，让三角形重叠
    // ✅ 三角形和文字的水平位置（将屏幕坐标转换为 CustomPaint 内部坐标）
    // 右侧：屏幕 x = screenWidth - 100（距离右边100位置）
    // 左侧：屏幕 x=100（距离左边100位置）
    final double screenX = isRightSide ? (screenWidth - 220.0) : 220.0;
    final double baseX = screenX - paintOffsetX;

    // ✅ 计算每个三角形的亮度（0.0-1.0）
    double getTriangleBrightness(int index) {
      // 每个三角形亮起的时间段：0-400ms, 400-800ms, 800-1200ms
      final phase = (animationValue * 3 + index * (1.0 / 3)) % 1.0;
      // 每个三角形在 400ms 内从暗到亮再到暗
      if (phase < 0.33) {
        return phase * 3.0; // 0.0 -> 1.0
      } else if (phase < 0.67) {
        return 1.0 - (phase - 0.33) * 3.0; // 1.0 -> 0.0
      } else {
        return 0.0; // ✅ 完全暗，不显示
      }
    }

    // ✅ 绘制三个三角形（后一个压前一个）
    for (int i = 0; i < 3; i++) {
      final brightness = getTriangleBrightness(i);
      // ✅ 如果亮度为0，完全不显示（alpha = 0）
      if (brightness <= 0.0) continue;

      final trianglePaint = Paint()
        ..color = Colors.white.withValues(alpha: brightness)
        ..style = PaintingStyle.fill;

      // ✅ 计算三角形位置（后一个压前一个：i=0在最左，i=1在中间压i=0，i=2在最右压i=1）
      final offsetX = isRightSide
          ? baseX + i * triangleSpacing // 向右：从左到右排列
          : baseX - i * triangleSpacing; // 向左：从右到左排列
      final offsetY = centerY - 12; // ✅ 向上偏移，为文字留出空间

      // ✅ 绘制三角形（向右或向左）
      final trianglePath = Path();
      if (isRightSide) {
        // ✅ 向右的三角形
        trianglePath.moveTo(offsetX, offsetY - triangleSize / 2);
        trianglePath.lineTo(offsetX + triangleSize, offsetY);
        trianglePath.lineTo(offsetX, offsetY + triangleSize / 2);
      } else {
        // ✅ 向左的三角形
        trianglePath.moveTo(offsetX, offsetY - triangleSize / 2);
        trianglePath.lineTo(offsetX - triangleSize, offsetY);
        trianglePath.lineTo(offsetX, offsetY + triangleSize / 2);
      }
      trianglePath.close();

      canvas.drawPath(trianglePath, trianglePaint);
    }

    // ✅ 绘制快进/快退秒数文字（半圆内部下方）
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${seekedSeconds}秒',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: Colors.black54,
              blurRadius: 8,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();

    // ✅ 文字位置：与三角形对齐，在三角形下方
    // ✅ 左边文字再靠左一点，右边文字再靠右一点
    const textOffset = 20.0; // ✅ 文字偏移量
    final textX = isRightSide
        ? baseX - textPainter.width / 2 + textOffset // ✅ 右边：向右偏移
        : baseX - textPainter.width / 2 - textOffset; // ✅ 左边：向左偏移
    final textY = centerY + 10; // ✅ 在三角形下方

    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant _SemicirclePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isRightSide != isRightSide ||
        oldDelegate.seekedSeconds != seekedSeconds;
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

/// ✅ 亮度调整指示器
class _BrightnessIndicator extends StatelessWidget {
  const _BrightnessIndicator({required this.brightness});

  final double brightness; // ✅ 0.0-1.0

  @override
  Widget build(BuildContext context) {
    final brightnessPercent = (brightness * 100).round();

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.brightness_6_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  '$brightnessPercent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ 音量调整指示器
class _VolumeIndicator extends StatelessWidget {
  const _VolumeIndicator({required this.volume});

  final double volume; // ✅ 0.0-100.0

  @override
  Widget build(BuildContext context) {
    final volumePercent = volume.round();

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  volumePercent == 0
                      ? Icons.volume_off_rounded
                      : volumePercent < 50
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  '$volumePercent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
