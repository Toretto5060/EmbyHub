import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/music/exoplayer_music_controller.dart';

/// 持久化存储的键
const String _lastPlayingSongKey = 'last_playing_song';
const String _lastPlayingPositionKey = 'last_playing_position';
const String _lastPlaylistKey = 'last_playlist';
const String _lastPlaylistIndexKey = 'last_playlist_index';

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
    this.repeatMode = 'off',
    this.shuffleMode = false,
  });

  final LocalSong? currentSong;
  final bool isPlaying;
  final bool isBuffering;
  final List<LocalSong> playlist;
  final int currentIndex;
  final Duration position;
  final Duration duration;
  final String repeatMode; // 'off' | 'one' | 'all'
  final bool shuffleMode;

  LocalMusicPlayerState copyWith({
    LocalSong? currentSong,
    bool? isPlaying,
    bool? isBuffering,
    List<LocalSong>? playlist,
    int? currentIndex,
    Duration? position,
    Duration? duration,
    String? repeatMode,
    bool? shuffleMode,
  }) {
    return LocalMusicPlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleMode: shuffleMode ?? this.shuffleMode,
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
      'duration': duration?.inMilliseconds,
      'path': path,
    };
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
    _stateSubscription = player.stateStream.listen((playerState) {
      state = state.copyWith(
        position: playerState.position,
        duration: playerState.duration,
        isPlaying: playerState.isPlaying,
        isBuffering: playerState.isBuffering,
        repeatMode: playerState.repeatMode,
        shuffleMode: playerState.shuffleMode,
      );

      // 每10秒保存一次位置
      if (playerState.position.inSeconds % 10 == 0 && playerState.isPlaying) {
        _savePlayingState();
      }
    });

    // 监听曲目切换
    _trackChangedSubscription = player.trackChangedStream.listen((event) {
      if (event.index >= 0 && event.index < state.playlist.length) {
        state = state.copyWith(
          currentIndex: event.index,
          currentSong: state.playlist[event.index],
          position: Duration.zero,
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

    // 监听错误
    _errorSubscription = player.errorStream.listen((error) {
      print('Music player error: $error');
    });
  }

  /// 加载上次播放状态
  Future<void> _loadLastPlayingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

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

      // 更新状态（不自动播放，只恢复状态）
      state = state.copyWith(
        currentSong: song,
        position: position,
        playlist: playlist.isNotEmpty ? playlist : [song],
        currentIndex: playlistIndex,
        isPlaying: false, // 不自动播放
      );
    } catch (e) {
      // 加载失败时忽略错误
      print('Failed to load last playing state: $e');
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

        // 保存播放列表（最多保存100首）
        if (state.playlist.isNotEmpty) {
          final playlistToSave = state.playlist.take(100).toList();
          final playlistJson = jsonEncode(
            playlistToSave.map((s) => s.toJson()).toList(),
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

  /// 播放单首歌曲
  Future<void> playSong(LocalSong song) async {
    print('LocalMusicPlayerNotifier: playSong called');
    print('  - path: ${song.path}');
    print('  - title: ${song.title}');
    print('  - coverUrl: ${song.albumArt}');

    // 更新 UI 状态
    state = state.copyWith(
      currentSong: song,
      isPlaying: true,
      position: Duration.zero,
    );

    // 调用原生播放器
    if (_player != null && song.path != null) {
      print('LocalMusicPlayerNotifier: calling _player.open()');
      await _player!.open(
        url: song.path!,
        title: song.title,
        artist: song.artist,
        album: song.album ?? '',
        coverUrl: song.albumArt,
        autoPlay: true,
      );
      print('LocalMusicPlayerNotifier: _player.open() completed');
    } else {
      print('LocalMusicPlayerNotifier: player is null or path is null');
    }

    _savePlayingState();
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    if (_player != null) {
      if (state.isPlaying) {
        await _player!.pause();
      } else {
        // 如果没有当前歌曲但有播放列表，先加载
        if (state.currentSong != null && !_player!.isInitialized) {
          await _openCurrentSong();
        }
        await _player!.play();
      }
    }
    // 状态由 stream 监听更新，这里只做备用
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  /// 暂停
  Future<void> pause() async {
    if (_player != null) {
      await _player!.pause();
    }
    state = state.copyWith(isPlaying: false);
    _savePlayingState();
  }

  /// 播放
  Future<void> play() async {
    if (_player != null) {
      if (state.currentSong != null && !_player!.isReady) {
        await _openCurrentSong();
      }
      await _player!.play();
    }
    state = state.copyWith(isPlaying: true);
  }

  /// 打开当前歌曲
  Future<void> _openCurrentSong() async {
    final song = state.currentSong;
    if (_player != null && song != null && song.path != null) {
      await _player!.open(
        url: song.path!,
        title: song.title,
        artist: song.artist,
        album: song.album ?? '',
        coverUrl: song.albumArt,
        startPosition: state.position,
        autoPlay: false,
      );
    }
  }

  /// 设置播放列表
  Future<void> setPlaylist(List<LocalSong> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

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

    if (_player != null) {
      await _player!.next();
    } else {
      // 非 Android 平台的备用逻辑
      final nextIndex = (state.currentIndex + 1) % state.playlist.length;
      state = state.copyWith(
        currentIndex: nextIndex,
        currentSong: state.playlist[nextIndex],
        isPlaying: true,
        position: Duration.zero,
      );
      _savePlayingState();
    }
  }

  /// 上一首
  Future<void> playPrevious() async {
    if (state.playlist.isEmpty) return;

    if (_player != null) {
      await _player!.previous();
    } else {
      // 非 Android 平台的备用逻辑
      final prevIndex = (state.currentIndex - 1 + state.playlist.length) %
          state.playlist.length;
      state = state.copyWith(
        currentIndex: prevIndex,
        currentSong: state.playlist[prevIndex],
        isPlaying: true,
        position: Duration.zero,
      );
      _savePlayingState();
    }
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    if (_player != null) {
      await _player!.seek(position);
    }
    state = state.copyWith(position: position);
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

  /// 设置循环模式
  Future<void> setRepeatMode(String mode) async {
    if (_player != null) {
      await _player!.setRepeatMode(mode);
    }
    state = state.copyWith(repeatMode: mode);
  }

  /// 设置随机播放
  Future<void> setShuffleMode(bool enabled) async {
    if (_player != null) {
      await _player!.setShuffleMode(enabled);
    }
    state = state.copyWith(shuffleMode: enabled);
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

  void updatePosition(Duration position) {
    state = state.copyWith(position: position);
    // 每10秒保存一次位置，避免频繁写入
    if (position.inSeconds % 10 == 0) {
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

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _trackChangedSubscription?.cancel();
    _playlistEndedSubscription?.cancel();
    _errorSubscription?.cancel();
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

/// 音乐播放页面是否展开
final musicPlayerExpandedProvider = StateProvider<bool>((ref) => false);

/// 请求折叠播放页面的触发器（每次增加表示请求折叠）
final collapsePlayerTriggerProvider = StateProvider<int>((ref) => 0);

/// 请求展开播放页面的触发器（每次增加表示请求展开）
final expandPlayerTriggerProvider = StateProvider<int>((ref) => 0);

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
