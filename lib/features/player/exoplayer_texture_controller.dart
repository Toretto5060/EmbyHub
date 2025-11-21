import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter 端的 ExoPlayer + Texture 控制器包装。
/// 通过 MethodChannel 与原生 Android 插件交互，暴露与 media_kit 接近的 API。
class ExoPlayerTextureController {
  static const MethodChannel _channel =
      MethodChannel('com.embyhub/exoplayer_texture');
  static const EventChannel _eventChannel =
      EventChannel('com.embyhub/exoplayer_texture/events');
  static const String _logTag = 'ExoPlayerTextureController';

  StreamController<Duration>? _positionController;
  StreamController<Duration>? _bufferController;
  StreamController<Duration>? _durationController;
  StreamController<bool>? _bufferingController;
  StreamController<bool>? _playingController;
  StreamController<bool>? _readyController;
  StreamController<String>? _errorController;
  StreamController<Size>? _videoSizeController;

  StreamSubscription<dynamic>? _eventSubscription;
  Completer<void>? _readyCompleter;
  Timer? _readyTimeoutTimer;

  int? _textureId;
  bool _ready = false;
  bool _isBuffering = true;
  bool _isPlaying = false;
  bool _isDisposed = false;
  int _activeStreamCount = 0;
  Duration? _lastEmittedPosition;

  static const Duration _positionEmitResolution = Duration(milliseconds: 200);

  /// 初始化插件并获取 TextureId。
  Future<int> initialize() async {
    _ensureNotDisposed();
    if (_textureId != null) {
      return _textureId!;
    }

    final textureId = await _channel.invokeMethod<int>('initialize') ??
        (throw Exception('Failed to initialize ExoPlayer texture'));
    _textureId = textureId;
    _updateEventSubscription();
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
    bool waitForReady = false,
  }) async {
    _ensureNotDisposed();
    await _ensureTextureInitialized();
    _ready = false;
    _lastEmittedPosition = null;
    _addEvent(_readyController, false);
    _failReadyWait(StateError('Player reopened before readiness resolved'));

    final sanitizedCacheConfig = _sanitizeCacheConfig(cacheConfig);
    final args = {
      'url': url,
      'headers': headers ?? const <String, String>{},
      'startPositionMs': startPosition?.inMilliseconds,
      'autoPlay': autoPlay,
      'isHls': isHls,
    };
    if (sanitizedCacheConfig != null) {
      args['cacheConfig'] = sanitizedCacheConfig;
    }

    await _invoke('open', args);
    if (waitForReady) {
      await waitUntilReady();
    }
  }

  /// 等待播放器进入 ready 状态。超时将抛出 [TimeoutException] 并同步推送到 [errorStream]。
  Future<void> waitUntilReady(
      {Duration timeout = const Duration(seconds: 15)}) {
    _ensureNotDisposed();
    _assertInitialized('waitUntilReady');
    if (_ready) {
      return Future.value();
    }
    final isNewWait = _readyCompleter == null;
    _readyCompleter ??= Completer<void>();
    final completer = _readyCompleter!;
    if (isNewWait) {
      _updateEventSubscription();
      _scheduleReadyTimeout(timeout, completer);
    }
    return completer.future;
  }

  Future<void> play() => _invoke('play');

  Future<void> pause() => _invoke('pause');

  Future<void> seek(Duration position) =>
      _invoke('seekTo', {'positionMs': position.inMilliseconds});

  Future<void> setRate(double rate) => _invoke('setRate', {'rate': rate});

  /// [volumePercent] 取值 0-100。
  Future<void> setVolume(double volumePercent) async {
    final normalized = (volumePercent / 100).clamp(0.0, 1.0);
    await _invoke('setVolume', {'volume': normalized});
  }

  Future<void> disableSubtitles() => _invoke('disableSubtitles');

  /// 释放资源。调用后请勿再监听任何流或调用其他控制方法。
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _failReadyWait(StateError('Controller disposed before readiness resolved'));
    _cancelEventSubscription();
    await _channel.invokeMethod('dispose');
    _textureId = null;

    await _closeController(_positionController);
    _positionController = null;
    await _closeController(_bufferController);
    _bufferController = null;
    await _closeController(_durationController);
    _durationController = null;
    await _closeController(_bufferingController);
    _bufferingController = null;
    await _closeController(_playingController);
    _playingController = null;
    await _closeController(_readyController);
    _readyController = null;
    await _closeController(_errorController);
    _errorController = null;
    await _closeController(_videoSizeController);
    _videoSizeController = null;
    _activeStreamCount = 0;
  }

  int? get textureId => _textureId;
  bool get isReady => _ready;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;

  /// 播放进度流（约 200 ms 节流；dispose 后不要再监听）。
  Stream<Duration> get positionStream => _getStream<Duration>(
        () => _positionController,
        (controller) => _positionController = controller,
      );

  /// 缓冲进度流（dispose 后不要再监听）。
  Stream<Duration> get bufferStream => _getStream<Duration>(
        () => _bufferController,
        (controller) => _bufferController = controller,
      );

  /// 总时长流（dispose 后不要再监听）。
  Stream<Duration> get durationStream => _getStream<Duration>(
        () => _durationController,
        (controller) => _durationController = controller,
      );

  /// 缓冲状态流（dispose 后不要再监听）。
  Stream<bool> get bufferingStream => _getStream<bool>(
        () => _bufferingController,
        (controller) => _bufferingController = controller,
      );

  /// 播放状态流（dispose 后不要再监听）。
  Stream<bool> get playingStream => _getStream<bool>(
        () => _playingController,
        (controller) => _playingController = controller,
      );

  /// Ready 状态流（dispose 后不要再监听）。
  Stream<bool> get readyStream => _getStream<bool>(
        () => _readyController,
        (controller) => _readyController = controller,
      );

  /// 错误事件流（dispose 后不要再监听）。
  Stream<String> get errorStream => _getStream<String>(
        () => _errorController,
        (controller) => _errorController = controller,
      );

  /// 视频尺寸流（dispose 后不要再监听）。
  Stream<Size> get videoSizeStream => _getStream<Size>(
        () => _videoSizeController,
        (controller) => _videoSizeController = controller,
      );

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      _handleError('Unexpected event: $event');
      return;
    }
    final map = Map<String, dynamic>.from(event);
    switch (map['event']) {
      case 'state':
        final positionMs = _asInt(map, 'position_ms');
        if (positionMs != null && positionMs >= 0) {
          _emitPosition(Duration(milliseconds: positionMs));
        }

        final bufferMs = _asInt(map, 'buffered_ms');
        if (bufferMs != null && bufferMs >= 0) {
          _addEvent(
            _bufferController,
            Duration(milliseconds: bufferMs),
          );
        }

        final durationMs = _asInt(map, 'duration_ms');
        if (durationMs != null && durationMs >= 0) {
          _addEvent(
            _durationController,
            Duration(milliseconds: durationMs),
          );
        }

        final buffering = map['isBuffering'] == true;
        _updateState<bool>(
          newValue: buffering,
          currentValue: _isBuffering,
          setter: (value) => _isBuffering = value,
          controller: _bufferingController,
        );

        final playing = map['isPlaying'] == true;
        _updateState<bool>(
          newValue: playing,
          currentValue: _isPlaying,
          setter: (value) => _isPlaying = value,
          controller: _playingController,
        );

        final ready = map['isReady'] == true;
        _updateState<bool>(
          newValue: ready,
          currentValue: _ready,
          setter: (value) => _ready = value,
          controller: _readyController,
        );
        // ready 变 true 时通知 waitUntilReady 调用者。
        if (ready && _readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
          _finishReadyWait();
        }
        _debugLog(
            'State => buffering=$buffering, playing=$playing, ready=$ready');
        break;
      case 'error':
        _handleError(map['message']?.toString() ?? 'Unknown playback error');
        break;
      case 'videoSize':
        final width = _asDouble(map, 'width');
        final height = _asDouble(map, 'height');
        if (width != null && width > 0 && height != null && height > 0) {
          _addEvent(
            _videoSizeController,
            Size(width, height),
          );
        }
        break;
    }
  }

  void _handleError(String message) {
    _addEvent(_errorController, message);
    _debugLog('Error => $message');
  }

  void _ensureEventSubscription() {
    if (_eventSubscription != null || !_shouldListenToEvents) {
      return;
    }
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) {
        _handleError(error.toString());
        _restartEventSubscription();
      },
    );
    _debugLog('Event subscription established');
  }

  void _cancelEventSubscription() {
    if (_eventSubscription == null) return;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _debugLog('Event subscription cancelled');
  }

  Future<void> _restartEventSubscription() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_shouldListenToEvents) {
      _debugLog('Restarting event subscription');
      _ensureEventSubscription();
    }
  }

  Map<String, dynamic>? _sanitizeCacheConfig(
      Map<String, dynamic>? cacheConfig) {
    if (cacheConfig == null || cacheConfig.isEmpty) {
      return null;
    }
    final sanitized = <String, dynamic>{};
    cacheConfig.forEach((key, value) {
      if (key.isEmpty) return;
      if (value is num || value is String || value is bool) {
        sanitized[key] = value;
      } else if (value is Map<String, dynamic>) {
        final nested = _sanitizeCacheConfig(value);
        if (nested != null) {
          sanitized[key] = nested;
        }
      }
    });
    return sanitized.isEmpty ? null : sanitized;
  }

  void _addEvent<T>(StreamController<T>? controller, T data) {
    if (controller == null || controller.isClosed) return;
    controller.add(data);
  }

  Future<void> _closeController<T>(StreamController<T>? controller) async {
    if (controller == null || controller.isClosed) return;
    await controller.close();
  }

  bool _updateState<T>({
    required T newValue,
    required T currentValue,
    required void Function(T value) setter,
    StreamController<T>? controller,
  }) {
    if (currentValue == newValue) {
      return false;
    }
    setter(newValue);
    _addEvent(controller, newValue);
    return true;
  }

  int? _asInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  double? _asDouble(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return null;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[$_logTag] $message');
    }
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    _ensureNotDisposed();
    _assertInitialized(method);
    try {
      await _channel.invokeMethod(method, arguments);
    } catch (error, stackTrace) {
      _handleError('Method $method failed: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Stream<T> _getStream<T>(
    StreamController<T>? Function() getter,
    void Function(StreamController<T> controller) setter,
  ) {
    if (_isDisposed) {
      return Stream<T>.empty();
    }
    return _ensureController<T>(getter(), setter).stream;
  }

  StreamController<T> _ensureController<T>(
    StreamController<T>? controller,
    void Function(StreamController<T> controller) setter,
  ) {
    if (controller != null) {
      return controller;
    }
    final newController = StreamController<T>.broadcast(
      onListen: _onStreamListen,
      onCancel: _onStreamCancel,
    );
    setter(newController);
    return newController;
  }

  void _emitPosition(Duration position) {
    if (_lastEmittedPosition == null ||
        (position - _lastEmittedPosition!).abs() >= _positionEmitResolution) {
      _lastEmittedPosition = position;
      _addEvent(_positionController, position);
    }
  }

  void _onStreamListen() {
    _activeStreamCount++;
    _updateEventSubscription();
  }

  void _onStreamCancel() {
    if (_activeStreamCount > 0) {
      _activeStreamCount--;
      _updateEventSubscription();
    }
  }

  void _updateEventSubscription() {
    if (_shouldListenToEvents) {
      _ensureEventSubscription();
    } else if (_eventSubscription != null) {
      _cancelEventSubscription();
    }
  }

  bool get _shouldListenToEvents =>
      !_isDisposed && (_activeStreamCount > 0 || _readyCompleter != null);

  void _scheduleReadyTimeout(Duration timeout, Completer<void> completer) {
    _readyTimeoutTimer?.cancel();
    _readyTimeoutTimer = Timer(timeout, () {
      if (identical(_readyCompleter, completer) && !completer.isCompleted) {
        final exception = TimeoutException(
            'ExoPlayerTextureController waitUntilReady timed out', timeout);
        completer.completeError(exception);
        _handleError(
            'waitUntilReady timed out after ${timeout.inMilliseconds} ms');
        _finishReadyWait();
      }
    });
  }

  void _finishReadyWait() {
    if (_readyCompleter == null) return;
    _readyTimeoutTimer?.cancel();
    _readyTimeoutTimer = null;
    _readyCompleter = null;
    _updateEventSubscription();
  }

  void _failReadyWait(Object error) {
    if (_readyCompleter == null) return;
    if (!_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(error);
    }
    _finishReadyWait();
  }

  Future<void> _ensureTextureInitialized() async {
    if (_textureId != null) {
      return;
    }
    await initialize();
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('ExoPlayerTextureController has been disposed');
    }
  }

  void _assertInitialized(String context) {
    if (_textureId == null) {
      throw StateError('$context called before initialize/open completed');
    }
  }
}
