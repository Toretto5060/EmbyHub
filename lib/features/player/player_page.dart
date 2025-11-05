import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({required this.itemId, super.key});
  final String itemId;

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

  static const _pip = MethodChannel('app.pip');

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration());
    _controller = VideoController(_player);
    _load();
  }

  Future<void> _load() async {
    final api = await EmbyApi.create();
    final media = api.buildHlsUrl(widget.itemId);
    final prefs = await SharedPreferences.getInstance();
    _speed = prefs.getDouble('playback_speed') ?? 1.0;
    await _player.setRate(_speed);
    await _player.open(Media(media.uri, httpHeaders: media.headers));
    _posSub = _player.stream.position
        .listen((pos) => setState(() => _position = pos));
    _player.stream.duration.listen((d) => setState(() => _duration = d));
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player.dispose();
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

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          color: isDark ? Colors.white : Colors.black87,
          onPressed: () => context.pop(),
        ),
        middle: Text(
          '播放器',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        backgroundColor: CupertinoColors.systemBackground,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: _ready
            ? Column(
                children: [
                  Expanded(
                      child:
                          Video(controller: _controller, fit: BoxFit.contain)),
                  _Controls(
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
                ],
              )
            : const Center(child: CupertinoActivityIndicator()),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(position)),
              Text(_fmt(duration)),
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
                  onPressed: onTogglePlay,
                  child: Icon(CupertinoIcons.playpause)),
              const SizedBox(width: 8),
              CupertinoButton(
                onPressed: () async {
                  final sel = await showCupertinoModalPopup<double>(
                    context: context,
                    builder: (context) => _SpeedSheet(current: speed),
                  );
                  if (sel != null) onSpeed(sel);
                },
                child: Text('${speed.toStringAsFixed(2)}x'),
              ),
              const Spacer(),
              CupertinoButton(
                  onPressed: onPip,
                  child: Icon(CupertinoIcons.rectangle_on_rectangle)),
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
