import 'package:flutter_riverpod/flutter_riverpod.dart';

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
