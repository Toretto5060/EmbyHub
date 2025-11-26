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

const bool _kPlayerLogging = false; // 已禁用日志
void _playerLog(String message) {
  // 日志已禁用
}

// 重要日志已禁用
void _playerLogImportant(String message) {
  // 日志已禁用
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
  static const Duration _playerReadyTimeout = Duration(seconds: 30);
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

      // 等待 positionStream 确认落在目标附近（误差 <1 秒）
      try {
        await _player.positionStream
            .firstWhere(
                (pos) => (pos - target).abs() < const Duration(seconds: 1))
            .timeout(const Duration(seconds: 3));
      } catch (_) {}

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

  // ✅ 自定义字幕URL
  String? _subtitleUrl;

  // ✅ MediaSourceId（用于构建字幕URL）
  String? _mediaSourceId;
  String? _playSessionId; // ✅ PlaySessionId，用于调用 /Sessions/Playing

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

    // ✅ 如果从上一页传入了 ItemInfo，立即设置（用于显示背景图）
    if (widget.itemInfo != null) {
      _itemDetails = widget.itemInfo;
      _itemType = widget.itemInfo!.type;
      _videoTitle = widget.itemInfo!.name ?? 'Video';
    }

    // ✅ 如果从上一页传入了 Logo URL，立即设置
    if (widget.logoUrl != null) {
      _logoUrl = widget.logoUrl;
    }

    // ✅ 在页面初始化时立即获取并保存原始亮度（在系统可能调整亮度之前）
    // 这样即使系统在进入全屏时自动调整了亮度，我们也能恢复正确的原始亮度
    _getCurrentBrightness().then((_) {
      if (_originalBrightness == null && _currentBrightness != null) {
        _originalBrightness = _currentBrightness;
      }
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
        _playerLog('🎬 [Player] PiP mode changed: $isInPipMode');
        if (mounted) {
          setState(() {
            _isInPipMode = isInPipMode;
          });
        }
      }

      return null;
    });

    _loadStreamSelections();
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
    } catch (e, stack) {
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

      setState(() => _isBuffering = isBuffering);

      // ✅ 如果从缓冲状态变为非缓冲状态，且播放器应该在播放但实际没有播放，则恢复播放
      if (wasBuffering && !isBuffering && !_player.isPlaying) {
        _playerLog(
            '🎬 [Player] Buffering ended, checking if need to resume playback...');
        // 延迟一小段时间，确保播放器状态稳定
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && !_player.isPlaying) {
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
    _readySub = _player.readyStream.listen((ready) {
      if (mounted) {
        setState(() => _ready = ready);
      }
    });

    _errorSub?.cancel();
    _errorSub = _player.errorStream.listen((message) {
      _playerLog('❌ [Player] Error: $message');
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
        maxWidth: qualityOption?['width'] as int?,
        maxHeight: qualityOption?['height'] as int?,
        maxBitrate: qualityOption?['bitrate'] as int?,
        startTimeTicks: currentPosition.inMicroseconds > 0
            ? (currentPosition.inMicroseconds * 10).toInt()
            : null,
      );

      _playerLog('🎬 [Player] New media URL: ${media.uri}');

      // ✅ 检测是否为 HLS 流
      final isHlsStream =
          media.uri.contains('.m3u8') || media.uri.contains('hls');

      // ✅ 使用激进的缓冲策略
      final cacheConfig = {
        'minBufferMs': 15000,
        'maxBufferMs': 60000,
        'bufferForPlaybackMs': 1500,
        'bufferForPlaybackAfterRebufferMs': 3000,
      };

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
          cacheConfig: cacheConfig, // ✅ 使用优化的缓冲配置
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
    } catch (e, stack) {
      _playerLog('❌ [Player] Reload player failed: $e');
    }
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
      if (_itemDetails == null && itemDetails != null) {
        if (mounted) {
          setState(() {
            _itemDetails = itemDetails;
            _itemType = itemDetails?.type;
          });
        } else {
          _itemDetails = itemDetails;
          _itemType = itemDetails?.type;
        }
      }

      // ✅ 获取Logo URL（优先使用传入的，避免重复请求）
      if (widget.logoUrl != null) {
        _playerLog('✅ [Player] Using cached logo URL');
        _logoUrl = widget.logoUrl;
      } else if (itemDetails != null && itemDetails.id != null) {
        // 对于Episode类型，尝试获取Series的Logo
        if (itemDetails.type == 'Episode' && itemDetails.seriesId != null) {
          // 优先使用传入的 seriesInfo
          if (widget.seriesInfo != null) {
            _playerLog('✅ [Player] Using cached series info for logo');
            if (widget.seriesInfo!.imageTags != null &&
                widget.seriesInfo!.imageTags!.containsKey('Logo')) {
              _logoUrl = api.buildImageUrl(
                itemId: itemDetails.seriesId!,
                type: 'Logo',
                maxWidth: 400,
                tag: widget.seriesInfo!.imageTags!['Logo'],
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
            final playbackInfo = await api.getPlaybackInfo(
              itemId: _currentItemId,
              userId: _userId!,
              startTimeTicks: 0,
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

            // ✅ 根据 PlaybackInfo 中的视频分辨率生成转码选项（优先使用 PlaybackInfo）
            final generatedOptions = playbackMediaSource != null
                ? _generateQualityOptionsFromMediaSource(playbackMediaSource)
                : _generateQualityOptions(itemDetails);
            _playerLog(
                '🎬 [Player] Generated options count: ${generatedOptions.length}');

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
      }

      _playerLog(
          '🎬 [Player] Initial load - Array indices - Audio: $_selectedAudioStreamIndex, Subtitle: $_selectedSubtitleStreamIndex');
      _playerLog(
          '🎬 [Player] Initial load - MediaStream indices - Audio: $actualAudioIndex, Subtitle: $actualSubtitleIndex');

      final media = await api.buildHlsUrl(
        _currentItemId,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
        maxWidth: qualityOption?['width'] as int?,
        maxHeight: qualityOption?['height'] as int?,
        maxBitrate: qualityOption?['bitrate'] as int?,
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
      // ✅ 使用激进的缓冲策略，适合高速网络
      final cacheConfig = {
        'minBufferMs': 15000, // 最小缓冲15秒（默认50秒太多）
        'maxBufferMs': 60000, // 最大缓冲60秒（默认50秒）
        'bufferForPlaybackMs': 1500, // 开始播放需要1.5秒缓冲（默认2.5秒）
        'bufferForPlaybackAfterRebufferMs': 3000, // 重新缓冲后需要3秒（默认5秒）
      };

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
          cacheConfig: cacheConfig, // ✅ 使用优化的缓冲配置
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

      // ✅ 播放器已通过原生层的 playWhenReady 自动开始播放
      _playerLogImportant('🎬 [Player] Playback started with autoPlay');

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
    _bufferSub?.cancel();
    _readySub?.cancel();
    _videoSizeSub?.cancel();
    _errorSub?.cancel();
    _networkSpeedSub?.cancel(); // ✅ 取消网络速度订阅
    _hideControlsTimer?.cancel();
    _videoFitHintTimer?.cancel(); // ✅ 取消视频裁切模式提示计时器
    _longPressTimer?.cancel(); // ✅ 取消长按定时器
    _speedAccelerationTimer?.cancel(); // ✅ 取消倍速加速定时器
    _speedListScrollController.dispose(); // ✅ 释放速度列表滚动控制器
    _qualityListScrollController.dispose(); // ✅ 释放分辨率列表滚动控制器
    _controlsAnimationController.dispose();
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

    // ✅ 找到选中项的索引（包括"自动"选项）
    int selectedIndex = 0; // 默认是"自动"
    if (_selectedQuality != null) {
      selectedIndex = _qualityOptions.indexWhere(
            (q) => q['label'] == _selectedQuality,
          ) +
          1; // +1 因为第一个是"自动"
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

  // 获取原始分辨率
  String? _getOriginalQuality() {
    if (_qualityOptions.isEmpty) return null;

    // 查找标记为原始的选项
    final originalOption = _qualityOptions.firstWhere(
      (q) => q['isOriginal'] == true,
      orElse: () => <String, dynamic>{},
    );

    if (originalOption.isNotEmpty) {
      return originalOption['label'] as String;
    }

    // 如果没有标记原始的，返回第一个（最高画质）
    return _qualityOptions.first['label'] as String;
  }

  // 质量优先模式：默认选择视频原始分辨率
  String? _selectQualityForQualityMode() {
    return _getOriginalQuality();
  }

  // 自动模式：根据网络环境自动切换到合适的分辨率
  // 速度好则最高使用原始分辨率，其他网络状态则根据原始分辨率依次往下
  String? _selectQualityForAutoMode() {
    if (_qualityOptions.isEmpty) return null;

    final speedMbps = (_currentSpeedKbps ?? 0) / 1000;

    // 没有网络速度数据，使用原始分辨率
    if (speedMbps <= 0) {
      return _getOriginalQuality();
    }

    // 根据网络速度选择合适的画质
    // 策略：选择比特率不超过网络速度 70% 的最高画质
    final targetBitrateMbps = speedMbps * 0.7;

    for (final option in _qualityOptions) {
      final maxBitrate = option['maxBitrate'] as int?;
      if (maxBitrate != null) {
        final bitrateMbps = maxBitrate / 1000000;
        if (bitrateMbps <= targetBitrateMbps) {
          return option['label'] as String;
        }
      }
    }

    // 网络太慢，选择最低画质
    return _qualityOptions.last['label'] as String;
  }

  // 速度优先模式：
  // 网络允许的情况下走自动
  // 网络状态不允许的情况下使用1080p的最低画质
  // 如果最高画质只有720p则使用最高画质
  String? _selectQualityForSpeedMode() {
    if (_qualityOptions.isEmpty) return null;

    final speedMbps = (_currentSpeedKbps ?? 0) / 1000;

    // 没有网络速度数据，使用保守策略
    if (speedMbps <= 0) {
      return _selectFallbackQualityForSpeedMode();
    }

    // 网络允许的情况下，走自动模式
    final autoQuality = _selectQualityForAutoMode();
    if (autoQuality != null) {
      // 检查自动选择的画质是否合理
      // 如果网络速度足够（>= 20Mbps），使用自动选择
      if (speedMbps >= 20) {
        return autoQuality;
      }
    }

    // 网络不够好，使用保守策略
    return _selectFallbackQualityForSpeedMode();
  }

  // 速度优先模式的保守策略
  String? _selectFallbackQualityForSpeedMode() {
    if (_qualityOptions.isEmpty) return null;

    // 查找最高分辨率
    int maxHeight = 0;
    for (final option in _qualityOptions) {
      final height = option['height'] as int? ?? 0;
      if (height > maxHeight) {
        maxHeight = height;
      }
    }

    // 如果最高画质只有720p或更低，使用最高画质
    if (maxHeight <= 720) {
      return _qualityOptions.first['label'] as String;
    }

    // 最高画质超过720p，查找1080p的最低比特率选项
    String? lowest1080p;
    int lowestBitrate = 999999999;

    for (final option in _qualityOptions) {
      final label = option['label'] as String;
      final height = option['height'] as int? ?? 0;
      final bitrate = option['maxBitrate'] as int? ?? 0;

      if (height == 1080 && bitrate > 0 && bitrate < lowestBitrate) {
        lowestBitrate = bitrate;
        lowest1080p = label;
      }
    }

    // 如果找到1080p选项，返回最低比特率的1080p
    if (lowest1080p != null) {
      return lowest1080p;
    }

    // 没有1080p，查找最接近1080p的选项（往下找）
    for (final option in _qualityOptions) {
      final height = option['height'] as int? ?? 0;
      if (height < 1080 && height >= 720) {
        return option['label'] as String;
      }
    }

    // 都没有，返回中等画质
    final middleIndex = _qualityOptions.length ~/ 2;
    return _qualityOptions[middleIndex]['label'] as String;
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
        _playerLogImportant(
            '🎬 [Player] Selected quality params: width=${selectedOption['width']}, '
            'height=${selectedOption['height']}, maxBitrate=${selectedOption['maxBitrate']}');
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
      }

      if (_selectedSubtitleStreamIndex != null &&
          _selectedSubtitleStreamIndex! >= 0) {
        if (_selectedSubtitleStreamIndex! < _subtitleStreams.length) {
          actualSubtitleIndex =
              _subtitleStreams[_selectedSubtitleStreamIndex!]['Index'] as int?;
        }
      } else if (_selectedSubtitleStreamIndex == -1) {
        actualSubtitleIndex = -1;
      }

      // ✅ 构建新的 HLS URL（带分辨率参数）
      final media = await _api!.buildHlsUrl(
        widget.itemId,
        audioStreamIndex: actualAudioIndex,
        subtitleStreamIndex: actualSubtitleIndex,
        maxWidth: qualityOption?['width'] as int?,
        maxHeight: qualityOption?['height'] as int?,
        maxBitrate: qualityOption?['bitrate'] as int?,
        startTimeTicks: currentPosition.inMicroseconds > 0
            ? (currentPosition.inMicroseconds * 10).toInt()
            : null,
      );

      _playerLog('🎬 [Player] New media URL with quality: ${media.uri}');

      // ✅ 检测是否为 HLS 流
      final isHlsStream =
          media.uri.contains('.m3u8') || media.uri.contains('hls');

      // ✅ 使用激进的缓冲策略
      final cacheConfig = {
        'minBufferMs': 15000,
        'maxBufferMs': 60000,
        'bufferForPlaybackMs': 1500,
        'bufferForPlaybackAfterRebufferMs': 3000,
      };

      // ✅ 重新打开媒体（使用快速启动逻辑）
      await _guardPlayerCommand(
        'reload media with quality',
        () => _player.open(
          url: media.uri,
          headers: media.headers,
          isHls: isHlsStream,
          autoPlay: wasPlaying, // ✅ 根据之前的播放状态决定是否自动播放
          startPosition: currentPosition > Duration.zero
              ? currentPosition
              : null, // ✅ 直接传入位置
          cacheConfig: cacheConfig, // ✅ 使用优化的缓冲配置
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

      _playerLogImportant('✅ [Player] Quality changed successfully');
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
    if (_isDraggingProgress || _suppressPositionUpdates) return;

    if (mounted) {
      setState(() {
        _position = pos;
      });
    }
    _syncProgress(pos);

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
      // ✅ 隐藏控制栏时，立即隐藏tooltip和速度列表
      // 注意：锁定时不自动解锁，保持锁定状态
      if (!willShow) {
        _showVideoFitHint = false;
        _showSpeedList = false;
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
    // ✅ 如果速度列表、音频菜单、字幕菜单正在显示或已锁定，不启动隐藏计时器
    if (_showSpeedList || _showAudioMenu || _showSubtitleMenu || _isLocked)
      return;

    _cancelHideControlsTimer();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _showControls &&
          _isPlaying &&
          !_showSpeedList &&
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
          // ✅ 立即隐藏tooltip和速度列表
          // 注意：锁定时不自动解锁，保持锁定状态
          _showVideoFitHint = false;
          _showSpeedList = false;
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
                    await _performSeek(d, resumeAfterSeek: shouldResume);
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
                  previousEpisode: _previousEpisode,
                  nextEpisode: _nextEpisode,
                  onPlayPreviousEpisode: _playPreviousEpisode,
                  onPlayNextEpisode: _playNextEpisode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 从 PlaybackInfo 的 MediaSource 生成分辨率选项（推荐使用）
  List<Map<String, dynamic>> _generateQualityOptionsFromMediaSource(
      Map<String, dynamic> mediaSource) {
    _playerLog('🎬 [Player] _generateQualityOptionsFromMediaSource called');

    // ✅ 打印 MediaSource 的关键字段
    _playerLog('🎬 [Player] MediaSource keys: ${mediaSource.keys.toList()}');
    _playerLog('🎬 [Player] MediaSource Width: ${mediaSource['Width']}');
    _playerLog('🎬 [Player] MediaSource Height: ${mediaSource['Height']}');
    _playerLog('🎬 [Player] MediaSource Bitrate: ${mediaSource['Bitrate']}');
    _playerLog(
        '🎬 [Player] MediaSource Container: ${mediaSource['Container']}');
    _playerLog(
        '🎬 [Player] MediaSource VideoCodec: ${mediaSource['VideoCodec']}');

    // ✅ 尝试多种方式获取视频分辨率
    int? originalWidth;
    int? originalHeight;
    int? originalBitrate = (mediaSource['Bitrate'] as num?)?.toInt();

    // ✅ 方式1: 直接从 MediaSource 获取（优先）
    originalWidth = (mediaSource['Width'] as num?)?.toInt();
    originalHeight = (mediaSource['Height'] as num?)?.toInt();

    _playerLog(
        '🎬 [Player] From MediaSource directly: ${originalWidth}x${originalHeight}');

    // ✅ 方式2: 从 MediaStreams 中获取视频流信息（备用）
    final mediaStreams = mediaSource['MediaStreams'];
    if (mediaStreams is List) {
      _playerLog('🎬 [Player] MediaStreams count: ${mediaStreams.length}');
      for (int i = 0; i < mediaStreams.length; i++) {
        final stream = mediaStreams[i];
        if (stream is Map) {
          _playerLog(
              '🎬 [Player] Stream $i - Type: ${stream['Type']}, Width: ${stream['Width']}, Height: ${stream['Height']}, BitRate: ${stream['BitRate']}');

          if (stream['Type'] == 'Video') {
            // 如果方式1没获取到，使用方式2
            if (originalWidth == null || originalHeight == null) {
              originalWidth = (stream['Width'] as num?)?.toInt();
              originalHeight = (stream['Height'] as num?)?.toInt();
            }
            // 如果视频流有比特率，使用视频流的比特率
            if (stream['BitRate'] != null) {
              originalBitrate = (stream['BitRate'] as num?)?.toInt();
            }
          }
        }
      }
    }

    _playerLog(
        '🎬 [Player] Final dimensions: ${originalWidth}x${originalHeight}, bitrate: $originalBitrate');

    if (originalHeight == null || originalHeight <= 0) {
      _playerLog('⚠️ [Player] No valid video height found in MediaSource');
      return const [];
    }

    _playerLog(
        '🎬 [Player] Original video: ${originalWidth}x${originalHeight}, bitrate: ${originalBitrate != null ? (originalBitrate / 1000000).round() : "unknown"}Mbps');

    return _buildQualityOptionsList(
        originalWidth, originalHeight, originalBitrate);
  }

  // ✅ 从 ItemInfo 生成分辨率选项（备用方法）
  List<Map<String, dynamic>> _generateQualityOptions(ItemInfo item) {
    _playerLog('🎬 [Player] _generateQualityOptions called');
    final media = _getPrimaryMediaSource(item);
    if (media == null) {
      _playerLog('❌ [Player] No media source found');
      return const [];
    }

    _playerLog('🎬 [Player] Media source: $media');

    // ✅ 获取原始视频的分辨率和比特率
    final originalWidth = (media['Width'] as num?)?.toInt();
    final originalHeight = (media['Height'] as num?)?.toInt();
    final originalBitrate = (media['Bitrate'] as num?)?.toInt();

    _playerLog(
        '🎬 [Player] Original dimensions: ${originalWidth}x${originalHeight}, bitrate: $originalBitrate');

    if (originalHeight == null || originalHeight <= 0) {
      _playerLog('⚠️ [Player] No valid video height found');
      return const [];
    }

    _playerLog(
        '🎬 [Player] Original video: ${originalWidth}x${originalHeight}, bitrate: ${originalBitrate != null ? (originalBitrate / 1000000).round() : "unknown"}Mbps');

    return _buildQualityOptionsList(
        originalWidth, originalHeight, originalBitrate);
  }

  // ✅ 构建分辨率选项列表（公共逻辑）
  List<Map<String, dynamic>> _buildQualityOptionsList(
      int? originalWidth, int? originalHeight, int? originalBitrate) {
    if (originalHeight == null || originalHeight <= 0) {
      return const [];
    }

    final options = <Map<String, dynamic>>[];

    // ✅ 判断视频级别（优先根据宽度判断，因为有超宽屏等特殊比例）
    String videoLevel;
    if (originalWidth != null && originalWidth >= 3840) {
      videoLevel = '4K'; // 宽度 >= 3840 就是 4K
    } else if (originalWidth != null && originalWidth >= 2560) {
      videoLevel = '2K'; // 宽度 >= 2560 就是 2K
    } else if (originalHeight >= 2160) {
      videoLevel = '4K'; // 高度 >= 2160 也是 4K
    } else if (originalHeight >= 1440) {
      videoLevel = '2K'; // 高度 >= 1440 也是 2K
    } else if (originalHeight >= 1080) {
      videoLevel = '1080p';
    } else if (originalHeight >= 720) {
      videoLevel = '720p';
    } else if (originalHeight >= 480) {
      videoLevel = '480p';
    } else {
      videoLevel = '360p';
    }

    _playerLog(
        '🎬 [Player] Video level detected: $videoLevel (${originalWidth}x${originalHeight})');

    // ✅ 定义分辨率和对应的多档位比特率（模仿 Emby 官方客户端）
    final resolutionOptions = {
      2160: {
        // 4K
        'label': '4K',
        'bitrates': [200, 160, 120, 100, 60, 40], // Mbps
      },
      1440: {
        // 2K
        'label': '2K',
        'bitrates': [100, 80, 60, 40, 30], // Mbps
      },
      1080: {
        // 1080p
        'label': '1080p',
        'bitrates': [60, 50, 40, 30, 25, 20], // Mbps
      },
      720: {
        // 720p
        'label': '720p',
        'bitrates': [40, 30, 20], // Mbps
      },
      480: {
        // 480p
        'label': '480p',
        'bitrates': [20, 15, 10], // Mbps
      },
      360: {
        // 360p
        'label': '360p',
        'bitrates': [10, 8, 6], // Mbps
      },
    };

    // ✅ 确定最大分辨率高度（根据视频级别）
    int maxResolutionHeight;
    if (videoLevel == '4K') {
      maxResolutionHeight = 2160;
    } else if (videoLevel == '2K') {
      maxResolutionHeight = 1440;
    } else if (videoLevel == '1080p') {
      maxResolutionHeight = 1080;
    } else if (videoLevel == '720p') {
      maxResolutionHeight = 720;
    } else if (videoLevel == '480p') {
      maxResolutionHeight = 480;
    } else {
      maxResolutionHeight = 360;
    }

    // ✅ 遍历所有分辨率选项
    for (final entry in resolutionOptions.entries) {
      final height = entry.key;
      final config = entry.value;
      final label = config['label'] as String;
      final bitrates = config['bitrates'] as List<int>;

      // ✅ 只添加不超过最大分辨率的选项
      if (height <= maxResolutionHeight) {
        // ✅ 计算对应的宽度（保持原始宽高比）
        final width = originalWidth != null && originalHeight > 0
            ? ((originalWidth / originalHeight) * height).round()
            : (height * 16 / 9).round(); // 默认使用 16:9 比例

        // ✅ 为每个分辨率添加多个比特率档位
        for (final bitrate in bitrates) {
          options.add({
            'label': '$label-${bitrate}Mbps',
            'width': width,
            'height': height,
            'bitrate': bitrate * 1000000, // 转换为 bps
            'maxBitrate': bitrate * 1000000,
          });
        }
      }
    }

    // ✅ 如果有原始比特率且不在列表中，添加原始分辨率选项
    if (originalBitrate != null) {
      // ✅ 使用之前检测的视频级别作为标签
      final originalLabel = videoLevel;

      final mbps = (originalBitrate / 1000000).round();
      final originalWidthCalculated =
          originalWidth ?? (originalHeight * 16 / 9).round();

      // ✅ 检查是否已经有相同的选项
      final hasSameOption = options.any((o) =>
          o['height'] == originalHeight &&
          ((o['bitrate'] as int) / 1000000).round() == mbps);

      if (!hasSameOption) {
        final originalOption = {
          'label': '$originalLabel-${mbps}Mbps (原始)',
          'width': originalWidthCalculated,
          'height': originalHeight,
          'bitrate': originalBitrate,
          'maxBitrate': originalBitrate,
          'isOriginal': true,
        };

        // ✅ 找到合适的位置插入（按比特率从高到低排序）
        int insertIndex = 0;
        for (int i = 0; i < options.length; i++) {
          final optionBitrate = options[i]['bitrate'] as int;
          if (originalBitrate >= optionBitrate) {
            insertIndex = i;
            break;
          }
          insertIndex = i + 1;
        }

        options.insert(insertIndex, originalOption);
        _playerLog(
            '🎬 [Player] Inserted original quality at index $insertIndex: $originalLabel-${mbps}Mbps');
      }
    }

    _playerLog(
        '🎬 [Player] Generated ${options.length} quality options for ${originalHeight}p');
    _playerLog(
        '🎬 [Player] First 5 options: ${options.take(5).map((o) => o['label']).join(', ')}');
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

  Future<void> _waitForPlayerReady() async {
    await _guardPlayerCommand(
      'wait until ready',
      () => _player.waitUntilReady(timeout: _playerReadyTimeout),
    );
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
        maxWidth: qualityOption?['width'] as int?,
        maxHeight: qualityOption?['height'] as int?,
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
    } catch (e, stack) {
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
}
