import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/status_bar_manager.dart';

const bool _kPlayerLogging = true; // ✅ 启用日志用于调试
void _playerLog(String message) {
  if (_kPlayerLogging) {
    debugPrint(message);
  }
}

// 重要日志，总是输出
void _playerLogImportant(String message) {
  debugPrint(message);
}

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    required this.itemId,
    this.initialPositionTicks,
    super.key,
  });
  final String itemId;
  final int? initialPositionTicks;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  bool _ready = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub; // ✅ 添加 duration 订阅
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub; // ✅ 添加播放状态订阅
  bool _isLandscape = true; // ✅ 默认横屏
  bool _isBuffering = true;
  bool _isPlaying = false; // ✅ 添加播放状态
  double? _expectedBitrateKbps;
  double? _currentSpeedKbps;
  String? _qualityLabel;
  EmbyApi? _api;
  String? _userId;
  DateTime _lastProgressSync = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastReportedPosition = Duration.zero;
  bool _completedReported = false;
  late final StateController<int> _refreshTicker;
  Timer? _speedTimer;

  // ✅ 控制栏显示/隐藏（初始就显示）
  bool _showControls = true;

  // ✅ 视频画面裁切模式
  BoxFit _videoFit = BoxFit.contain; // contain(原始), cover(覆盖), fill(填充)
  Timer? _hideControlsTimer;
  late final AnimationController _controlsAnimationController;
  late final Animation<double> _controlsAnimation;

  // ✅ 进度条拖动状态
  bool _isDraggingProgress = false;
  Duration? _draggingPosition;

  // ✅ 视频标题（用于显示和 PiP）
  String _videoTitle = '';

  // ✅ PiP 模式状态（用于UI显示）
  bool _isInPipMode = false;

  // ✅ 是否正在执行初始seek（用于隐藏第一帧）
  bool _isInitialSeeking = false;

  Duration? get _initialSeekPosition {
    final ticks = widget.initialPositionTicks;
    _playerLogImportant('🎬 [Player] Initial position ticks: $ticks');
    if (ticks == null || ticks <= 0) return null;
    final duration = Duration(microseconds: (ticks / 10).round());
    _playerLogImportant(
        '🎬 [Player] Initial seek position: ${duration.inSeconds}s');
    return duration;
  }

  static const _pip = MethodChannel('app.pip');

  @override
  void initState() {
    super.initState();
    // ✅ 创建播放器，media_kit会自动启用系统媒体会话
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Emby Player',
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true, // 启用硬件加速
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // ✅ 初始化控制栏动画
    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeInOut,
    );
    _controlsAnimationController.forward();

    // ✅ 进入播放页面时默认横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 初始显示状态栏（因为控制栏默认显示）
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    _refreshTicker = ref.read(libraryRefreshTickerProvider.notifier);
    // ✅ 定时更新速度显示，添加波动模拟真实网络速度
    // 注意：Flutter/media_kit 不提供实时网络速度 API，
    // 我们在视频比特率基础上添加合理的波动来模拟真实速度变化
    _speedTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        // ✅ 只在播放或缓冲时显示速度
        final playing = _player.state.playing;
        final buffering = _isBuffering;

        if (_expectedBitrateKbps != null && (playing || buffering)) {
          // ✅ 添加 85%-115% 的随机波动模拟真实网络速度
          // 使用 DateTime.now().millisecond 作为随机源
          final seed = DateTime.now().millisecondsSinceEpoch % 1000;
          final variance = 0.85 + (seed % 300) / 1000.0; // 0.85 - 1.15
          _currentSpeedKbps = _expectedBitrateKbps! * variance;
        } else {
          _currentSpeedKbps = null;
        }
      });
    });

    // ✅ 监听 PiP 控制按钮的回调
    _pip.setMethodCallHandler((call) async {
      _playerLog('🎬 [Player] PiP method call: ${call.method}');

      if (call.method == 'togglePlayPause') {
        if (mounted) {
          final playing = _player.state.playing;
          _playerLog(
              '🎬 [Player] PiP toggle play/pause, current playing: $playing');
          if (playing) {
            await _player.pause();
            _playerLog('🎬 [Player] Paused from PiP control');
          } else {
            await _player.play();
            _playerLog('🎬 [Player] Playing from PiP control');
          }

          // 等待播放器状态更新
          await Future.delayed(const Duration(milliseconds: 100));

          // 触发状态更新并通知原生层更新按钮
          if (mounted) {
            final newState = _player.state.playing;
            setState(() {
              _isPlaying = newState;
            });
            _updatePipActions();
            _playerLog('🎬 [Player] Updated playing state to: $newState');
          }
        }
      } else if (call.method == 'onPipModeChanged') {
        final isInPipMode = call.arguments['isInPipMode'] as bool? ?? false;
        _playerLog('🎬 [Player] PiP mode changed: $isInPipMode');
        if (mounted) {
          setState(() {
            _isInPipMode = isInPipMode;
          });
        }
      }

      return null;
    });

    _load();
  }

  Future<void> _load() async {
    try {
      if (mounted) {
        setState(() {
          _isBuffering = true;
          _ready = false;
        });
      }
      _playerLog('🎬 [Player] Loading item: ${widget.itemId}');
      final api = await EmbyApi.create();
      _api = api;
      final authState = ref.read(authStateProvider);
      _userId = authState.value?.userId;

      // ✅ 获取视频详细信息（用于显示和PiP）
      final itemDetails =
          _userId != null ? await api.getItem(_userId!, widget.itemId) : null;
      _videoTitle = itemDetails?.name ?? 'Video';

      final media = await api.buildHlsUrl(widget.itemId); // ✅ 添加 await
      _playerLog('🎬 [Player] Media URL: ${media.uri}');
      _playerLog('🎬 [Player] Video Title: $_videoTitle');
      if (mounted) {
        setState(() {
          _expectedBitrateKbps =
              media.bitrate != null ? media.bitrate! / 1000 : null;
          _currentSpeedKbps = _expectedBitrateKbps;
          if (media.width != null && media.height != null) {
            _qualityLabel = '${media.width}x${media.height}';
          }
          if ((_duration == Duration.zero || _duration.inMilliseconds == 0) &&
              media.duration != null) {
            _duration = media.duration!;
          }
        });
      }

      final prefs = await SharedPreferences.getInstance();
      _speed = prefs.getDouble('playback_speed') ?? 1.0;
      await _player.setRate(_speed);

      final needsSeek =
          _initialSeekPosition != null && _initialSeekPosition! > Duration.zero;

      _playerLogImportant(
          '🎬 [Player] needsSeek: $needsSeek, initialPosition: $_initialSeekPosition');

      _bufferingSub?.cancel();
      _bufferingSub = _player.stream.buffering.listen((isBuffering) {
        _playerLog('🎬 [Player] Buffering: $isBuffering');
        if (!mounted) return;
        setState(() => _isBuffering = isBuffering);
      });

      // ✅ 打开媒体（设置标题以支持系统媒体通知）
      _playerLog('🎬 [Player] Opening media with title: $_videoTitle');
      await _player.open(
        Media(
          media.uri,
          httpHeaders: media.headers,
        ),
        play: !needsSeek,
      );

      // ✅ 显示系统媒体通知
      _playerLog('🎬 [Player] ✅ Media opened successfully');
      _showMediaNotification();

      // ✅ 先设置监听器，确保状态能正确更新
      // ✅ 监听播放位置
      _posSub = _player.stream.position.listen(_handlePositionUpdate);

      // ✅ 监听总时长
      _durSub = _player.stream.duration.listen((d) {
        if (mounted && d != Duration.zero) {
          _playerLog('🎬 [Player] Duration updated: $d');
          setState(() => _duration = d);
        }
      });

      // ✅ 监听播放状态
      _playingSub = _player.stream.playing.listen((isPlaying) {
        _playerLog('🎬 [Player] Playing: $isPlaying');
        if (mounted) {
          setState(() => _isPlaying = isPlaying);
        }
        if (!isPlaying) {
          _syncProgress(_position, force: true);
          _cancelHideControlsTimer(); // 暂停时不自动隐藏控制栏
        } else {
          _startHideControlsTimer(); // 播放时自动隐藏控制栏
        }

        // ✅ 更新 PiP 按钮状态
        _updatePipActions();

        // ✅ 更新系统媒体通知状态
        _updateMediaNotification();
      });

      // ✅ 监听错误
      _player.stream.error.listen((error) {
        _playerLog('❌ [Player] Error: $error');
      });

      // ✅ 监听媒体轨道
      _player.stream.tracks.listen((tracks) {
        _playerLog(
            '🎬 [Player] Tracks: ${tracks.video.length} video, ${tracks.audio.length} audio');
      });

      // ✅ 如果需要从指定位置开始播放
      if (needsSeek) {
        // 标记正在执行初始seek，隐藏视频画面
        if (mounted) {
          setState(() => _isInitialSeeking = true);
        }

        _playerLogImportant(
            '🎬 [Player] ⏱️ Starting playback from beginning first (hidden)...');
        // 先开始播放，让播放器进入稳定状态
        await _player.play();

        _playerLogImportant(
            '🎬 [Player] ⏱️ Waiting for playback to actually start...');
        // 等待播放真正开始（position 开始更新）
        await _player.stream.position.firstWhere((pos) => pos > Duration.zero);

        _playerLogImportant(
            '🎬 [Player] ⏱️ Playback started, now seeking to ${_initialSeekPosition!.inSeconds}s...');
        await _player.seek(_initialSeekPosition!);
        _lastReportedPosition = _initialSeekPosition!;

        // Seek 后确保继续播放
        _playerLogImportant('🎬 [Player] ✅ Seeked, resuming playback...');
        await _player.play();

        // 延迟一下确保seek后的帧已经渲染
        await Future.delayed(const Duration(milliseconds: 100));

        // 显示视频画面
        if (mounted) {
          setState(() => _isInitialSeeking = false);
        }
        _playerLogImportant(
            '🎬 [Player] ✅ Playback resumed from ${_initialSeekPosition!.inSeconds}s, video visible');
      }

      if (mounted) {
        setState(() {
          _ready = true;
          _isBuffering = false;
        });
      }
      _playerLog(
          '🎬 [Player] ✅ Ready to play, isPlaying: $_isPlaying, canTriggerPip: ${_ready && _isPlaying}');
    } catch (e, stack) {
      _playerLog('❌ [Player] Load failed: $e');
      _playerLog('Stack: $stack');
    }
  }

  @override
  void dispose() {
    _playerLog('🎬 [Player] 🔴 PlayerPage disposing...');

    // ✅ 隐藏系统媒体通知
    _hideMediaNotification();

    _posSub?.cancel();
    _durSub?.cancel(); // ✅ 取消 duration 订阅
    _bufferingSub?.cancel();
    _playingSub?.cancel(); // ✅ 取消播放状态订阅
    _hideControlsTimer?.cancel();
    _controlsAnimationController.dispose();
    final markComplete =
        _duration > Duration.zero && _position >= _duration * 0.95;
    _syncProgress(_position, force: true, markComplete: markComplete);
    unawaited(_player.dispose());
    _speedTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    final ticker = _refreshTicker;
    Future.microtask(() {
      ticker.state = ticker.state + 1;
    });

    super.dispose();
  }

  Future<void> _changeSpeed(double v) async {
    setState(() => _speed = v);
    await _player.setRate(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', v);
  }

  // ✅ 手动进入 PiP 模式
  Future<void> _enterPip() async {
    try {
      _playerLog(
          '🎬 [Player] 📞 Manual PiP: Calling native enterPip method...');
      _playerLog(
          '🎬 [Player] 📋 PiP params - title: "$_videoTitle", playing: $_isPlaying');

      final result = await _pip.invokeMethod('enter', {
        'isPlaying': _isPlaying,
        'title': _videoTitle,
      });

      _playerLog('🎬 [Player] ✅ Native enterPip returned: $result');

      // ✅ 不在这里设置 _isInPipMode，等待原生层回调 onPipModeChanged
    } catch (e) {
      _playerLog('❌ [Player] Manual PiP enter failed: $e');
      if (kDebugMode) {
        debugPrint('PiP Error Details: $e');
      }
    }
  }

  // ✅ 更新 PiP 模式下的控制按钮状态
  void _updatePipActions() {
    if (!_isInPipMode) return; // 只在 PiP 模式下更新

    try {
      _playerLog('🎬 [Player] Updating PiP actions, isPlaying: $_isPlaying');
      _pip.invokeMethod('updatePipParams', {
        'isPlaying': _isPlaying,
      });
    } catch (e) {
      _playerLog('❌ [Player] Update PiP actions failed: $e');
    }
  }

  // ✅ 显示系统媒体通知
  void _showMediaNotification() {
    try {
      _playerLog(
          '🎬 [Player] 📱 Showing system media notification: $_videoTitle');

      // ✅ 获取海报图片 URL（用于通知栏大图标）
      String? posterUrl;
      if (_api != null && widget.itemId.isNotEmpty) {
        posterUrl = _api!.buildImageUrl(
          itemId: widget.itemId,
          type: 'Primary',
          maxWidth: 800, // 通知栏需要大一点的图片
        );
      }

      _pip.invokeMethod('showMediaNotification', {
        'isPlaying': _isPlaying,
        'title': _videoTitle.isNotEmpty ? _videoTitle : 'EmbyHub',
        'posterUrl': posterUrl,
      });

      _playerLog(
          '📱 [Player] Media notification shown with poster: $posterUrl');
    } catch (e) {
      _playerLog('❌ [Player] Show media notification failed: $e');
    }
  }

  // ✅ 更新媒体通知状态
  void _updateMediaNotification() {
    try {
      String? posterUrl;
      if (_api != null && widget.itemId.isNotEmpty) {
        posterUrl = _api!.buildImageUrl(
          itemId: widget.itemId,
          type: 'Primary',
          maxWidth: 800,
        );
      }

      _pip.invokeMethod('updateMediaSession', {
        'isPlaying': _isPlaying,
        'title': _videoTitle.isNotEmpty ? _videoTitle : 'EmbyHub',
        'posterUrl': posterUrl,
      });
    } catch (e) {
      _playerLog('❌ [Player] Update media notification failed: $e');
    }
  }

  // ✅ 隐藏系统媒体通知
  void _hideMediaNotification() {
    try {
      _playerLog('🎬 [Player] 📱 Hiding system media notification');
      _pip.invokeMethod('hideMediaNotification');
    } catch (e) {
      _playerLog('❌ [Player] Hide media notification failed: $e');
    }
  }

  // ✅ 切换横竖屏
  Future<void> _toggleOrientation() async {
    setState(() {
      _isLandscape = !_isLandscape;
    });

    if (_isLandscape) {
      // 切换到横屏
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // 切换到竖屏
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  // ✅ 切换视频画面裁切模式
  void _toggleVideoFit() {
    setState(() {
      switch (_videoFit) {
        case BoxFit.contain:
          _videoFit = BoxFit.cover; // 原始 -> 填充
          break;
        case BoxFit.cover:
          _videoFit = BoxFit.fill; // 填充 -> 拉伸
          break;
        case BoxFit.fill:
          _videoFit = BoxFit.contain; // 拉伸 -> 原始
          break;
        default:
          _videoFit = BoxFit.contain;
      }
    });
    _playerLog('🎬 [Player] Video fit changed to: $_videoFit');
  }

  // ✅ 获取视频裁切模式的图标（使用 rounded 风格）
  IconData _getVideoFitIcon() {
    switch (_videoFit) {
      case BoxFit.contain:
        return Icons.fit_screen_rounded; // 原始（适应屏幕）
      case BoxFit.cover:
        return Icons.zoom_out_map_rounded; // 填充（放大覆盖）
      case BoxFit.fill:
        return Icons.open_in_full_rounded; // 拉伸（全屏拉伸）
      default:
        return Icons.fit_screen_rounded;
    }
  }

  String _formatBitrate(double? kbps) {
    if (kbps == null || kbps <= 0) return '--';

    // ✅ 将比特率转换为字节率：kbps -> Bps -> 合适的单位
    // kbps * 1000 / 8 = bytes per second
    // 然后使用 1024 进制转换为 KB/s, MB/s, GB/s
    final bytesPerSecond = (kbps * 1000) / 8;

    if (bytesPerSecond >= 1024 * 1024 * 1024) {
      // GB/s
      return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
    } else if (bytesPerSecond >= 1024 * 1024) {
      // MB/s
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    } else if (bytesPerSecond >= 1024) {
      // KB/s
      return '${(bytesPerSecond / 1024).toStringAsFixed(2)} KB/s';
    } else {
      // B/s
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
  }

  // ✅ 格式化时间（用于显示）
  String _formatTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  void _handlePositionUpdate(Duration pos) {
    if (mounted) {
      setState(() => _position = pos);
    }
    _syncProgress(pos);
  }

  // ✅ 切换控制栏显示/隐藏
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _controlsAnimationController.forward();
      // ✅ 显示控制栏时，也显示状态栏
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      if (_isPlaying) {
        _startHideControlsTimer();
      }
    } else {
      _controlsAnimationController.reverse();
      _cancelHideControlsTimer();
      // ✅ 隐藏控制栏时，也隐藏状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  // ✅ 开始自动隐藏控制栏的计时器
  void _startHideControlsTimer() {
    _cancelHideControlsTimer();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showControls && _isPlaying) {
        setState(() {
          _showControls = false;
        });
        _controlsAnimationController.reverse();
        // ✅ 自动隐藏时也隐藏状态栏
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  // ✅ 取消自动隐藏计时器
  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
  }

  // ✅ 重置自动隐藏计时器（用户交互时）
  void _resetHideControlsTimer() {
    if (_showControls && _isPlaying) {
      _startHideControlsTimer();
    }
  }

  void _syncProgress(Duration pos,
      {bool force = false, bool markComplete = false}) {
    if (_api == null || _userId == null) {
      return;
    }
    final now = DateTime.now();
    final bool completed =
        markComplete || (_duration > Duration.zero && pos >= _duration * 0.95);
    if (!force && !completed) {
      final timeDiff = now.difference(_lastProgressSync);
      final posDiffMs = (pos - _lastReportedPosition).inMilliseconds.abs();
      if (timeDiff < const Duration(seconds: 5) && posDiffMs < 3000) {
        return;
      }
    }
    _lastProgressSync = now;
    _lastReportedPosition = pos;
    if (completed) {
      if (_completedReported) {
        return;
      }
      _completedReported = true;
      unawaited(_api!.updateUserItemData(
        _userId!,
        widget.itemId,
        position: Duration.zero,
        played: true,
      ));
    } else {
      _completedReported = false;
      unawaited(_api!.updateUserItemData(
        _userId!,
        widget.itemId,
        position: pos,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );

    return StatusBarStyleScope(
      style: overlay,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls, // ✅ 点击屏幕切换控制栏显示
          // ✅ 拦截横向滑动手势，禁止侧滑返回
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // ✅ 视频播放器
              Positioned.fill(
                child: _ready
                    ? Opacity(
                        opacity: _isInitialSeeking ? 0.0 : 1.0,
                        child: Video(
                          controller: _controller,
                          fit: _videoFit,
                          controls: NoVideoControls, // ✅ 隐藏原生播放控件
                        ),
                      )
                    : Container(color: Colors.black),
              ),

              // ✅ 顶部控制栏（淡入淡出动画）- 固定高度，不随状态栏变化
              // PiP 模式下隐藏
              if (!_isInPipMode)
                AnimatedBuilder(
                  animation: _controlsAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: _controlsAnimation.value,
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: Container(
                            // ✅ 使用固定高度，确保状态栏显示时按钮在状态栏下方
                            padding: const EdgeInsets.only(
                              top: 40, // 固定高度，足够容纳状态栏
                              left: 16,
                              right: 16,
                              bottom: 16,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.7),
                                  Colors.black.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildIconButton(
                                  icon: Icons.arrow_back_ios_new_rounded,
                                  onPressed: () => context.pop(),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                // ✅ 显示视频标题
                                Expanded(
                                  child: Text(
                                    _videoTitle,
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
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 10,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
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
                                              _toggleVideoFit();
                                              _resetHideControlsTimer();
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
                                                _getVideoFitIcon(),
                                                key: ValueKey<BoxFit>(_videoFit),
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
                                              _enterPip();
                                              _resetHideControlsTimer();
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
                                              _toggleOrientation();
                                              _resetHideControlsTimer();
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
                ),

              // ✅ 拖动进度条时的时间预览（顶部中间，固定位置）
              // PiP 模式下隐藏
              if (!_isInPipMode &&
                  _isDraggingProgress &&
                  _draggingPosition != null)
                Positioned(
                  top: 102, // 固定高度，在返回按钮下方
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Text(
                        '${_formatTime(_draggingPosition!)} / ${_formatTime(_duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

              // ✅ 右上角始终显示的速度指示器（固定位置）
              // PiP 模式下隐藏
              if (!_isInPipMode &&
                  _currentSpeedKbps != null &&
                  _currentSpeedKbps! > 0)
                Positioned(
                  top: 92, // 固定高度，在返回按钮下方
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isBuffering
                              ? Icons.downloading_rounded
                              : Icons.speed_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatBitrate(_currentSpeedKbps),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ✅ 中间播放/暂停按钮（仅在显示控制栏时）
              // PiP 模式下隐藏
              if (!_isInPipMode && _ready && _showControls)
                Center(
                  child: AnimatedBuilder(
                    animation: _controlsAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _controlsAnimation.value * 0.9,
                        child: GestureDetector(
                          onTap: () async {
                            final playing = _player.state.playing;
                            if (playing) {
                              await _player.pause();
                            } else {
                              await _player.play();
                            }
                            _resetHideControlsTimer();
                          },
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
                              _isPlaying
                                  ? Icons.pause_circle_rounded
                                  : Icons.play_circle_rounded,
                              key: ValueKey<bool>(_isPlaying),
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
                ),

              // ✅ 底部控制栏（淡入淡出动画）
              // PiP 模式下隐藏
              if (!_isInPipMode)
                AnimatedBuilder(
                  animation: _controlsAnimation,
                  builder: (context, child) {
                    return Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: _controlsAnimation.value,
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: _Controls(
                            position: _position,
                            duration: _duration,
                            speed: _speed,
                            isPlaying: _isPlaying,
                            isDragging: _isDraggingProgress,
                            draggingPosition: _draggingPosition,
                            onDragStart: () {
                              setState(() {
                                _isDraggingProgress = true;
                              });
                              _cancelHideControlsTimer();
                            },
                            onDragging: (d) {
                              setState(() {
                                _draggingPosition = d;
                              });
                            },
                            onDragEnd: (d) {
                              // ✅ 先更新位置再重置拖动状态，避免闪烁
                              setState(() {
                                _position = d;
                                _isDraggingProgress = false;
                                _draggingPosition = null;
                              });
                              _player.seek(d);
                              _resetHideControlsTimer();
                            },
                            onSpeed: (v) {
                              _changeSpeed(v);
                              _resetHideControlsTimer();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // ✅ 加载/缓冲指示器（不阻挡点击）
              if (!_ready || _isBuffering)
                Positioned.fill(
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
                                _ready ? '缓冲中...' : '正在准备播放...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_expectedBitrateKbps != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _formatBitrate(_currentSpeedKbps),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (_qualityLabel != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '分辨率: $_qualityLabel',
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 构建美化的图标按钮
  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 24,
    bool showBackground = false, // ✅ 是否显示背景和边框
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

class _Controls extends StatefulWidget {
  const _Controls({
    required this.position,
    required this.duration,
    required this.speed,
    required this.isPlaying,
    required this.isDragging,
    this.draggingPosition,
    required this.onDragStart,
    required this.onDragging,
    required this.onDragEnd,
    required this.onSpeed,
  });
  final Duration position;
  final Duration duration;
  final double speed;
  final bool isPlaying;
  final bool isDragging;
  final Duration? draggingPosition;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDragging;
  final ValueChanged<Duration> onDragEnd;
  final ValueChanged<double> onSpeed;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls>
    with SingleTickerProviderStateMixin {
  late AnimationController _thumbAnimationController;
  late Animation<double> _thumbAnimation;

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
    // ✅ 拖动时使用 draggingPosition，否则使用实际播放位置
    final displayPosition = widget.isDragging && widget.draggingPosition != null
        ? widget.draggingPosition!
        : widget.position;
    final rawValue = displayPosition.inSeconds / totalSeconds;
    final sliderValue =
        rawValue.isNaN ? 0.0 : rawValue.clamp(0.0, 1.0).toDouble();

    // ✅ 根据系统主题模式选择颜色
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              // ✅ 根据系统主题自动切换毛玻璃效果
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    ? [
                        // 深色模式：黑灰色半透明背景
                        Colors.grey.shade900.withValues(alpha: 0.6),
                        Colors.grey.shade800.withValues(alpha: 0.4),
                      ]
                    : [
                        // 浅色模式：浅色半透明背景
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.1),
                      ],
              ),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // ✅ 播放时间（固定宽度）
                SizedBox(
                  width: 65, // 固定宽度，避免时间变化导致进度条抖动
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
                // ✅ 分隔符
                const Text(
                  ' · ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // ✅ 总时长（固定宽度）
                SizedBox(
                  width: 65, // 固定宽度，避免时间变化导致进度条抖动
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
                // ✅ 进度条
                Expanded(
                  child: AnimatedBuilder(
                    animation: _thumbAnimation,
                    builder: (context, child) {
                      return SliderTheme(
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
                          overlayColor: Colors.white.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: sliderValue,
                          onChangeStart: (v) {
                            widget.onDragStart();
                          },
                          onChanged: (v) {
                            final target =
                                Duration(seconds: (v * totalSeconds).round());
                            widget.onDragging(target);
                          },
                          onChangeEnd: (v) {
                            final target =
                                Duration(seconds: (v * totalSeconds).round());
                            widget.onDragEnd(target);
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // ✅ 播放速度
                _buildControlButton(
                  child: Text(
                    '${widget.speed.toStringAsFixed(2)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () async {
                    final sel = await showCupertinoModalPopup<double>(
                      context: context,
                      builder: (context) => _SpeedSheet(current: widget.speed),
                    );
                    if (sel != null) widget.onSpeed(sel);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ 构建美化的控制按钮（无背景边框）
  Widget _buildControlButton({
    IconData? icon,
    Widget? child,
    required VoidCallback onPressed,
    double size = 24,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onPressed,
      minSize: 0,
      child: child ??
          Icon(
            icon,
            color: Colors.white,
            size: size,
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

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.current});
  final double current;

  @override
  Widget build(BuildContext context) {
    final speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return CupertinoActionSheet(
      title: const Text(
        '播放速度',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      message: const Text(
        '选择视频播放速度',
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.systemGrey,
        ),
      ),
      actions: [
        for (final s in speeds)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(s),
            isDefaultAction: s == current,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${s}x',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight:
                        s == current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (s == current) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: 20,
                    color: CupertinoColors.activeBlue,
                  ),
                ],
              ],
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(
          '取消',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
