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

const bool _kPlayerLogging = false; // ✅ 禁用日志，提升性能（倍速播放时大量日志会拖慢速度）
void _playerLog(String message) {
  if (_kPlayerLogging) {}
}

// 重要日志，总是输出
void _playerLogImportant(String message) {}

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
  // ✅ 速度档位列表
  static const List<double> _speedOptions = [
    0.5,
    0.75,
    1.0,
    1.5,
    1.75,
    2.0,
    3.0
  ];
  // ✅ 显示速度列表的状态
  bool _showSpeedList = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub; // ✅ 添加 duration 订阅
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub; // ✅ 添加播放状态订阅
  bool _isLandscape = true; // ✅ 默认横屏
  bool _isBuffering = true;
  bool _isPlaying = false; // ✅ 添加播放状态
  Duration _bufferPosition = Duration.zero; // ✅ 实时缓冲进度
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

  // ✅ 控制栏显示/隐藏（初始隐藏，点击屏幕显示）
  bool _showControls = false;

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

  // ✅ 视频裁切模式提示
  bool _showVideoFitHint = false;
  Timer? _videoFitHintTimer;

  // ✅ 速度列表滚动控制器
  final ScrollController _speedListScrollController = ScrollController();

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
      configuration: PlayerConfiguration(
        title: 'Emby Player',
        // ✅ 设置日志级别（减少日志输出，提升性能）
        logLevel: MPVLogLevel.error,

        // ===== bufferSize: 播放器内部缓冲区大小 =====
        // 说明：这是播放器在内存中保存已解码视频帧的缓冲区大小
        // 用途：更大的缓冲区可以保存更多已解码的帧，减少解码压力
        // 注意：已解码帧占用空间较大（1080p约3-5MB/帧），1GB可以缓存几百帧
        bufferSize: 1024 * 1024 * 1024, // 1GB 缓冲区
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        // ✅ 启用硬件加速，提升解码性能（特别是倍速播放时）
        enableHardwareAcceleration: true,
        // ✅ 改为 false，提升倍速播放稳定性
        // 说明：true 会延迟 Surface 附加，可能导致倍速时帧显示不及时
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
    // ✅ 初始状态是隐藏的，不执行forward

    // ✅ 进入播放页面时默认横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 初始隐藏状态栏（因为控制栏默认隐藏）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _refreshTicker = ref.read(libraryRefreshTickerProvider.notifier);

    // ✅ 定时更新缓冲时的速度显示，添加波动模拟真实网络速度
    // 注意：Flutter/media_kit 不提供实时网络速度 API，
    // 我们在视频比特率基础上添加合理的波动来模拟真实速度变化
    _speedTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        // ✅ 只在缓冲时显示速度
        final buffering = _isBuffering;

        if (_expectedBitrateKbps != null && buffering) {
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
          _bufferPosition = Duration.zero; // 重置缓冲进度
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
          // ✅ 初始值设为预期比特率（会被Timer更新）
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

      // ✅ 读取保存的视频裁切模式
      final videoFitString = prefs.getString('video_fit') ?? 'contain';
      if (mounted) {
        setState(() {
          switch (videoFitString) {
            case 'contain':
              _videoFit = BoxFit.contain;
              break;
            case 'cover':
              _videoFit = BoxFit.cover;
              break;
            case 'fill':
              _videoFit = BoxFit.fill;
              break;
            default:
              _videoFit = BoxFit.contain;
          }
        });
      }

      final needsSeek =
          _initialSeekPosition != null && _initialSeekPosition! > Duration.zero;

      _playerLogImportant(
          '🎬 [Player] needsSeek: $needsSeek, initialPosition: $_initialSeekPosition');

      // ✅ 如果需要seek，先静音，避免第一帧有声音
      if (needsSeek) {
        await _player.setVolume(0.0);
        _playerLogImportant('🎬 [Player] 🔇 Pre-muted for initial seek');
      }

      // ✅ 打开媒体（设置标题以支持系统媒体通知）
      _playerLog('🎬 [Player] Opening media with title: $_videoTitle');
      await _player.open(
        Media(
          media.uri,
          httpHeaders: media.headers,
          extras: {
            // ===== 大容量缓冲配置 =====
            // demuxer-max-bytes: 向前缓存上限
            // 说明：从当前位置向后可以缓存多少压缩视频数据
            // 作用：5GB可缓存约3-4小时的1080p视频，充分利用快速网络
            'demuxer-max-bytes': '5G',

            // demuxer-max-back-bytes: 向后缓存上限
            // 说明：当前位置之前保留多少已播放的数据
            // 作用：倒退时直接从缓存读取，不重新下载
            'demuxer-max-back-bytes': '3G',

            // cache: 启用缓存
            'cache': 'yes',

            // cache-secs: 目标缓存时长
            // 说明：尝试缓存多长时间的视频（秒）
            // 作用：与空间限制配合，达到任一限制停止缓存
            'cache-secs': '3600',

            // demuxer-readahead-secs: 积极预读
            // 说明：提前读取未来多少秒的数据
            // 作用：播放器会持续下载，填满缓冲区
            'demuxer-readahead-secs': '1800',

            // stream-buffer-size: 网络流缓冲区
            // 说明：从网络读取数据的临时缓冲
            // 作用：更大的缓冲 = 更快的下载速度
            'stream-buffer-size': '64M',

            // demuxer-seekable-cache: 可搜索缓存
            // 说明：缓存支持随机访问
            // 作用：在已缓存区域seek不会丢失数据
            'demuxer-seekable-cache': 'yes',

            // force-seekable: 强制可搜索
            'force-seekable': 'yes',

            //==========================
            //【核心：解码与渲染优化】
            //==========================
            'hwdec': 'mediacodec-auto', // Android 最稳定硬解
            'gpu-api': 'opengl', // GPU 渲染最稳定

            // 防止倍速画面跳动
            'video-sync': 'audio',

            // 不使用插帧，减少卡顿
            'interpolation': 'no',

            // 减少解码压力（倍速时很重要）
            'vd-lavc-skiploopfilter': 'all',
            'vd-lavc-skipidct': 'approx',
            'vd-lavc-fast': 'yes',

            // 帧丢弃策略：优先保证流畅性
            'framedrop': 'vo',
            //==========================
            //【音频：防止倍速时声音异常】
            //==========================
            'audio-pitch-correction': 'yes',

            //==========================
            //【稳定性】
            //==========================
            'opengl-early-flush': 'no', // 防止倍速时丢帧
            'msg-level': 'all=no', // 关闭大量冗余日志
          },
        ),
        play: !needsSeek,
      );

      // ✅ 在 open 之后设置 buffering 监听，确保能正确捕获缓冲状态
      _bufferingSub?.cancel();
      _bufferingSub = _player.stream.buffering.listen((isBuffering) {
        _playerLog('🎬 [Player] Buffering状态变化: $isBuffering');
        if (!mounted) return;
        setState(() => _isBuffering = isBuffering);
      });

      // ✅ 如果不需要seek，设置音量为100%
      // 如果需要seek，在seek流程中控制音量（先静音再恢复）
      if (!needsSeek) {
        await _player.setVolume(100.0);
        _playerLog('🎬 [Player] Volume set to 100%');
      }

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

      // ✅ 监听缓冲进度（用于显示进度条上的缓冲位置）
      _player.stream.buffer.listen((buffer) {
        if (mounted && buffer > Duration.zero) {
          setState(() {
            _bufferPosition = buffer; // 直接使用实时缓冲位置
          });
        }
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
            '🎬 [Player] ⏱️ Starting playback from beginning first (hidden and muted)...');

        // 先开始播放，让播放器进入稳定状态（已在open前静音）
        await _player.play();

        _playerLogImportant(
            '🎬 [Player] ⏱️ Waiting for playback to actually start...');
        // 等待播放真正开始（position 开始更新）
        await _player.stream.position.firstWhere((pos) => pos > Duration.zero);

        _playerLogImportant(
            '🎬 [Player] ⏱️ Playback started, now seeking to ${_initialSeekPosition!.inSeconds}s...');
        await _player.seek(_initialSeekPosition!);
        _lastReportedPosition = _initialSeekPosition!;

        // Seek 后恢复音量并确保继续播放
        _playerLogImportant(
            '🎬 [Player] ✅ Seeked, restoring volume and resuming playback...');
        await _player.setVolume(100.0);
        _playerLogImportant('🎬 [Player] 🔊 Volume restored to 100%');
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
          // ✅ 不在这里设置 _isBuffering = false
          // _isBuffering 由 buffering stream 控制，确保缓冲完成后才消失
        });
      }
      _playerLog(
          '🎬 [Player] ✅ Ready to play, isPlaying: $_isPlaying, isBuffering: $_isBuffering');
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
    _videoFitHintTimer?.cancel(); // ✅ 取消视频裁切模式提示计时器
    _speedListScrollController.dispose(); // ✅ 释放速度列表滚动控制器
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
    _playerLog('🎬 [Player] Changing playback speed to: ${v}x');
    setState(() => _speed = v);
    await _player.setRate(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', v);
    _playerLog('🎬 [Player] ✅ Playback speed changed to: ${v}x');
  }

  // ✅ 增加速度档位
  Future<void> _increaseSpeed() async {
    final currentIndex = _speedOptions.indexOf(_speed);
    if (currentIndex < _speedOptions.length - 1) {
      final newSpeed = _speedOptions[currentIndex + 1];
      await _changeSpeed(newSpeed);
    }
  }

  // ✅ 减少速度档位
  Future<void> _decreaseSpeed() async {
    final currentIndex = _speedOptions.indexOf(_speed);
    if (currentIndex > 0) {
      final newSpeed = _speedOptions[currentIndex - 1];
      await _changeSpeed(newSpeed);
    }
  }

  // ✅ 检查是否可以增加速度
  bool get _canIncreaseSpeed => _speed < _speedOptions.last;

  // ✅ 检查是否可以减少速度
  bool get _canDecreaseSpeed => _speed > _speedOptions.first;

  // ✅ 滚动到选中的速度项
  void _scrollToSelectedSpeed() {
    if (!_speedListScrollController.hasClients) return;

    final selectedIndex = _speedOptions.indexOf(_speed);
    if (selectedIndex == -1) return;

    // 每个按钮的高度约为 48（padding 12*2 + 文字行高约24）
    const itemHeight = 48.0;
    final targetOffset = selectedIndex * itemHeight;

    // 滚动到目标位置，居中显示
    final maxScrollExtent = _speedListScrollController.position.maxScrollExtent;
    final viewportHeight =
        _speedListScrollController.position.viewportDimension;
    final centeredOffset = (targetOffset - viewportHeight / 2 + itemHeight / 2)
        .clamp(0.0, maxScrollExtent);

    _speedListScrollController.animateTo(
      centeredOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
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
      if (kDebugMode) {}
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
  Future<void> _toggleVideoFit() async {
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
      // ✅ 显示模式提示
      _showVideoFitHint = true;
    });
    _playerLog(
        '🎬 [Player] Video fit changed to: $_videoFit (${_getVideoFitName()})');

    // ✅ 保存裁切模式到 SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    String videoFitString;
    switch (_videoFit) {
      case BoxFit.contain:
        videoFitString = 'contain';
        break;
      case BoxFit.cover:
        videoFitString = 'cover';
        break;
      case BoxFit.fill:
        videoFitString = 'fill';
        break;
      default:
        videoFitString = 'contain';
    }
    await prefs.setString('video_fit', videoFitString);

    // ✅ 取消之前的计时器
    _videoFitHintTimer?.cancel();
    // ✅ 2秒后自动隐藏提示
    _videoFitHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showVideoFitHint = false;
        });
      }
    });
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

  // ✅ 获取视频裁切模式的名称
  String _getVideoFitName() {
    switch (_videoFit) {
      case BoxFit.contain:
        return '适应屏幕';
      case BoxFit.cover:
        return '填充屏幕';
      case BoxFit.fill:
        return '拉伸填充';
      default:
        return '适应屏幕';
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
    // ✅ 拖动期间忽略位置更新，避免闪烁
    if (_isDraggingProgress) return;

    if (mounted) {
      setState(() => _position = pos);
    }
    _syncProgress(pos);
  }

  // ✅ 切换控制栏显示/隐藏
  void _toggleControls() {
    final bool willShow = !_showControls;
    setState(() {
      _showControls = willShow;
      // ✅ 隐藏控制栏时，立即隐藏tooltip和速度列表
      if (!willShow) {
        _showVideoFitHint = false;
        _showSpeedList = false;
      }
    });

    if (willShow) {
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
      // ✅ 取消tooltip计时器
      _videoFitHintTimer?.cancel();
    }
  }

  // ✅ 开始自动隐藏控制栏的计时器
  void _startHideControlsTimer() {
    // ✅ 如果速度列表正在显示，不启动隐藏计时器
    if (_showSpeedList) return;

    _cancelHideControlsTimer();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showControls && _isPlaying && !_showSpeedList) {
        _controlsAnimationController.reverse();
        // ✅ 自动隐藏时也隐藏状态栏
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // ✅ 取消tooltip计时器
        _videoFitHintTimer?.cancel();
        setState(() {
          _showControls = false;
          // ✅ 立即隐藏tooltip和速度列表
          _showVideoFitHint = false;
          _showSpeedList = false;
        });
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
                            decoration: const BoxDecoration(),
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
                                    filter: ImageFilter.blur(
                                        sigmaX: 20, sigmaY: 20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: Theme.of(context)
                                                      .brightness ==
                                                  Brightness.dark
                                              ? [
                                                  Colors.grey.shade900
                                                      .withValues(alpha: 0.6),
                                                  Colors.grey.shade800
                                                      .withValues(alpha: 0.4),
                                                ]
                                              : [
                                                  Colors.white
                                                      .withValues(alpha: 0.2),
                                                  Colors.white
                                                      .withValues(alpha: 0.1),
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
                                              _toggleVideoFit();
                                              _resetHideControlsTimer();
                                            },
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              transitionBuilder:
                                                  (child, animation) {
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
                                                key:
                                                    ValueKey<BoxFit>(_videoFit),
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
                                              Icons
                                                  .picture_in_picture_alt_rounded,
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

              // ✅ 拖动进度条时的时间预览（与顶部工具条水平对齐）
              // PiP 模式下隐藏
              if (!_isInPipMode &&
                  _isDraggingProgress &&
                  _draggingPosition != null)
                Positioned(
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
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_formatTime(_draggingPosition!)} / ${_formatTime(_duration)}',
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
                ),

              // ✅ 视频裁切模式提示（tooltip样式，显示在按钮下方）
              // PiP 模式下隐藏
              if (!_isInPipMode && _showVideoFitHint)
                Positioned(
                  top: 90, // 在顶部按钮下方，紧贴按钮组
                  right: 85, // 对齐裁剪按钮位置
                  child: AnimatedOpacity(
                    opacity: _showVideoFitHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ 箭头（三角形）
                        CustomPaint(
                          size: const Size(12, 6),
                          painter: _TooltipArrowPainter(
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getVideoFitName(),
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
                ),

              // ✅ 中间播放/暂停按钮（仅在显示控制栏时）
              // PiP 模式下隐藏，缓冲时也隐藏
              if (!_isInPipMode && _ready && _showControls && !_isBuffering)
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

              // ✅ 右侧速度控制（仅在显示控制栏时）
              // PiP 模式下隐藏，一进来就显示
              if (!_isInPipMode && _showControls)
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _controlsAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _controlsAnimation.value,
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
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
                                              Colors.white
                                                  .withValues(alpha: 0.2),
                                              Colors.white
                                                  .withValues(alpha: 0.1),
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
                                          if (_canIncreaseSpeed) {
                                            _increaseSpeed();
                                            // ✅ 关闭倍速列表
                                            if (_showSpeedList) {
                                              setState(() {
                                                _showSpeedList = false;
                                              });
                                            }
                                            _resetHideControlsTimer();
                                          }
                                          // ✅ 不可用时点击无任何反应，不重置计时器
                                        },
                                        child: Icon(
                                          Icons.add_rounded,
                                          color: _canIncreaseSpeed
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.3),
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
                                          final willShow = !_showSpeedList;
                                          setState(() {
                                            _showSpeedList = willShow;
                                          });
                                          if (willShow) {
                                            // ✅ 显示列表时，取消自动隐藏计时器
                                            _cancelHideControlsTimer();
                                            // ✅ 滚动到选中项
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              _scrollToSelectedSpeed();
                                            });
                                          } else {
                                            // ✅ 隐藏列表时，重新启动自动隐藏计时器
                                            _resetHideControlsTimer();
                                          }
                                        },
                                        child: SizedBox(
                                          width: 30, // ✅ 固定宽度，避免文字变化导致宽度变化
                                          child: Text(
                                            '${_speed.toStringAsFixed(1)}x',
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
                                          if (_canDecreaseSpeed) {
                                            _decreaseSpeed();
                                            // ✅ 关闭倍速列表
                                            if (_showSpeedList) {
                                              setState(() {
                                                _showSpeedList = false;
                                              });
                                            }
                                            _resetHideControlsTimer();
                                          }
                                          // ✅ 不可用时点击无任何反应，不重置计时器
                                        },
                                        child: Icon(
                                          Icons.remove_rounded,
                                          color: _canDecreaseSpeed
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.3),
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
                            bufferPosition: _bufferPosition, // ✅ 传递实时缓冲进度
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
                            onDragEnd: (d) async {
                              // ✅ 先更新位置和隐藏预览
                              setState(() {
                                _position = d;
                                _draggingPosition = null;
                              });

                              // ✅ 执行seek操作
                              await _player.seek(d);

                              // ✅ seek完成后，延迟一小段时间再重置拖动状态
                              // 确保播放器位置已经更新，避免闪烁
                              await Future.delayed(
                                  const Duration(milliseconds: 100));

                              if (mounted) {
                                setState(() {
                                  _isDraggingProgress = false;
                                });
                              }

                              _resetHideControlsTimer();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // ✅ 加载/缓冲指示器（不阻挡点击）
              // 显示条件：未准备好 或 正在缓冲 或 还未开始播放（position为0）
              if (!_ready ||
                  _isBuffering ||
                  (_ready && _position == Duration.zero))
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
                                !_ready
                                    ? '加载中...'
                                    : _isBuffering
                                        ? '缓冲中...'
                                        : '准备中...',
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

              // ✅ 速度档位列表（显示在左侧，放在最后确保在最上层）
              if (!_isInPipMode && _showSpeedList && _showControls)
                Positioned(
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
                                colors: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? [
                                        Colors.grey.shade900
                                            .withValues(alpha: 0.7),
                                        Colors.grey.shade800
                                            .withValues(alpha: 0.5),
                                      ]
                                    : [
                                        Colors.white.withValues(alpha: 0.25),
                                        Colors.white.withValues(alpha: 0.15),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SingleChildScrollView(
                              controller: _speedListScrollController,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _speedOptions.map((speed) {
                                  final isSelected = speed == _speed;
                                  return CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    onPressed: () async {
                                      await _changeSpeed(speed);
                                      setState(() {
                                        _showSpeedList = false;
                                      });
                                      _resetHideControlsTimer();
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
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
    required this.bufferPosition, // ✅ 缓冲进度
    required this.isPlaying,
    required this.isDragging,
    this.draggingPosition,
    required this.onDragStart,
    required this.onDragging,
    required this.onDragEnd,
  });
  final Duration position;
  final Duration duration;
  final Duration bufferPosition; // ✅ 缓冲进度
  final bool isPlaying;
  final bool isDragging;
  final Duration? draggingPosition;
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
                      // 计算缓冲进度值
                      final bufferValue =
                          widget.bufferPosition.inSeconds / totalSeconds;
                      final bufferSliderValue = bufferValue.isNaN
                          ? 0.0
                          : bufferValue.clamp(0.0, 1.0).toDouble();

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // 计算缓冲区域的起始和结束位置（像素）
                          final playedWidth = width * sliderValue;
                          final bufferedWidth = width * bufferSliderValue;

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // ✅ 缓冲进度条（浅白色，只显示从播放位置到缓冲位置）
                              if (bufferedWidth > playedWidth)
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24), // Slider的默认padding
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        margin: EdgeInsets.only(
                                            left: (width - 48) *
                                                sliderValue), // 减去padding后的宽度
                                        width: (width - 48) *
                                            (bufferSliderValue -
                                                sliderValue), // 缓冲区域宽度
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.5), // 缓冲进度颜色
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(1.5),
                                            bottomRight: Radius.circular(1.5),
                                          ), // 左侧直角，右侧圆角
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // ✅ 播放进度条
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

// ✅ Tooltip箭头绘制器
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
