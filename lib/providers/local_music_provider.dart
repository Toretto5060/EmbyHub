import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.playlist = const [],
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final LocalSong? currentSong;
  final bool isPlaying;
  final List<LocalSong> playlist;
  final int currentIndex;
  final Duration position;
  final Duration duration;

  LocalMusicPlayerState copyWith({
    LocalSong? currentSong,
    bool? isPlaying,
    List<LocalSong>? playlist,
    int? currentIndex,
    Duration? position,
    Duration? duration,
  }) {
    return LocalMusicPlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
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
class LocalMusicPlayerNotifier extends StateNotifier<LocalMusicPlayerState> {
  LocalMusicPlayerNotifier() : super(const LocalMusicPlayerState()) {
    // 初始化时加载上次播放状态
    _loadLastPlayingState();
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

  void playSong(LocalSong song) {
    state = state.copyWith(
      currentSong: song,
      isPlaying: true,
    );
    _savePlayingState();
  }

  void togglePlayPause() {
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  void pause() {
    state = state.copyWith(isPlaying: false);
    _savePlayingState(); // 暂停时保存位置
  }

  void play() {
    state = state.copyWith(isPlaying: true);
  }

  void setPlaylist(List<LocalSong> songs, {int startIndex = 0}) {
    if (songs.isEmpty) return;
    state = state.copyWith(
      playlist: songs,
      currentIndex: startIndex,
      currentSong: songs[startIndex],
      isPlaying: true,
    );
    _savePlayingState();
  }

  void playNext() {
    if (state.playlist.isEmpty) return;
    final nextIndex = (state.currentIndex + 1) % state.playlist.length;
    state = state.copyWith(
      currentIndex: nextIndex,
      currentSong: state.playlist[nextIndex],
      isPlaying: true,
      position: Duration.zero, // 重置播放位置
    );
    _savePlayingState();
  }

  void playPrevious() {
    if (state.playlist.isEmpty) return;
    final prevIndex = (state.currentIndex - 1 + state.playlist.length) %
        state.playlist.length;
    state = state.copyWith(
      currentIndex: prevIndex,
      currentSong: state.playlist[prevIndex],
      isPlaying: true,
      position: Duration.zero, // 重置播放位置
    );
    _savePlayingState();
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

  void clear() {
    state = const LocalMusicPlayerState();
    _clearSavedState();
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
