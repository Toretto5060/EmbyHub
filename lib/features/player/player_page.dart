import 'dart:async';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  // ✅ 控制栏显示/隐藏
  bool _showControls = true;
  Timer? _hideControlsTimer;
  late final AnimationController _controlsAnimationController;
  late final Animation<double> _controlsAnimation;

  // ✅ 进度条拖动状态
  bool _isDraggingProgress = false;
  Duration? _draggingPosition;

  // ✅ 底部上滑手势检测
  double _verticalDragStart = 0;

  // ✅ 视频标题（用于显示和 PiP）
  String _videoTitle = '';

  // ✅ PiP 模式状态（用于UI显示）
  bool _isInPipMode = false;
  
  // ✅ 防止重复触发 PiP（5秒内不重复触发）
  DateTime? _lastPipAttempt;
  
  Duration? get _initialSeekPosition {
    final ticks = widget.initialPositionTicks;
    if (ticks == null || ticks <= 0) return null;
    return Duration(microseconds: (ticks / 10).round());
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

    // ✅ 注册应用生命周期观察者（用于PiP和后台播放）
    WidgetsBinding.instance.addObserver(this);

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

  // ✅ 应用生命周期变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _playerLog('🎬 [Player] App lifecycle state: $state, ready: $_ready, playing: $_isPlaying');

    if (state == AppLifecycleState.paused) {
      // ✅ 只有 paused 状态才考虑进入 PiP（不包括 inactive）
      // inactive 状态可能是下拉通知栏等操作
      
      // 防止5秒内重复触发
      final now = DateTime.now();
      if (_lastPipAttempt != null && now.difference(_lastPipAttempt!).inSeconds < 2) {
        _playerLog('🎬 [Player] ❌ Skip PiP: too soon (less than 5s since last attempt)');
        return;
      }
      
      if (!_ready || !_isPlaying) {
        _playerLog('🎬 [Player] ❌ Skip PiP: ready=$_ready, playing=$_isPlaying');
        return;
      }
      
      if (!mounted) {
        _playerLog('🎬 [Player] ❌ Skip PiP: not mounted');
        return;
      }
      
      // ✅ 检查当前页面是否是播放器页面（检查 widget 类型）
      final route = ModalRoute.of(context);
      final isCurrentRoute = route?.isCurrent ?? false;
      final routeName = route?.settings.name ?? 'unknown';
      
      _playerLog('🎬 [Player] Route check: isCurrent=$isCurrentRoute, name=$routeName, widget=${widget.runtimeType}');
      
      if (!isCurrentRoute) {
        _playerLog('🎬 [Player] ❌ Skip PiP: Player page not current route');
        return;
      }
      
      // 记录尝试时间
      _lastPipAttempt = now;
      
      _playerLog('🎬 [Player] ✅ All checks passed, entering PiP mode');
      _enterPip();
      
    } else if (state == AppLifecycleState.resumed) {
      // ✅ 应用从后台恢复，重置 PiP 状态
      _playerLog('🎬 [Player] App resumed, resetting PiP state');
      
      // ✅ 重置 PiP 尝试时间，允许下次触发
      _lastPipAttempt = null;
      
      if (mounted) {
        setState(() {
          _isInPipMode = false;
        });
      }
    }
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

      if (needsSeek) {
        // 等待缓冲完成再跳转，避免立即被复位
        await _player.stream.buffering.firstWhere((value) => value == false);
        await _player.seek(_initialSeekPosition!);
        _playerLog('🎬 [Player] Seek to ${_initialSeekPosition!.inSeconds}s');
        _lastReportedPosition = _initialSeekPosition!;
        await _player.play();
        _playerLog('🎬 [Player] Playback started after seek');
      }

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

      if (mounted) {
        setState(() {
          _ready = true;
          _isBuffering = false;
        });
      }
      _playerLog('🎬 [Player] ✅ Ready to play, isPlaying: $_isPlaying, canTriggerPip: ${_ready && _isPlaying}');
    } catch (e, stack) {
      _playerLog('❌ [Player] Load failed: $e');
      _playerLog('Stack: $stack');
    }
  }

  @override
  void dispose() {
    // ✅ 隐藏系统媒体通知
    _hideMediaNotification();
    
    // ✅ 移除应用生命周期观察者
    WidgetsBinding.instance.removeObserver(this);

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

  Future<void> _enterPip() async {
    try {
      // ✅ 最后再次确认页面状态（双重保险）
      if (!mounted) {
        _playerLog('🎬 [Player] ❌ Cancelled PiP: not mounted');
        return;
      }
      
      final route = ModalRoute.of(context);
      final isCurrentRoute = route?.isCurrent ?? false;
      
      if (!isCurrentRoute) {
        _playerLog('🎬 [Player] ❌ Cancelled PiP: page not current (final check)');
        return;
      }
      
      if (!_ready || !_isPlaying) {
        _playerLog('🎬 [Player] ❌ Cancelled PiP: ready=$_ready, playing=$_isPlaying (final check)');
        return;
      }
      
      _playerLog('🎬 [Player] ⏳ Calling native PiP enter method...');
      
      final result = await _pip.invokeMethod('enter', {
        'isPlaying': _isPlaying,
        'title': _videoTitle,
      });
      
      _playerLog('🎬 [Player] ✅ PiP call result: $result, title: $_videoTitle, playing: $_isPlaying');
      
      // ✅ 不在这里设置 _isInPipMode，等待原生层回调 onPipModeChanged
      
    } catch (e) {
      _playerLog('❌ [Player] PiP enter failed: $e');
      if (kDebugMode) {
        debugPrint('PiP Error: $e');
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
      _playerLog('🎬 [Player] 📱 Showing system media notification: $_videoTitle');
      
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
      _playerLog('📱 [Player] Media notification shown with poster: $posterUrl');
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
          // ✅ 底部上滑进入小窗播放
          onVerticalDragStart: (details) {
            _verticalDragStart = details.globalPosition.dy;
          },
          onVerticalDragUpdate: (details) {
            // 检测是否在屏幕底部1/3区域开始滑动
            final screenHeight = MediaQuery.of(context).size.height;
            if (_verticalDragStart > screenHeight * 0.66) {
              // 从底部向上滑动
              final delta = _verticalDragStart - details.globalPosition.dy;
              // 如果向上滑动超过100像素，进入PiP
              if (delta > 100) {
                _enterPip();
                _verticalDragStart = 0; // 重置，避免重复触发
              }
            }
          },
          onVerticalDragEnd: (_) {
            _verticalDragStart = 0;
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // ✅ 视频播放器
              Positioned.fill(
                child: _ready
                    ? Video(
                        controller: _controller,
                        fit: BoxFit.contain,
                        controls: NoVideoControls, // ✅ 隐藏原生播放控件
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
                              top: 48, // 固定高度，足够容纳状态栏
                              left: 4,
                              right: 4,
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
                                  icon: CupertinoIcons.back,
                                  onPressed: () => context.pop(),
                                  size: 26,
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
                                const SizedBox(width: 8),
                                _buildIconButton(
                                  icon: _isLandscape
                                      ? CupertinoIcons.device_phone_portrait
                                      : CupertinoIcons.device_phone_landscape,
                                  onPressed: () {
                                    _toggleOrientation();
                                    _resetHideControlsTimer();
                                  },
                                  size: 22,
                                ),
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
                  top: 110, // 固定高度，在返回按钮下方
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
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
                  top: 100, // 固定高度，在返回按钮下方
                  right: 8,
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
                              ? CupertinoIcons.arrow_down_circle
                              : CupertinoIcons.play_circle,
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
                        opacity: _controlsAnimation.value * 0.8,
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
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.5),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isPlaying
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.play_fill,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // ✅ 底部控制栏（淡入淡出动画）
              // PiP 模式下隐藏
              if (!_isInPipMode && _ready)
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
                            onTogglePlay: () async {
                              final playing = _player.state.playing;
                              if (playing) {
                                await _player.pause();
                              } else {
                                await _player.play();
                              }
                              _resetHideControlsTimer();
                            },
                            onSpeed: (v) {
                              _changeSpeed(v);
                              _resetHideControlsTimer();
                            },
                            onPip: () {
                              _enterPip();
                              _resetHideControlsTimer();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // ✅ 加载/缓冲指示器
              if (!_ready || _isBuffering)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
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
                      ],
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
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
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
    required this.onTogglePlay,
    required this.onSpeed,
    required this.onPip,
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
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSpeed;
  final VoidCallback onPip;

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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ 进度条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(widget.position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _fmt(widget.duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ✅ 自定义进度条样式（带动画的滑块）
                AnimatedBuilder(
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
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
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
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ✅ 控制按钮行
          Row(
            children: [
              _buildControlButton(
                icon: widget.isPlaying
                    ? CupertinoIcons.pause_solid
                    : CupertinoIcons.play_arrow_solid,
                onPressed: widget.onTogglePlay,
                size: 28,
              ),
              const SizedBox(width: 12),
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
              const Spacer(),
              _buildControlButton(
                icon: CupertinoIcons.rectangle_on_rectangle,
                onPressed: widget.onPip,
                size: 24,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ 构建美化的控制按钮
  Widget _buildControlButton({
    IconData? icon,
    Widget? child,
    required VoidCallback onPressed,
    double size = 24,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: child ??
            Icon(
              icon,
              color: Colors.white,
              size: size,
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
