import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';

/// Flutter 端的 ExoPlayer + Texture 控制器包装。
/// 通过 MethodChannel 与原生 Android 插件交互，暴露与 media_kit 接近的 API。
class ExoPlayerTextureController {
  static const MethodChannel _channel =
      MethodChannel('com.embyhub/exoplayer_texture');
  static const EventChannel _eventChannel =
      EventChannel('com.embyhub/exoplayer_texture/events');

  final _positionController = StreamController<Duration>.broadcast();
  final _bufferController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _readyController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _videoSizeController = StreamController<Size>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  Completer<void>? _readyCompleter;

  int? _textureId;
  bool _ready = false;
  bool _isBuffering = true;
  bool _isPlaying = false;
  bool _isDisposed = false;

  /// 初始化插件并获取 TextureId。
  Future<int> initialize() async {
    if (_textureId != null) {
      return _textureId!;
    }

    final textureId = await _channel.invokeMethod<int>('initialize') ??
        (throw Exception('Failed to initialize ExoPlayer texture'));
    _textureId = textureId;
    _eventSubscription ??= _eventChannel
        .receiveBroadcastStream()
        .listen(_handleEvent, onError: (Object error) {
      _handleError(error.toString());
    });
    return textureId;
  }

  /// 打开媒体。
  Future<void> open({
    required String url,
    Map<String, String>? headers,
    Duration? startPosition,
    bool autoPlay = true,
    Map<String, dynamic>? cacheConfig,
    bool isHls = false,
  }) async {
    _ready = false;
    _readyController.add(false);
    _readyCompleter = Completer<void>();

    await _channel.invokeMethod('open', {
      'url': url,
      'headers': headers ?? const <String, String>{},
      'startPositionMs': startPosition?.inMilliseconds,
      'autoPlay': autoPlay,
      'cacheConfig': cacheConfig,
      'isHls': isHls,
    });
  }

  /// 等待播放器进入 ready 状态。
  Future<void> waitUntilReady(
      {Duration timeout = const Duration(seconds: 15)}) {
    if (_ready) {
      return Future.value();
    }
    _readyCompleter ??= Completer<void>();
    return _readyCompleter!.future.timeout(timeout, onTimeout: () {});
  }

  Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  Future<void> seek(Duration position) async {
    await _channel.invokeMethod('seekTo', {
      'positionMs': position.inMilliseconds,
    });
  }

  Future<void> setRate(double rate) async {
    await _channel.invokeMethod('setRate', {'rate': rate});
  }

  /// [volumePercent] 取值 0-100。
  Future<void> setVolume(double volumePercent) async {
    final normalized = (volumePercent / 100).clamp(0.0, 1.0);
    await _channel.invokeMethod('setVolume', {'volume': normalized});
  }

  Future<void> disableSubtitles() async {
    await _channel.invokeMethod('disableSubtitles');
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await _eventSubscription?.cancel();
    await _channel.invokeMethod('dispose');
    _textureId = null;

    await _positionController.close();
    await _bufferController.close();
    await _durationController.close();
    await _bufferingController.close();
    await _playingController.close();
    await _readyController.close();
    await _errorController.close();
    await _videoSizeController.close();
  }

  int? get textureId => _textureId;
  bool get isReady => _ready;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get bufferStream => _bufferController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<bool> get bufferingStream => _bufferingController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<bool> get readyStream => _readyController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Size> get videoSizeStream => _videoSizeController.stream;

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);
    switch (map['event']) {
      case 'state':
        final positionMs = (map['position_ms'] as num?)?.toInt();
        if (positionMs != null && positionMs >= 0) {
          _positionController.add(Duration(milliseconds: positionMs));
        }

        final bufferMs = (map['buffered_ms'] as num?)?.toInt();
        if (bufferMs != null && bufferMs >= 0) {
          _bufferController.add(Duration(milliseconds: bufferMs));
        }

        final durationMs = (map['duration_ms'] as num?)?.toInt();
        if (durationMs != null && durationMs >= 0) {
          _durationController.add(Duration(milliseconds: durationMs));
        }

        final buffering = map['isBuffering'] == true;
        if (_isBuffering != buffering) {
          _isBuffering = buffering;
          _bufferingController.add(buffering);
        }

        final playing = map['isPlaying'] == true;
        if (_isPlaying != playing) {
          _isPlaying = playing;
          _playingController.add(playing);
        }

        final ready = map['isReady'] == true;
        if (_ready != ready) {
          _ready = ready;
          _readyController.add(ready);
        }
        if (ready && _readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
        }
        break;
      case 'error':
        _handleError(map['message']?.toString() ?? 'Unknown playback error');
        break;
      case 'videoSize':
        final width = (map['width'] as num?)?.toDouble();
        final height = (map['height'] as num?)?.toDouble();
        if (width != null && width > 0 && height != null && height > 0) {
          _videoSizeController.add(Size(width, height));
        }
        break;
    }
  }

  void _handleError(String message) {
    _errorController.add(message);
  }
}
