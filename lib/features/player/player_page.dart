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
import 'custom_subtitle_overlay.dart';
import 'player_controls.dart';

const bool _kPlayerLogging = true; // ✅ 临时启用日志，用于调试字幕问题
void _playerLog(String message) {
  if (_kPlayerLogging) {
    debugPrint(message);
  }
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

  // ✅ 音频和字幕选择
  int? _selectedAudioStreamIndex;
  int? _selectedSubtitleStreamIndex;
  bool _hasManuallySelectedSubtitle = false;
  bool _hasManuallySelectedAudio = false;
  List<Map<String, dynamic>> _audioStreams = [];
  List<Map<String, dynamic>> _subtitleStreams = [];

  // ✅ 自定义字幕URL
  String? _subtitleUrl;

  // ✅ MediaSourceId（用于构建字幕URL）
  String? _mediaSourceId;

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
        // 注意：已解码帧占用空间较大（1080p约3-5MB/帧）
        // 降低缓冲区大小，避免 ImageReader 缓冲区溢出导致黑屏
        bufferSize: 256 * 1024 * 1024, // 256MB 缓冲区（降低以减少缓冲区压力）
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        // ✅ 启用硬件加速，提升解码性能（特别是倍速播放时）
        enableHardwareAcceleration: true,
        // ✅ 改为 false，延迟 Surface 附加，避免 ImageReader 缓冲区溢出
        // 说明：true 可能导致在视频参数确定前就附加 Surface，引发缓冲区错误
        // false 会等待视频参数确定后再附加，更稳定
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // ✅ 创建播放器后立即禁用字幕显示
    _disableSubtitle();

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

    _loadStreamSelections();
    _load();
  }

  /// ✅ 禁用字幕显示（在创建播放器后立即调用）
  Future<void> _disableSubtitle() async {
    try {
      // 尝试使用 setSubtitleTrack 禁用字幕
      // 如果 SubtitleTrack.no() 不存在，extras 配置中的设置应该已经足够
      try {
        await _player.setSubtitleTrack(SubtitleTrack.no());
        _playerLog('🎬 [Player] Subtitle disabled via setSubtitleTrack');
      } catch (e) {
        // 如果 SubtitleTrack.no() 不存在，只记录日志，extras 配置应该已经禁用了字幕
        _playerLog('🎬 [Player] Subtitle should be disabled by extras config');
      }
    } catch (e) {
      _playerLog('❌ [Player] Failed to disable subtitle: $e');
    }
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

  /// ✅ 保存音频和字幕选择
  Future<void> _saveStreamSelections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedAudioStreamIndex != null) {
        await prefs.setInt(
            'item_${widget.itemId}_audio', _selectedAudioStreamIndex!);
      }
      if (_selectedSubtitleStreamIndex != null) {
        await prefs.setInt(
            'item_${widget.itemId}_subtitle', _selectedSubtitleStreamIndex!);
      }
      await prefs.setBool(
          'item_${widget.itemId}_manual_audio', _hasManuallySelectedAudio);
      await prefs.setBool('item_${widget.itemId}_manual_subtitle',
          _hasManuallySelectedSubtitle);
    } catch (e) {
      _playerLog('❌ [Player] Save stream selections failed: $e');
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
      _playerLog('🎬 [Player] Loading item: ${widget.itemId}');
      final api = await EmbyApi.create();
      _api = api;
      final authState = ref.read(authStateProvider);
      _userId = authState.value?.userId;

      // ✅ 获取视频详细信息（用于显示和PiP）
      final itemDetails =
          _userId != null ? await api.getItem(_userId!, widget.itemId) : null;
      _videoTitle = itemDetails?.name ?? 'Video';

      // ✅ 提取音频和字幕流
      if (itemDetails != null) {
        _audioStreams = _getAudioStreams(itemDetails);
        _subtitleStreams = _getSubtitleStreams(itemDetails);

        // ✅ 获取 PlaybackInfo 以获取正确的 MediaSourceId
        if (_userId != null) {
          try {
            final playbackInfo = await api.getPlaybackInfo(
              itemId: widget.itemId,
              userId: _userId!,
            );
            _playerLog('🎬 [Player] PlaybackInfo: $playbackInfo');

            // ✅ 从 PlaybackInfo 中获取 MediaSourceId
            if (playbackInfo['MediaSources'] != null &&
                playbackInfo['MediaSources'] is List &&
                (playbackInfo['MediaSources'] as List).isNotEmpty) {
              final mediaSource = (playbackInfo['MediaSources'] as List).first;
              if (mediaSource is Map) {
                _mediaSourceId = mediaSource['Id'] as String?;
                _playerLog(
                    '🎬 [Player] MediaSourceId from PlaybackInfo: $_mediaSourceId');
              }
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

            // 视频同步方式：使用 display-resample 更温和，避免音频处理
            'video-sync': 'display-resample',

            // 不使用插帧，减少卡顿
            'interpolation': 'no',

            // 减少解码压力（倍速时很重要）
            'vd-lavc-skiploopfilter': 'all',
            'vd-lavc-skipidct': 'approx',
            'vd-lavc-fast': 'yes',

            // 帧丢弃策略：优先保证流畅性，更积极的丢帧
            'framedrop': 'decoder+vo',

            //==========================
            //【ImageReader 缓冲区限制 - 解决黑屏问题】
            //==========================
            // 限制视频输出缓冲区数量，避免 ImageReader 缓冲区溢出
            'opengl-glfinish': 'yes', // 确保 OpenGL 命令及时执行
            'opengl-swapinterval': '0', // 不限制交换间隔，提高流畅度
            'video-latency-hacks': 'yes', // 启用视频延迟优化
            //==========================
            //【音频：使用系统音效设置】
            //==========================
            'audio-pitch-correction': 'yes', // 倍速时保持音调
            'volume-max': '200', // 允许音量最大到 200%
            // ✅ 使用系统默认音频输出，让系统音效设置生效
            // media_kit 默认使用系统音频输出（Android: AudioTrack, iOS: AVAudioEngine）
            // 系统音效（均衡器、低音增强等）会自动应用到音频流
            // 不设置 'ao' 参数，让 media_kit 使用默认音频输出
            // 不设置任何音频滤镜（'af'），保持原始音频流，让系统处理
            // MainActivity 中已配置 AudioAttributes，确保系统音效自动应用
            //==========================
            //【稳定性】
            //==========================
            'opengl-early-flush': 'no', // 防止倍速时丢帧
            'msg-level': 'all=no', // 关闭大量冗余日志

            //==========================
            //【字幕：完全禁用原生字幕显示】
            //==========================
            'sub-visibility': 'no', // 禁用原生字幕显示
            'sub-auto': 'no', // 禁用自动加载字幕
            'sub-forced-only': 'no', // 不显示强制字幕
            'sub-ass-override': 'no', // 禁用 ASS 字幕覆盖
            'sub-ass-style-override': 'no', // 禁用 ASS 样式覆盖
            'sid': 'no', // 禁用字幕轨道（不选择任何字幕轨道）
          },
        ),
        play: !needsSeek,
      );

      // ✅ 在 open 之后再次确保字幕被禁用
      await _disableSubtitle();

      // ✅ 在 open 之后设置 buffering 监听，确保能正确捕获缓冲状态
      _bufferingSub?.cancel();
      _bufferingSub = _player.stream.buffering.listen((isBuffering) {
        _playerLog('🎬 [Player] Buffering状态变化: $isBuffering');
        if (!mounted) return;
        setState(() => _isBuffering = isBuffering);
      });

      // ✅ 如果不需要seek，设置音量为150%（增强音量）
      // 如果需要seek，在seek流程中控制音量（先静音再恢复）
      // 注意：dynaudnorm 已经会增强音量，所以播放器音量设置为 150% 即可
      if (!needsSeek) {
        await _player.setVolume(150.0);
        _playerLog('🎬 [Player] Volume set to 150%');
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

      // ✅ 监听媒体轨道，并在轨道加载后确保禁用字幕
      _player.stream.tracks.listen((tracks) {
        _playerLog(
            '🎬 [Player] Tracks: ${tracks.video.length} video, ${tracks.audio.length} audio, ${tracks.subtitle.length} subtitle');
        // 确保字幕被禁用（轨道加载后可能自动启用字幕，需要再次禁用）
        if (tracks.subtitle.isNotEmpty) {
          _disableSubtitle();
          _playerLog('🎬 [Player] Subtitle tracks detected, disabled again');
        }
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
        await _player.setVolume(150.0);
        _playerLogImportant('🎬 [Player] 🔊 Volume restored to 150%');
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
              // ✅ 视频播放器（最底层，使用 IgnorePointer 让触摸事件穿透）
              Positioned.fill(
                child: _ready
                    ? Opacity(
                        opacity: _isInitialSeeking ? 0.0 : 1.0,
                        child: IgnorePointer(
                          child: Video(
                            controller: _controller,
                            fit: _videoFit,
                            controls: NoVideoControls, // ✅ 隐藏原生播放控件
                          ),
                        ),
                      )
                    : Container(color: Colors.black),
              ),

              // ✅ 自定义字幕显示组件（中间层，在视频上方，UI控制层下方）
              if (!_isInPipMode && _ready)
                CustomSubtitleOverlay(
                  position: _position,
                  subtitleUrl: _subtitleUrl,
                  isVisible: true, // 始终显示字幕（当有字幕时）
                  showControls: _showControls, // ✅ 传递控制栏显示状态
                ),

              // ✅ 触摸检测层（当控制层隐藏时，用于显示控制层）
              // 必须在 UI 控制层之前，让 UI 控制层能处理事件
              Positioned.fill(
                child: IgnorePointer(
                  // ✅ 当控制层显示时，忽略触摸检测层
                  // 当控制层隐藏时，触摸检测层可以接收事件来显示控制层
                  ignoring: _showControls,
                  child: GestureDetector(
                    onTap: () {
                      // ✅ 点击屏幕显示控制栏
                      if (!_showSpeedList) {
                        _toggleControls();
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
                  player: _player,
                  onToggleVideoFit: _toggleVideoFit,
                  onEnterPip: _enterPip,
                  onToggleOrientation: _toggleOrientation,
                  onPlayPause: () async {
                    final playing = _player.state.playing;
                    if (playing) {
                      await _player.pause();
                    } else {
                      await _player.play();
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
                    });
                    _cancelHideControlsTimer();
                  },
                  onDragging: (d) {
                    setState(() {
                      _draggingPosition = d;
                    });
                  },
                  onDragEnd: (d) async {
                    setState(() {
                      _position = d;
                      _draggingPosition = null;
                    });
                    await _player.seek(d);
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (mounted) {
                      setState(() {
                        _isDraggingProgress = false;
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            final elementMap = element as Map<dynamic, dynamic>;
            final streamMap = Map<String, dynamic>.from(elementMap
                .map((key, value) => MapEntry(key.toString(), value)));
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
    if (_subtitleStreams.isEmpty) return;

    final current = _selectedSubtitleStreamIndex;
    if (current != null && current >= 0 && current < _subtitleStreams.length) {
      return;
    }

    if (_hasManuallySelectedSubtitle) {
      final defaultIndex = _subtitleStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      final fallback = defaultIndex != -1 ? defaultIndex : 0;
      if (mounted) {
        setState(() {
          _selectedSubtitleStreamIndex = fallback;
        });
      }
      return;
    }

    int selectedIndex = _findBestChineseSubtitle(_subtitleStreams);

    if (selectedIndex == -1) {
      final defaultIndex = _subtitleStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      selectedIndex = defaultIndex != -1 ? defaultIndex : 0;
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

  // ✅ 格式化音频流
  String _formatAudioStream(Map<String, dynamic> stream) {
    final codec = stream['Codec']?.toString().toUpperCase();
    final channels = (stream['Channels'] as num?)?.toInt();
    final language = stream['Language']?.toString();

    final displayTitle = stream['DisplayTitle']?.toString();
    if (displayTitle != null && displayTitle.isNotEmpty) {
      return displayTitle;
    }

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

  // ✅ 格式化字幕流
  String _formatSubtitleStream(Map<String, dynamic> stream) {
    final displayTitle = stream['DisplayTitle']?.toString();
    if (displayTitle != null && displayTitle.isNotEmpty) {
      return displayTitle;
    }

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
    final double bottom = (overlaySize.height - buttonOffset.dy) + spacing;

    final scrollController = ScrollController();

    void scheduleScroll() {
      if (_selectedAudioStreamIndex == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        const itemHeight = 48.0;
        final target = _selectedAudioStreamIndex! * itemHeight;
        final maxExtent = scrollController.position.maxScrollExtent;
        final viewport = scrollController.position.viewportDimension;
        final offset =
            (target - viewport / 2 + itemHeight / 2).clamp(0.0, maxExtent);
        scrollController.jumpTo(offset);
      });
    }

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        scheduleScroll();
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                                final label = _formatAudioStream(data);
                                final isDefault =
                                    (data['IsDefault'] as bool?) == true;
                                final hasDefaultTag = label.contains('默认');
                                final isSelected =
                                    index == _selectedAudioStreamIndex;
                                final displayLabel = isDefault && !hasDefaultTag
                                    ? '$label (默认)'
                                    : label;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogCtx).pop(index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayLabel,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
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
    _resetHideControlsTimer();

    if (result != null && result >= 0 && result < _audioStreams.length) {
      setState(() {
        _selectedAudioStreamIndex = result;
        _hasManuallySelectedAudio = true;
      });
      _saveStreamSelections();
    }
  }

  // ✅ 显示字幕选择菜单
  Future<void> _showSubtitleSelectionMenu(BuildContext anchorContext) async {
    if (_subtitleStreams.isEmpty) return;

    _cancelHideControlsTimer();

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
    final double bottom = (overlaySize.height - buttonOffset.dy) + spacing;

    final scrollController = ScrollController();

    void scheduleScroll() {
      if (_selectedSubtitleStreamIndex == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        const itemHeight = 48.0;
        final target = _selectedSubtitleStreamIndex! * itemHeight;
        final maxExtent = scrollController.position.maxScrollExtent;
        final viewport = scrollController.position.viewportDimension;
        final offset =
            (target - viewport / 2 + itemHeight / 2).clamp(0.0, maxExtent);
        scrollController.jumpTo(offset);
      });
    }

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        scheduleScroll();
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                              _subtitleStreams.length,
                              (index) {
                                final label = _formatSubtitleStream(
                                    _subtitleStreams[index]);
                                final isDefault = (_subtitleStreams[index]
                                        ['IsDefault'] as bool?) ==
                                    true;
                                final hasDefaultTag = label.contains('默认');
                                final isSelected =
                                    index == _selectedSubtitleStreamIndex;

                                final displayLabel = isDefault && !hasDefaultTag
                                    ? '$label (默认)'
                                    : label;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogCtx).pop(index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayLabel,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
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
    _resetHideControlsTimer();

    if (result != null && result >= 0 && result < _subtitleStreams.length) {
      setState(() {
        _selectedSubtitleStreamIndex = result;
        _hasManuallySelectedSubtitle = true;
      });
      _saveStreamSelections();
      _updateSubtitleUrl();
    }
  }

  /// ✅ 更新字幕URL（尝试多种格式找到可用的）
  Future<void> _updateSubtitleUrl() async {
    if (_api == null || _selectedSubtitleStreamIndex == null) {
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
        // ✅ 获取所有可能的字幕 URL 格式
        final urls = await _api!.buildSubtitleUrls(
          itemId: widget.itemId,
          subtitleStreamIndex: subtitleIndex,
          mediaSourceId: _mediaSourceId,
          format: 'vtt',
        );

        print('🔥🔥🔥 [Player] Generated ${urls.length} subtitle URL variants');
        for (var i = 0; i < urls.length; i++) {
          print('🔥 [Player] URL $i: ${urls[i]}');
        }

        // ✅ 将所有 URL 传递给字幕组件，让它尝试每一个直到成功
        if (mounted && urls.isNotEmpty) {
          final combinedUrl = urls.join('|||');
          print(
              '🔥 [Player] Setting subtitle URL: ${combinedUrl.substring(0, combinedUrl.length > 100 ? 100 : combinedUrl.length)}...');
          setState(() {
            // 使用特殊格式传递多个 URL，用 '|||' 分隔
            _subtitleUrl = combinedUrl;
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
    }
  }
}
