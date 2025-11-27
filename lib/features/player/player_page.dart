import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/status_bar_manager.dart';
import '../../utils/theme_utils.dart';
import '../../widgets/fade_in_image.dart';
import 'custom_subtitle_overlay.dart';
import 'exoplayer_texture_controller.dart';
import 'player_controls.dart';

void _playerLog(String message) {
  if (kDebugMode) {
    print(message);
  }
}

void _playerLogImportant(String message) {
  if (kDebugMode) {
    print(message);
  }
}

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    required this.itemId,
    this.initialPositionTicks,
    this.itemInfo, // ✅ 可选的 ItemInfo，避免重复请求
    this.logoUrl, // ✅ 可选的 Logo URL，避免重复请求
    this.backdropUrl, // ✅ 可选的背景图 URL，避免重复请求
    this.backdropImage, // ✅ 可选的背景图对象，立即显示
    this.seriesInfo, // ✅ 可选的 Series 信息（用于 Episode）
    super.key,
  });
  final String itemId;
  final int? initialPositionTicks;
  final ItemInfo? itemInfo; // ✅ 从上一页传入的 ItemInfo
  final String? logoUrl; // ✅ 从上一页传入的 Logo URL
  final String? backdropUrl; // ✅ 从上一页传入的背景图 URL
  final ui.Image? backdropImage; // ✅ 从上一页传入的背景图对象（立即显示）
  final ItemInfo? seriesInfo; // ✅ 从上一页传入的 Series 信息

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final ExoPlayerTextureController _player;
  int? _textureId;
  Size _videoSize = const Size(1920, 1080);
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
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _readySub;
  StreamSubscription<Size>? _videoSizeSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<double>? _networkSpeedSub; // ✅ 网络速度订阅
  Future<void>? _seekChain;
  bool _isLandscape = true; // ✅ 默认横屏
  bool _isBuffering = true;
  bool _isPlaying = false; // ✅ 添加播放状态
  Duration _bufferPosition = Duration.zero; // ✅ 实时缓冲进度
  double? _expectedBitrateKbps;
  double? _currentSpeedKbps;
  String? _qualityLabel;

  // ✅ 错误处理和重试
  int _errorRetryCount = 0;
  static const int _maxRetryCount = 3;
  Timer? _retryTimer;

  // ✅ 音频轨道自动切换
  Set<int> _triedAudioIndices = {}; // 已尝试过的音频轨道索引
  bool _showAudioSwitchHint = false; // ✅ 是否显示音频切换提示
  String _audioSwitchHintText = ''; // ✅ 音频切换提示文本
  Timer? _audioSwitchHintTimer; // ✅ 音频切换提示自动隐藏定时器

  // ✅ 应用生命周期
  bool _isManuallyEnteringPip = false; // ✅ 是否正在手动进入 PiP（点击按钮）

  // ✅ 预加载下一集
  bool _hasPreloadedNextEpisode = false;

  // ✅ 播放统计
  int _bufferingCount = 0;
  Duration _totalBufferingTime = Duration.zero;
  DateTime? _lastBufferingStart;
  int _errorCount = 0;
  EmbyApi? _api;
  String? _userId;
  DateTime _lastProgressSync = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastReportedPosition = Duration.zero;
  bool _completedReported = false;
  bool _progressSyncUnavailableLogged = false;
  // ✅ 移除 _refreshTicker，改为在页面生命周期时手动刷新

  // ✅ 控制栏显示/隐藏（初始显示，视频开始播放后自动隐藏）
  bool _showControls = true;

  // ✅ 控制栏锁定状态（锁定后隐藏其他控件，只显示锁定按钮）
  bool _isLocked = false;

  // ✅ 长按快进/快退状态
  bool _isLongPressingForward = false;
  bool _isLongPressingRewind = false;
  Offset? _longPressPosition;
  double? _originalSpeed; // 保存原始倍速，用于恢复
  Timer? _longPressTimer; // 长按定时器（用于倒退时的定时更新）
  Timer? _speedAccelerationTimer; // ✅ 倍速加速定时器（用于平滑加速到3倍速）
  DateTime? _longPressStartTime; // ✅ 长按开始时间（用于显示按住时长）
  bool _suppressPositionUpdates = false; // ✅ 长按seek时抑制位置更新

  // ✅ 视频画面裁切模式
  BoxFit _videoFit = BoxFit.contain; // contain(原始), cover(覆盖), fill(填充)
  Timer? _hideControlsTimer;
  late final AnimationController _controlsAnimationController;
  late final Animation<double> _controlsAnimation;

  // ✅ 进度条拖动状态
  bool _isDraggingProgress = false;
  Duration? _draggingPosition;
  bool _wasPlayingBeforeDrag = false;
  Future<void> _performSeek(
    Duration target, {
    bool resumeAfterSeek = true,
    bool forcePlayAfterSeek = false,
    bool waitForConfirmation = true, // ✅ 新增参数，拖动时不等待确认
  }) {
    _seekChain ??= Future.value();
    return _seekChain = _seekChain!.then((_) async {
      _playerLogImportant(
          '🎬 [Player] 🔁 Seek requested to ${target.inSeconds}s (resume: $resumeAfterSeek)');
      final wasPlaying = _isPlaying;
      if (wasPlaying) {
        await _playerPause();
        _playerLogImportant('🎬 [Player] 🔁 Paused for seek');
      }
      await _playerSeek(target);
      _lastReportedPosition = target;
      if (mounted) {
        setState(() {
          _position = target;
        });
      }

      // ✅ 只在需要时等待确认（拖动进度条时不等待，提升响应速度）
      if (waitForConfirmation) {
        try {
          await _player.positionStream
              .firstWhere(
                  (pos) => (pos - target).abs() < const Duration(seconds: 1))
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      final shouldResume = forcePlayAfterSeek || resumeAfterSeek;
      if (shouldResume) {
        await _playerPlay();
        _playerLogImportant('🎬 [Player] 🔁 Seek done, resumed playback');
      } else {
        _playerLogImportant('🎬 [Player] 🔁 Seek done, remain paused');
      }
    }).whenComplete(() {
      _seekChain = null;
    });
  }

  // ✅ 亮度/音量控制状态
  bool _isAdjustingBrightness = false; // ✅ 是否正在调整亮度
  bool _isAdjustingVolume = false; // ✅ 是否正在调整音量
  double? _currentBrightness; // ✅ 当前亮度（0.0-1.0）
  double? _currentVolume; // ✅ 当前音量（0-100）
  double? _brightnessAdjustStartValue; // ✅ 开始调整时的亮度
  double? _volumeAdjustStartValue; // ✅ 开始调整时的音量
  double? _originalBrightness; // ✅ 进入播放页面时的原始亮度（退出时恢复）
  Offset? _verticalDragStartPosition; // ✅ 垂直拖动开始位置
  bool _hasTriggeredVolumeAdjust = false; // ✅ 是否已触发音量调整
  bool _hasTriggeredBrightnessAdjust = false; // ✅ 是否已触发亮度调整
  DateTime? _verticalDragStartTime; // ✅ 垂直拖动开始时间（用于计算速度）

  // ✅ 视频标题（用于显示和 PiP）
  String _videoTitle = '';

  // ✅ PiP 模式状态（用于UI显示）
  bool _isInPipMode = false;

  // ✅ 影片详细信息
  ItemInfo? _itemDetails;
  String? _itemType; // Movie, Episode, etc.
  String? _logoUrl; // Logo图片URL
  ItemInfo? _previousEpisode; // 上一集
  ItemInfo? _nextEpisode; // 下一集
  bool _isSwitchingEpisode = false; // ✅ 是否正在切换剧集（防止重复点击）
  String _currentItemId = ''; // ✅ 当前播放的itemId
  bool _hasReportedPlaybackStart = false; // ✅ 是否已汇报播放开始（防止重复汇报）
  bool _hasReportedPlaybackStopped = false; // ✅ 是否已汇报播放停止（防止重复汇报）
  bool _hasStartedPlayback = false; // ✅ 是否已经开始过播放（用于控制背景图显示）
  bool _isFirstTimeAutoPlay = true; // ✅ 是否是首次自动播放（用于延迟隐藏控制栏）

  // ✅ 是否正在执行初始seek（用于隐藏第一帧）
  // bool _isInitialSeeking = false;

  // ✅ 视频裁切模式提示
  bool _showVideoFitHint = false;
  Timer? _videoFitHintTimer;

  // ✅ 速度列表滚动控制器
  final ScrollController _speedListScrollController = ScrollController();

  // ✅ 分辨率选择
  List<Map<String, dynamic>> _qualityOptions = []; // ✅ 可选分辨率列表
  String? _selectedQuality; // ✅ 当前选中的分辨率（null表示自动）
  bool _showQualityList = false; // ✅ 是否显示分辨率列表
  final ScrollController _qualityListScrollController = ScrollController();

  // ✅ 音频和字幕选择
  int? _selectedAudioStreamIndex;
  int? _selectedSubtitleStreamIndex;
  bool _hasManuallySelectedSubtitle = false;
  bool _hasManuallySelectedAudio = false;
  List<Map<String, dynamic>> _audioStreams = [];
  List<Map<String, dynamic>> _subtitleStreams = [];
  bool _showAudioMenu = false; // ✅ 是否显示音频选择菜单
  bool _showSubtitleMenu = false; // ✅ 是否显示字幕选择菜单

  // ✅ 视频详情弹窗
  bool _showMediaInfo = false; // ✅ 是否显示媒体信息弹窗

  // ✅ 自定义字幕URL
  String? _subtitleUrl;

  // ✅ MediaSourceId（用于构建字幕URL）
  String? _mediaSourceId;
  String? _playSessionId; // ✅ PlaySessionId，用于调用 /Sessions/Playing

  // ✅ 实时会话信息（包含转码状态）
  Map<String, dynamic>? _sessionInfo;
  Timer? _sessionInfoUpdateTimer; // ✅ 弹窗打开时的实时更新定时器

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

    // ✅ 保存当前itemId
    _currentItemId = widget.itemId;

    // ✅ 重置 PiP 状态，防止上次播放的 PiP 状态影响本次播放
    _isInPipMode = false;

    // ✅ 禁用自动进入 PiP（防止其他页面的 PiP 状态影响播放页面）
    if (Platform.isAndroid) {
      try {
        _playerLog('🎬 [Player] Disabling auto-enter PiP on page init');
        unawaited(_pip.invokeMethod('exit'));
      } catch (e) {
        _playerLog('❌ [Player] Failed to disable auto-enter PiP: $e');
      }
    }

    // ✅ 如果从上一页传入了 ItemInfo，立即设置（用于显示背景图）
    final itemInfo = widget.itemInfo;
    if (itemInfo != null) {
      _itemDetails = itemInfo;
      _itemType = itemInfo.type;
      _videoTitle = itemInfo.name;
    }

    // ✅ 如果从上一页传入了 Logo URL，立即设置
    if (widget.logoUrl != null) {
      _logoUrl = widget.logoUrl;
    }

    // ✅ 在页面初始化时立即获取并保存原始亮度（在系统可能调整亮度之前）
    // 这样即使系统在进入全屏时自动调整了亮度，我们也能恢复正确的原始亮度
    _getCurrentBrightness().then((_) {
      _originalBrightness = _currentBrightness;
    });

    // ✅ 创建 ExoPlayer 控制器
    _player = ExoPlayerTextureController();
    _initializeExoPlayer();

    // ✅ 初始化控制栏动画
    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeInOut,
    );
    // ✅ 初始状态是显示的，立即执行forward
    _controlsAnimationController.value = 1.0; // 立即设置为显示状态

    // ✅ 进入播放页面时默认横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 初始显示控制栏，但保持全屏沉浸式（不显示系统状态栏）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ✅ 添加应用生命周期监听
    WidgetsBinding.instance.addObserver(this);

    // ✅ 网络速度现在通过 ExoPlayer 的 networkSpeedStream 实时获取
    // 不再需要模拟速度，移除 _speedTimer

    // ✅ 监听 PiP 控制按钮的回调
    _pip.setMethodCallHandler((call) async {
      _playerLog('🎬 [Player] PiP method call: ${call.method}');

      if (call.method == 'togglePlayPause') {
        if (mounted) {
          final playing = _player.isPlaying;
          _playerLog(
              '🎬 [Player] PiP toggle play/pause, current playing: $playing');
          if (playing) {
            await _playerPause();
            _playerLog('🎬 [Player] Paused from PiP control');
          } else {
            await _playerPlay();
            _playerLog('🎬 [Player] Playing from PiP control');
          }

          // 等待播放器状态更新
          await Future.delayed(const Duration(milliseconds: 100));

          // 触发状态更新并通知原生层更新按钮
          if (mounted) {
            final newState = _player.isPlaying;
            setState(() {
              _isPlaying = newState;
            });
            _updatePipActions();
            _playerLog('🎬 [Player] Updated playing state to: $newState');
          }
        }
      } else if (call.method == 'onPipModeChanged') {
        final isInPipMode = call.arguments['isInPipMode'] as bool? ?? false;
        _playerLog(
            '🎬 [Player] PiP mode changed (from native): $isInPipMode, current playing: $_isPlaying');

        if (mounted) {
          setState(() {
            _isInPipMode = isInPipMode;
          });

          // ✅ 退出 PiP 模式时，恢复全屏状态
          if (!isInPipMode) {
            _playerLog('🎬 [Player] Exited PiP mode, back to fullscreen');
            // ✅ 重置手动进入 PiP 标志
            _isManuallyEnteringPip = false;
            // ✅ 确保系统 UI 处于正确状态
            if (_showControls) {
              SystemChrome.setEnabledSystemUIMode(
                SystemUiMode.manual,
                overlays: SystemUiOverlay.values,
              );
            } else {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            }
          }

          _playerLog(
              '🎬 [Player] PiP state updated, current state: ${_isPlaying ? "playing" : "paused"}');
        }
      }

      return null;
    });

    _loadStreamSelections();
  }

  /// ✅ 获取会话信息（在需要时调用）
  Future<void> _fetchSessionInfo() async {
    try {
      final api = await EmbyApi.create();
      final sessionInfo = await api.getCurrentSession();
      if (mounted && sessionInfo != null) {
        setState(() {
          _sessionInfo = sessionInfo;
        });
      }
    } catch (e) {
      _playerLog('⚠️ [Player] Failed to get session info: $e');
    }
  }

  /// ✅ 启动会话信息实时更新定时器（弹窗打开时）
  void _startSessionInfoUpdateTimer() {
    _sessionInfoUpdateTimer?.cancel();
    _sessionInfoUpdateTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || !_showMediaInfo) {
        timer.cancel();
        return;
      }
      await _fetchSessionInfo();
    });
  }

  /// ✅ 停止会话信息实时更新定时器（弹窗关闭时）
  void _stopSessionInfoUpdateTimer() {
    _sessionInfoUpdateTimer?.cancel();
    _sessionInfoUpdateTimer = null;
  }

  /// ✅ 禁用字幕显示（在创建播放器后立即调用）
  Future<void> _disableSubtitle() async {
    await _guardPlayerCommand(
      'disable subtitles',
      () async {
        await _player.disableSubtitles();
        _playerLog('🎬 [Player] Subtitle disabled via ExoPlayer plugin');
      },
      swallowErrors: true,
    );
  }

  /// ✅ 加载保存的音频和字幕选择
  Future<void> _loadStreamSelections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasManualAudio =
          prefs.getBool('item_${widget.itemId}_manual_audio') ?? false;
      final hasManualSubtitle =
          prefs.getBool('item_${widget.itemId}_manual_subtitle') ?? false;

      final audioIndex =
          hasManualAudio ? prefs.getInt('item_${widget.itemId}_audio') : null;
      final subtitleIndex = prefs.getInt('item_${widget.itemId}_subtitle');

      if (mounted) {
        setState(() {
          _selectedAudioStreamIndex = audioIndex;
          _selectedSubtitleStreamIndex = subtitleIndex;
          _hasManuallySelectedAudio = hasManualAudio;
          _hasManuallySelectedSubtitle = hasManualSubtitle;
        });
      }
    } catch (e) {
      _playerLog('❌ [Player] Load stream selections failed: $e');
    }
  }

  Future<void> _initializeExoPlayer() async {
    try {
      final textureId = await _guardPlayerRequest<int>(
        'initialize ExoPlayer',
        () => _player.initialize(),
      );
      if (textureId == null) return;
      if (!mounted) return;
      setState(() {
        _textureId = textureId;
      });
      _attachPlayerStreams();
      await _disableSubtitle();
      await _load();
    } catch (e) {
      _playerLog('❌ [Player] Initialize ExoPlayer failed: $e');
    }
  }

  void _attachPlayerStreams() {
    _posSub?.cancel();
    _posSub = _player.positionStream.listen(_handlePositionUpdate);

    _durSub?.cancel();
    _durSub = _player.durationStream.listen((d) {
      if (mounted && d != Duration.zero) {
        _playerLog('🎬 [Player] Duration updated: $d');
        setState(() => _duration = d);
      }
    });

    _bufferSub?.cancel();
    _bufferSub = _player.bufferStream.listen((buffer) {
      if (mounted) {
        _bufferPosition = buffer;
        final bufferSeconds = buffer.inSeconds;
        final positionSeconds = _position.inSeconds;
        final bufferedAhead = (buffer - _position).inSeconds;
        _playerLog(
            '🎬 [Player] Buffer updated: ${bufferSeconds}s, position: ${positionSeconds}s, buffered ahead: ${bufferedAhead}s');
        setState(() {});
      }
    });

    _bufferingSub?.cancel();
    _bufferingSub = _player.bufferingStream.listen((isBuffering) async {
      final bufferSeconds = _bufferPosition.inSeconds;
      final positionSeconds = _position.inSeconds;
      final bufferedAhead = (_bufferPosition - _position).inSeconds;
      _playerLog(
          '🎬 [Player] Buffering状态变化: $isBuffering, buffer: ${bufferSeconds}s, position: ${positionSeconds}s, buffered ahead: ${bufferedAhead}s');
      if (!mounted) return;

      // ✅ 记录之前的缓冲状态
      final wasBuffering = _isBuffering;

      // ✅ 统计缓冲信息
      if (isBuffering) {
        _bufferingCount++;
        _lastBufferingStart = DateTime.now();
      } else if (_lastBufferingStart != null) {
        final bufferingDuration =
            DateTime.now().difference(_lastBufferingStart!);
        _totalBufferingTime += bufferingDuration;
        _playerLog(
            '📊 [Player] Buffering duration: ${bufferingDuration.inMilliseconds}ms');
      }

      setState(() => _isBuffering = isBuffering);

      // ✅ 如果从缓冲状态变为非缓冲状态，且播放器应该在播放但实际没有播放，则恢复播放
      // ✅ 但要确保已经完成初始加载（_ready == true），避免与初始播放逻辑冲突
      if (wasBuffering && !isBuffering && _ready && !_player.isPlaying) {
        _playerLog(
            '🎬 [Player] Buffering ended, checking if need to resume playback...');
        // 延迟一小段时间，确保播放器状态稳定
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted && _ready && !_player.isPlaying) {
          _playerLog('🎬 [Player] Resuming playback after buffering');
          await _playerPlay();
        }
      }
    });

    _playingSub?.cancel();
    _playingSub = _player.playingStream.listen((isPlaying) async {
      _playerLog('🎬 [Player] Playing: $isPlaying');
      if (mounted) {
        setState(() {
          _isPlaying = isPlaying;
          // ✅ 开始播放时，标记已开始播放（隐藏背景图）
          if (isPlaying && !_hasStartedPlayback) {
            _hasStartedPlayback = true;
          }
        });

        // ✅ 通知原生层播放状态，用于 onUserLeaveHint 自动进入 PiP
        if (Platform.isAndroid) {
          try {
            await _pip.invokeMethod('setPlayingState', {
              'isPlaying': isPlaying,
              'title': _videoTitle,
            });
            _playerLog('🎬 [Player] Notified native playing state: $isPlaying');
          } catch (e) {
            _playerLog('❌ [Player] Failed to notify native playing state: $e');
          }
        }
      }
      if (!isPlaying) {
        _syncProgress(_position, force: true);
        _cancelHideControlsTimer(); // 暂停时不自动隐藏控制栏
      } else {
        // ✅ 播放时，如果控制栏显示则启动自动隐藏计时器
        if (_showControls) {
          // ✅ 如果是首次自动播放，立刻隐藏控制栏（但要检查是否有菜单显示）
          if (_isFirstTimeAutoPlay) {
            _isFirstTimeAutoPlay = false;
            // ✅ 如果有音频或字幕菜单显示，不隐藏控制栏
            if (!_showAudioMenu && !_showSubtitleMenu) {
              _playerLog(
                  '🎬 [Player] First time auto play, hide controls immediately');
              _controlsAnimationController.reverse();
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              if (mounted) {
                setState(() {
                  _showControls = false;
                });
              }
            }
          } else {
            // ✅ 非首次播放（用户手动显示控制栏后），3秒后自动隐藏
            _startHideControlsTimer();
          }
        }

        // ✅ 只在未汇报过播放开始时才汇报（防止重复汇报）
        if (!_hasReportedPlaybackStart &&
            _api != null &&
            _userId != null &&
            _playSessionId != null &&
            _mediaSourceId != null) {
          try {
            final audioIndex = _getCurrentAudioStreamIndex();
            final subtitleIndex = _getCurrentSubtitleStreamIndex();
            _playerLog(
                '🎬 [Player] Reporting playback start - Audio: $audioIndex, Subtitle: $subtitleIndex');

            await _api!.reportPlaybackStart(
              itemId: _currentItemId,
              userId: _userId!,
              playSessionId: _playSessionId!,
              mediaSourceId: _mediaSourceId,
              positionTicks: _initialSeekPosition != null
                  ? (_initialSeekPosition!.inMicroseconds * 10).toInt()
                  : 0,
              audioStreamIndex: audioIndex,
              subtitleStreamIndex: subtitleIndex,
            );
            _hasReportedPlaybackStart = true; // ✅ 标记已汇报
            _playerLog('✅ [Player] Reported playback start to Emby server');
          } catch (e) {
            _playerLog('⚠️ [Player] Failed to report playback start: $e');
          }
        }
      }

      _updatePipActions();
      _updateMediaNotification();
    });

    _readySub?.cancel();
    _readySub = _player.readyStream.listen((ready) async {
      if (mounted) {
        setState(() => _ready = ready);
      }

      // ✅ 当播放器准备就绪时，确保播放已经开始
      if (ready && mounted) {
        // 延迟检查，给 autoPlay 一些时间生效
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && _ready && !_player.isPlaying && !_isBuffering) {
          _playerLogImportant(
              '🎬 [Player] Player ready but not playing, starting playback');
          await _playerPlay();
        }
      }
    });

    _errorSub?.cancel();
    _errorSub = _player.errorStream.listen((message) {
      _playerLog('❌ [Player] Error: $message');
      _handlePlaybackError(message);
    });

    _videoSizeSub?.cancel();
    _videoSizeSub = _player.videoSizeStream.listen((size) {
      if (mounted) {
        setState(() => _videoSize = size);
      }
    });

    _networkSpeedSub?.cancel();
    _networkSpeedSub = _player.networkSpeedStream.listen((speedBps) {
      if (mounted) {
        // ✅ 将 bps 转换为 kbps（始终更新，不仅在缓冲时）
        final speedKbps = speedBps / 1000;
        setState(() {
          _currentSpeedKbps = speedKbps;
        });
        // ✅ 只在缓冲时显示日志
        if (_isBuffering) {
          _playerLog(
              '📶 [Player] Network speed: ${(speedKbps / 1000).toStringAsFixed(1)} Mbps');
        }
      }
    });
  }

  // ✅ 保存音频和字幕选择（保存数组索引，用于UI显示）
  Future<void> _saveStreamSelections() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ 保存音频数组索引
      if (_selectedAudioStreamIndex != null &&
          _selectedAudioStreamIndex! >= 0) {
        await prefs.setInt(
            'item_${widget.itemId}_audio', _selectedAudioStreamIndex!);
        _playerLog('💾 [Player] 保存音频选择(数组索引): $_selectedAudioStreamIndex');
      }

      // ✅ 保存字幕数组索引（支持-1表示不显示）
      if (_selectedSubtitleStreamIndex != null) {
        await prefs.setInt(
            'item_${widget.itemId}_subtitle', _selectedSubtitleStreamIndex!);
        _playerLog(
            '💾 [Player] 保存字幕选择(数组索引): $_selectedSubtitleStreamIndex, manual: $_hasManuallySelectedSubtitle');
      }

      await prefs.setBool(
          'item_${widget.itemId}_manual_audio', _hasManuallySelectedAudio);
      await prefs.setBool('item_${widget.itemId}_manual_subtitle',
          _hasManuallySelectedSubtitle);
    } catch (e) {
      _playerLog('❌ [Player] Save stream selections failed: $e');
    }
  }

  // ✅ 重新加载播放器（当音频或字幕流改变时）
  Future<void> _reloadPlayer() async {
    if (_api == null) return;

    try {
      _playerLogImportant(
          '🔄 [Player] Reloading player with new stream selection...');

      // ✅ 保存当前播放位置
      final currentPosition = _position;
      final wasPlaying = _isPlaying;

      // ✅ 暂停播放
      if (wasPlaying) {
        await _playerPause();
      }

      // ✅ 获取选中的画质参数
      Map<String, dynamic>? qualityOption;
      if (_selectedQuality != null && _qualityOptions.isNotEmpty) {
        qualityOption = _qualityOptions.firstWhere(
          (q) => q['label'] == _selectedQuality,
          orElse: () => <String, dynamic>{},
        );
      }

      // ✅ 获取实际的 MediaStream Index（不是数组索引）
      int? actualAudioIndex;
      int? actualSubtitleIndex;

      if (_selectedAudioStreamIndex != null &&
          _selectedAudioStreamIndex! >= 0 &&
          _selectedAudioStreamIndex! < _audioStreams.length) {
        actualAudioIndex =
            _audioStreams[_selectedAudioStreamIndex!]['Index'] as int?;
      }

      if (_selectedSubtitleStreamIndex != null &&
          _selectedSubtitleStreamIndex! >= 0) {
        if (_selectedSubtitleStreamIndex! < _subtitleStreams.length) {
          actualSubtitleIndex =
              _subtitleStreams[_selectedSubtitleStreamIndex!]['Index'] as int?;
        }
      } else if (_selectedSubtitleStreamIndex == -1) {
        // -1 表示不显示字幕
        actualSubtitleIndex = -1;
      }

      _playerLog(
          '🎬 [Player] Array indices - Audio: $_selectedAudioStreamIndex, Subtitle: $_selectedSubtitleStreamIndex');
      _playerLog(
          '🎬 [Player] MediaStream indices - Audio: $actualAudioIndex, Subtitle: $actualSubtitleIndex');

      // ✅ 构建新的 HLS URL
      final media = await _api!.buildHlsUrl(
        widget.itemId,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
        maxBitrate: qualityOption?['bitrate'] as int?,
        startTimeTicks: currentPosition.inMicroseconds > 0
            ? (currentPosition.inMicroseconds * 10).toInt()
            : null,
      );

      _playerLog('🎬 [Player] New media URL: ${media.uri}');

      // ✅ 检测是否为 HLS 流
      final isHlsStream =
          media.uri.contains('.m3u8') || media.uri.contains('hls');

      // ✅ 使用自适应缓冲策略
      final cacheConfig = _getAdaptiveCacheConfig();

      // ✅ 重新打开媒体（使用快速启动逻辑）
      await _guardPlayerCommand(
        'reload media',
        () => _player.open(
          url: media.uri,
          headers: media.headers,
          isHls: isHlsStream,
          autoPlay: wasPlaying, // ✅ 根据之前的播放状态决定是否自动播放
          startPosition: currentPosition > Duration.zero
              ? currentPosition
              : null, // ✅ 直接传入位置
          cacheConfig: cacheConfig, // ✅ 使用自适应缓冲配置
        ),
      );

      // ✅ 禁用内置字幕
      await _disableSubtitle();

      // ✅ 更新 UI 位置
      if (currentPosition > Duration.zero && mounted) {
        setState(() {
          _position = currentPosition;
        });
      }

      _playerLogImportant('✅ [Player] Player reloaded successfully');
    } catch (e) {
      _playerLog('❌ [Player] Reload player failed: $e');
    }
  }

  Future<void> _load() async {
    try {
      // ✅ 重置音频轨道尝试记录
      _triedAudioIndices.clear();

      if (mounted) {
        setState(() {
          _isBuffering = true;
          _ready = false;
          _bufferPosition = Duration.zero; // 重置缓冲进度
        });
      }
      _playerLog('🎬 [Player] Loading item: $_currentItemId');
      final api = await EmbyApi.create();
      _api = api;
      final authState = ref.read(authStateProvider);
      _userId = authState.value?.userId;

      // ✅ 获取视频详细信息（用于显示和PiP）
      // 如果从上一页传入了 ItemInfo，就使用缓存数据，避免重复请求
      ItemInfo? itemDetails;
      if (widget.itemInfo != null) {
        _playerLog('✅ [Player] Using cached ItemInfo, skip getItem request');
        itemDetails = widget.itemInfo;
      } else if (_itemDetails != null) {
        // 如果 initState 中已经设置了（从 widget.itemInfo），就使用现有的
        _playerLog('✅ [Player] Using ItemInfo from initState');
        itemDetails = _itemDetails;
      } else {
        itemDetails = _userId != null
            ? await api.getItem(_userId!, _currentItemId)
            : null;
      }

      // ✅ 更新标题（如果还没有设置）
      if (_videoTitle.isEmpty || _videoTitle == 'Video') {
        _videoTitle = itemDetails?.name ?? 'Video';
      }

      // ✅ 更新 itemDetails 并触发 UI 刷新（如果还没有设置）
      if (_itemDetails == null) {
        final details = itemDetails;
        if (details != null) {
          if (mounted) {
            setState(() {
              _itemDetails = details;
              _itemType = details.type;
            });
          } else {
            _itemDetails = details;
            _itemType = details.type;
          }
        }
      }

      // ✅ 获取Logo URL（优先使用传入的，避免重复请求）
      final logoUrl = widget.logoUrl;
      if (logoUrl != null) {
        _playerLog('✅ [Player] Using cached logo URL');
        _logoUrl = logoUrl;
      } else if (itemDetails != null && itemDetails.id != null) {
        // 对于Episode类型，尝试获取Series的Logo
        if (itemDetails.type == 'Episode' && itemDetails.seriesId != null) {
          // 优先使用传入的 seriesInfo
          final seriesInfo = widget.seriesInfo;
          if (seriesInfo != null) {
            _playerLog('✅ [Player] Using cached series info for logo');
            if (seriesInfo.imageTags != null &&
                seriesInfo.imageTags!.containsKey('Logo')) {
              _logoUrl = api.buildImageUrl(
                itemId: itemDetails.seriesId!,
                type: 'Logo',
                maxWidth: 400,
                tag: seriesInfo.imageTags!['Logo'],
              );
            }
          } else {
            try {
              final seriesInfo =
                  await api.getItem(_userId!, itemDetails.seriesId!);
              if (seriesInfo.imageTags != null &&
                  seriesInfo.imageTags!.containsKey('Logo')) {
                _logoUrl = api.buildImageUrl(
                  itemId: itemDetails.seriesId!,
                  type: 'Logo',
                  maxWidth: 400,
                  tag: seriesInfo.imageTags!['Logo'],
                );
              }
            } catch (e) {
              _playerLog('⚠️ [Player] Failed to get series logo: $e');
            }
          }
        } else {
          // 对于Movie等类型，直接获取Logo
          if (itemDetails.imageTags != null &&
              itemDetails.imageTags!.containsKey('Logo')) {
            _logoUrl = api.buildImageUrl(
              itemId: itemDetails.id!,
              type: 'Logo',
              maxWidth: 400,
              tag: itemDetails.imageTags!['Logo'],
            );
          }
        }
      }

      // ✅ 如果是Episode类型，获取上一集和下一集
      if (itemDetails != null &&
          itemDetails.type == 'Episode' &&
          itemDetails.seriesId != null &&
          _userId != null) {
        try {
          _previousEpisode = await api.getPreviousEpisode(
            userId: _userId!,
            seriesId: itemDetails.seriesId!,
            currentEpisodeId: _currentItemId,
          );
          _nextEpisode = await api.getNextEpisode(
            userId: _userId!,
            seriesId: itemDetails.seriesId!,
            currentEpisodeId: _currentItemId,
          );
          _playerLog(
              '🎬 [Player] Previous episode: ${_previousEpisode?.name}, Next episode: ${_nextEpisode?.name}');
        } catch (e) {
          _playerLog('⚠️ [Player] Failed to get previous/next episode: $e');
        }
      }

      // ✅ 提取音频和字幕流
      if (itemDetails != null) {
        _audioStreams = _getAudioStreams(itemDetails);
        _subtitleStreams = _getSubtitleStreams(itemDetails);

        // ✅ 获取 PlaybackInfo 以获取正确的 MediaSourceId 和分辨率选项
        if (_userId != null) {
          try {
            // ✅ 获取实际的 MediaStream Index（用于 PlaybackInfo）
            int? actualAudioIndex;
            int? actualSubtitleIndex;

            if (_hasManuallySelectedAudio &&
                _selectedAudioStreamIndex != null &&
                _selectedAudioStreamIndex! >= 0 &&
                _selectedAudioStreamIndex! < _audioStreams.length) {
              actualAudioIndex =
                  _audioStreams[_selectedAudioStreamIndex!]['Index'] as int?;
            }

            if (_hasManuallySelectedSubtitle &&
                _selectedSubtitleStreamIndex != null) {
              if (_selectedSubtitleStreamIndex! >= 0 &&
                  _selectedSubtitleStreamIndex! < _subtitleStreams.length) {
                actualSubtitleIndex =
                    _subtitleStreams[_selectedSubtitleStreamIndex!]['Index']
                        as int?;
              } else if (_selectedSubtitleStreamIndex == -1) {
                actualSubtitleIndex = -1;
              }
            }

            _playerLog(
                '🎬 [Player] PlaybackInfo request - Audio Index: $actualAudioIndex, Subtitle Index: $actualSubtitleIndex');

            // ✅ 调用 PlaybackInfo，传递音频和字幕索引
            // ✅ 如果有初始播放位置（恢复播放），传递对应的 ticks 值
            final playbackInfo = await api.getPlaybackInfo(
              itemId: _currentItemId,
              userId: _userId!,
              startTimeTicks: _initialSeekPosition != null
                  ? (_initialSeekPosition!.inMicroseconds * 10).toInt()
                  : 0,
              isPlayback: false,
              autoOpenLiveStream: false,
              audioStreamIndex: actualAudioIndex,
              subtitleStreamIndex: actualSubtitleIndex,
            );
            _playerLog('🎬 [Player] PlaybackInfo: $playbackInfo');

            // ✅ 从 PlaybackInfo 中获取 MediaSourceId 和视频信息
            Map<String, dynamic>? playbackMediaSource;
            if (playbackInfo['MediaSources'] != null &&
                playbackInfo['MediaSources'] is List &&
                (playbackInfo['MediaSources'] as List).isNotEmpty) {
              final firstSource = (playbackInfo['MediaSources'] as List).first;
              if (firstSource is Map) {
                playbackMediaSource = Map<String, dynamic>.from(firstSource);
                _mediaSourceId = playbackMediaSource['Id'] as String?;
                _playerLog(
                    '🎬 [Player] MediaSourceId from PlaybackInfo: $_mediaSourceId');
              }
            }

            // ✅ 根据原始视频分辨率和码率生成画质选项
            // ✅ 优先从 MediaSource 获取宽高，如果没有则从 VideoStream 获取
            final mediaWidth = (playbackMediaSource?['Width'] as num?)?.toInt();
            final mediaHeight =
                (playbackMediaSource?['Height'] as num?)?.toInt();
            final videoStream =
                _getVideoStreamFromMediaSource(playbackMediaSource);
            final sourceWidth =
                mediaWidth ?? (videoStream?['Width'] as num?)?.toInt();
            final sourceHeight =
                mediaHeight ?? (videoStream?['Height'] as num?)?.toInt();

            // ✅ 从视频流中获取比特率（不是整个 MediaSource 的比特率）
            final videoBitrate = (videoStream?['BitRate'] as num?)?.toInt();
            _playerLog(
                '🎬 [Player] Video stream bitrate: $videoBitrate (${videoBitrate != null ? (videoBitrate / 1000000).toStringAsFixed(1) : "unknown"}Mbps)');

            final generatedOptions = _generateSimpleQualityOptions(
                videoBitrate, sourceWidth, sourceHeight);
            _playerLog(
                '🎬 [Player] Original: ${sourceWidth}x${sourceHeight}, bitrate: $videoBitrate, Generated quality options: ${generatedOptions.map((o) => o['label']).join(', ')}');

            if (mounted) {
              setState(() {
                _qualityOptions = generatedOptions;
              });
            }

            // ✅ 加载分辨率选择逻辑
            final prefs = await SharedPreferences.getInstance();

            // ✅ 检查该视频是否手动选择过画质
            final hasManualSelection =
                prefs.getBool('manual_quality_${widget.itemId}') ?? false;
            final savedQuality =
                prefs.getString('selected_quality_${widget.itemId}');

            String? selectedQuality;

            if (hasManualSelection &&
                savedQuality != null &&
                _qualityOptions.any((q) => q['label'] == savedQuality)) {
              // 该视频手动选择过画质，使用手动选择的
              selectedQuality = savedQuality;
              _playerLog(
                  '🎬 [Player] Using manual selection: $selectedQuality');
            } else {
              // 该视频没有手动选择过，根据播放质量策略自动选择
              final qualityStrategy =
                  prefs.getString('playback_quality_strategy') ?? 'quality';

              if (qualityStrategy == 'quality') {
                // 质量优先：选择原始分辨率
                selectedQuality = _selectQualityForQualityMode();
                _playerLog('🎬 [Player] Quality priority: $selectedQuality');
              } else if (qualityStrategy == 'speed') {
                // 速度优先：网络允许时走自动，否则使用1080p最低画质
                selectedQuality = _selectQualityForSpeedMode();
                _playerLog('🎬 [Player] Speed priority: $selectedQuality');
              } else {
                // 自动：根据网络速度自动切换
                selectedQuality = _selectQualityForAutoMode();
                _playerLog('🎬 [Player] Auto mode: $selectedQuality');
              }

              // 如果没有选中任何画质，使用原始分辨率作为后备
              if (selectedQuality == null) {
                selectedQuality = _getOriginalQuality();
                _playerLog(
                    '🎬 [Player] Fallback to original quality: $selectedQuality');
              }
            }

            if (selectedQuality != null && mounted) {
              setState(() {
                _selectedQuality = selectedQuality;
              });
            }
          } catch (e) {
            _playerLog('❌ [Player] Failed to get PlaybackInfo: $e');
            // ✅ 如果 PlaybackInfo 失败，尝试从 itemDetails 获取 MediaSourceId
            final media = _getPrimaryMediaSource(itemDetails);
            if (media != null) {
              _mediaSourceId = media['Id'] as String?;
              _playerLog(
                  '🎬 [Player] MediaSourceId from itemDetails: $_mediaSourceId');
            }
          }
        }

        _ensureAudioSelection();
        _ensureSubtitleSelection();
        // ✅ 初始化字幕URL
        _updateSubtitleUrl();
      }

      // ✅ 构建 HLS URL
      // 注意：对于 HLS 流，Emby 会自动处理音频和字幕选择
      // 只有在用户手动选择时才传递参数，否则让 Emby 自动选择

      // ✅ 获取选中的画质参数
      Map<String, dynamic>? qualityOption;
      if (_selectedQuality != null && _qualityOptions.isNotEmpty) {
        qualityOption = _qualityOptions.firstWhere(
          (q) => q['label'] == _selectedQuality,
          orElse: () => <String, dynamic>{},
        );
        if (qualityOption.isEmpty) {
          qualityOption = null;
        }
        _playerLogImportant(
            '🎬 [Player] Selected quality: ${qualityOption?['label']}, '
            'bitrate=${qualityOption?['bitrate']}');
      } else {
        _playerLogImportant(
            '🎬 [Player] No quality selected (will use original quality)');
      }

      // ✅ 获取实际的 MediaStream Index（不是数组索引）
      int? actualAudioIndex;
      int? actualSubtitleIndex;

      if (_hasManuallySelectedAudio &&
          _selectedAudioStreamIndex != null &&
          _selectedAudioStreamIndex! >= 0 &&
          _selectedAudioStreamIndex! < _audioStreams.length) {
        actualAudioIndex =
            _audioStreams[_selectedAudioStreamIndex!]['Index'] as int?;
      } else if (_audioStreams.isNotEmpty) {
        // ✅ 如果没有手动选择，使用第一个音轨
        actualAudioIndex = _audioStreams[0]['Index'] as int?;
        _playerLog(
            '🎬 [Player] Using default audio track (Index: $actualAudioIndex)');
      }

      if (_hasManuallySelectedSubtitle &&
          _selectedSubtitleStreamIndex != null) {
        if (_selectedSubtitleStreamIndex! >= 0 &&
            _selectedSubtitleStreamIndex! < _subtitleStreams.length) {
          actualSubtitleIndex =
              _subtitleStreams[_selectedSubtitleStreamIndex!]['Index'] as int?;
        } else if (_selectedSubtitleStreamIndex == -1) {
          // -1 表示不显示字幕
          actualSubtitleIndex = -1;
        }
      } else {
        // ✅ 如果没有手动选择字幕，默认不显示字幕
        actualSubtitleIndex = -1;
        _playerLog('🎬 [Player] Using default subtitle setting (disabled)');
      }

      _playerLog(
          '🎬 [Player] Initial load - Array indices - Audio: $_selectedAudioStreamIndex, Subtitle: $_selectedSubtitleStreamIndex');
      _playerLog(
          '🎬 [Player] Initial load - MediaStream indices - Audio: $actualAudioIndex, Subtitle: $actualSubtitleIndex');

      final requestedBitrate = qualityOption?['bitrate'] as int?;
      _playerLogImportant(
          '🎬 [Player] Initial load with bitrate: $requestedBitrate');

      final media = await api.buildHlsUrl(
        _currentItemId,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
        maxBitrate: requestedBitrate,
        startTimeTicks: _initialSeekPosition != null
            ? (_initialSeekPosition!.inMicroseconds * 10).toInt()
            : null,
        cachedItemJson: itemDetails?.toJson(), // ✅ 传入缓存数据，避免重复请求
      );
      _playerLog('🎬 [Player] Media URL: ${media.uri}');
      _playerLog('🎬 [Player] Video Title: $_videoTitle');
      _playerLog(
          '🎬 [Player] Selected audio stream: $_selectedAudioStreamIndex, subtitle stream: $_selectedSubtitleStreamIndex');

      // ✅ 保存 PlaySessionId 和 MediaSourceId，用于调用 /Sessions/Playing
      _playSessionId = media.playSessionId;
      _mediaSourceId =
          media.mediaSourceId; // ✅ 使用从 TranscodingUrl 返回的 mediaSourceId
      _playerLog('🎬 [Player] PlaySessionId: $_playSessionId');
      _playerLog('🎬 [Player] MediaSourceId: $_mediaSourceId');
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
      await _playerSetRate(_speed);

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

      final resumeFromSavedPosition =
          _initialSeekPosition != null && _initialSeekPosition! > Duration.zero;

      _playerLogImportant(
          '🎬 [Player] resumeFromSavedPosition: $resumeFromSavedPosition, initialPosition: $_initialSeekPosition');

      // ✅ 打开媒体（设置标题以支持系统媒体通知）
      _playerLog('🎬 [Player] Opening media with title: $_videoTitle');

      // ✅ 检测是否为 HLS 流
      final isHlsStream =
          media.uri.contains('.m3u8') || media.uri.contains('hls');
      _playerLog('🎬 [Player] Is HLS stream: $isHlsStream');
      _playerLog('🎬 [Player] Media URI: ${media.uri}');
      _playerLog(
          '🎬 [Player] Video resolution: ${media.width}x${media.height}');
      _playerLog('🎬 [Player] Video bitrate: ${media.bitrate} bps');

      // ✅ 优化：使用 autoPlay 立即开始播放，提升响应速度
      // ✅ 使用自适应缓冲策略，根据网络速度动态调整
      final cacheConfig = _getAdaptiveCacheConfig();

      await _guardPlayerCommand(
        'open media',
        () => _player.open(
          url: media.uri,
          headers: media.headers,
          isHls: isHlsStream,
          autoPlay: true, // ✅ 立即自动播放，加快启动速度
          startPosition: resumeFromSavedPosition
              ? _initialSeekPosition
              : null, // ✅ 直接传入起始位置
          cacheConfig: cacheConfig, // ✅ 使用自适应缓冲配置
        ),
      );

      // ✅ 在 open 之后再次确保字幕被禁用
      await _disableSubtitle();

      await _playerSetVolume(100.0);
      _currentVolume = 100.0; // ✅ 保存当前音量
      _playerLog('🎬 [Player] Volume set to 100%');

      // ✅ 显示系统媒体通知
      _playerLog('🎬 [Player] ✅ Media opened successfully');
      _showMediaNotification();

      // ✅ 等待播放器准备就绪并确保开始播放
      _playerLogImportant(
          '🎬 [Player] Waiting for player ready and ensuring playback...');
      await Future.delayed(const Duration(milliseconds: 300));

      // ✅ 明确检查并启动播放（防止 autoPlay 失败）
      if (mounted && !_player.isPlaying) {
        _playerLogImportant(
            '🎬 [Player] AutoPlay did not start, manually starting playback');
        await _playerPlay();
      } else {
        _playerLogImportant('🎬 [Player] Playback started with autoPlay');
      }

      // ✅ 更新初始位置（如果有）
      if (resumeFromSavedPosition && _initialSeekPosition != null) {
        if (mounted) {
          setState(() {
            _position = _initialSeekPosition!;
          });
        }
        _lastReportedPosition = _initialSeekPosition!;
      }

      if (mounted) {
        setState(() {
          _ready = true;
          // ✅ 不在这里设置 _isBuffering = false
          // _isBuffering 由 buffering stream 控制，确保缓冲完成后才消失
        });
        // ✅ 获取当前音量（亮度已在 initState 时保存）
        _getCurrentVolume();

        // ✅ 如果原始亮度还未保存（可能在 initState 时获取失败），再次尝试保存
        // 注意：只在 _originalBrightness 为 null 时保存，避免覆盖已保存的原始值
        if (_originalBrightness == null) {
          _getCurrentBrightness().then((_) {
            if (_originalBrightness == null && _currentBrightness != null) {
              _originalBrightness = _currentBrightness;
            }
          });
        }
      }
      _playerLog(
          '🎬 [Player] ✅ Ready to play, isPlaying: $_isPlaying, isBuffering: $_isBuffering');
    } catch (e) {
      _playerLog('❌ [Player] Load failed: $e');
    }
  }

  @override
  void dispose() {
    _playerLog('🎬 [Player] 🔴 PlayerPage disposing...');

    // ✅ 上报播放统计
    _reportPlaybackStats();

    // ✅ 隐藏系统媒体通知
    _hideMediaNotification();

    _posSub?.cancel();
    _durSub?.cancel(); // ✅ 取消 duration 订阅
    _bufferingSub?.cancel();
    _playingSub?.cancel(); // ✅ 取消播放状态订阅
    _bufferSub?.cancel();
    _readySub?.cancel();
    _videoSizeSub?.cancel();
    _errorSub?.cancel();
    _networkSpeedSub?.cancel(); // ✅ 取消网络速度订阅
    _hideControlsTimer?.cancel();
    _videoFitHintTimer?.cancel(); // ✅ 取消视频裁切模式提示计时器
    _longPressTimer?.cancel(); // ✅ 取消长按定时器
    _speedAccelerationTimer?.cancel(); // ✅ 取消倍速加速定时器
    _retryTimer?.cancel(); // ✅ 取消重试定时器
    _sessionInfoUpdateTimer?.cancel(); // ✅ 取消会话信息更新定时器
    _audioSwitchHintTimer?.cancel(); // ✅ 取消音频切换提示定时器
    _speedListScrollController.dispose(); // ✅ 释放速度列表滚动控制器
    _qualityListScrollController.dispose(); // ✅ 释放分辨率列表滚动控制器
    _controlsAnimationController.dispose();

    // ✅ 清空大对象引用，帮助 GC
    _itemDetails = null;
    _previousEpisode = null;
    _nextEpisode = null;
    _audioStreams = [];
    _subtitleStreams = [];
    _qualityOptions = [];
    final markComplete =
        _duration > Duration.zero && _position >= _duration * 0.95;
    _syncProgress(_position, force: true, markComplete: markComplete);

    // ✅ 通知 Emby 服务器停止播放
    if (_api != null &&
        _userId != null &&
        _playSessionId != null &&
        _mediaSourceId != null) {
      final positionTicks = (_position.inMicroseconds * 10).toInt();
      unawaited(_api!.reportPlaybackStopped(
        itemId: _currentItemId,
        userId: _userId!,
        playSessionId: _playSessionId!,
        mediaSourceId: _mediaSourceId,
        positionTicks: positionTicks,
      ));
      _playerLog('✅ [Player] Reported playback stopped to Emby server');
    }
    // ✅ 退出时确保保存字幕和音频选择（不等待，后台执行）
    unawaited(_saveStreamSelections());
    unawaited(_player.dispose());

    // ✅ 重置 PiP 状态并禁用自动进入 PiP
    _isInPipMode = false;
    if (Platform.isAndroid) {
      try {
        _playerLog('🎬 [Player] Disabling auto-enter PiP on page dispose');
        unawaited(_pip.invokeMethod('exit'));
      } catch (e) {
        _playerLog(
            '❌ [Player] Failed to disable auto-enter PiP on dispose: $e');
      }
    }

    // ✅ 恢复原始亮度（只有在保存了原始亮度时才恢复）
    // 注意：在 dispose 前获取保存的原始亮度值，防止被修改
    // TODO: 暂时注释掉，等待修复亮度恢复问题
    /*
    final brightnessToRestore = _originalBrightness;
    if (brightnessToRestore != null) {
      // 使用 unawaited，因为 dispose 不能是 async
      unawaited(_setBrightness(brightnessToRestore));
    }
    */
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    // ✅ 移除 libraryRefreshTickerProvider 的使用，全局刷新在页面生命周期时进行
    // 播放页面退出时，刷新首页的继续观看列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(resumeProvider);
      }
    });

    // ✅ 移除应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  Future<void> _changeSpeed(double v) async {
    _playerLog('🎬 [Player] Changing playback speed to: ${v}x');
    setState(() => _speed = v);
    await _playerSetRate(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', v);
    _playerLog('🎬 [Player] ✅ Playback speed changed to: ${v}x');
  }

  // ✅ 设置屏幕亮度
  Future<void> _setBrightness(double brightness) async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.embyhub/brightness');
        await platform
            .invokeMethod('setBrightness', {'brightness': brightness});
      } else if (Platform.isIOS) {
        // iOS 使用系统 API
        const platform = MethodChannel('com.embyhub/brightness');
        await platform
            .invokeMethod('setBrightness', {'brightness': brightness});
      }
    } on PlatformException catch (e) {
      _playerLog(
          '❌ [Player] Failed to set brightness (code: ${e.code}): ${e.message}');
    } catch (e) {
      _playerLog('❌ [Player] Failed to set brightness: $e');
    }
  }

  // ✅ 获取当前屏幕亮度
  Future<void> _getCurrentBrightness() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        const platform = MethodChannel('com.embyhub/brightness');
        final brightness = await platform.invokeMethod<double>('getBrightness');
        if (brightness != null && mounted) {
          setState(() {
            _currentBrightness = brightness;
          });
        }
      }
    } on PlatformException catch (e) {
      _playerLog(
          '❌ [Player] Failed to get brightness (code: ${e.code}): ${e.message}');
    } catch (e) {
      _playerLog('❌ [Player] Failed to get brightness: $e');
    }
  }

  // ✅ 获取当前系统音量
  Future<void> _getCurrentVolume() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.embyhub/brightness');
        final volume = await platform.invokeMethod<double>('getVolume');
        if (volume != null && mounted) {
          setState(() {
            _currentVolume = volume;
          });
        }
      } else if (Platform.isIOS) {
        const platform = MethodChannel('com.embyhub/brightness');
        final volume = await platform.invokeMethod<double>('getVolume');
        if (volume != null && mounted) {
          setState(() {
            _currentVolume = volume;
          });
        }
      }
    } on PlatformException catch (e) {
      _playerLog(
          '❌ [Player] Failed to get volume (code: ${e.code}): ${e.message}');
    } catch (e) {
      _playerLog('🎬 [Player] Failed to get volume: $e');
    }
  }

  // ✅ 设置系统音量
  Future<void> _setSystemVolume(double volume) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        const platform = MethodChannel('com.embyhub/brightness');
        await platform.invokeMethod('setVolume', {'volume': volume});
      }
    } on PlatformException catch (e) {
      _playerLog(
          '❌ [Player] Failed to set volume (code: ${e.code}): ${e.message}');
    } catch (e) {
      _playerLog('🎬 [Player] Failed to set volume: $e');
    }
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

  // ✅ 停止长按
  void _stopLongPress() async {
    _longPressTimer?.cancel();
    _suppressPositionUpdates = false;

    if (_isLongPressingForward || _isLongPressingRewind) {
      final originalSpeed = _originalSpeed;

      setState(() {
        _isLongPressingForward = false;
        _isLongPressingRewind = false;
        _longPressPosition = null;
        _longPressStartTime = null; // ✅ 清除长按开始时间
        _originalSpeed = null; // ✅ 清除原始倍速
      });

      // ✅ 恢复原始倍速（平滑恢复，1秒内完成）
      if (originalSpeed != null) {
        _restoreSpeed(originalSpeed);
      }
    }
  }

  void _applyTransientSpeed(double targetSpeed) {
    unawaited(_playerSetRate(
      targetSpeed,
      swallowErrors: true,
      action: 'set transient playback speed',
    ));
    if (mounted) {
      setState(() {
        _speed = targetSpeed;
      });
    } else {
      _speed = targetSpeed;
    }
  }

  // ✅ 开始倍速加速（从当前倍速平滑加速到3倍速，1秒内完成）
  void _startSpeedAcceleration() {
    _speedAccelerationTimer?.cancel();
    final startSpeed = _speed;
    final targetSpeed = 3.0;
    final duration = const Duration(seconds: 1); // ✅ 1秒内完成加速
    const updateInterval = Duration(milliseconds: 50); // ✅ 每50ms更新一次
    final totalSteps = duration.inMilliseconds / updateInterval.inMilliseconds;
    final speedStep = (targetSpeed - startSpeed) / totalSteps;

    int step = 0;
    _speedAccelerationTimer = Timer.periodic(updateInterval, (timer) {
      if (!mounted || (!_isLongPressingForward && !_isLongPressingRewind)) {
        timer.cancel();
        return;
      }

      step++;
      final currentSpeed = startSpeed + (speedStep * step);
      final clampedSpeed = currentSpeed.clamp(startSpeed, targetSpeed);

      // ✅ 更新倍速（临时设置，不写入偏好）
      _applyTransientSpeed(clampedSpeed);

      // ✅ 如果达到目标倍速，停止定时器
      if (clampedSpeed >= targetSpeed) {
        timer.cancel();
      }
    });
  }

  // ✅ 开始倍速减速（从当前倍速平滑减速到0.1，1秒内完成）
  void _startSpeedDeceleration() {
    _speedAccelerationTimer?.cancel();
    final startSpeed = _speed;
    final targetSpeed = 0.1;
    final duration = const Duration(seconds: 1); // ✅ 1秒内完成减速
    const updateInterval = Duration(milliseconds: 50); // ✅ 每50ms更新一次
    final totalSteps = duration.inMilliseconds / updateInterval.inMilliseconds;
    final speedStep = (targetSpeed - startSpeed) / totalSteps;

    int step = 0;
    _speedAccelerationTimer = Timer.periodic(updateInterval, (timer) {
      if (!mounted || !_isLongPressingRewind) {
        timer.cancel();
        return;
      }

      step++;
      final currentSpeed = startSpeed + (speedStep * step);
      final clampedSpeed = currentSpeed.clamp(targetSpeed, startSpeed);

      // ✅ 更新倍速（临时设置，不写入偏好）
      _applyTransientSpeed(clampedSpeed);

      // ✅ 如果达到目标倍速，停止定时器
      if (clampedSpeed <= targetSpeed) {
        timer.cancel();
      }
    });
  }

  // ✅ 恢复倍速（从当前倍速平滑恢复到目标倍速，1秒内完成）
  void _restoreSpeed(double targetSpeed) {
    _speedAccelerationTimer?.cancel();
    final startSpeed = _speed;
    final duration = const Duration(seconds: 1); // ✅ 1秒内完成恢复
    const updateInterval = Duration(milliseconds: 50); // ✅ 每50ms更新一次
    final totalSteps = duration.inMilliseconds / updateInterval.inMilliseconds;
    final speedStep = (targetSpeed - startSpeed) / totalSteps;

    int step = 0;
    _speedAccelerationTimer = Timer.periodic(updateInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      step++;
      final currentSpeed = startSpeed + (speedStep * step);
      final clampedSpeed = startSpeed < targetSpeed
          ? currentSpeed.clamp(startSpeed, targetSpeed)
          : currentSpeed.clamp(targetSpeed, startSpeed);

      // ✅ 更新倍速（临时设置，不写入偏好）
      _applyTransientSpeed(clampedSpeed);

      // ✅ 如果达到目标倍速，停止定时器
      if ((startSpeed < targetSpeed && clampedSpeed >= targetSpeed) ||
          (startSpeed > targetSpeed && clampedSpeed <= targetSpeed)) {
        timer.cancel();
        unawaited(_changeSpeed(targetSpeed));
      }
    });
  }

  // ✅ 开始倒退定时器
  void _startRewindTimer() {
    _longPressTimer?.cancel();
    bool _isSeeking = false; // ✅ 防止并发 seek
    _suppressPositionUpdates = true;
    _longPressTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isLongPressingRewind || !mounted || _isSeeking) {
        if (!_isLongPressingRewind || !mounted) {
          timer.cancel();
        }
        return;
      }

      _isSeeking = true;
      try {
        // ✅ 每100ms倒退一次（3倍速倒退）
        final newPosition = _position - const Duration(milliseconds: 300);
        final targetPosition =
            newPosition < Duration.zero ? Duration.zero : newPosition;

        // ✅ seek 到目标位置（倍速已降到0.1，画面会实时更新）
        await _playerSeek(
          targetPosition,
          swallowErrors: true,
        );

        if (mounted) {
          setState(() {
            _position = targetPosition;
          });
        }
      } catch (e) {
        _playerLog('❌ [Player] Long-press rewind seek failed: $e');
        timer.cancel();
      } finally {
        _isSeeking = false;
      }
    });
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

  // ✅ 滚动到选中的分辨率项
  void _scrollToSelectedQuality() {
    if (!_qualityListScrollController.hasClients) return;

    // ✅ 找到选中项的索引（"自动"现在在最后）
    int selectedIndex = _qualityOptions.length; // 默认是"自动"（最后一个）
    if (_selectedQuality != null) {
      selectedIndex = _qualityOptions.indexWhere(
        (q) => q['label'] == _selectedQuality,
      );
      // 如果找不到，默认为"自动"（最后一个）
      if (selectedIndex == -1) {
        selectedIndex = _qualityOptions.length;
      }
    }

    // 每个按钮的高度约为 48（padding 12*2 + 文字行高约24）
    const itemHeight = 48.0;
    final targetOffset = selectedIndex * itemHeight;

    // 滚动到目标位置，居中显示
    final maxScrollExtent =
        _qualityListScrollController.position.maxScrollExtent;
    final viewportHeight =
        _qualityListScrollController.position.viewportDimension;
    final centeredOffset = (targetOffset - viewportHeight / 2 + itemHeight / 2)
        .clamp(0.0, maxScrollExtent);

    _qualityListScrollController.animateTo(
      centeredOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  // 获取最高画质
  String? _getOriginalQuality() {
    if (_qualityOptions.isEmpty) return null;
    // 返回第一个选项（最高画质）
    return _qualityOptions.first['label'] as String;
  }

  // 质量优先模式：选择最高画质
  String? _selectQualityForQualityMode() {
    return _getOriginalQuality();
  }

  // 自动模式：根据网络速度选择合适的画质
  String? _selectQualityForAutoMode() {
    if (_qualityOptions.isEmpty) return null;

    final speedMbps = (_currentSpeedKbps ?? 0) / 1000;

    // 没有网络速度数据，使用最高画质
    if (speedMbps <= 0) {
      return _getOriginalQuality();
    }

    // ✅ 根据网络速度选择合适的画质，但要确保该档位存在
    final availableLabels =
        _qualityOptions.map((o) => o['label'] as String).toList();

    String? targetQuality;
    if (speedMbps >= 120) {
      targetQuality = '超清';
    } else if (speedMbps >= 60) {
      targetQuality = '高清';
    } else if (speedMbps >= 30) {
      targetQuality = '清晰';
    } else {
      targetQuality = '流畅';
    }

    // ✅ 如果目标档位不存在，选择最接近的较低档位
    if (availableLabels.contains(targetQuality)) {
      return targetQuality;
    }

    // ✅ 目标档位不存在，从目标档位往下找第一个可用的
    final preferredOrder = ['超清', '高清', '清晰', '流畅'];
    final targetIndex = preferredOrder.indexOf(targetQuality);

    for (int i = targetIndex + 1; i < preferredOrder.length; i++) {
      if (availableLabels.contains(preferredOrder[i])) {
        return preferredOrder[i];
      }
    }

    // ✅ 都没找到，返回最低画质
    return _qualityOptions.last['label'] as String;
  }

  // 速度优先模式：选择平衡的画质
  String? _selectQualityForSpeedMode() {
    if (_qualityOptions.isEmpty) return null;

    final speedMbps = (_currentSpeedKbps ?? 0) / 1000;
    final availableLabels =
        _qualityOptions.map((o) => o['label'] as String).toList();

    String? targetQuality;

    // 没有网络速度数据，优先选择高清，如果没有则选次高档位
    if (speedMbps <= 0) {
      if (availableLabels.contains('高清')) {
        return '高清';
      } else {
        return _qualityOptions.first['label'] as String; // 返回最高可用档位
      }
    }

    // 根据网络速度选择
    if (speedMbps >= 60) {
      targetQuality = '高清';
    } else if (speedMbps >= 30) {
      targetQuality = '清晰';
    } else {
      targetQuality = '流畅';
    }

    // ✅ 如果目标档位不存在，选择最接近的较低档位
    if (availableLabels.contains(targetQuality)) {
      return targetQuality;
    }

    // ✅ 目标档位不存在，从目标档位往下找第一个可用的
    final preferredOrder = ['高清', '清晰', '流畅'];
    final targetIndex = preferredOrder.indexOf(targetQuality);

    if (targetIndex >= 0) {
      for (int i = targetIndex + 1; i < preferredOrder.length; i++) {
        if (availableLabels.contains(preferredOrder[i])) {
          return preferredOrder[i];
        }
      }
    }

    // ✅ 都没找到，返回最低画质
    return _qualityOptions.last['label'] as String;
  }

  // ✅ 分辨率选择回调
  Future<void> _onQualitySelected(String? quality) async {
    if (_api == null) return;

    setState(() {
      _selectedQuality = quality;
    });

    // ✅ 持久化分辨率选择（标记为手动选择）
    final prefs = await SharedPreferences.getInstance();
    if (quality != null) {
      await prefs.setString('selected_quality_${widget.itemId}', quality);
      // ✅ 标记该视频已手动选择过画质
      await prefs.setBool('manual_quality_${widget.itemId}', true);
      _playerLogImportant('🎬 [Player] Quality manually changed to: $quality');
    } else {
      await prefs.remove('selected_quality_${widget.itemId}');
      await prefs.remove('manual_quality_${widget.itemId}');
      _playerLogImportant('🎬 [Player] Quality reset to auto');
    }

    // ✅ 获取选中分辨率的参数
    Map<String, dynamic>? selectedOption;
    if (quality != null) {
      selectedOption = _qualityOptions.firstWhere(
        (q) => q['label'] == quality,
        orElse: () => <String, dynamic>{},
      );
      if (selectedOption.isNotEmpty) {
        final bitrate = selectedOption['bitrate'] as int?;
        final bitrateMbps = bitrate != null
            ? (bitrate / 1000000).toStringAsFixed(1)
            : 'unknown';
        _playerLogImportant(
            '🎬 [Player] Selected quality: ${selectedOption['label']}, bitrate: ${bitrateMbps}Mbps');
      }
    }

    // ✅ 重新加载播放器以应用新的分辨率
    await _reloadPlayerWithQuality(selectedOption);
  }

  // ✅ 使用指定分辨率重新加载播放器
  Future<void> _reloadPlayerWithQuality(
      Map<String, dynamic>? qualityOption) async {
    if (_api == null) return;

    try {
      _playerLogImportant(
          '🔄 [Player] Reloading player with quality: ${qualityOption?['label'] ?? "自动"}');

      // ✅ 保存当前播放位置
      final currentPosition = _position;
      final wasPlaying = _isPlaying;

      // ✅ 暂停播放
      if (wasPlaying) {
        await _playerPause();
      }

      // ✅ 获取实际的 MediaStream Index（不是数组索引）
      int? actualAudioIndex;
      int? actualSubtitleIndex;

      if (_selectedAudioStreamIndex != null &&
          _selectedAudioStreamIndex! >= 0 &&
          _selectedAudioStreamIndex! < _audioStreams.length) {
        actualAudioIndex =
            _audioStreams[_selectedAudioStreamIndex!]['Index'] as int?;
      } else if (_audioStreams.isNotEmpty) {
        // ✅ 如果没有选择，使用第一个音轨
        actualAudioIndex = _audioStreams[0]['Index'] as int?;
      }

      if (_selectedSubtitleStreamIndex != null &&
          _selectedSubtitleStreamIndex! >= 0) {
        if (_selectedSubtitleStreamIndex! < _subtitleStreams.length) {
          actualSubtitleIndex =
              _subtitleStreams[_selectedSubtitleStreamIndex!]['Index'] as int?;
        }
      } else if (_selectedSubtitleStreamIndex == -1) {
        actualSubtitleIndex = -1;
      } else {
        // ✅ 如果没有选择字幕，默认不显示
        actualSubtitleIndex = -1;
      }

      // ✅ 构建新的 HLS URL（带码率参数）
      final requestedBitrate = qualityOption?['bitrate'] as int?;
      _playerLogImportant(
          '🔄 [Player] Building HLS URL with bitrate: $requestedBitrate');

      final media = await _api!.buildHlsUrl(
        widget.itemId,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
        maxBitrate: requestedBitrate,
        startTimeTicks: currentPosition.inMicroseconds > 0
            ? (currentPosition.inMicroseconds * 10).toInt()
            : null,
        currentPlaySessionId: _playSessionId, // ✅ 传递当前会话ID
      );

      _playerLogImportant(
          '🎬 [Player] New media URL with quality: ${media.uri}');

      // ✅ 更新 PlaySessionId 和 MediaSourceId（切换清晰度后会变化）
      if (media.playSessionId != null) {
        _playSessionId = media.playSessionId;
        _playerLogImportant(
            '🎬 [Player] Updated PlaySessionId: $_playSessionId');
      }
      if (media.mediaSourceId != null) {
        _mediaSourceId = media.mediaSourceId;
        _playerLogImportant(
            '🎬 [Player] Updated MediaSourceId: $_mediaSourceId');
      }

      // ✅ 检测是否为 HLS 流
      final isHlsStream =
          media.uri.contains('.m3u8') || media.uri.contains('hls');

      // ✅ 使用自适应缓冲策略
      final cacheConfig = _getAdaptiveCacheConfig();

      // ✅ 重新打开媒体（使用快速启动逻辑）
      _playerLogImportant(
          '🔄 [Player] Opening new media - wasPlaying: $wasPlaying, position: ${currentPosition.inSeconds}s');

      await _guardPlayerCommand(
        'reload media with quality',
        () => _player.open(
          url: media.uri,
          headers: media.headers,
          isHls: isHlsStream,
          autoPlay: false, // ✅ 先不自动播放，等加载完成后手动播放
          startPosition: currentPosition > Duration.zero
              ? currentPosition
              : null, // ✅ 直接传入位置
          cacheConfig: cacheConfig, // ✅ 使用自适应缓冲配置
        ),
      );

      // ✅ 禁用内置字幕
      await _disableSubtitle();

      // ✅ 等待播放器准备就绪
      _playerLogImportant('🔄 [Player] Waiting for player ready...');
      await Future.delayed(const Duration(milliseconds: 300));

      // ✅ 如果之前在播放，恢复播放
      if (wasPlaying && mounted) {
        _playerLogImportant(
            '▶️ [Player] Resuming playback after quality change');
        await _playerPlay();
      }

      // ✅ 更新 UI 位置
      if (currentPosition > Duration.zero && mounted) {
        setState(() {
          _position = currentPosition;
        });
      }

      _playerLogImportant('✅ [Player] Quality changed successfully');

      // ✅ 切换清晰度后，获取最新的会话信息
      await _fetchSessionInfo();
    } catch (e) {
      _playerLog('❌ [Player] Failed to change quality: $e');
    }
  }

  // ✅ 手动进入 PiP 模式
  Future<void> _enterPip() async {
    try {
      _playerLog(
          '🎬 [Player] 📞 Manual PiP: Calling native enterPip method...');
      _playerLog(
          '🎬 [Player] 📋 PiP params - title: "$_videoTitle", playing: $_isPlaying');

      // ✅ 立即设置 PiP 状态，防止 inactive 生命周期暂停播放
      // 必须在调用原生方法之前同步设置，因为原生方法会立即触发 inactive 状态
      _isInPipMode = true;
      _isManuallyEnteringPip = true; // ✅ 标记正在手动进入 PiP
      _playerLog(
          '🎬 [Player] ✅ Pre-set _isInPipMode = true, _isManuallyEnteringPip = true before entering PiP');

      final result = await _pip.invokeMethod('enter', {
        'isPlaying': _isPlaying,
        'title': _videoTitle,
      });

      _playerLog('🎬 [Player] ✅ Native enterPip returned: $result');

      // 触发 UI 更新
      if (mounted) {
        setState(() {});
      }

      // ✅ 延迟重置标志，确保 inactive 状态已经处理完
      Future.delayed(const Duration(milliseconds: 500), () {
        _isManuallyEnteringPip = false;
      });
    } catch (e) {
      _playerLog('❌ [Player] Manual PiP enter failed: $e');
      // 如果进入失败，恢复状态
      _isInPipMode = false;
      _isManuallyEnteringPip = false;
      if (mounted) {
        setState(() {});
      }
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
    if (_isDraggingProgress || _suppressPositionUpdates) return;

    if (mounted) {
      setState(() {
        _position = pos;
      });
    }
    _syncProgress(pos);

    // ✅ 预加载下一集（90% 时）
    if (_duration > Duration.zero &&
        pos >= _duration * 0.9 &&
        !_hasPreloadedNextEpisode &&
        _itemType == 'Episode' &&
        _nextEpisode != null &&
        _nextEpisode!.id != null) {
      _hasPreloadedNextEpisode = true;
      _preloadNextEpisode();
    }

    // ✅ 检查是否播放完毕（播放进度 >= 98%）
    if (_duration > Duration.zero && pos >= _duration * 0.98) {
      _handlePlaybackCompleted();
    }
  }

  // ✅ 处理播放完毕
  bool _hasHandledCompletion = false;
  void _handlePlaybackCompleted() {
    if (_hasHandledCompletion) return;
    _hasHandledCompletion = true;

    _playerLogImportant('🎬 [Player] Playback completed');

    if (_itemType == 'Episode') {
      // ✅ 电视剧：自动播放下一集（如果有）
      if (_nextEpisode != null && _nextEpisode!.id != null) {
        _playerLogImportant(
            '🎬 [Player] Auto-playing next episode: ${_nextEpisode!.name}');
        // 延迟1秒后播放下一集
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => PlayerPage(
                  itemId: _nextEpisode!.id!,
                  initialPositionTicks: null,
                ),
              ),
            );
          }
        });
      } else {
        // ✅ 最后一集，退出播放页面
        _playerLogImportant('🎬 [Player] Last episode, exiting player');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } else if (_itemType == 'Movie') {
      // ✅ 电影：自动退出播放页面
      _playerLogImportant('🎬 [Player] Movie completed, exiting player');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  // ✅ 切换控制栏显示/隐藏
  void _toggleControls() {
    final bool willShow = !_showControls;
    setState(() {
      _showControls = willShow;
      // ✅ 隐藏控制栏时，立即隐藏tooltip、速度列表和分辨率列表
      // 注意：锁定时不自动解锁，保持锁定状态
      if (!willShow) {
        _showVideoFitHint = false;
        _showSpeedList = false;
        _showQualityList = false;
        // 不在这里解锁，保持锁定状态
      }
    });

    if (willShow) {
      _controlsAnimationController.forward();
      // ✅ 显示控制栏时，不显示状态栏（保持全屏效果）
      // 状态栏保持隐藏，只显示控制层
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    // ✅ 如果速度列表、分辨率列表、音频菜单、字幕菜单正在显示或已锁定，不启动隐藏计时器
    if (_showSpeedList ||
        _showQualityList ||
        _showAudioMenu ||
        _showSubtitleMenu ||
        _isLocked) return;

    _cancelHideControlsTimer();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _showControls &&
          _isPlaying &&
          !_showSpeedList &&
          !_showQualityList &&
          !_showAudioMenu &&
          !_showSubtitleMenu &&
          !_isLocked) {
        _controlsAnimationController.reverse();
        // ✅ 自动隐藏时也隐藏状态栏
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // ✅ 取消tooltip计时器
        _videoFitHintTimer?.cancel();
        setState(() {
          _showControls = false;
          // ✅ 立即隐藏tooltip、速度列表和分辨率列表
          // 注意：锁定时不自动解锁，保持锁定状态
          _showVideoFitHint = false;
          _showSpeedList = false;
          _showQualityList = false;
          // 不在这里解锁，保持锁定状态
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
      if (!_progressSyncUnavailableLogged) {
        _playerLog(
            '⚠️ [Player] Skip progress sync: api=${_api != null}, user=$_userId');
        _progressSyncUnavailableLogged = true;
      }
      return;
    }
    _progressSyncUnavailableLogged = false;
    final now = DateTime.now();
    final bool completed =
        markComplete || (_duration > Duration.zero && pos >= _duration * 0.95);
    if (!force && !completed) {
      final timeDiff = now.difference(_lastProgressSync);
      final posDiffMs = (pos - _lastReportedPosition).inMilliseconds.abs();
      if (timeDiff < const Duration(seconds: 3) && posDiffMs < 2000) {
        return;
      }
    }
    _lastProgressSync = now;
    _lastReportedPosition = pos;

    // ✅ 通知 Emby 服务器播放进度更新（用于记录播放历史）
    if (_playSessionId != null && _mediaSourceId != null) {
      final positionTicks = (pos.inMicroseconds * 10).toInt();
      final audioIndex = _getCurrentAudioStreamIndex();
      final subtitleIndex = _getCurrentSubtitleStreamIndex();

      unawaited(_api!.reportPlaybackProgress(
        itemId: _currentItemId,
        userId: _userId!,
        playSessionId: _playSessionId!,
        mediaSourceId: _mediaSourceId,
        positionTicks: positionTicks,
        isPaused: !_isPlaying,
        audioStreamIndex: audioIndex,
        subtitleStreamIndex: subtitleIndex,
      ));
    }

    if (completed) {
      if (_completedReported) {
        return;
      }
      _completedReported = true;
      unawaited(_api!.updateUserItemData(
        _userId!,
        _currentItemId,
        position: Duration.zero,
        played: true,
      ));
    } else {
      _completedReported = false;
      unawaited(_api!.updateUserItemData(
        _userId!,
        _currentItemId,
        position: pos,
      ));
    }
  }

  // ✅ 构建背景图（在没有画面时显示）
  Widget _buildBackgroundImage() {
    final itemId = _currentItemId;
    if (itemId.isEmpty) {
      return Container(color: Colors.black);
    }

    // ✅ 优先使用传递的图片对象，立即显示（无需等待加载）
    if (widget.backdropImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RawImage(
            image: widget.backdropImage,
            fit: BoxFit.cover,
          ),
          Container(
            color: Colors.black.withOpacity(0.75),
          ),
        ],
      );
    }

    // ✅ 如果传递了背景图 URL，直接显示，不需要等待 API 初始化
    if (widget.backdropUrl != null && widget.backdropUrl!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          EmbyFadeInImage(
            imageUrl: widget.backdropUrl!,
            fit: BoxFit.cover,
            placeholder: Container(color: Colors.black),
          ),
          Container(
            color: Colors.black.withOpacity(0.75),
          ),
        ],
      );
    }

    // ✅ 如果没有传递背景图 URL，使用 FutureBuilder 等待 API 初始化
    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(color: Colors.black);
        }

        final api = snapshot.data!;
        String? backdropUrl;
        // ✅ 先检查是否有 Backdrop 标签，避免生成无效的 URL（404）
        if (_itemDetails != null) {
          // ✅ 对于Episode类型，优先使用父项（Series）的背景图
          if (_itemDetails!.type == 'Episode') {
            // 1. 尝试使用父项的背景图（Series的Backdrop）
            if (_itemDetails!.parentBackdropImageTags?.isNotEmpty ?? false) {
              final parentBackdropItemId = _itemDetails!.parentBackdropItemId;
              if (parentBackdropItemId != null &&
                  parentBackdropItemId.isNotEmpty) {
                backdropUrl = api.buildImageUrl(
                  itemId: parentBackdropItemId, // ✅ 使用父项ID
                  type: 'Backdrop',
                  maxWidth: 1920,
                  tag: _itemDetails!.parentBackdropImageTags!.first,
                );
              }
            }

            // 2. 如果父项没有背景图，尝试使用Episode自己的背景图
            if (backdropUrl == null &&
                (_itemDetails!.backdropImageTags?.isNotEmpty ?? false)) {
              backdropUrl = api.buildImageUrl(
                itemId: itemId,
                type: 'Backdrop',
                maxWidth: 1920,
                tag: _itemDetails!.backdropImageTags!.first,
              );
            }

            // 3. 如果都没有背景图，尝试使用Series的Primary图片
            if (backdropUrl == null) {
              final seriesId = _itemDetails!.seriesId;
              if (seriesId != null && seriesId.isNotEmpty) {
                backdropUrl = api.buildImageUrl(
                  itemId: seriesId,
                  type: 'Primary',
                  maxWidth: 1920,
                );
              }
            }
          } else {
            // ✅ 对于非Episode类型（Movie等），使用自己的背景图
            if (_itemDetails!.backdropImageTags?.isNotEmpty ?? false) {
              backdropUrl = api.buildImageUrl(
                itemId: itemId,
                type: 'Backdrop',
                maxWidth: 1920,
                tag: _itemDetails!.backdropImageTags!.first,
              );
            }

            // ✅ 如果没有 Backdrop，尝试使用 Primary 图片作为备用
            if (backdropUrl == null) {
              final primaryTag = _itemDetails!.imageTags?['Primary'] ?? '';
              if (primaryTag.isNotEmpty) {
                backdropUrl = api.buildImageUrl(
                  itemId: itemId,
                  type: 'Primary',
                  maxWidth: 1920,
                  tag: primaryTag,
                );
              }
            }
          }
        }

        // ✅ 如果都没有，显示黑色背景
        if (backdropUrl == null || backdropUrl.isEmpty) {
          return Container(color: Colors.black);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // ✅ 背景图（使用 EmbyFadeInImage 以支持缓存）
            EmbyFadeInImage(
              imageUrl: backdropUrl,
              fit: BoxFit.cover,
              placeholder: Container(color: Colors.black),
            ),
            // ✅ 半透明黑色遮罩，避免背景图太亮（增加透明度到0.6）
            Container(
              color: Colors.black.withOpacity(0.75),
            ),
          ],
        );
      },
    );
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
      child: PopScope(
        // ✅ 完全禁止侧滑返回和系统返回键
        // 返回键的行为：如果控制层显示，则返回；否则显示控制层
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return; // 如果已经返回，不再处理
          // ✅ 如果控制层显示，允许返回
          if (_showControls) {
            Navigator.of(context).pop();
          } else {
            // ✅ 否则显示控制层
            _toggleControls();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // ✅ 视频播放器（最底层）
              Positioned.fill(
                child: _ready && _textureId != null
                    ? Opacity(
                        opacity: 1.0,
                        child: IgnorePointer(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = _videoSize.width > 0
                                  ? _videoSize.width
                                  : constraints.maxWidth;
                              final height = _videoSize.height > 0
                                  ? _videoSize.height
                                  : constraints.maxHeight;
                              return FittedBox(
                                fit: _videoFit,
                                child: SizedBox(
                                  width: width,
                                  height: height,
                                  child: Texture(
                                    textureId: _textureId!,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    : Container(color: Colors.black),
              ),

              // ✅ 背景图（在视频上方，作为占位图）
              // 显示条件：
              // 1. 还没开始播放过（初始化阶段）
              // 2. 正在缓冲且没有画面（_isBuffering && _position == Duration.zero）
              // 3. 未准备好（!_ready）
              Builder(
                builder: (context) {
                  final shouldShow = !_hasStartedPlayback ||
                      !_ready ||
                      (_isBuffering && _position == Duration.zero);
                  if (shouldShow) {
                    return Positioned.fill(
                      child: _buildBackgroundImage(),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // ✅ 自定义字幕显示组件（中间层，在视频上方，UI控制层下方）
              if (!_isInPipMode)
                CustomSubtitleOverlay(
                  position: _position,
                  subtitleUrl: _subtitleUrl,
                  isVisible: _ready,
                  showControls: _showControls, // ✅ 传递控制栏显示状态
                  isLocked: _isLocked, // ✅ 传递锁定状态
                  isEpisode: _itemType == 'Episode', // ✅ 传递是否为电视剧类型
                ),

              // ✅ 触摸检测层（当控制层隐藏时，用于显示控制层；长按快进/快退）
              // 必须在 UI 控制层之前，让 UI 控制层能处理事件
              Positioned.fill(
                child: IgnorePointer(
                  // ✅ 当控制层显示且未锁定时，忽略触摸检测层
                  // 当控制层隐藏或锁定时，触摸检测层可以接收事件
                  ignoring: _showControls && !_isLocked,
                  child: GestureDetector(
                    onTap: () {
                      // ✅ 点击屏幕显示控制栏
                      if (!_showSpeedList &&
                          !_isLongPressingForward &&
                          !_isLongPressingRewind) {
                        _toggleControls();
                      }
                    },
                    onLongPressStart: (details) {
                      // ✅ 长按开始：检测左右侧屏幕
                      if (!_ready || _isInPipMode) return;

                      final screenWidth = MediaQuery.of(context).size.width;
                      final touchX = details.localPosition.dx;
                      final isRightSide = touchX > screenWidth / 2;

                      setState(() {
                        _longPressPosition = details.localPosition;
                        _longPressStartTime = DateTime.now(); // ✅ 记录长按开始时间
                        if (isRightSide) {
                          // ✅ 长按右侧：从当前倍速平滑加速到3倍速播放
                          _isLongPressingForward = true;
                          _originalSpeed = _speed;
                          _startSpeedAcceleration(); // ✅ 开始平滑加速
                        } else {
                          // ✅ 长按左侧：从当前倍速平滑减速到0.1倍速，然后通过seek倒退
                          _isLongPressingRewind = true;
                          _originalSpeed = _speed;
                          _startSpeedDeceleration(); // ✅ 开始平滑减速到0.1
                          // ✅ 开始定时倒退
                          _startRewindTimer();
                        }
                      });
                    },
                    onLongPressEnd: (details) {
                      // ✅ 长按结束：恢复原始倍速
                      _stopLongPress();
                    },
                    onLongPressCancel: () {
                      // ✅ 长按取消：恢复原始倍速
                      _stopLongPress();
                    },
                    // ✅ 垂直滑动：左侧控制亮度，右侧控制音量
                    // 只在没有显示其他播放控制UI时生效（不受锁定影响）
                    // 防误触：判断是否是缓慢垂直滑动
                    onVerticalDragStart: (details) {
                      if (!_ready || _isInPipMode || _showControls) return;

                      final screenWidth = MediaQuery.of(context).size.width;
                      final touchX = details.localPosition.dx;
                      final isRightSide = touchX > screenWidth / 2;

                      _verticalDragStartPosition = details.localPosition;
                      _verticalDragStartTime = DateTime.now();
                      _hasTriggeredVolumeAdjust = false;
                      _hasTriggeredBrightnessAdjust = false;

                      if (isRightSide) {
                        // ✅ 右侧：准备控制音量（但还未触发）
                        _volumeAdjustStartValue = _currentVolume ?? 50.0;
                      } else {
                        // ✅ 左侧：准备控制亮度（但还未触发）
                        _brightnessAdjustStartValue = _currentBrightness ?? 0.5;
                      }
                    },
                    onVerticalDragUpdate: (details) async {
                      if (!_ready || _isInPipMode || _showControls) return;
                      if (_verticalDragStartPosition == null ||
                          _verticalDragStartTime == null) return;

                      final screenWidth = MediaQuery.of(context).size.width;
                      final screenHeight = MediaQuery.of(context).size.height;
                      final touchX = details.localPosition.dx;
                      final isRightSide = touchX > screenWidth / 2;

                      // ✅ 计算滑动距离
                      final deltaX = (details.localPosition.dx -
                              _verticalDragStartPosition!.dx)
                          .abs();
                      final deltaY = (_verticalDragStartPosition!.dy -
                              details.localPosition.dy)
                          .abs();
                      final deltaYPercent = deltaY / screenHeight;

                      // ✅ 计算滑动时间
                      final elapsed =
                          DateTime.now().difference(_verticalDragStartTime!);
                      final elapsedSeconds = elapsed.inMilliseconds / 1000.0;

                      // ✅ 判断是否已经触发（如果已触发，则去除所有限制）
                      final isAlreadyTriggered = _hasTriggeredVolumeAdjust ||
                          _hasTriggeredBrightnessAdjust;

                      if (!isAlreadyTriggered) {
                        // ✅ 防误触判断（仅在未触发时检查）：
                        // 1. 必须是垂直滑动（水平位移小于垂直位移的 30%）
                        // 2. 必须是缓慢滑动（速度不能太快，至少需要滑动屏幕高度的 4% 且时间超过 0.2 秒）
                        // 3. 滑动速度不能超过屏幕高度/秒（避免快速滑动误触）
                        final isVerticalSwipe =
                            deltaX < deltaY * 0.3; // ✅ 水平位移小于垂直位移的30%
                        final minDistance = 0.04; // ✅ 至少滑动屏幕高度的4%
                        final minTime = 0.2; // ✅ 至少需要0.2秒
                        final maxSpeed = 2.0; // ✅ 最大速度：2倍屏幕高度/秒

                        final hasMinDistance = deltaYPercent >= minDistance;
                        final hasMinTime = elapsedSeconds >= minTime;
                        final speed = deltaYPercent /
                            elapsedSeconds.clamp(0.01, 1.0); // ✅ 避免除零
                        final isSlowSwipe = speed <= maxSpeed;

                        // ✅ 判断是否满足触发条件
                        final shouldTrigger = isVerticalSwipe &&
                            hasMinDistance &&
                            hasMinTime &&
                            isSlowSwipe;

                        if (!shouldTrigger) {
                          // ✅ 不满足条件，不触发
                          return;
                        }

                        // ✅ 触发调整
                        if (isRightSide && !_hasTriggeredVolumeAdjust) {
                          _hasTriggeredVolumeAdjust = true;
                          _isAdjustingVolume = true;
                          if (mounted) setState(() {});
                        } else if (!isRightSide &&
                            !_hasTriggeredBrightnessAdjust) {
                          _hasTriggeredBrightnessAdjust = true;
                          _isAdjustingBrightness = true;
                          if (mounted) setState(() {});
                        }
                      }

                      // ✅ 已触发后，去除所有限制，只要手指没有松开就可以自由调整
                      // 不再检查垂直滑动、距离、时间、速度等任何限制
                      final deltaYForAdjust = _verticalDragStartPosition!.dy -
                          details.localPosition.dy;
                      final deltaPercent = deltaYForAdjust / screenHeight;

                      if (_isAdjustingVolume && _hasTriggeredVolumeAdjust) {
                        // ✅ 右侧：调整系统音量（0-100）
                        final newVolume =
                            (_volumeAdjustStartValue! + deltaPercent * 100)
                                .clamp(0.0, 100.0);
                        await _setSystemVolume(newVolume);
                        if (mounted) {
                          setState(() {
                            _currentVolume = newVolume;
                          });
                        }
                      } else if (_isAdjustingBrightness &&
                          _hasTriggeredBrightnessAdjust) {
                        // ✅ 左侧：调整亮度（0-1）
                        final newBrightness =
                            (_brightnessAdjustStartValue! + deltaPercent)
                                .clamp(0.0, 1.0);
                        await _setBrightness(newBrightness);
                        if (mounted) {
                          setState(() {
                            _currentBrightness = newBrightness;
                          });
                        }
                      }
                    },
                    onVerticalDragEnd: (details) {
                      // ✅ 手指松开时，停止触发
                      _verticalDragStartPosition = null;
                      _verticalDragStartTime = null;
                      _hasTriggeredVolumeAdjust = false;
                      _hasTriggeredBrightnessAdjust = false;
                      // ✅ 延迟隐藏，让用户看到最终数值
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) {
                          setState(() {
                            _isAdjustingBrightness = false;
                            _isAdjustingVolume = false;
                          });
                        }
                      });
                    },
                    onVerticalDragCancel: () {
                      // ✅ 取消拖动时，停止触发
                      _verticalDragStartPosition = null;
                      _verticalDragStartTime = null;
                      _hasTriggeredVolumeAdjust = false;
                      _hasTriggeredBrightnessAdjust = false;
                      // ✅ 立即隐藏弹窗
                      if (mounted) {
                        setState(() {
                          _isAdjustingBrightness = false;
                          _isAdjustingVolume = false;
                        });
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),

              // ✅ UI 控制层（最上层，所有控制相关的 UI 组件）
              PlayerControls(
                state: PlayerControlsState(
                  isInPipMode: _isInPipMode,
                  ready: _ready,
                  showControls: _showControls,
                  isBuffering: _isBuffering,
                  isPlaying: _isPlaying,
                  position: _position,
                  duration: _duration,
                  bufferPosition: _bufferPosition,
                  isDraggingProgress: _isDraggingProgress,
                  draggingPosition: _draggingPosition,
                  videoTitle: _videoTitle,
                  videoFit: _videoFit,
                  showVideoFitHint: _showVideoFitHint,
                  speed: _speed,
                  showSpeedList: _showSpeedList,
                  speedOptions: _speedOptions,
                  expectedBitrateKbps: _expectedBitrateKbps,
                  currentSpeedKbps: _currentSpeedKbps,
                  qualityLabel: _qualityLabel,
                  audioStreams: _audioStreams,
                  subtitleStreams: _subtitleStreams,
                  selectedAudioStreamIndex: _selectedAudioStreamIndex,
                  selectedSubtitleStreamIndex: _selectedSubtitleStreamIndex,
                  controlsAnimation: _controlsAnimation,
                  speedListScrollController: _speedListScrollController,
                  onToggleVideoFit: _toggleVideoFit,
                  onEnterPip: _enterPip,
                  onToggleOrientation: _toggleOrientation,
                  onPlayPause: () async {
                    final playing = _isPlaying;
                    // ✅ 只调用播放器方法，状态由 stream 监听更新
                    if (playing) {
                      await _playerPause();
                    } else {
                      await _playerPlay();
                    }
                    _resetHideControlsTimer();
                  },
                  onIncreaseSpeed: _increaseSpeed,
                  onDecreaseSpeed: _decreaseSpeed,
                  onChangeSpeed: _changeSpeed,
                  onScrollToSelectedSpeed: _scrollToSelectedSpeed,
                  onShowAudioSelectionMenu: _showAudioSelectionMenu,
                  onShowSubtitleSelectionMenu: _showSubtitleSelectionMenu,
                  onDragStart: () {
                    setState(() {
                      _isDraggingProgress = true;
                      _wasPlayingBeforeDrag = _isPlaying;
                    });
                    _cancelHideControlsTimer();
                  },
                  onDragging: (d) {
                    setState(() {
                      _draggingPosition = d;
                    });
                  },
                  onDragEnd: (d) async {
                    final shouldResume = _wasPlayingBeforeDrag;
                    setState(() {
                      _draggingPosition = null;
                    });
                    await _performSeek(
                      d,
                      resumeAfterSeek: shouldResume,
                      waitForConfirmation: false, // ✅ 拖动时不等待确认，提升响应速度
                    );
                    if (mounted) {
                      setState(() {
                        _isDraggingProgress = false;
                        _wasPlayingBeforeDrag = false;
                      });
                    }
                    _resetHideControlsTimer();
                  },
                  onResetHideControlsTimer: _resetHideControlsTimer,
                  onCancelHideControlsTimer: _cancelHideControlsTimer,
                  onSetState: (callback) => setState(callback),
                  onShowSpeedListChanged: (show) {
                    setState(() {
                      _showSpeedList = show;
                    });
                  },
                  onToggleControls: _toggleControls,
                  getVideoFitIcon: _getVideoFitIcon,
                  getVideoFitName: _getVideoFitName,
                  formatTime: _formatTime,
                  formatBitrate: _formatBitrate,
                  canIncreaseSpeed: _canIncreaseSpeed,
                  canDecreaseSpeed: _canDecreaseSpeed,
                  isLocked: _isLocked,
                  onToggleLock: () {
                    setState(() {
                      _isLocked = !_isLocked;
                    });
                    if (_isLocked) {
                      // 锁定时取消自动隐藏计时器
                      _cancelHideControlsTimer();
                    } else {
                      // 解锁时重新启动自动隐藏计时器（如果正在播放）
                      if (_isPlaying) {
                        _startHideControlsTimer();
                      }
                    }
                  },
                  onRewind: () async {
                    final shouldResume = _isPlaying;
                    final newPosition = _position - const Duration(seconds: 10);
                    final targetPosition = newPosition < Duration.zero
                        ? Duration.zero
                        : newPosition;
                    await _performSeek(targetPosition,
                        resumeAfterSeek: shouldResume);
                    _resetHideControlsTimer();
                  },
                  onForward: () async {
                    final shouldResume = _isPlaying;
                    final newPosition = _position + const Duration(seconds: 20);
                    final targetPosition =
                        newPosition > _duration ? _duration : newPosition;
                    await _performSeek(targetPosition,
                        resumeAfterSeek: shouldResume);
                    _resetHideControlsTimer();
                  },
                  isLongPressingForward: _isLongPressingForward,
                  isLongPressingRewind: _isLongPressingRewind,
                  longPressPosition: _longPressPosition,
                  longPressStartTime: _longPressStartTime,
                  isAdjustingBrightness: _isAdjustingBrightness,
                  isAdjustingVolume: _isAdjustingVolume,
                  currentBrightness: _currentBrightness,
                  currentVolume: _currentVolume,
                  qualityOptions: _qualityOptions,
                  selectedQuality: _selectedQuality,
                  showQualityList: _showQualityList,
                  onQualitySelected: _onQualitySelected,
                  onShowQualityListChanged: (show) {
                    setState(() {
                      _showQualityList = show;
                    });
                  },
                  qualityListScrollController: _qualityListScrollController,
                  onScrollToSelectedQuality: _scrollToSelectedQuality,
                  itemType: _itemType,
                  logoUrl: _logoUrl,
                  itemDetails: _itemDetails,
                  sessionInfo: _sessionInfo, // ✅ 传递实时会话信息
                  previousEpisode: _previousEpisode,
                  nextEpisode: _nextEpisode,
                  onPlayPreviousEpisode: _playPreviousEpisode,
                  onPlayNextEpisode: _playNextEpisode,
                  showMediaInfo: _showMediaInfo,
                  onToggleMediaInfo: () async {
                    setState(() {
                      _showMediaInfo = !_showMediaInfo;
                    });

                    if (_showMediaInfo) {
                      // ✅ 打开详情弹窗时，立即获取一次会话信息
                      await _fetchSessionInfo();
                      // ✅ 启动定时器，每5秒更新一次（用于实时更新HLS帧率等信息）
                      _startSessionInfoUpdateTimer();
                    } else {
                      // ✅ 关闭详情弹窗时，停止定时器
                      _stopSessionInfoUpdateTimer();
                    }
                  },
                ),
              ),

              // ✅ 音频切换提示（类似裁切提示的样式，显示在底部进度条上方右侧）
              if (_showAudioSwitchHint)
                Positioned(
                  bottom: 86, // ✅ 在进度条上方，距离更近一些
                  right: 30, // ✅ 往左移动一些，不要太靠右
                  child: AnimatedOpacity(
                    opacity: _showAudioSwitchHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.grey.shade900.withValues(alpha: 0.6),
                                Colors.grey.shade800.withValues(alpha: 0.4),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _audioSwitchHintText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
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

  // ✅ 从 MediaSource 中获取视频流信息
  Map<String, dynamic>? _getVideoStreamFromMediaSource(
      Map<String, dynamic>? media) {
    if (media == null) return null;
    final streams = media['MediaStreams'];
    if (streams is List) {
      for (final stream in streams) {
        if (stream is Map &&
            (stream['Type'] as String?)?.toLowerCase() == 'video') {
          return Map<String, dynamic>.from(stream);
        }
      }
    }
    return null;
  }

  // ✅ 根据原始分辨率和码率生成画质档位选项
  List<Map<String, dynamic>> _generateSimpleQualityOptions(
      int? originalBitrate, int? sourceWidth, int? sourceHeight) {
    final options = <Map<String, dynamic>>[];

    // ✅ 定义所有可能的档位（从高到低）
    // 超清：适用于4K/2K视频
    // 高清：适用于1080p及以上视频
    // 清晰：适用于720p及以上视频
    // 流畅：适用于所有视频
    final allLevels = [
      {
        'label': '超清',
        'bitrate': 120000000,
        'minWidth': 2560,
        'minHeight': 1440
      }, // 120 Mbps, 需要2K+
      {
        'label': '高清',
        'bitrate': 60000000,
        'minWidth': 1920,
        'minHeight': 1080
      }, // 60 Mbps, 需要1080p+
      {
        'label': '清晰',
        'bitrate': 4000000,
        'minWidth': 1280,
        'minHeight': 720
      }, // 4 Mbps, 需要720p+
      {
        'label': '流畅',
        'bitrate': 1000000,
        'minWidth': 0,
        'minHeight': 0
      }, // 1 Mbps, 所有视频
    ];

    // ✅ 根据视频分辨率筛选档位（优先使用宽度，与 item_detail_page.dart 一致）
    if (sourceWidth != null && sourceWidth > 0) {
      // 优先使用宽度判断
      for (final level in allLevels) {
        final minWidth = level['minWidth'] as int;
        if (sourceWidth >= minWidth) {
          options.add({
            'label': level['label'],
            'bitrate': level['bitrate'],
          });
        }
      }
    } else if (sourceHeight != null && sourceHeight > 0) {
      // 如果没有宽度，使用高度判断
      for (final level in allLevels) {
        final minHeight = level['minHeight'] as int;
        if (sourceHeight >= minHeight) {
          options.add({
            'label': level['label'],
            'bitrate': level['bitrate'],
          });
        }
      }
    } else {
      // ✅ 没有分辨率信息，返回所有档位
      for (final level in allLevels) {
        options.add({
          'label': level['label'],
          'bitrate': level['bitrate'],
        });
      }
    }

    // ✅ 确保至少有一个档位
    if (options.isEmpty) {
      options.add({
        'label': '流畅',
        'bitrate': 1000000,
      });
    }

    return options;
  }

  // ✅ 获取音频流
  List<Map<String, dynamic>> _getAudioStreams(ItemInfo item) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) return const [];
    final streams = media['MediaStreams'];
    if (streams is List) {
      return streams
          .where((element) =>
              element is Map &&
              (element['Type'] as String?)?.toLowerCase() == 'audio')
          .map((element) => Map<String, dynamic>.from(
              (element as Map<dynamic, dynamic>)
                  .map((key, value) => MapEntry(key.toString(), value))))
          .toList();
    }
    return const [];
  }

  // ✅ 获取字幕流（保存原始 MediaStreams 中的索引）
  List<Map<String, dynamic>> _getSubtitleStreams(ItemInfo item) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) return const [];
    final streams = media['MediaStreams'];
    if (streams is List) {
      final result = <Map<String, dynamic>>[];
      for (int i = 0; i < streams.length; i++) {
        final element = streams[i];
        if (element is Map) {
          final type = (element['Type'] as String?)?.toLowerCase();
          if (type == 'subtitle') {
            final streamMap = Map<String, dynamic>.from(
                element.map((key, value) => MapEntry(key.toString(), value)));
            // ✅ 保存字幕流在原始 MediaStreams 数组中的索引位置
            // 这是 Emby API 需要的索引
            streamMap['_originalIndex'] = i;
            result.add(streamMap);
          }
        }
      }
      return result;
    }
    return const [];
  }

  // ✅ 获取主要媒体源
  Map<String, dynamic>? _getPrimaryMediaSource(ItemInfo item) {
    final sources = item.mediaSources;
    if (sources == null || sources.isEmpty) return null;
    return sources.first;
  }

  // ✅ 确保音频选择
  void _ensureAudioSelection() {
    if (_audioStreams.isEmpty) return;

    final current = _selectedAudioStreamIndex;
    if (current != null && current >= 0 && current < _audioStreams.length) {
      return;
    }

    if (_hasManuallySelectedAudio) {
      final defaultIndex = _audioStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      final fallback = defaultIndex != -1 ? defaultIndex : 0;
      if (mounted) {
        setState(() {
          _selectedAudioStreamIndex = fallback;
        });
      }
      return;
    }

    final defaultIndex = _audioStreams
        .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
    final fallback = defaultIndex != -1 ? defaultIndex : 0;

    if (mounted) {
      setState(() {
        _selectedAudioStreamIndex = fallback;
      });
    }
  }

  // ✅ 确保字幕选择
  void _ensureSubtitleSelection() {
    if (_subtitleStreams.isEmpty) {
      _playerLog('⚠️ [Player] No subtitle streams available');
      return;
    }

    final current = _selectedSubtitleStreamIndex;
    _playerLog(
        '🎬 [Player] _ensureSubtitleSelection - current: $current, hasManual: $_hasManuallySelectedSubtitle');

    // ✅ 如果用户选择了"不显示"（-1），则保持不显示，不自动选择
    if (current == -1) {
      _playerLog('🎬 [Player] Subtitle disabled by user (-1)');
      _updateSubtitleUrl();
      return;
    }

    // ✅ 如果当前选择有效，保持不变
    if (current != null && current >= 0 && current < _subtitleStreams.length) {
      _playerLog('🎬 [Player] Current subtitle selection valid: $current');
      _updateSubtitleUrl();
      return;
    }

    // ✅ 如果用户手动选择过但索引无效，回退到默认或第一个
    if (_hasManuallySelectedSubtitle) {
      _playerLog(
          '🎬 [Player] Manual selection but index invalid, falling back to default');
      final defaultIndex = _subtitleStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      final fallback = defaultIndex != -1 ? defaultIndex : 0;
      if (mounted) {
        setState(() {
          _selectedSubtitleStreamIndex = fallback;
        });
        _updateSubtitleUrl();
      }
      return;
    }

    // ✅ 自动选择最佳中文字幕
    _playerLog('🎬 [Player] Auto-selecting best Chinese subtitle');
    int selectedIndex = _findBestChineseSubtitle(_subtitleStreams);

    if (selectedIndex == -1) {
      final defaultIndex = _subtitleStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      selectedIndex = defaultIndex != -1 ? defaultIndex : 0;
      _playerLog(
          '🎬 [Player] No Chinese subtitle found, using default or first: $selectedIndex');
    } else {
      _playerLog('🎬 [Player] Found Chinese subtitle at index: $selectedIndex');
    }

    if (mounted) {
      setState(() {
        _selectedSubtitleStreamIndex = selectedIndex;
      });
      _saveStreamSelections();
      _updateSubtitleUrl();
    }
  }

  // ✅ 查找最佳中文字幕
  int _findBestChineseSubtitle(List<Map<String, dynamic>> subtitleStreams) {
    int index = subtitleStreams.indexWhere((stream) {
      final lang = stream['Language']?.toString() ?? '';
      final displayTitle = stream['DisplayTitle']?.toString() ?? '';
      final title = stream['Title']?.toString() ?? '';
      final combined = '$lang $displayTitle $title'.toLowerCase();
      return combined.contains('chinese') && combined.contains('simplified');
    });
    if (index != -1) return index;

    index = subtitleStreams.indexWhere((stream) {
      final lang = stream['Language']?.toString() ?? '';
      final displayTitle = stream['DisplayTitle']?.toString() ?? '';
      final title = stream['Title']?.toString() ?? '';
      final combined = '$lang $displayTitle $title'.toLowerCase();
      return combined.contains('chinese') && combined.contains('traditional');
    });
    if (index != -1) return index;

    index = subtitleStreams.indexWhere((stream) {
      final lang = stream['Language']?.toString() ?? '';
      final displayTitle = stream['DisplayTitle']?.toString() ?? '';
      final title = stream['Title']?.toString() ?? '';
      final combined = '$lang $displayTitle $title'.toLowerCase();
      return combined.contains('chinese');
    });
    if (index != -1) return index;

    index = subtitleStreams.indexWhere((stream) {
      final lang = (stream['Language']?.toString() ?? '').toLowerCase();
      return lang == 'chi' ||
          lang == 'zh' ||
          lang == 'cn' ||
          lang == 'chs' ||
          lang == 'cht' ||
          lang == 'zh-cn' ||
          lang == 'zh-tw';
    });

    return index;
  }

  // ✅ 格式化音频流（仅用于选中后的显示）
  String _formatAudioStream(Map<String, dynamic> stream) {
    final displayTitle = stream['DisplayTitle']?.toString() ?? '';

    // ✅ 如果有 DisplayTitle，直接使用
    if (displayTitle.isNotEmpty) {
      return displayTitle;
    }

    // ✅ 如果没有 DisplayTitle，尝试使用 Title
    final title = stream['Title']?.toString() ?? '';
    if (title.isNotEmpty) {
      return title;
    }

    // ✅ 如果都没有，回退到手动构建
    final codec = stream['Codec']?.toString().toUpperCase();
    final channels = (stream['Channels'] as num?)?.toInt();
    final language = stream['Language']?.toString();

    final parts = <String>[];
    if (language != null && language.isNotEmpty) {
      parts.add(language);
    }
    if (codec != null && codec.isNotEmpty) parts.add(codec);
    if (channels != null) {
      final channelLabel = channels == 2
          ? '2.0'
          : channels == 6
              ? '5.1'
              : channels.toString();
      parts.add(channelLabel);
    }

    return parts.isEmpty ? '未知' : parts.join(' ');
  }

  // ✅ 格式化字幕流（仅用于选中后的显示）
  String _formatSubtitleStream(Map<String, dynamic> stream) {
    final displayTitle = stream['DisplayTitle']?.toString() ?? '';

    // ✅ 如果有 DisplayTitle，直接使用
    if (displayTitle.isNotEmpty) {
      return displayTitle;
    }

    // ✅ 如果没有 DisplayTitle，尝试使用 Title
    final title = stream['Title']?.toString() ?? '';
    if (title.isNotEmpty) {
      return title;
    }

    // ✅ 如果都没有，回退到手动构建
    final language = stream['Language']?.toString();
    final codec = stream['Codec']?.toString().toUpperCase();
    final isForced = stream['IsForced'] == true;

    final parts = <String>[];
    if (language != null && language.isNotEmpty) {
      parts.add(language);
    }
    if (codec != null && codec.isNotEmpty) {
      parts.add(codec);
    }
    if (isForced) {
      parts.add('强制');
    }

    return parts.isEmpty ? '未知字幕' : parts.join(' ');
  }

  // ✅ 显示音频选择菜单
  Future<void> _showAudioSelectionMenu(BuildContext anchorContext) async {
    if (_audioStreams.isEmpty) return;

    _cancelHideControlsTimer();

    // ✅ 标记音频菜单正在显示
    setState(() {
      _showAudioMenu = true;
    });

    final RenderBox? button = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay;
    final RenderBox? overlayBox =
        overlay?.context.findRenderObject() as RenderBox?;

    if (button == null || overlayBox == null) {
      _resetHideControlsTimer();
      return;
    }

    final Offset buttonOffset =
        button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Size overlaySize = overlayBox.size;

    double panelWidth = 240.0;
    const double maxHeight = 230.0;
    const double spacing = 12.0;

    const double minLeftMargin = 16.0;
    const double rightMargin = 18.0;

    final double maxAllowedWidth =
        overlaySize.width - minLeftMargin - rightMargin;
    if (panelWidth > maxAllowedWidth) {
      panelWidth = maxAllowedWidth.clamp(120.0, panelWidth);
    }

    double left = buttonOffset.dx + button.size.width - panelWidth;
    final double maxLeft = overlaySize.width - panelWidth - rightMargin;

    if (maxLeft < minLeftMargin) {
      panelWidth = (overlaySize.width - minLeftMargin - rightMargin)
          .clamp(120.0, panelWidth);
      left = minLeftMargin;
    } else {
      left = left.clamp(minLeftMargin, maxLeft);
    }
    final double bottom = (overlaySize.height - buttonOffset.dy) + spacing + 10;

    final scrollController = ScrollController();
    final itemKeys = List.generate(
      _audioStreams.length,
      (index) => GlobalKey(),
    );

    void scheduleScroll() {
      if (_selectedAudioStreamIndex == null ||
          _selectedAudioStreamIndex! < 0 ||
          _selectedAudioStreamIndex! >= itemKeys.length) return;
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          final key = itemKeys[_selectedAudioStreamIndex!];
          final context = key.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: 0.0, // ✅ 滚动到顶部
            );
          }
        } catch (e) {
          // 忽略滚动错误
        }
      });
    }

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        scheduleScroll();
        final isDark = isDarkModeFromContext(context, ref);
        final gradientColors = isDark
            ? [
                Colors.grey.shade900.withValues(alpha: 0.7),
                Colors.grey.shade800.withValues(alpha: 0.5),
              ]
            : [
                Colors.white.withValues(alpha: 0.25),
                Colors.white.withValues(alpha: 0.15),
              ];

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
              Positioned(
                left: left,
                bottom: bottom,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: panelWidth,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              _audioStreams.length,
                              (index) {
                                final data = _audioStreams[index];
                                final displayTitle =
                                    data['DisplayTitle']?.toString() ?? '';
                                final title = data['Title']?.toString() ?? '';
                                final isDefault =
                                    (data['IsDefault'] as bool?) == true;
                                final isSelected =
                                    index == _selectedAudioStreamIndex;

                                // ✅ 主标题：优先使用 DisplayTitle
                                String mainLabel = displayTitle.isNotEmpty
                                    ? displayTitle
                                    : _formatAudioStream(data);

                                // ✅ 添加默认标记
                                if (isDefault && !mainLabel.contains('默认')) {
                                  mainLabel = '$mainLabel (默认)';
                                }

                                // ✅ 副标题：如果 Title 存在且不同于 DisplayTitle
                                final hasSubtitle = title.isNotEmpty &&
                                    title != displayTitle &&
                                    displayTitle.isNotEmpty;

                                return Material(
                                  key: itemKeys[index], // ✅ 添加 key 用于滚动定位
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogCtx).pop(index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  mainLabel,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                                if (hasSubtitle) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    title,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.6),
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
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
        );
      },
    );

    scrollController.dispose();

    // ✅ 标记音频菜单已关闭
    setState(() {
      _showAudioMenu = false;
    });

    _resetHideControlsTimer();

    if (result != null && result >= 0 && result < _audioStreams.length) {
      final previousIndex = _selectedAudioStreamIndex;
      setState(() {
        _selectedAudioStreamIndex = result;
        _hasManuallySelectedAudio = true;
      });
      await _saveStreamSelections();

      // ✅ 如果音频流改变，重新加载播放器
      if (previousIndex != result) {
        _playerLogImportant(
            '🔄 [Player] Audio stream changed from $previousIndex to $result, reloading...');
        await _reloadPlayer();
      }
    }
  }

  // ✅ 显示字幕选择菜单
  Future<void> _showSubtitleSelectionMenu(BuildContext anchorContext) async {
    if (_subtitleStreams.isEmpty) return;

    _cancelHideControlsTimer();

    // ✅ 标记字幕菜单正在显示
    setState(() {
      _showSubtitleMenu = true;
    });

    final RenderBox? button = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay;
    final RenderBox? overlayBox =
        overlay?.context.findRenderObject() as RenderBox?;

    if (button == null || overlayBox == null) {
      _resetHideControlsTimer();
      return;
    }

    final Offset buttonOffset =
        button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Size overlaySize = overlayBox.size;

    double panelWidth = 240.0;
    const double maxHeight = 230.0;
    const double spacing = 12.0;

    const double minLeftMargin = 16.0;
    const double rightMargin = 18.0;

    final double maxAllowedWidth =
        overlaySize.width - minLeftMargin - rightMargin;
    if (panelWidth > maxAllowedWidth) {
      panelWidth = maxAllowedWidth.clamp(120.0, panelWidth);
    }

    double left = buttonOffset.dx + button.size.width - panelWidth;
    final double maxLeft = overlaySize.width - panelWidth - rightMargin;

    if (maxLeft < minLeftMargin) {
      panelWidth = (overlaySize.width - minLeftMargin - rightMargin)
          .clamp(120.0, panelWidth);
      left = minLeftMargin;
    } else {
      left = left.clamp(minLeftMargin, maxLeft);
    }
    final double bottom = (overlaySize.height - buttonOffset.dy) + spacing + 10;

    final scrollController = ScrollController();
    // ✅ +1 因为第一个是"不显示"选项
    final itemKeys = List.generate(
      _subtitleStreams.length + 1,
      (index) => GlobalKey(),
    );

    void scheduleScroll() {
      if (_selectedSubtitleStreamIndex == null) return;
      // ✅ -1 表示"不显示"，对应 itemKeys[0]
      // >=0 表示字幕流索引，对应 itemKeys[index + 1]
      final keyIndex = _selectedSubtitleStreamIndex == -1
          ? 0
          : _selectedSubtitleStreamIndex! + 1;
      if (keyIndex < 0 || keyIndex >= itemKeys.length) return;
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          final key = itemKeys[keyIndex];
          final context = key.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: 0.0, // ✅ 滚动到顶部
            );
          }
        } catch (e) {
          // 忽略滚动错误
        }
      });
    }

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        scheduleScroll();
        final isDark = isDarkModeFromContext(context, ref);
        final gradientColors = isDark
            ? [
                Colors.grey.shade900.withValues(alpha: 0.7),
                Colors.grey.shade800.withValues(alpha: 0.5),
              ]
            : [
                Colors.white.withValues(alpha: 0.25),
                Colors.white.withValues(alpha: 0.15),
              ];

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
              Positioned(
                left: left,
                bottom: bottom,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: panelWidth,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ✅ 只有当字幕数量大于0时才添加"不显示"选项
                              if (_subtitleStreams.isNotEmpty)
                                Material(
                                  key: itemKeys[0], // ✅ "不显示"选项的 key
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogCtx).pop(-1),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '不显示',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight:
                                                    _selectedSubtitleStreamIndex ==
                                                            -1
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          if (_selectedSubtitleStreamIndex ==
                                              -1)
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              // ✅ 字幕流列表
                              ...List.generate(
                                _subtitleStreams.length,
                                (index) {
                                  final data = _subtitleStreams[index];
                                  final displayTitle =
                                      data['DisplayTitle']?.toString() ?? '';
                                  final title = data['Title']?.toString() ?? '';
                                  final isDefault =
                                      (data['IsDefault'] as bool?) == true;
                                  final isSelected =
                                      index == _selectedSubtitleStreamIndex;

                                  // ✅ 主标题：优先使用 DisplayTitle
                                  String mainLabel = displayTitle.isNotEmpty
                                      ? displayTitle
                                      : _formatSubtitleStream(data);

                                  // ✅ 添加默认标记
                                  if (isDefault && !mainLabel.contains('默认')) {
                                    mainLabel = '$mainLabel (默认)';
                                  }

                                  // ✅ 副标题：如果 Title 存在且不同于 DisplayTitle
                                  final hasSubtitle = title.isNotEmpty &&
                                      title != displayTitle &&
                                      displayTitle.isNotEmpty;

                                  return Material(
                                    key: itemKeys[index +
                                        1], // ✅ 字幕流的 key（+1 因为第一个是"不显示"）
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () =>
                                          Navigator.of(dialogCtx).pop(index),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    mainLabel,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (hasSubtitle) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      title,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.6),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              const Icon(
                                                Icons.check_rounded,
                                                size: 20,
                                                color: Colors.white,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    scrollController.dispose();

    // ✅ 标记字幕菜单已关闭
    setState(() {
      _showSubtitleMenu = false;
    });

    _resetHideControlsTimer();

    // ✅ 支持选择"不显示"（-1）或有效的字幕流索引
    if (result != null &&
        (result == -1 || (result >= 0 && result < _subtitleStreams.length))) {
      final previousIndex = _selectedSubtitleStreamIndex;
      setState(() {
        _selectedSubtitleStreamIndex = result;
        _hasManuallySelectedSubtitle = true;
      });
      await _saveStreamSelections();
      _updateSubtitleUrl();

      // ✅ 检查是否为内嵌字幕（需要重新加载播放器）
      // 外挂字幕通过 URL 加载，不需要重新加载播放器
      if (previousIndex != result &&
          result >= 0 &&
          result < _subtitleStreams.length) {
        final subtitleStream = _subtitleStreams[result];
        final isExternal = (subtitleStream['IsExternal'] as bool?) == true;

        // ✅ 如果是内嵌字幕，需要重新加载播放器
        if (!isExternal) {
          _playerLogImportant(
              '🔄 [Player] Embedded subtitle stream changed from $previousIndex to $result, reloading...');
          await _reloadPlayer();
        }
      }
    }
  }

  /// ✅ 更新字幕URL（尝试多种格式找到可用的）
  Future<void> _updateSubtitleUrl() async {
    // ✅ 如果选择的是"不显示"（-1），则清空字幕URL
    if (_api == null ||
        _selectedSubtitleStreamIndex == null ||
        _selectedSubtitleStreamIndex == -1) {
      setState(() {
        _subtitleUrl = null;
      });
      return;
    }

    try {
      final subtitleStream = _subtitleStreams[_selectedSubtitleStreamIndex!];

      // ✅ 调试信息：打印字幕流的完整信息
      _playerLog('🎬 [Player] Subtitle stream data: $subtitleStream');

      // ✅ Emby API 可能需要使用字幕流的 Index 字段（不是数组索引）
      // 根据 Emby API 文档，字幕 URL 格式为：
      // /Videos/{itemId}/Subtitles/{streamIndex}/Stream.{format}
      // 其中 streamIndex 是字幕流在 MediaStreams 中的 Index 字段值
      int? subtitleIndex = subtitleStream['Index'] as int?;

      // ✅ 如果 Index 不存在，尝试使用 _originalIndex（数组位置）
      if (subtitleIndex == null) {
        subtitleIndex = subtitleStream['_originalIndex'] as int?;
        _playerLog('🎬 [Player] Using _originalIndex: $subtitleIndex');
      } else {
        _playerLog('🎬 [Player] Using Index field: $subtitleIndex');
      }

      if (subtitleIndex != null) {
        // ✅ 获取字幕 URL：优先尝试文本格式，如果是 PGSSUB 则直接使用图片流
        final codec = subtitleStream['Codec']?.toString().toLowerCase() ?? '';
        final urls = <String>[];

        if (codec == 'pgssub' || codec == 'dvd_subtitle' || codec == 'dvdsub') {
          // ✅ 图片字幕：直接获取原始流 URL（不指定 format）
          _playerLog('🎬 [Player] Detected image subtitle codec: $codec');
          urls.addAll(await _api!.buildSubtitleUrls(
            itemId: widget.itemId,
            subtitleStreamIndex: subtitleIndex,
            mediaSourceId: _mediaSourceId,
            // 不指定 format，让 Emby 返回原始图片流
          ));
        } else {
          // ✅ 文本字幕：尝试多种格式
          final formats = ['vtt', 'srt', 'ass'];
          for (final fmt in formats) {
            urls.addAll(await _api!.buildSubtitleUrls(
              itemId: widget.itemId,
              subtitleStreamIndex: subtitleIndex,
              mediaSourceId: _mediaSourceId,
              format: fmt,
            ));
          }
        }

        _playerLog(
            '🎬 [Player] Generated ${urls.length} subtitle URL variants for stream $subtitleIndex (codec=$codec)');

        final distinctUrls = urls.toSet().toList();

        if (mounted && distinctUrls.isNotEmpty) {
          final combinedUrl = distinctUrls.join('|||');
          final previewLength =
              combinedUrl.length > 120 ? 120 : combinedUrl.length;
          _playerLog(
              '🎬 [Player] Applying subtitle URL variants (preview: ${combinedUrl.substring(0, previewLength)})');
          setState(() {
            _subtitleUrl = combinedUrl;
          });
          _playerLog(
              '🎬 [Player] subtitleUrl set, urls=${distinctUrls.length}, length=${combinedUrl.length}');
        } else if (mounted) {
          _playerLog('❌ [Player] No subtitle URL variants generated');
          setState(() {
            _subtitleUrl = null;
          });
        }
      } else {
        _playerLog('❌ [Player] Subtitle index not found');
        if (mounted) {
          setState(() {
            _subtitleUrl = null;
          });
        }
      }
    } catch (e) {
      _playerLog('❌ [Player] Update subtitle URL failed: $e');
      if (mounted) {
        setState(() {
          _subtitleUrl = null;
        });
      }
      _playerLog('❌ [Player] subtitleUrl cleared due to error');
    }
  }

  Future<void> _guardPlayerCommand(
    String action,
    Future<void> Function() command, {
    bool swallowErrors = false,
  }) async {
    try {
      await command();
    } catch (error, stackTrace) {
      _handlePlayerError(action, error, stackTrace, swallowErrors);
    }
  }

  Future<T?> _guardPlayerRequest<T>(
    String action,
    Future<T> Function() request, {
    bool swallowErrors = false,
  }) async {
    try {
      return await request();
    } catch (error, stackTrace) {
      _handlePlayerError(action, error, stackTrace, swallowErrors);
    }
    return null;
  }

  void _handlePlayerError(
    String action,
    Object error,
    StackTrace stackTrace,
    bool swallowErrors,
  ) {
    _playerLog('❌ [Player] $action failed: $error');
    if (!swallowErrors) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _playerPlay() =>
      _guardPlayerCommand('play', _player.play, swallowErrors: true);

  Future<void> _playerPause() =>
      _guardPlayerCommand('pause', _player.pause, swallowErrors: true);

  Future<void> _playerSeek(
    Duration position, {
    bool swallowErrors = false,
  }) =>
      _guardPlayerCommand(
        'seek to ${position.inMilliseconds}ms',
        () => _player.seek(position),
        swallowErrors: swallowErrors,
      );

  Future<void> _playerSetRate(
    double rate, {
    bool swallowErrors = false,
    String action = 'set playback speed',
  }) =>
      _guardPlayerCommand(
        action,
        () => _player.setRate(rate),
        swallowErrors: swallowErrors,
      );

  Future<void> _playerSetVolume(double volumePercent) => _guardPlayerCommand(
        'set volume',
        () => _player.setVolume(volumePercent),
      );

  // ✅ 获取当前选中的音频 MediaStream Index（不是数组索引）
  int? _getCurrentAudioStreamIndex() {
    if (_selectedAudioStreamIndex != null &&
        _selectedAudioStreamIndex! >= 0 &&
        _selectedAudioStreamIndex! < _audioStreams.length) {
      return _audioStreams[_selectedAudioStreamIndex!]['Index'] as int?;
    }
    return null;
  }

  // ✅ 获取当前选中的字幕 MediaStream Index（不是数组索引）
  int? _getCurrentSubtitleStreamIndex() {
    if (_selectedSubtitleStreamIndex == null) {
      return null;
    }
    if (_selectedSubtitleStreamIndex == -1) {
      return -1; // 不显示字幕
    }
    if (_selectedSubtitleStreamIndex! >= 0 &&
        _selectedSubtitleStreamIndex! < _subtitleStreams.length) {
      return _subtitleStreams[_selectedSubtitleStreamIndex!]['Index'] as int?;
    }
    return null;
  }

  // ✅ 切换到新剧集（直接切换URL，不重新创建播放器）
  Future<void> _switchToNewEpisode(String newItemId) async {
    _playerLogImportant('🎬 [Player] Switching to new episode: $newItemId');

    try {
      // ✅ 先向 Emby 汇报旧剧集的播放停止（只汇报一次）
      if (!_hasReportedPlaybackStopped &&
          _api != null &&
          _userId != null &&
          _playSessionId != null &&
          _mediaSourceId != null) {
        try {
          final positionTicks = (_position.inMicroseconds * 10).toInt();
          await _api!.reportPlaybackStopped(
            itemId: _currentItemId, // 旧剧集的ID
            userId: _userId!,
            playSessionId: _playSessionId!,
            mediaSourceId: _mediaSourceId,
            positionTicks: positionTicks,
          );
          _hasReportedPlaybackStopped = true; // ✅ 标记已汇报
          _playerLog('✅ [Player] Reported playback stopped for old episode');
        } catch (e) {
          _playerLog('⚠️ [Player] Failed to report playback stopped: $e');
        }
      }

      // ✅ 更新当前itemId
      _currentItemId = newItemId;

      // ✅ 重置状态并更新UI
      if (mounted) {
        setState(() {
          _hasHandledCompletion = false;
          _completedReported = false;
          _lastReportedPosition = Duration.zero;
          _position = Duration.zero;
          _duration = Duration.zero;
          _bufferPosition = Duration.zero;
          _isBuffering = true;
          _ready = false;
          _hasReportedPlaybackStart = false; // ✅ 重置播放开始汇报标志
          _hasReportedPlaybackStopped = false; // ✅ 重置播放停止汇报标志
          _hasStartedPlayback = false; // ✅ 重置播放标志，显示新剧集的背景图
          _isFirstTimeAutoPlay = true; // ✅ 重置首次播放标志，新剧集延迟隐藏控制栏
        });
      }

      // ✅ 获取新剧集的信息
      if (_api == null || _userId == null) {
        _playerLog('⚠️ [Player] API or userId not available');
        return;
      }

      final itemDetails = await _api!.getItem(_userId!, _currentItemId);
      _videoTitle = itemDetails.name;

      // ✅ 更新 itemDetails 并触发 UI 刷新（显示背景图）
      if (mounted) {
        setState(() {
          _itemDetails = itemDetails;
          _itemType = itemDetails.type;
        });
      } else {
        _itemDetails = itemDetails;
        _itemType = itemDetails.type;
      }

      // ✅ 如果是Episode类型，获取上一集和下一集
      if (itemDetails.type == 'Episode' && itemDetails.seriesId != null) {
        _previousEpisode = await _api!.getPreviousEpisode(
          userId: _userId!,
          seriesId: itemDetails.seriesId!,
          currentEpisodeId: _currentItemId,
        );
        _nextEpisode = await _api!.getNextEpisode(
          userId: _userId!,
          seriesId: itemDetails.seriesId!,
          currentEpisodeId: _currentItemId,
        );
      }

      // ✅ 更新音频和字幕流信息（新剧集）
      _audioStreams = _getAudioStreams(itemDetails);
      _subtitleStreams = _getSubtitleStreams(itemDetails);

      // ✅ 获取实际的 MediaStream Index（用于 PlaybackInfo）
      int? actualAudioIndex;
      int? actualSubtitleIndex;

      if (_hasManuallySelectedAudio &&
          _selectedAudioStreamIndex != null &&
          _selectedAudioStreamIndex! >= 0 &&
          _selectedAudioStreamIndex! < _audioStreams.length) {
        actualAudioIndex =
            _audioStreams[_selectedAudioStreamIndex!]['Index'] as int?;
      }

      if (_hasManuallySelectedSubtitle &&
          _selectedSubtitleStreamIndex != null) {
        if (_selectedSubtitleStreamIndex! >= 0 &&
            _selectedSubtitleStreamIndex! < _subtitleStreams.length) {
          actualSubtitleIndex =
              _subtitleStreams[_selectedSubtitleStreamIndex!]['Index'] as int?;
        } else if (_selectedSubtitleStreamIndex == -1) {
          actualSubtitleIndex = -1;
        }
      }

      _playerLog(
          '🎬 [Player] Switch episode - Audio Index: $actualAudioIndex, Subtitle Index: $actualSubtitleIndex');

      // ✅ 获取PlaybackInfo和MediaSourceId（传递音频和字幕索引）
      final playbackInfo = await _api!.getPlaybackInfo(
        itemId: _currentItemId,
        userId: _userId!,
        startTimeTicks: 0,
        isPlayback: false,
        autoOpenLiveStream: false,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
      );

      if (playbackInfo['MediaSources'] != null &&
          playbackInfo['MediaSources'] is List &&
          (playbackInfo['MediaSources'] as List).isNotEmpty) {
        final firstSource = (playbackInfo['MediaSources'] as List).first;
        if (firstSource is Map) {
          final playbackMediaSource = Map<String, dynamic>.from(firstSource);
          _mediaSourceId = playbackMediaSource['Id'] as String?;
          _playSessionId = playbackInfo['PlaySessionId'] as String?;
        }
      }

      // ✅ 获取选中的画质参数
      Map<String, dynamic>? qualityOption;
      if (_selectedQuality != null && _qualityOptions.isNotEmpty) {
        qualityOption = _qualityOptions.firstWhere(
          (q) => q['label'] == _selectedQuality,
          orElse: () => <String, dynamic>{},
        );
      }

      // ✅ 构建新的HLS URL（复用之前计算的 actualAudioIndex 和 actualSubtitleIndex）
      final media = await _api!.buildHlsUrl(
        _currentItemId,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
        maxBitrate: qualityOption?['bitrate'] as int?,
        startTimeTicks: 0, // 新剧集从头开始
      );

      _playerLogImportant('🎬 [Player] New episode URL: ${media.uri}');

      // ✅ 直接切换播放URL（不重新创建播放器）
      await _guardPlayerCommand(
        'switch episode',
        () => _player.open(
          url: media.uri,
          headers: media.headers,
          isHls: true,
          autoPlay: true, // 自动播放新剧集
          startPosition: Duration.zero, // 从头开始
        ),
      );

      _playerLogImportant('✅ [Player] Successfully switched to new episode');

      // ✅ 主动向 Emby 汇报新剧集的播放开始
      if (_playSessionId != null && _mediaSourceId != null) {
        try {
          final audioIndex = _getCurrentAudioStreamIndex();
          final subtitleIndex = _getCurrentSubtitleStreamIndex();
          _playerLog(
              '🎬 [Player] Reporting new episode start - Audio: $audioIndex, Subtitle: $subtitleIndex');

          await _api!.reportPlaybackStart(
            itemId: _currentItemId,
            userId: _userId!,
            playSessionId: _playSessionId!,
            mediaSourceId: _mediaSourceId,
            positionTicks: 0, // 从头开始
            audioStreamIndex: audioIndex,
            subtitleStreamIndex: subtitleIndex,
          );
          _hasReportedPlaybackStart = true; // ✅ 标记已汇报，防止重复
          _playerLog('✅ [Player] Reported playback start for new episode');
        } catch (e) {
          _playerLog('⚠️ [Player] Failed to report playback start: $e');
        }
      }
    } catch (e) {
      _playerLog('❌ [Player] Failed to switch episode: $e');
    } finally {
      // ✅ 重置切换标志
      _isSwitchingEpisode = false;
    }
  }

  // ✅ 播放上一集
  void _playPreviousEpisode() {
    // ✅ 防止重复点击
    if (_isSwitchingEpisode) {
      _playerLog('⚠️ [Player] Already switching episode, ignoring click');
      return;
    }

    if (_previousEpisode == null || _previousEpisode!.id == null) {
      _playerLog('⚠️ [Player] No previous episode available');
      return;
    }

    if (!mounted) return;

    _isSwitchingEpisode = true;
    final episodeId = _previousEpisode!.id!;
    final episodeName = _previousEpisode!.name;

    _playerLogImportant('🎬 [Player] Playing previous episode: $episodeName');

    // ✅ 切换到新剧集（直接切换URL）
    _switchToNewEpisode(episodeId);
  }

  // ✅ 播放下一集
  void _playNextEpisode() {
    // ✅ 防止重复点击
    if (_isSwitchingEpisode) {
      _playerLog('⚠️ [Player] Already switching episode, ignoring click');
      return;
    }

    if (_nextEpisode == null || _nextEpisode!.id == null) {
      _playerLog('⚠️ [Player] No next episode available');
      return;
    }

    if (!mounted) return;

    _isSwitchingEpisode = true;
    final episodeId = _nextEpisode!.id!;
    final episodeName = _nextEpisode!.name;

    _playerLogImportant('🎬 [Player] Playing next episode: $episodeName');

    // ✅ 切换到新剧集（直接切换URL）
    _switchToNewEpisode(episodeId);
  }

  // ✅ 应用生命周期状态变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _playerLog(
        '🎬 [Player] App lifecycle state: $state, isInPipMode: $_isInPipMode, isPlaying: $_isPlaying, isManuallyEnteringPip: $_isManuallyEnteringPip');

    switch (state) {
      case AppLifecycleState.inactive:
        // ✅ 应用失去焦点（如来电、下拉通知栏、进入任务中心、按Home键等）
        // 不要在这里暂停播放，让原生层的 onUserLeaveHint 决定是进入 PiP 还是暂停
        // 只有手动进入 PiP 时才需要特殊处理（防止闪烁）
        if (_isManuallyEnteringPip) {
          _playerLog('🎬 [Player] Manually entering PiP, keep playing');
        } else {
          _playerLog(
              '🎬 [Player] Inactive state, waiting for native onUserLeaveHint or paused state');
        }
        break;

      case AppLifecycleState.paused:
        // ✅ 应用进入后台（此时 onUserLeaveHint 已经触发）
        // 如果不在 PiP 模式，说明 onUserLeaveHint 没有进入 PiP（如下拉通知栏），需要暂停播放
        _playerLog('🎬 [Player] App paused, isInPipMode: $_isInPipMode');
        if (!_isInPipMode && _isPlaying) {
          _playerPause();
          _playerLog('🎬 [Player] Auto-paused on background (not in PiP)');
        }
        break;

      case AppLifecycleState.resumed:
        // 应用恢复前台，重置状态
        _isManuallyEnteringPip = false;
        _playerLog('🎬 [Player] App resumed');
        break;

      default:
        break;
    }
  }

  // ✅ 获取全速缓冲配置（极度激进策略）
  Map<String, dynamic> _getAdaptiveCacheConfig() {
    // ✅ 使用极度激进的缓冲策略，全速下载
    // maxBufferMs 设置为 30 分钟（1800秒），让播放器可以缓存整部电影/剧集
    // minBufferMs 设置为 3 秒，更快启动
    // bufferForPlaybackMs 设置为 300ms，几乎瞬间开始播放
    // 这样可以充分利用 100Mbps+ 的高速带宽，快速缓存整个视频
    _playerLog(
        '🚀 [Player] Using ULTRA-AGGRESSIVE FULL SPEED cache config - Maximum buffering enabled');
    _playerLog(
        '🚀 [Player] Target: Cache entire video at full network speed (100+ Mbps)');
    return {
      'minBufferMs': 3000, // 最小缓冲 3 秒（超快启动）
      'maxBufferMs': 1800000, // 最大缓冲 30 分钟（可缓存整部电影）
      'bufferForPlaybackMs': 300, // 只需 0.3 秒即可开始播放（瞬间启动）
      'bufferForPlaybackAfterRebufferMs': 500, // 重新缓冲后 0.5 秒继续（极速恢复）
      'targetBufferBytes': -1, // 不限制目标缓冲字节数（无限制）
      'prioritizeTimeOverSizeThresholds': true, // 优先时间而非大小
      'backBufferDurationMs': 0, // 不保留后向缓冲（节省内存，全力前向缓冲）
      'maxLoadingQueueSize': 10, // 最大加载队列（允许更多并发下载）
    };
  }

  // ✅ 处理播放错误
  Future<void> _handlePlaybackError(String error) async {
    _errorCount++;

    final errorLower = error.toLowerCase();

    // ✅ 检查是否是可能与音频相关的错误（HTTP 500、Source error 等）
    // 这些错误通常是服务器转码失败，很可能是音频编解码器不支持导致
    final isPossibleAudioError = errorLower.contains('source error') ||
        errorLower.contains('500') ||
        errorLower.contains('secondaryaudionotsupported') ||
        errorLower.contains('audio') && errorLower.contains('not supported');

    if (isPossibleAudioError) {
      _playerLog('🎵 [Player] Possible audio error detected: $error');

      // ✅ 记录当前尝试的音频轨道
      if (_selectedAudioStreamIndex != null &&
          _selectedAudioStreamIndex! >= 0) {
        _triedAudioIndices.add(_selectedAudioStreamIndex!);
      }

      // ✅ 检查是否还有未尝试的音频轨道
      final hasMoreAudioTracks =
          _audioStreams.length > _triedAudioIndices.length;

      if (hasMoreAudioTracks) {
        // ✅ 尝试切换到下一个音频轨道
        if (await _tryNextAudioTrack()) {
          _playerLog('✅ [Player] Switched to next audio track, retrying...');

          // ✅ 标记为用户手动选择（自动切换成功后视作手动选择）
          _hasManuallySelectedAudio = true;

          // ✅ 持久化保存音频选择
          await _saveStreamSelections();

          // 切换成功，重新加载播放器
          try {
            await _reloadPlayer();
            _errorRetryCount = 0;
            return;
          } catch (e) {
            _playerLog('❌ [Player] Reload with new audio failed: $e');
            // 不递归调用，等待播放器自己报错后再次触发 _handlePlaybackError
            return;
          }
        }
      }

      // ✅ 所有音频轨道都尝试过了，显示错误
      _playerLog(
          '❌ [Player] All audio tracks tried (${_triedAudioIndices.length}/${_audioStreams.length}), showing error dialog');
      _showErrorDialog(
          '所有音频轨道都不支持\n\n已尝试 ${_triedAudioIndices.length} 个音频轨道\n\n请尝试：\n1. 更新服务器\n2. 检查音频编解码器支持\n3. 使用其他播放器');
      _triedAudioIndices.clear(); // 重置已尝试列表
      return;
    }

    // 其他网络错误可以重试
    if (errorLower.contains('network') ||
        errorLower.contains('timeout') ||
        errorLower.contains('connection')) {
      if (_errorRetryCount < _maxRetryCount) {
        _errorRetryCount++;
        _playerLog(
            '🔄 [Player] Retrying... ($_errorRetryCount/$_maxRetryCount)');

        // 延迟重试，避免频繁请求
        _retryTimer?.cancel();
        _retryTimer = Timer(Duration(seconds: _errorRetryCount * 2), () async {
          if (mounted) {
            try {
              await _reloadPlayer();
              _errorRetryCount = 0; // 重试成功，重置计数
            } catch (e) {
              _playerLog('❌ [Player] Retry failed: $e');
            }
          }
        });
      } else {
        // 达到最大重试次数，显示错误提示
        _showErrorDialog('播放失败，已重试 $_maxRetryCount 次\n\n错误：$error');
        _errorRetryCount = 0; // 重置计数
      }
    } else {
      // 其他错误直接提示
      _showErrorDialog('播放出错：$error');
    }
  }

  // ✅ 尝试切换到下一个可用的音频轨道
  Future<bool> _tryNextAudioTrack() async {
    if (_audioStreams.isEmpty) {
      _playerLog('⚠️ [Player] No audio streams available');
      return false;
    }

    // ✅ 找到下一个未尝试过的音频轨道
    for (int i = 0; i < _audioStreams.length; i++) {
      if (!_triedAudioIndices.contains(i)) {
        final audioStream = _audioStreams[i];
        final language = audioStream['DisplayLanguage'] ??
            audioStream['Language'] ??
            'Unknown';
        final codec =
            audioStream['Codec']?.toString().toUpperCase() ?? 'Unknown';
        final channelLayout = audioStream['ChannelLayout'] ?? '';

        _playerLog('🎵 [Player] Trying audio track $i: $language ($codec)');

        // ✅ 显示音频切换提示
        _showAudioSwitchToast('音频不支持，正在切换\n$language $codec $channelLayout');

        if (mounted) {
          setState(() {
            _selectedAudioStreamIndex = i;
          });
          _playerLog(
              '✅ [Player] Updated _selectedAudioStreamIndex to $i (UI will sync)');
        } else {
          _selectedAudioStreamIndex = i;
          _playerLog(
              '✅ [Player] Updated _selectedAudioStreamIndex to $i (not mounted)');
        }

        return true;
      }
    }

    _playerLog('⚠️ [Player] All audio tracks have been tried');
    return false;
  }

  // ✅ 显示音频切换提示
  void _showAudioSwitchToast(String message) {
    _audioSwitchHintTimer?.cancel();

    if (mounted) {
      setState(() {
        _audioSwitchHintText = message;
        _showAudioSwitchHint = true;
      });
    }

    // ✅ 3秒后自动隐藏
    _audioSwitchHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showAudioSwitchHint = false;
        });
      }
    });
  }

  // ✅ 显示错误对话框
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('播放错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // 退出播放页
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ✅ 预加载下一集
  Future<void> _preloadNextEpisode() async {
    if (_nextEpisode?.id == null || _api == null || _userId == null) return;

    try {
      _playerLog('🚀 [Player] Preloading next episode...');

      // 获取选中的画质参数
      Map<String, dynamic>? qualityOption;
      if (_selectedQuality != null && _qualityOptions.isNotEmpty) {
        qualityOption = _qualityOptions.firstWhere(
          (q) => q['label'] == _selectedQuality,
          orElse: () => <String, dynamic>{},
        );
      }

      // 预加载下一集的 URL（不实际播放）
      await _api!.buildHlsUrl(
        _nextEpisode!.id!,
        maxBitrate: qualityOption?['bitrate'] as int?,
      );

      _playerLog('✅ [Player] Next episode preloaded');
    } catch (e) {
      _playerLog('⚠️ [Player] Failed to preload next episode: $e');
    }
  }

  // ✅ 上报播放统计
  void _reportPlaybackStats() {
    final averageSpeed = _currentSpeedKbps ?? 0;
    _playerLog('''
📊 [Player] Playback Stats:
  - Buffering count: $_bufferingCount
  - Total buffering time: ${_totalBufferingTime.inSeconds}s
  - Error count: $_errorCount
  - Average speed: ${(averageSpeed / 1000).toStringAsFixed(1)} Mbps
  - Video title: $_videoTitle
  - Duration: ${_formatTime(_duration)}
  - Final position: ${_formatTime(_position)}
  ''');
  }
}
