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

const bool _kPlayerLogging = false;
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

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  bool _ready = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub; // ✅ 添加 duration 订阅
  bool _isLandscape = true; // ✅ 默认横屏
  EmbyApi? _api;
  String? _userId;
  DateTime _lastProgressSync = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastReportedPosition = Duration.zero;
  bool _completedReported = false;
  late final StateController<int> _refreshTicker;
  Duration? get _initialSeekPosition {
    final ticks = widget.initialPositionTicks;
    if (ticks == null || ticks <= 0) return null;
    return Duration(microseconds: (ticks / 10).round());
  }

  static const _pip = MethodChannel('app.pip');

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration());
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true, // 启用硬件加速
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // ✅ 进入播放页面时默认横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 隐藏状态栏和导航栏，实现全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _refreshTicker = ref.read(libraryRefreshTickerProvider.notifier);

    _load();
  }

  Future<void> _load() async {
    try {
      _playerLog('🎬 [Player] Loading item: ${widget.itemId}');
      final api = await EmbyApi.create();
      _api = api;
      final authState = ref.read(authStateProvider);
      _userId = authState.value?.userId;
      final media = await api.buildHlsUrl(widget.itemId); // ✅ 添加 await
      _playerLog('🎬 [Player] Media URL: ${media.uri}');

      final prefs = await SharedPreferences.getInstance();
      _speed = prefs.getDouble('playback_speed') ?? 1.0;
      await _player.setRate(_speed);

      // ✅ 打开媒体并自动播放
      await _player.open(Media(media.uri, httpHeaders: media.headers),
          play: true);
      _playerLog('🎬 [Player] Media opened and playing');
      final initialSeek = _initialSeekPosition;
      if (initialSeek != null && initialSeek > Duration.zero) {
        await _player.seek(initialSeek);
        _playerLog('🎬 [Player] Seek to ${initialSeek.inSeconds}s');
        _lastReportedPosition = initialSeek;
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
      _player.stream.playing.listen((isPlaying) {
        _playerLog('🎬 [Player] Playing: $isPlaying');
        if (!isPlaying) {
          _syncProgress(_position, force: true);
        }
      });

      // ✅ 监听错误
      _player.stream.error.listen((error) {
        _playerLog('❌ [Player] Error: $error');
      });

      // ✅ 监听缓冲状态
      _player.stream.buffering.listen((isBuffering) {
        _playerLog('🎬 [Player] Buffering: $isBuffering');
      });

      // ✅ 监听媒体轨道
      _player.stream.tracks.listen((tracks) {
        _playerLog(
            '🎬 [Player] Tracks: ${tracks.video.length} video, ${tracks.audio.length} audio');
      });

      setState(() => _ready = true);
      _playerLog('🎬 [Player] Ready to play');
    } catch (e, stack) {
      _playerLog('❌ [Player] Load failed: $e');
      _playerLog('Stack: $stack');
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel(); // ✅ 取消 duration 订阅
    _player.dispose();
    final markComplete =
        _duration > Duration.zero && _position >= _duration * 0.95;
    _syncProgress(_position, force: true, markComplete: markComplete);
    Future.microtask(() {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      _refreshTicker.state = _refreshTicker.state + 1;
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
      await _pip.invokeMethod('enter');
    } catch (_) {}
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

  // ✅ 格式化时间
  String _fmt(Duration d) {
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
        body: _ready
            ? Stack(
                children: [
                  // ✅ 全屏视频播放器（从状态栏到底部）
                  Positioned.fill(
                    child: Video(
                      controller: _controller,
                      fit: BoxFit.contain,
                      controls: NoVideoControls, // ✅ 隐藏原生播放控件
                    ),
                  ),
                  // ✅ 悬浮的返回按钮和标题（顶部）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top,
                        left: 8,
                        right: 8,
                        bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              // 返回按钮
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () => context.pop(),
                                child: const Icon(
                                  CupertinoIcons.back,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const Spacer(),
                              // 调试信息
                              Text(
                                'Duration: ${_fmt(_duration)} | Pos: ${_fmt(_position)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              // 横竖屏切换按钮
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _toggleOrientation,
                                child: Icon(
                                  _isLandscape
                                      ? CupertinoIcons.device_phone_portrait
                                      : CupertinoIcons.device_phone_landscape,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ✅ 悬浮的播放控件（底部）
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _Controls(
                      position: _position,
                      duration: _duration,
                      speed: _speed,
                      onSeek: (d) => _player.seek(d),
                      onTogglePlay: () async {
                        final playing = _player.state.playing;
                        if (playing) {
                          await _player.pause();
                        } else {
                          await _player.play();
                        }
                        setState(() {});
                      },
                      onSpeed: _changeSpeed,
                      onPip: _enterPip,
                    ),
                  ),
                ],
              )
            : const Center(
                child: CupertinoActivityIndicator(
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.position,
    required this.duration,
    required this.speed,
    required this.onSeek,
    required this.onTogglePlay,
    required this.onSpeed,
    required this.onPip,
  });
  final Duration position;
  final Duration duration;
  final double speed;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSpeed;
  final VoidCallback onPip;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = duration.inSeconds.clamp(1, 1 << 30);
    final value = position.inSeconds / totalSeconds;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt(position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                _fmt(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          CupertinoSlider(
            value: value.isNaN ? 0 : value,
            onChanged: (v) {
              final target = Duration(seconds: (v * totalSeconds).round());
              onSeek(target);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onTogglePlay,
                child: const Icon(
                  CupertinoIcons.playpause,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final sel = await showCupertinoModalPopup<double>(
                    context: context,
                    builder: (context) => _SpeedSheet(current: speed),
                  );
                  if (sel != null) onSpeed(sel);
                },
                child: Text(
                  '${speed.toStringAsFixed(2)}x',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onPip,
                child: const Icon(
                  CupertinoIcons.rectangle_on_rectangle,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ],
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
      title: const Text('倍速'),
      actions: [
        for (final s in speeds)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(s),
            isDefaultAction: s == current,
            child: Text('${s}x'),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    );
  }
}
