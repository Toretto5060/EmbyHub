import 'dart:async';

import 'package:flutter/services.dart';

/// Flutter 端的 ExoPlayer 音乐播放器控制器。
/// 通过 MethodChannel 与原生 Android 插件交互，支持：
/// - 音乐播放控制（播放、暂停、跳转、上一首、下一首）
/// - 系统媒体通知（锁屏/通知栏显示）
/// - MediaSession 集成（蓝牙耳机、车载系统控制）
/// - 播放列表管理
class ExoPlayerMusicController {
  static const MethodChannel _channel =
      MethodChannel('com.embyhub/exoplayer_music');
  static const EventChannel _eventChannel =
      EventChannel('com.embyhub/exoplayer_music/events');

  StreamController<Duration>? _positionController;
  StreamController<Duration>? _bufferController;
  StreamController<Duration>? _durationController;
  StreamController<bool>? _bufferingController;
  StreamController<bool>? _playingController;
  StreamController<bool>? _readyController;
  StreamController<String>? _errorController;
  StreamController<TrackChangedEvent>? _trackChangedController;
  StreamController<void>? _playlistEndedController;
  StreamController<MusicPlayerState>? _stateController;

  StreamSubscription<dynamic>? _eventSubscription;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isReady = false;
  int _currentIndex = 0;
  int _playlistLength = 0;
  String _repeatMode = 'off';
  bool _shuffleMode = false;
  int _activeStreamCount = 0;

  /// 单例模式
  static ExoPlayerMusicController? _instance;
  static ExoPlayerMusicController get instance {
    _instance ??= ExoPlayerMusicController._();
    return _instance!;
  }

  ExoPlayerMusicController._();

  /// 初始化播放器
  Future<void> initialize() async {
    _ensureNotDisposed();
    if (_isInitialized) return;

    try {
      final result = await _channel.invokeMethod<bool>('initialize');
      _isInitialized = result == true;
      _updateEventSubscription();
    } catch (e) {
      _handleError('初始化失败: $e');
      rethrow;
    }
  }

  /// 打开单个媒体
  Future<void> open({
    required String url,
    Map<String, String>? headers,
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    Duration? startPosition,
    bool autoPlay = true,
  }) async {
    _ensureNotDisposed();
    await _ensureInitialized();

    await _channel.invokeMethod('open', {
      'url': url,
      'headers': headers ?? const <String, String>{},
      'title': title ?? '',
      'artist': artist ?? '',
      'album': album ?? '',
      'coverUrl': coverUrl,
      'startPositionMs': startPosition?.inMilliseconds,
      'autoPlay': autoPlay,
    });
  }

  /// 设置播放列表
  Future<void> setPlaylist({
    required List<MusicItem> items,
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    _ensureNotDisposed();
    await _ensureInitialized();

    final itemsList = items
        .map((item) => {
              'url': item.url,
              'headers': item.headers ?? const <String, String>{},
              'title': item.title,
              'artist': item.artist,
              'album': item.album,
              'coverUrl': item.coverUrl,
            })
        .toList();

    await _channel.invokeMethod('setPlaylist', {
      'items': itemsList,
      'startIndex': startIndex,
      'autoPlay': autoPlay,
    });
  }

  /// 播放
  Future<void> play() async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('play');
  }

  /// 暂停
  Future<void> pause() async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('pause');
  }

  /// 停止
  Future<void> stop() async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('stop');
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('seekTo', {
      'positionMs': position.inMilliseconds,
    });
  }

  /// 下一首
  Future<void> next() async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('next');
  }

  /// 上一首
  Future<void> previous() async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('previous');
  }

  /// 跳转到指定索引
  Future<void> skipToIndex(int index) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('skipToIndex', {'index': index});
  }

  /// 设置播放速度
  Future<void> setRate(double rate) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('setRate', {'rate': rate});
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('setVolume', {'volume': volume});
  }

  /// 设置循环模式
  /// [mode]: 'off' | 'one' | 'all'
  Future<void> setRepeatMode(String mode) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('setRepeatMode', {'mode': mode});
  }

  /// 设置随机播放
  Future<void> setShuffleMode(bool enabled) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('setShuffleMode', {'enabled': enabled});
  }

  /// 更新媒体信息（用于更新通知栏显示）
  Future<void> updateMetadata({
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
  }) async {
    _ensureNotDisposed();
    await _ensureInitialized();
    await _channel.invokeMethod('updateMetadata', {
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
    });
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _cancelEventSubscription();
    await _channel.invokeMethod('dispose');
    _isInitialized = false;

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
    await _closeController(_trackChangedController);
    _trackChangedController = null;
    await _closeController(_playlistEndedController);
    _playlistEndedController = null;
    await _closeController(_stateController);
    _stateController = null;
    _activeStreamCount = 0;
  }

  // ==================== Getters ====================

  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isReady => _isReady;
  int get currentIndex => _currentIndex;
  int get playlistLength => _playlistLength;
  String get repeatMode => _repeatMode;
  bool get shuffleMode => _shuffleMode;

  // ==================== Streams ====================

  /// 播放进度流
  Stream<Duration> get positionStream => _getStream<Duration>(
        () => _positionController,
        (controller) => _positionController = controller,
      );

  /// 缓冲进度流
  Stream<Duration> get bufferStream => _getStream<Duration>(
        () => _bufferController,
        (controller) => _bufferController = controller,
      );

  /// 总时长流
  Stream<Duration> get durationStream => _getStream<Duration>(
        () => _durationController,
        (controller) => _durationController = controller,
      );

  /// 缓冲状态流
  Stream<bool> get bufferingStream => _getStream<bool>(
        () => _bufferingController,
        (controller) => _bufferingController = controller,
      );

  /// 播放状态流
  Stream<bool> get playingStream => _getStream<bool>(
        () => _playingController,
        (controller) => _playingController = controller,
      );

  /// Ready 状态流
  Stream<bool> get readyStream => _getStream<bool>(
        () => _readyController,
        (controller) => _readyController = controller,
      );

  /// 错误事件流
  Stream<String> get errorStream => _getStream<String>(
        () => _errorController,
        (controller) => _errorController = controller,
      );

  /// 曲目变化事件流
  Stream<TrackChangedEvent> get trackChangedStream =>
      _getStream<TrackChangedEvent>(
        () => _trackChangedController,
        (controller) => _trackChangedController = controller,
      );

  /// 播放列表结束事件流
  Stream<void> get playlistEndedStream => _getStream<void>(
        () => _playlistEndedController,
        (controller) => _playlistEndedController = controller,
      );

  /// 完整状态流
  Stream<MusicPlayerState> get stateStream => _getStream<MusicPlayerState>(
        () => _stateController,
        (controller) => _stateController = controller,
      );

  // ==================== Private Methods ====================

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      _handleError('Unexpected event: $event');
      return;
    }
    final map = Map<String, dynamic>.from(event);
    switch (map['event']) {
      case 'state':
        _handleStateEvent(map);
        break;
      case 'error':
        _handleError(map['message']?.toString() ?? 'Unknown playback error');
        break;
      case 'trackChanged':
        _handleTrackChanged(map);
        break;
      case 'playlistEnded':
        _addEvent(_playlistEndedController, null);
        break;
    }
  }

  void _handleStateEvent(Map<String, dynamic> map) {
    final positionMs = _asInt(map, 'position_ms');
    if (positionMs != null && positionMs >= 0) {
      _addEvent(_positionController, Duration(milliseconds: positionMs));
    }

    final bufferMs = _asInt(map, 'buffered_ms');
    if (bufferMs != null && bufferMs >= 0) {
      _addEvent(_bufferController, Duration(milliseconds: bufferMs));
    }

    final durationMs = _asInt(map, 'duration_ms');
    if (durationMs != null && durationMs >= 0) {
      _addEvent(_durationController, Duration(milliseconds: durationMs));
    }

    final buffering = map['isBuffering'] == true;
    if (_isBuffering != buffering) {
      _isBuffering = buffering;
      _addEvent(_bufferingController, buffering);
    }

    final playing = map['isPlaying'] == true;
    if (_isPlaying != playing) {
      _isPlaying = playing;
      _addEvent(_playingController, playing);
    }

    final ready = map['isReady'] == true;
    if (_isReady != ready) {
      _isReady = ready;
      _addEvent(_readyController, ready);
    }

    _currentIndex = _asInt(map, 'currentIndex') ?? 0;
    _playlistLength = _asInt(map, 'playlistLength') ?? 0;
    _repeatMode = map['repeatMode']?.toString() ?? 'off';
    _shuffleMode = map['shuffleMode'] == true;

    // 发送完整状态
    _addEvent(
      _stateController,
      MusicPlayerState(
        position: Duration(milliseconds: positionMs ?? 0),
        duration: Duration(milliseconds: durationMs ?? 0),
        bufferedPosition: Duration(milliseconds: bufferMs ?? 0),
        isPlaying: playing,
        isBuffering: buffering,
        isReady: ready,
        currentIndex: _currentIndex,
        playlistLength: _playlistLength,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
      ),
    );
  }

  void _handleTrackChanged(Map<String, dynamic> map) {
    final event = TrackChangedEvent(
      index: _asInt(map, 'index') ?? 0,
      title: map['title']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      album: map['album']?.toString() ?? '',
      coverUrl: map['coverUrl']?.toString(),
    );
    _addEvent(_trackChangedController, event);
  }

  void _handleError(String message) {
    _addEvent(_errorController, message);
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
  }

  void _cancelEventSubscription() {
    if (_eventSubscription == null) return;
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<void> _restartEventSubscription() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_shouldListenToEvents) {
      _ensureEventSubscription();
    }
  }

  void _addEvent<T>(StreamController<T>? controller, T data) {
    if (controller == null || controller.isClosed) return;
    controller.add(data);
  }

  Future<void> _closeController<T>(StreamController<T>? controller) async {
    if (controller == null || controller.isClosed) return;
    await controller.close();
  }

  int? _asInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
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

  bool get _shouldListenToEvents => !_isDisposed && _activeStreamCount > 0;

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('ExoPlayerMusicController has been disposed');
    }
  }
}

/// 音乐项数据类
class MusicItem {
  const MusicItem({
    required this.url,
    this.headers,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.coverUrl,
  });

  final String url;
  final Map<String, String>? headers;
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
}

/// 曲目变化事件
class TrackChangedEvent {
  const TrackChangedEvent({
    required this.index,
    required this.title,
    required this.artist,
    required this.album,
    this.coverUrl,
  });

  final int index;
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
}

/// 音乐播放器状态
class MusicPlayerState {
  const MusicPlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isReady = false,
    this.currentIndex = 0,
    this.playlistLength = 0,
    this.repeatMode = 'off',
    this.shuffleMode = false,
  });

  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final bool isPlaying;
  final bool isBuffering;
  final bool isReady;
  final int currentIndex;
  final int playlistLength;
  final String repeatMode;
  final bool shuffleMode;
}
