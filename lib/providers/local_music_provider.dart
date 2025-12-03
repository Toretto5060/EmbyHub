import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.duration,
    this.path,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? albumArt;
  final Duration? duration;
  final String? path;
}

/// 本地音乐播放器状态管理
class LocalMusicPlayerNotifier extends StateNotifier<LocalMusicPlayerState> {
  LocalMusicPlayerNotifier() : super(const LocalMusicPlayerState());

  void playSong(LocalSong song) {
    state = state.copyWith(
      currentSong: song,
      isPlaying: true,
    );
  }

  void togglePlayPause() {
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  void pause() {
    state = state.copyWith(isPlaying: false);
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
  }

  void playNext() {
    if (state.playlist.isEmpty) return;
    final nextIndex = (state.currentIndex + 1) % state.playlist.length;
    state = state.copyWith(
      currentIndex: nextIndex,
      currentSong: state.playlist[nextIndex],
      isPlaying: true,
    );
  }

  void playPrevious() {
    if (state.playlist.isEmpty) return;
    final prevIndex = (state.currentIndex - 1 + state.playlist.length) %
        state.playlist.length;
    state = state.copyWith(
      currentIndex: prevIndex,
      currentSong: state.playlist[prevIndex],
      isPlaying: true,
    );
  }

  void updatePosition(Duration position) {
    state = state.copyWith(position: position);
  }

  void updateDuration(Duration duration) {
    state = state.copyWith(duration: duration);
  }

  void clear() {
    state = const LocalMusicPlayerState();
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
