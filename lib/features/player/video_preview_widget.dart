import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'exoplayer_texture_controller.dart';

/// ✅ 视频预览组件
/// 在拖动进度条时显示预览画面
///
/// 实现方案：
/// 1. 使用 MediaMetadataRetriever 在原生层提取指定位置的视频帧
/// 2. 将帧作为图片显示在预览窗口中
/// 3. 使用节流机制避免频繁提取帧
class VideoPreviewWidget extends StatefulWidget {
  const VideoPreviewWidget({
    required this.player,
    required this.previewPosition,
    required this.duration,
    required this.formatTime,
    super.key,
  });

  final ExoPlayerTextureController player;
  final Duration previewPosition;
  final Duration duration;
  final String Function(Duration) formatTime;

  @override
  State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  Timer? _frameDebounceTimer;
  Timer? _loadingIndicatorTimer;
  Uint8List? _currentFrameBytes;
  bool _isLoadingFrame = false;
  bool _showLoadingIndicator = false; // ✅ 控制是否显示加载指示器
  Duration? _pendingPosition; // ✅ 记录待加载的位置
  Duration? _lastLoadedPosition; // ✅ 记录上次加载的位置
  Duration? _lastRequestPosition; // ✅ 记录上次请求的位置（用于判断是否真的移动了）

  // ✅ 位置变化阈值（毫秒）：小于此值视为没有移动
  static const int _positionChangeThreshold = 60000; // 60秒

  @override
  void initState() {
    super.initState();
    _lastRequestPosition = widget.previewPosition;
    _loadFrameAtPosition(widget.previewPosition);
  }

  @override
  void didUpdateWidget(VideoPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ 当预览位置变化时，使用节流机制加载新帧
    if (widget.previewPosition != oldWidget.previewPosition) {
      _scheduleFrameLoad(widget.previewPosition);
    }
  }

  @override
  void dispose() {
    _frameDebounceTimer?.cancel();
    _loadingIndicatorTimer?.cancel();
    super.dispose();
  }

  /// ✅ 节流加载帧（避免过于频繁的请求）
  void _scheduleFrameLoad(Duration position) {
    // ✅ 记录最新的待加载位置
    _pendingPosition = position;

    // ✅ 取消之前的定时器
    _frameDebounceTimer?.cancel();

    // ✅ 如果正在加载，等待加载完成后会自动处理 _pendingPosition
    if (_isLoadingFrame) {
      // ✅ 检查位置变化是否足够大，如果变化大才显示加载指示器
      final diff = _lastLoadedPosition != null
          ? (position.inMilliseconds - _lastLoadedPosition!.inMilliseconds)
              .abs()
          : _positionChangeThreshold + 1;

      if (diff >= _positionChangeThreshold) {
        _showLoadingIndicatorImmediately();
      }
      return;
    }

    // ✅ 检查位置变化是否足够大（与上次请求位置比较）
    final lastRequest = _lastRequestPosition;
    final diff = lastRequest != null
        ? (position.inMilliseconds - lastRequest.inMilliseconds).abs()
        : _positionChangeThreshold + 1;

    // ✅ 如果位置变化超过阈值，立即加载（不等待节流）
    if (diff >= _positionChangeThreshold) {
      _lastRequestPosition = position;
      _loadFrameAtPosition(position);
      return;
    }

    // ✅ 位置变化不够大，使用节流等待（可能是用户在微调）
    _frameDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_pendingPosition != null) {
        // ✅ 再次检查位置是否变化了
        final lastRequest = _lastRequestPosition;
        final diff = lastRequest != null
            ? (_pendingPosition!.inMilliseconds - lastRequest.inMilliseconds)
                .abs()
            : _positionChangeThreshold + 1;

        // ✅ 只有位置变化超过阈值时才加载
        if (diff >= _positionChangeThreshold) {
          _lastRequestPosition = _pendingPosition;
          _loadFrameAtPosition(_pendingPosition!);
        } else {
          // ✅ 位置变化太小，清除待加载位置
          _pendingPosition = null;
        }
      }
    });
  }

  /// ✅ 立即显示加载指示器（当有新的待加载位置时）
  void _showLoadingIndicatorImmediately() {
    if (!_showLoadingIndicator && mounted) {
      setState(() {
        _showLoadingIndicator = true;
      });
    }
  }

  /// ✅ 延迟显示加载指示器（避免闪烁）
  void _scheduleLoadingIndicator() {
    _loadingIndicatorTimer?.cancel();
    // ✅ 如果 150ms 后还在加载，才显示加载指示器
    _loadingIndicatorTimer = Timer(const Duration(milliseconds: 150), () {
      if (_isLoadingFrame && mounted) {
        setState(() {
          _showLoadingIndicator = true;
        });
      }
    });
  }

  /// ✅ 加载指定位置的视频帧
  Future<void> _loadFrameAtPosition(Duration position) async {
    if (_isLoadingFrame) return;

    // ✅ 避免重复加载相同位置（使用阈值判断）
    if (_lastLoadedPosition != null) {
      final diff =
          (position.inMilliseconds - _lastLoadedPosition!.inMilliseconds).abs();
      if (diff < _positionChangeThreshold) {
        _pendingPosition = null;
        return;
      }
    }

    setState(() {
      _isLoadingFrame = true;
    });

    // ✅ 延迟显示加载指示器，避免快速加载时的闪烁
    _scheduleLoadingIndicator();

    try {
      final frameBytes = await widget.player.getFrameAtPosition(position);
      if (mounted && frameBytes != null) {
        setState(() {
          _currentFrameBytes = frameBytes;
          _lastLoadedPosition = position;
          _isLoadingFrame = false;
          _showLoadingIndicator = false;
        });
        _loadingIndicatorTimer?.cancel();
      } else {
        if (mounted) {
          setState(() {
            _isLoadingFrame = false;
            _showLoadingIndicator = false;
          });
          _loadingIndicatorTimer?.cancel();
        }
      }
    } catch (e) {
      print('❌ [PreviewWidget] Failed to load frame: $e');
      if (mounted) {
        setState(() {
          _isLoadingFrame = false;
          _showLoadingIndicator = false;
        });
        _loadingIndicatorTimer?.cancel();
      }
    }

    // ✅ 加载完成后，检查是否有新的待加载位置
    if (mounted && _pendingPosition != null) {
      final pending = _pendingPosition!;

      // ✅ 检查待加载位置与刚加载的位置是否有足够差异
      final diff = (pending.inMilliseconds - position.inMilliseconds).abs();
      if (diff >= _positionChangeThreshold) {
        // ✅ 更新请求位置并清除待加载位置
        _lastRequestPosition = pending;
        _pendingPosition = null;

        // ✅ 短暂延迟后加载新位置
        _frameDebounceTimer?.cancel();
        _frameDebounceTimer = Timer(const Duration(milliseconds: 100), () {
          _loadFrameAtPosition(pending);
        });
      } else {
        // ✅ 位置变化不够大，清除待加载位置
        _pendingPosition = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 计算预览窗口的位置（跟随滑块）
    final progress = widget.duration.inMilliseconds > 0
        ? widget.previewPosition.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;
    final clampedProgress = progress.clamp(0.0, 1.0);

    // ✅ 预览窗口尺寸（只显示画面，不显示时间）
    const previewWidth = 160.0;
    const previewHeight = 90.0;
    const previewRadius = 8.0;
    const bottomMargin = 70.0; // 距离进度条的距离

    // ✅ 精确计算实际进度条的布局
    // 参考 player_controls.dart 的 _BottomControlsBar 布局：
    // 外层 padding: 16 (左右)
    // 内层 Container padding: 16 (左右)
    // 时间显示: 65 + 分隔符 + 65 = 约 140px
    // SizedBox: 12px
    // Slider 内部 padding: 24 (左右，用于缓冲条显示)
    final screenWidth = MediaQuery.of(context).size.width;
    const outerPadding = 16.0;
    const innerPadding = 16.0;
    const timeWidth = 140.0; // 65 + 分隔符 + 65
    const spacer = 12.0;
    const sliderInternalPadding = 24.0; // Slider 内部的 padding

    // Slider 实际可拖动区域的左边距
    final sliderLeft = outerPadding +
        innerPadding +
        timeWidth +
        spacer +
        sliderInternalPadding;

    // Slider 实际可拖动区域的宽度（需要减去右侧的按钮和padding）
    // 右侧：字幕按钮(40) + 音频按钮(40) + spacer(12) + innerPadding(16) + outerPadding(16) + sliderInternalPadding(24)
    const rightButtons = 40.0 + 40.0; // 字幕 + 音频按钮
    const sliderRight =
        spacer + innerPadding + outerPadding + sliderInternalPadding;
    final sliderWidth = screenWidth - sliderLeft - rightButtons - sliderRight;

    // ✅ 计算预览窗口的水平位置（居中对齐滑块，然后向右偏移）
    final centerX = sliderLeft + (sliderWidth * clampedProgress);
    const horizontalOffset = 10.0; // ✅ 向右偏移 20px
    var previewLeft = centerX - (previewWidth / 2) + horizontalOffset;

    // ✅ 边界检查，防止预览窗口超出屏幕
    const horizontalPadding = 16.0;
    if (previewLeft < horizontalPadding) {
      previewLeft = horizontalPadding;
    } else if (previewLeft + previewWidth > screenWidth - horizontalPadding) {
      previewLeft = screenWidth - horizontalPadding - previewWidth;
    }

    return Positioned(
      left: previewLeft,
      bottom: bottomMargin,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 150),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: 0.8 + (0.2 * value),
              child: child,
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(previewRadius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: previewWidth,
              height: previewHeight,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(previewRadius),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(previewRadius - 1),
                child: Container(
                  color: Colors.black,
                  child: _showLoadingIndicator
                      ? Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white.withOpacity(0.9),
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : (_currentFrameBytes != null
                          ? Image.memory(
                              _currentFrameBytes!,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                            )
                          : Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.white.withOpacity(0.3),
                                size: 32,
                              ),
                            )),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
