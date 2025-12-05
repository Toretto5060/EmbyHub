import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/music/exoplayer_music_controller.dart';

/// 持久化存储的键
const String _lastPlayingSongKey = 'last_playing_song';
const String _lastPlayingPositionKey = 'last_playing_position';
const String _lastPlaylistKey = 'last_playlist';
const String _lastPlaylistIndexKey = 'last_playlist_index';
const String _playModeKey = 'play_mode';

/// 播放模式枚举
enum PlayMode {
  /// 列表循环：播放完最后一首后从第一首开始
  listLoop,

  /// 单曲循环：一直播放当前曲目
  singleLoop,

  /// 随机播放：在当前播放列表中随机播放
  shuffle,
}

/// 本地音乐播放状态
class LocalMusicPlayerState {
  const LocalMusicPlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.isBuffering = false,
    this.playlist = const [],
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playMode = PlayMode.listLoop, // 默认列表循环
    this.isNextDirection = true, // 切换方向：true=下一首，false=上一首
  });

  final LocalSong? currentSong;
  final bool isPlaying;
  final bool isBuffering;
  final List<LocalSong> playlist;
  final int currentIndex;
  final Duration position;
  final Duration duration;
  final PlayMode playMode;
  final bool isNextDirection; // 切换方向：true=下一首（从右滑入），false=上一首（从左滑入）

  LocalMusicPlayerState copyWith({
    LocalSong? currentSong,
    bool? isPlaying,
    bool? isBuffering,
    List<LocalSong>? playlist,
    int? currentIndex,
    Duration? position,
    Duration? duration,
    PlayMode? playMode,
    bool? isNextDirection,
  }) {
    return LocalMusicPlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playMode: playMode ?? this.playMode,
      isNextDirection: isNextDirection ?? this.isNextDirection,
    );
  }
}

/// 本地歌曲模型
class LocalSong {
  const LocalSong({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.albumArt,
    this.lyrics,
    this.bitrate,
    this.bitDepth,
    this.sampleRate,
    this.duration,
    this.path,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? albumArt;
  final String? lyrics; // 歌词
  final int? bitrate; // 比特率 (kbps)
  final int? bitDepth; // 位深 (bits)
  final int? sampleRate; // 采样率 (Hz)
  final Duration? duration;
  final String? path;

  /// 从 JSON 创建 LocalSong
  factory LocalSong.fromJson(Map<String, dynamic> json) {
    return LocalSong(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      albumArt: json['albumArt'] as String?,
      lyrics: json['lyrics'] as String?,
      bitrate: json['bitrate'] as int?,
      bitDepth: json['bitDepth'] as int?,
      sampleRate: json['sampleRate'] as int?,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      path: json['path'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArt': albumArt,
      'lyrics': lyrics,
      'bitrate': bitrate,
      'bitDepth': bitDepth,
      'sampleRate': sampleRate,
      'duration': duration?.inMilliseconds,
      'path': path,
    };
  }

  /// 复制并修改
  LocalSong copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumArt,
    String? lyrics,
    int? bitrate,
    int? bitDepth,
    int? sampleRate,
    Duration? duration,
    String? path,
  }) {
    return LocalSong(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArt: albumArt ?? this.albumArt,
      lyrics: lyrics ?? this.lyrics,
      bitrate: bitrate ?? this.bitrate,
      bitDepth: bitDepth ?? this.bitDepth,
      sampleRate: sampleRate ?? this.sampleRate,
      duration: duration ?? this.duration,
      path: path ?? this.path,
    );
  }
}

/// 本地音乐播放器状态管理
/// 集成 ExoPlayerMusicController 实现真正的音乐播放和系统媒体通知
class LocalMusicPlayerNotifier extends StateNotifier<LocalMusicPlayerState> {
  LocalMusicPlayerNotifier() : super(const LocalMusicPlayerState()) {
    _initializePlayer();
  }

  /// ExoPlayer 音乐控制器（仅 Android）
  ExoPlayerMusicController? _player;

  /// 事件订阅
  StreamSubscription<MusicPlayerState>? _stateSubscription;
  StreamSubscription<TrackChangedEvent>? _trackChangedSubscription;
  StreamSubscription<void>? _playlistEndedSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<void>? _mediaButtonNextSubscription;
  StreamSubscription<void>? _mediaButtonPreviousSubscription;
  StreamSubscription<void>? _mediaButtonPlaySubscription;
  StreamSubscription<void>? _mediaButtonPauseSubscription;

  /// 是否正在切换歌曲（用于在 trackChanged 事件中判断是手动还是自动切换）
  bool _isSwitchingTrack = false;

  /// 随机播放历史记录（存储播放过的歌曲索引）
  final List<int> _shuffleHistory = [];

  /// 随机播放历史记录的当前位置（用于上一曲/下一曲导航）
  int _shuffleHistoryIndex = -1;

  /// 已播放过的歌曲索引集合（用于优先播放未播放的歌曲）
  final Set<int> _playedIndices = {};

  /// 初始化播放器
  Future<void> _initializePlayer() async {
    // 仅在 Android 平台使用 ExoPlayer
    if (Platform.isAndroid) {
      _player = ExoPlayerMusicController.instance;
      await _player!.initialize();
      _setupPlayerListeners();
    }

    // 加载上次播放状态
    await _loadLastPlayingState();
  }

  /// 设置播放器事件监听
  void _setupPlayerListeners() {
    final player = _player;
    if (player == null) return;

    // 监听播放状态变化
    // 注意：isPlaying 状态由用户操作控制，不从原生播放器同步
    // 只同步 position、duration、isBuffering
    _stateSubscription = player.stateStream.listen((playerState) {
      final oldPositionSec = state.position.inSeconds;
      final newPositionSec = playerState.position.inSeconds;

      state = state.copyWith(
        position: playerState.position,
        duration: playerState.duration,
        isBuffering: playerState.isBuffering,
      );

      // 每秒保存一次位置（当秒数变化时保存）
      if (newPositionSec != oldPositionSec && state.isPlaying) {
        _savePlayingState();
      }
    });

    // 监听曲目切换（自动播放下一首时触发）
    _trackChangedSubscription = player.trackChangedStream.listen((event) {
      if (event.index >= 0 && event.index < state.playlist.length) {
        // 如果不是手动切换（_isSwitchingTrack=false），则是自动播放下一首
        // 自动播放下一首按"下一首"方向处理
        final isNext = _isSwitchingTrack ? state.isNextDirection : true;

        state = state.copyWith(
          currentIndex: event.index,
          currentSong: state.playlist[event.index],
          position: Duration.zero,
          isNextDirection: isNext,
        );
        _savePlayingState();
      }
    });

    // 监听播放列表结束
    _playlistEndedSubscription = player.playlistEndedStream.listen((_) {
      // 播放列表播放完毕
      state = state.copyWith(isPlaying: false);
      _savePlayingState();
    });

    // 监听错误 - 播放失败时将状态改为暂停
    _errorSubscription = player.errorStream.listen((error) {
      print('Music player error: $error');
      // 播放失败，将状态改为暂停
      state = state.copyWith(isPlaying: false);
    });

    // 监听媒体按钮下一曲（支持随机播放模式）
    _mediaButtonNextSubscription = player.mediaButtonNextStream.listen((_) {
      playNext();
    });

    // 监听媒体按钮上一曲（支持随机播放模式）
    _mediaButtonPreviousSubscription =
        player.mediaButtonPreviousStream.listen((_) {
      playPrevious();
    });

    // 监听媒体按钮播放（由媒体通知触发）
    _mediaButtonPlaySubscription = player.mediaButtonPlayStream.listen((_) {
      // 更新 UI 状态为播放中
      state = state.copyWith(isPlaying: true);
    });

    // 监听媒体按钮暂停（由媒体通知触发）
    _mediaButtonPauseSubscription = player.mediaButtonPauseStream.listen((_) {
      // 更新 UI 状态为暂停
      state = state.copyWith(isPlaying: false);
    });
  }

  /// 加载上次播放状态
  Future<void> _loadLastPlayingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载播放模式
      final playModeIndex = prefs.getInt(_playModeKey) ?? 0;
      final playMode =
          PlayMode.values[playModeIndex.clamp(0, PlayMode.values.length - 1)];
      state = state.copyWith(playMode: playMode);

      // 加载上次播放的歌曲
      final songJson = prefs.getString(_lastPlayingSongKey);
      if (songJson == null) return;

      final songData = jsonDecode(songJson) as Map<String, dynamic>;
      final song = LocalSong.fromJson(songData);

      // 加载上次播放位置
      final positionMs = prefs.getInt(_lastPlayingPositionKey) ?? 0;
      final position = Duration(milliseconds: positionMs);

      // 加载播放列表
      final playlistJson = prefs.getString(_lastPlaylistKey);
      List<LocalSong> playlist = [];
      if (playlistJson != null) {
        final playlistData = jsonDecode(playlistJson) as List;
        playlist = playlistData
            .map((e) => LocalSong.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 加载播放列表索引
      final playlistIndex = prefs.getInt(_lastPlaylistIndexKey) ?? 0;

      // 确保播放列表不为空
      final finalPlaylist = playlist.isNotEmpty ? playlist : [song];
      final finalIndex = playlistIndex.clamp(0, finalPlaylist.length - 1);

      // 更新状态（不自动播放，只恢复状态）
      state = state.copyWith(
        currentSong: song,
        position: position,
        playlist: finalPlaylist,
        currentIndex: finalIndex,
        isPlaying: false, // 不自动播放
      );

      // ✅ 将播放列表预加载到原生播放器（不自动播放）
      await _preloadPlaylistToPlayer(finalPlaylist, finalIndex, position);
    } catch (e) {
      // 加载失败时忽略错误
      print('Failed to load last playing state: $e');
    }
  }

  /// 预加载播放列表到原生播放器（不自动播放）
  Future<void> _preloadPlaylistToPlayer(
    List<LocalSong> playlist,
    int startIndex,
    Duration startPosition,
  ) async {
    if (_player == null || playlist.isEmpty) return;

    final items = playlist
        .where((s) => s.path != null)
        .map((s) => MusicItem(
              url: s.path!,
              title: s.title,
              artist: s.artist,
              album: s.album ?? '',
              coverUrl: s.albumArt,
            ))
        .toList();

    if (items.isNotEmpty) {
      await _player!.setPlaylist(
        items: items,
        startIndex: startIndex,
        autoPlay: false, // 不自动播放
      );
      // 恢复播放位置
      if (startPosition.inMilliseconds > 0) {
        await _player!.seek(startPosition);
      }

      // 将当前歌曲添加到随机播放历史记录（用于上一首功能）
      _addToShuffleHistory(startIndex);
    }
  }

  /// 保存当前播放状态
  Future<void> _savePlayingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (state.currentSong != null) {
        // 保存当前歌曲
        final songJson = jsonEncode(state.currentSong!.toJson());
        await prefs.setString(_lastPlayingSongKey, songJson);

        // 保存播放位置
        await prefs.setInt(
            _lastPlayingPositionKey, state.position.inMilliseconds);

        // 保存播放列表（保存全部）
        if (state.playlist.isNotEmpty) {
          final playlistJson = jsonEncode(
            state.playlist.map((s) => s.toJson()).toList(),
          );
          await prefs.setString(_lastPlaylistKey, playlistJson);
          await prefs.setInt(_lastPlaylistIndexKey, state.currentIndex);
        }
      }
    } catch (e) {
      // 保存失败时忽略错误
      print('Failed to save playing state: $e');
    }
  }

  /// 播放单首歌曲（将该歌曲作为播放列表的唯一曲目）
  /// 注意：通常应该使用 setPlaylist 来设置播放列表
  Future<void> playSong(LocalSong song) async {
    // 将单首歌曲作为播放列表
    await setPlaylist([song], startIndex: 0);
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    // 立即更新 UI 状态，让响应更快
    final wasPlaying = state.isPlaying;
    state = state.copyWith(isPlaying: !wasPlaying);

    // 异步调用原生播放器
    if (_player != null) {
      if (wasPlaying) {
        _player!.pause(); // 不使用 await
      } else {
        // 使用与 play() 相同的逻辑：检查播放器是否真正准备好
        if (state.currentSong != null) {
          final isReady = await _player!.checkPlayerReady();
          if (!isReady) {
            // 播放器未准备好（可能是通知被清除后停止了），需要重新加载媒体源并自动播放
            await _openCurrentSongAndPlay();
          } else {
            _player!.play(); // 不使用 await
          }
        }
      }
    }
  }

  /// 暂停
  Future<void> pause() async {
    // 立即更新 UI 状态
    state = state.copyWith(isPlaying: false);

    // 异步调用原生播放器（不等待）
    _player?.pause();
    _savePlayingState();
  }

  /// 播放
  Future<void> play() async {
    // 立即更新 UI 状态
    state = state.copyWith(isPlaying: true);

    // 异步调用原生播放器
    if (_player != null && state.currentSong != null) {
      // 每次播放前都检查播放器是否真正准备好（同步查询原生端状态）
      // 这样可以正确处理通知被清除后播放器被停止的情况
      final isReady = await _player!.checkPlayerReady();
      if (!isReady) {
        // 播放器未准备好（可能是通知被清除后停止了），需要重新加载媒体源并自动播放
        await _openCurrentSongAndPlay();
      } else {
        _player!.play(); // 不使用 await
      }
    }
  }

  /// 打开当前歌曲并自动播放（用于播放器被停止后重新开始播放）
  Future<void> _openCurrentSongAndPlay() async {
    final song = state.currentSong;
    if (_player == null || song == null) return;

    // 如果有播放列表，加载整个播放列表并自动播放
    if (state.playlist.isNotEmpty) {
      final items = state.playlist
          .where((s) => s.path != null)
          .map((s) => MusicItem(
                url: s.path!,
                title: s.title,
                artist: s.artist,
                album: s.album ?? '',
                coverUrl: s.albumArt,
              ))
          .toList();

      if (items.isNotEmpty) {
        await _player!.setPlaylist(
          items: items,
          startIndex: state.currentIndex,
          autoPlay: true, // 自动播放
          startPosition: state.position, // 从当前位置开始播放
        );
      }
    } else if (song.path != null) {
      // 否则只打开单首歌曲并自动播放
      await _player!.open(
        url: song.path!,
        title: song.title,
        artist: song.artist,
        album: song.album ?? '',
        coverUrl: song.albumArt,
        startPosition: state.position,
        autoPlay: true, // 自动播放
      );
    }
  }

  /// 设置播放列表
  Future<void> setPlaylist(List<LocalSong> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    // 清除随机播放历史记录（新播放列表）
    _clearShuffleHistory();
    // 将起始歌曲添加到历史记录
    if (state.playMode == PlayMode.shuffle) {
      _addToShuffleHistory(startIndex);
    }

    // 更新 UI 状态
    state = state.copyWith(
      playlist: songs,
      currentIndex: startIndex,
      currentSong: songs[startIndex],
      isPlaying: true,
      position: Duration.zero,
    );

    // 调用原生播放器设置播放列表
    if (_player != null) {
      final items = songs
          .where((s) => s.path != null)
          .map((s) => MusicItem(
                url: s.path!,
                title: s.title,
                artist: s.artist,
                album: s.album ?? '',
                coverUrl: s.albumArt,
              ))
          .toList();

      if (items.isNotEmpty) {
        await _player!.setPlaylist(
          items: items,
          startIndex: startIndex,
          autoPlay: true,
        );
      }
    }

    _savePlayingState();
  }

  /// 下一首
  Future<void> playNext() async {
    if (state.playlist.isEmpty) return;

    // 标记正在手动切换歌曲（用于 trackChanged 事件判断方向）
    _isSwitchingTrack = true;

    int nextIndex;
    switch (state.playMode) {
      case PlayMode.singleLoop:
        // 单曲循环：保持当前索引，重新播放
        nextIndex = state.currentIndex;
        break;
      case PlayMode.shuffle:
        // 随机播放（带历史记录）
        nextIndex = _getNextShuffleIndex();
        break;
      case PlayMode.listLoop:
        // 列表循环：顺序播放
        nextIndex = (state.currentIndex + 1) % state.playlist.length;
        break;
    }

    // 更新 UI 状态（方向为下一首，切换后自动播放）
    state = state.copyWith(
      currentIndex: nextIndex,
      currentSong: state.playlist[nextIndex],
      position: Duration.zero,
      isPlaying: true, // 切换后自动播放
      isNextDirection: true, // 下一首方向
    );

    // 调用原生播放器切换并播放
    if (state.playMode == PlayMode.singleLoop) {
      // 单曲循环：重新播放当前歌曲
      await _player?.seek(Duration.zero);
      _player?.play();
    } else {
      // 切换到指定索引并播放
      await _player?.skipToIndex(nextIndex);
      _player?.play();
    }

    _isSwitchingTrack = false;
    _savePlayingState();
  }

  /// 上一首
  Future<void> playPrevious() async {
    if (state.playlist.isEmpty) return;

    // 标记正在手动切换歌曲（用于 trackChanged 事件判断方向）
    _isSwitchingTrack = true;

    int prevIndex;
    switch (state.playMode) {
      case PlayMode.singleLoop:
        // 单曲循环：保持当前索引，重新播放
        prevIndex = state.currentIndex;
        break;
      case PlayMode.shuffle:
        // 随机播放（带历史记录）：回到上一首播放过的歌曲
        prevIndex = _getPreviousShuffleIndex();
        break;
      case PlayMode.listLoop:
        // 列表循环：顺序播放
        prevIndex = (state.currentIndex - 1 + state.playlist.length) %
            state.playlist.length;
        break;
    }

    // 更新 UI 状态（方向为上一首，切换后自动播放）
    state = state.copyWith(
      currentIndex: prevIndex,
      currentSong: state.playlist[prevIndex],
      position: Duration.zero,
      isPlaying: true, // 切换后自动播放
      isNextDirection: false, // 上一首方向
    );

    // 调用原生播放器切换并播放
    if (state.playMode == PlayMode.singleLoop) {
      // 单曲循环：重新播放当前歌曲
      await _player?.seek(Duration.zero);
      _player?.play();
    } else {
      // 切换到指定索引并播放
      await _player?.skipToIndex(prevIndex);
      _player?.play();
    }

    _isSwitchingTrack = false;
    _savePlayingState();
  }

  /// 获取下一首随机播放的索引（带历史记录，优先未播放的歌曲）
  int _getNextShuffleIndex() {
    if (state.playlist.length == 1) {
      return 0;
    }

    // 如果当前在历史记录中间位置，且后面还有记录，则使用历史记录
    if (_shuffleHistoryIndex >= 0 &&
        _shuffleHistoryIndex < _shuffleHistory.length - 1) {
      _shuffleHistoryIndex++;
      return _shuffleHistory[_shuffleHistoryIndex];
    }

    // 否则，随机选择一首新歌曲
    final random = Random();
    int nextIndex;

    // 找出所有未播放过的歌曲索引
    final unplayedIndices = <int>[];
    for (int i = 0; i < state.playlist.length; i++) {
      if (!_playedIndices.contains(i) && i != state.currentIndex) {
        unplayedIndices.add(i);
      }
    }

    if (unplayedIndices.isNotEmpty) {
      // 优先从未播放过的歌曲中随机选择
      nextIndex = unplayedIndices[random.nextInt(unplayedIndices.length)];
    } else {
      // 所有歌曲都播放过了，重置已播放记录，重新开始
      _playedIndices.clear();
      // 从除当前歌曲外的所有歌曲中随机选择
      do {
        nextIndex = random.nextInt(state.playlist.length);
      } while (nextIndex == state.currentIndex);
    }

    // 记录到历史
    _addToShuffleHistory(nextIndex);

    return nextIndex;
  }

  /// 获取上一首随机播放的索引（从历史记录中获取，没有则随机）
  int _getPreviousShuffleIndex() {
    if (state.playlist.length == 1) {
      return 0;
    }

    // 如果历史记录中有上一首，则返回上一首
    if (_shuffleHistoryIndex > 0) {
      _shuffleHistoryIndex--;
      return _shuffleHistory[_shuffleHistoryIndex];
    }

    // 如果没有历史记录或已经是第一首，随机选择一首（不同于当前歌曲）
    final random = Random();
    int randomIndex;
    do {
      randomIndex = random.nextInt(state.playlist.length);
    } while (randomIndex == state.currentIndex && state.playlist.length > 1);

    // 将随机选择的歌曲插入到历史记录开头
    _shuffleHistory.insert(0, randomIndex);
    // _shuffleHistoryIndex 保持为 0，指向新插入的歌曲
    _shuffleHistoryIndex = 0;

    return randomIndex;
  }

  /// 添加索引到随机播放历史记录
  void _addToShuffleHistory(int index) {
    // 如果当前不在历史记录末尾，删除后面的记录
    if (_shuffleHistoryIndex >= 0 &&
        _shuffleHistoryIndex < _shuffleHistory.length - 1) {
      _shuffleHistory.removeRange(
          _shuffleHistoryIndex + 1, _shuffleHistory.length);
    }

    // 添加新索引到历史记录
    _shuffleHistory.add(index);
    _shuffleHistoryIndex = _shuffleHistory.length - 1;

    // 记录为已播放
    _playedIndices.add(index);

    // 限制历史记录长度，避免内存占用过多
    if (_shuffleHistory.length > 100) {
      _shuffleHistory.removeAt(0);
      _shuffleHistoryIndex--;
    }
  }

  /// 清除随机播放历史记录（当播放列表改变或切换播放模式时调用）
  void _clearShuffleHistory() {
    _shuffleHistory.clear();
    _shuffleHistoryIndex = -1;
    _playedIndices.clear();
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    if (_player != null) {
      await _player!.seek(position);
    }
    state = state.copyWith(position: position);
    // 立即保存播放位置
    _savePlayingState();
  }

  /// 跳转到播放列表中的指定索引
  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= state.playlist.length) return;

    if (_player != null) {
      await _player!.skipToIndex(index);
    } else {
      state = state.copyWith(
        currentIndex: index,
        currentSong: state.playlist[index],
        isPlaying: true,
        position: Duration.zero,
      );
    }
    _savePlayingState();
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    final oldMode = state.playMode;
    state = state.copyWith(playMode: mode);

    // 如果切换到随机模式，初始化历史记录
    if (mode == PlayMode.shuffle && oldMode != PlayMode.shuffle) {
      _clearShuffleHistory();
      // 将当前歌曲添加到历史记录
      if (state.currentIndex >= 0) {
        _addToShuffleHistory(state.currentIndex);
      }
    }

    // 持久化存储
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_playModeKey, mode.index);
  }

  /// 切换播放模式（循环切换：列表循环 -> 单曲循环 -> 随机播放）
  Future<void> togglePlayMode() async {
    final currentMode = state.playMode;
    final nextMode = switch (currentMode) {
      PlayMode.listLoop => PlayMode.singleLoop,
      PlayMode.singleLoop => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.listLoop,
    };
    await setPlayMode(nextMode);
  }

  /// 设置播放速度
  Future<void> setRate(double rate) async {
    if (_player != null) {
      await _player!.setRate(rate);
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    if (_player != null) {
      await _player!.setVolume(volume);
    }
  }

  // 上次保存的秒数，用于避免同一秒内重复保存
  int _lastSavedPositionSec = -1;

  void updatePosition(Duration position) {
    final oldPositionSec = state.position.inSeconds;
    state = state.copyWith(position: position);

    // 每秒保存一次位置（当秒数变化时保存）
    final newPositionSec = position.inSeconds;
    if (newPositionSec != oldPositionSec &&
        newPositionSec != _lastSavedPositionSec) {
      _lastSavedPositionSec = newPositionSec;
      _savePlayingState();
    }
  }

  void updateDuration(Duration duration) {
    state = state.copyWith(duration: duration);
  }

  /// 停止播放并清除状态
  Future<void> stop() async {
    if (_player != null) {
      await _player!.stop();
    }
    state = state.copyWith(isPlaying: false);
    _savePlayingState();
  }

  /// 清除播放状态
  Future<void> clear() async {
    if (_player != null) {
      await _player!.stop();
    }
    state = const LocalMusicPlayerState();
    await _clearSavedState();
  }

  /// 清除保存的播放状态
  Future<void> _clearSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastPlayingSongKey);
      await prefs.remove(_lastPlayingPositionKey);
      await prefs.remove(_lastPlaylistKey);
      await prefs.remove(_lastPlaylistIndexKey);
    } catch (e) {
      print('Failed to clear saved state: $e');
    }
  }

  /// 清除播放列表的持久化缓存（公开方法）
  Future<void> clearSavedPlaylist() async {
    await _clearSavedState();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _trackChangedSubscription?.cancel();
    _playlistEndedSubscription?.cancel();
    _errorSubscription?.cancel();
    _mediaButtonNextSubscription?.cancel();
    _mediaButtonPreviousSubscription?.cancel();
    _mediaButtonPlaySubscription?.cancel();
    _mediaButtonPauseSubscription?.cancel();
    // 注意：不要 dispose 单例的 _player
    super.dispose();
  }
}

final localMusicPlayerProvider =
    StateNotifierProvider<LocalMusicPlayerNotifier, LocalMusicPlayerState>(
  (ref) => LocalMusicPlayerNotifier(),
);

/// 音乐页面是否显示的状态
final musicPageVisibleProvider = StateProvider<bool>((ref) => false);

/// 音乐页面抽屉是否展开
final musicDrawerOpenProvider = StateProvider<bool>((ref) => false);

/// 请求关闭抽屉的触发器（每次增加表示请求关闭）
final closeDrawerTriggerProvider = StateProvider<int>((ref) => 0);

/// 音乐播放页面是否展开
final musicPlayerExpandedProvider = StateProvider<bool>((ref) => false);

/// 请求折叠播放页面的触发器（每次增加表示请求折叠）
final collapsePlayerTriggerProvider = StateProvider<int>((ref) => 0);

/// 请求展开播放页面的触发器（每次增加表示请求展开）
final expandPlayerTriggerProvider = StateProvider<int>((ref) => 0);

/// 展开播放页面时是否跳过动画（用于初始化直接进入全屏播放器）
final skipExpandAnimationProvider = StateProvider<bool>((ref) => false);

/// 请求展开播放页面并直接显示播放列表的触发器
final expandToPlaylistTriggerProvider = StateProvider<int>((ref) => 0);

/// ✅ 静态标记：是否需要初始展开播放器（在路由创建时设置，在第一帧就可以访问）
/// 这个变量用于解决 Provider 在 widget 构建期间无法修改的问题
class InitialExpandMarker {
  static bool shouldExpand = false;

  /// 设置需要初始展开
  static void set() {
    shouldExpand = true;
  }

  /// 清除标记
  static void clear() {
    shouldExpand = false;
  }

  /// 消费标记（获取后自动清除）
  static bool consume() {
    final value = shouldExpand;
    shouldExpand = false;
    return value;
  }
}

/// 当前选中的音乐导航项
enum MusicNavItem {
  songs, // 歌曲
  albums, // 专辑
  artists, // 艺术家
  folders, // 文件夹
  playlists, // 歌单
  scan, // 扫描音乐
  library, // 音乐库
  stats, // 统计
  settings, // 设置
}

final currentMusicNavProvider =
    StateProvider<MusicNavItem>((ref) => MusicNavItem.songs);

/// 音乐来源模式
enum MusicSourceMode {
  local, // 本地音乐
  server, // 服务器媒体库音乐
}

/// 当前音乐来源模式
final musicSourceModeProvider =
    StateProvider<MusicSourceMode>((ref) => MusicSourceMode.local);

/// 启动页面模式
enum StartupPageMode {
  defaultMode, // 默认：正常进入首页
  music, // 音乐：进入音乐tab并全屏播放器
  live, // 直播：暂时也进入首页
}

/// 音乐tab标记的存储key
const String _musicTabActiveKey = 'music_tab_active';

/// 启动页面模式的存储key
const String _startupPageModeKey = 'startup_page_mode';

/// 音乐tab标记管理
class MusicTabMarker {
  /// 设置音乐tab标记（进入音乐tab时调用）
  static Future<void> setActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_musicTabActiveKey, true);
  }

  /// 清除音乐tab标记（退出音乐tab时调用）
  static Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_musicTabActiveKey);
  }

  /// 检查是否有音乐tab标记
  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_musicTabActiveKey) ?? false;
  }
}

/// 启动页面模式管理
class StartupPageManager {
  /// 获取启动页面模式
  static Future<StartupPageMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_startupPageModeKey);
    switch (modeStr) {
      case 'music':
        return StartupPageMode.music;
      case 'live':
        return StartupPageMode.live;
      default:
        return StartupPageMode.defaultMode;
    }
  }

  /// 设置启动页面模式
  static Future<void> setMode(StartupPageMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String modeStr;
    switch (mode) {
      case StartupPageMode.music:
        modeStr = 'music';
        break;
      case StartupPageMode.live:
        modeStr = 'live';
        break;
      case StartupPageMode.defaultMode:
        modeStr = 'default';
        break;
    }
    await prefs.setString(_startupPageModeKey, modeStr);
  }

  /// 判断是否应该直接进入音乐页面
  /// 条件：设置为音乐模式，或者设置为默认模式且有音乐tab标记
  static Future<bool> shouldEnterMusicPage() async {
    final mode = await getMode();
    if (mode == StartupPageMode.music) {
      return true;
    }
    if (mode == StartupPageMode.defaultMode) {
      return await MusicTabMarker.isActive();
    }
    return false;
  }
}

/// 睡眠定时器状态
class SleepTimerState {
  const SleepTimerState({
    this.isActive = false,
    this.remainingSeconds = 0,
    this.totalSeconds = 0,
    this.extendToSongEnd = false,
  });

  final bool isActive;
  final int remainingSeconds; // 剩余秒数
  final int totalSeconds; // 总秒数
  final bool extendToSongEnd; // 是否延长到整首歌播完

  SleepTimerState copyWith({
    bool? isActive,
    int? remainingSeconds,
    int? totalSeconds,
    bool? extendToSongEnd,
  }) {
    return SleepTimerState(
      isActive: isActive ?? this.isActive,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      extendToSongEnd: extendToSongEnd ?? this.extendToSongEnd,
    );
  }
}

/// 睡眠定时器 Provider
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier(ref);
});

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  SleepTimerNotifier(this.ref) : super(const SleepTimerState());

  final Ref ref;
  Timer? _timer;
  bool _waitingForSongEnd = false;

  /// 开始定时器
  void startTimer(int minutes, bool extendToSongEnd) {
    // 取消之前的定时器
    _timer?.cancel();
    _waitingForSongEnd = false;

    final totalSeconds = minutes * 60;
    state = SleepTimerState(
      isActive: true,
      remainingSeconds: totalSeconds,
      totalSeconds: totalSeconds,
      extendToSongEnd: extendToSongEnd,
    );

    // 每秒更新剩余时间
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds > 0) {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      } else {
        // 时间到
        _onTimerEnd();
      }
    });
  }

  /// 停止定时器
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _waitingForSongEnd = false;
    state = const SleepTimerState();
  }

  /// 定时器结束处理
  void _onTimerEnd() {
    _timer?.cancel();
    _timer = null;

    if (state.extendToSongEnd) {
      // 等待当前歌曲播放完毕
      _waitingForSongEnd = true;
      // 监听歌曲切换事件
      _listenForSongEnd();
    } else {
      // 直接停止播放并退出
      _stopAndExit();
    }
  }

  /// 监听歌曲结束
  void _listenForSongEnd() {
    // 订阅播放状态变化
    final playerState = ref.read(localMusicPlayerProvider);
    final currentSongId = playerState.currentSong?.id;

    // 使用定时器检查歌曲是否切换
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_waitingForSongEnd) {
        timer.cancel();
        return;
      }

      final newState = ref.read(localMusicPlayerProvider);
      // 如果歌曲切换了或者停止播放了
      if (newState.currentSong?.id != currentSongId || !newState.isPlaying) {
        timer.cancel();
        _waitingForSongEnd = false;
        _stopAndExit();
      }
    });
  }

  /// 停止播放并退出 app
  void _stopAndExit() {
    // 停止播放
    ref.read(localMusicPlayerProvider.notifier).stop();
    // 重置状态
    state = const SleepTimerState();
    // 退出 app
    exit(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
