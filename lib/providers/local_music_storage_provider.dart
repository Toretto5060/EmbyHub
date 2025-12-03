import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_music_provider.dart';

/// 本地音乐数据存储管理
/// 支持按用户（本地/服务器用户）存储数据

// 存储键前缀
const String _storageKeyPrefix = 'local_music_';

/// 获取当前用户的存储键前缀
Future<String> _getUserKeyPrefix() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('emby_user_id');
  // 如果有服务器用户ID，使用服务器用户前缀；否则使用本地用户前缀
  if (userId != null && userId.isNotEmpty) {
    return '${_storageKeyPrefix}server_$userId';
  }
  return '${_storageKeyPrefix}local';
}

/// 歌单数据模型
class MusicPlaylist {
  final String id;
  final String name;
  final List<String> songIds;
  final DateTime createdAt;
  final bool isDefault; // 是否为默认歌单（不可删除）

  const MusicPlaylist({
    required this.id,
    required this.name,
    this.songIds = const [],
    required this.createdAt,
    this.isDefault = false,
  });

  MusicPlaylist copyWith({
    String? id,
    String? name,
    List<String>? songIds,
    DateTime? createdAt,
    bool? isDefault,
  }) {
    return MusicPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      songIds: songIds ?? this.songIds,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songIds': songIds,
      'createdAt': createdAt.toIso8601String(),
      'isDefault': isDefault,
    };
  }

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    return MusicPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      songIds: (json['songIds'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

/// 本地音乐数据状态
class LocalMusicStorageState {
  final List<LocalSong> songs;
  final List<MusicPlaylist> playlists;
  final bool isLoading;
  final String? error;

  const LocalMusicStorageState({
    this.songs = const [],
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  LocalMusicStorageState copyWith({
    List<LocalSong>? songs,
    List<MusicPlaylist>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return LocalMusicStorageState(
      songs: songs ?? this.songs,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 本地音乐数据存储管理器
class LocalMusicStorageNotifier extends StateNotifier<LocalMusicStorageState> {
  LocalMusicStorageNotifier()
      : super(const LocalMusicStorageState(isLoading: true)) {
    _initialize();
  }

  /// 默认歌单列表
  static const List<Map<String, String>> defaultPlaylists = [
    {'id': 'favorites', 'name': '我喜欢的音乐'},
    {'id': 'recent', 'name': '最近播放'},
    {'id': 'workout', 'name': '运动歌单'},
    {'id': 'sleep', 'name': '睡前音乐'},
  ];

  Future<void> _initialize() async {
    await loadData();
  }

  /// 加载数据
  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final keyPrefix = await _getUserKeyPrefix();
      final prefs = await SharedPreferences.getInstance();

      // 加载歌曲列表
      final songsJson = prefs.getString('${keyPrefix}_songs');
      List<LocalSong> songs = [];
      if (songsJson != null && songsJson.isNotEmpty) {
        final songsList = jsonDecode(songsJson) as List<dynamic>;
        songs = songsList.map((json) => _localSongFromJson(json)).toList();
      }

      // 加载歌单列表
      final playlistsJson = prefs.getString('${keyPrefix}_playlists');
      List<MusicPlaylist> playlists = [];
      if (playlistsJson != null && playlistsJson.isNotEmpty) {
        final playlistsList = jsonDecode(playlistsJson) as List<dynamic>;
        playlists =
            playlistsList.map((json) => MusicPlaylist.fromJson(json)).toList();
      }

      // 如果没有歌单，创建默认歌单
      if (playlists.isEmpty) {
        playlists = defaultPlaylists
            .map((p) => MusicPlaylist(
                  id: p['id']!,
                  name: p['name']!,
                  createdAt: DateTime.now(),
                  isDefault: true,
                ))
            .toList();
        await _savePlaylists(playlists);
      }

      state = state.copyWith(
        songs: songs,
        playlists: playlists,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 保存歌曲列表
  Future<void> _saveSongs(List<LocalSong> songs) async {
    final keyPrefix = await _getUserKeyPrefix();
    final prefs = await SharedPreferences.getInstance();
    final songsJson =
        jsonEncode(songs.map((s) => _localSongToJson(s)).toList());
    await prefs.setString('${keyPrefix}_songs', songsJson);
  }

  /// 保存歌单列表
  Future<void> _savePlaylists(List<MusicPlaylist> playlists) async {
    final keyPrefix = await _getUserKeyPrefix();
    final prefs = await SharedPreferences.getInstance();
    final playlistsJson = jsonEncode(playlists.map((p) => p.toJson()).toList());
    await prefs.setString('${keyPrefix}_playlists', playlistsJson);
  }

  /// 添加歌曲（如果已存在则更新）
  Future<void> addSongs(List<LocalSong> newSongs) async {
    final updatedSongs = [...state.songs];
    for (final song in newSongs) {
      // 查找是否已存在
      final existingIndex = updatedSongs.indexWhere((s) => s.id == song.id);
      if (existingIndex >= 0) {
        // 更新已存在的歌曲信息
        updatedSongs[existingIndex] = song;
      } else {
        // 添加新歌曲
        updatedSongs.add(song);
      }
    }
    state = state.copyWith(songs: updatedSongs);
    await _saveSongs(updatedSongs);
  }

  /// 删除歌曲
  Future<void> removeSong(String songId) async {
    final updatedSongs = state.songs.where((s) => s.id != songId).toList();
    state = state.copyWith(songs: updatedSongs);
    await _saveSongs(updatedSongs);

    // 同时从所有歌单中移除该歌曲
    final updatedPlaylists = state.playlists.map((p) {
      if (p.songIds.contains(songId)) {
        return p.copyWith(
            songIds: p.songIds.where((id) => id != songId).toList());
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
  }

  /// 清空所有歌曲
  Future<void> clearAllSongs() async {
    state = state.copyWith(songs: []);
    await _saveSongs([]);

    // 清空所有歌单中的歌曲
    final updatedPlaylists =
        state.playlists.map((p) => p.copyWith(songIds: [])).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
  }

  /// 创建歌单
  Future<MusicPlaylist> createPlaylist(String name) async {
    final newPlaylist = MusicPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
      isDefault: false,
    );
    final updatedPlaylists = [...state.playlists, newPlaylist];
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
    return newPlaylist;
  }

  /// 删除歌单（默认歌单不可删除）
  Future<bool> deletePlaylist(String playlistId) async {
    final playlist = state.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => throw Exception('歌单不存在'),
    );
    if (playlist.isDefault) {
      return false; // 默认歌单不可删除
    }
    final updatedPlaylists =
        state.playlists.where((p) => p.id != playlistId).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
    return true;
  }

  /// 重命名歌单
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final updatedPlaylists = state.playlists.map((p) {
      if (p.id == playlistId) {
        return p.copyWith(name: newName);
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
  }

  /// 添加歌曲到歌单
  Future<void> addSongsToPlaylist(
      String playlistId, List<String> songIds) async {
    final updatedPlaylists = state.playlists.map((p) {
      if (p.id == playlistId) {
        final newSongIds = [...p.songIds];
        for (final songId in songIds) {
          if (!newSongIds.contains(songId)) {
            newSongIds.add(songId);
          }
        }
        return p.copyWith(songIds: newSongIds);
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
  }

  /// 从歌单中移除歌曲
  Future<void> removeSongsFromPlaylist(
      String playlistId, List<String> songIds) async {
    final updatedPlaylists = state.playlists.map((p) {
      if (p.id == playlistId) {
        return p.copyWith(
          songIds: p.songIds.where((id) => !songIds.contains(id)).toList(),
        );
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
  }

  /// 获取歌单中的歌曲
  List<LocalSong> getPlaylistSongs(String playlistId) {
    final playlist = state.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => throw Exception('歌单不存在'),
    );
    return state.songs.where((s) => playlist.songIds.contains(s.id)).toList();
  }

  /// 添加到最近播放
  Future<void> addToRecentlyPlayed(String songId) async {
    const recentPlaylistId = 'recent';
    final playlist = state.playlists.firstWhere(
      (p) => p.id == recentPlaylistId,
      orElse: () => throw Exception('最近播放歌单不存在'),
    );

    // 将歌曲移到最前面
    final newSongIds = [
      songId,
      ...playlist.songIds.where((id) => id != songId)
    ];
    // 限制最近播放数量为100首
    final limitedSongIds = newSongIds.take(100).toList();

    final updatedPlaylists = state.playlists.map((p) {
      if (p.id == recentPlaylistId) {
        return p.copyWith(songIds: limitedSongIds);
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updatedPlaylists);
    await _savePlaylists(updatedPlaylists);
  }

  /// 切换喜欢状态
  Future<bool> toggleFavorite(String songId) async {
    const favoritesPlaylistId = 'favorites';
    final playlist = state.playlists.firstWhere(
      (p) => p.id == favoritesPlaylistId,
      orElse: () => throw Exception('我喜欢的音乐歌单不存在'),
    );

    final isFavorite = playlist.songIds.contains(songId);
    if (isFavorite) {
      await removeSongsFromPlaylist(favoritesPlaylistId, [songId]);
    } else {
      await addSongsToPlaylist(favoritesPlaylistId, [songId]);
    }
    return !isFavorite;
  }

  /// 检查歌曲是否已收藏
  bool isFavorite(String songId) {
    const favoritesPlaylistId = 'favorites';
    final playlist = state.playlists.firstWhere(
      (p) => p.id == favoritesPlaylistId,
      orElse: () => throw Exception('我喜欢的音乐歌单不存在'),
    );
    return playlist.songIds.contains(songId);
  }
}

/// LocalSong 的 JSON 序列化辅助方法
Map<String, dynamic> _localSongToJson(LocalSong song) {
  return {
    'id': song.id,
    'title': song.title,
    'artist': song.artist,
    'album': song.album,
    'albumArt': song.albumArt,
    'lyrics': song.lyrics,
    'bitrate': song.bitrate,
    'duration': song.duration?.inMilliseconds,
    'path': song.path,
  };
}

LocalSong _localSongFromJson(Map<String, dynamic> json) {
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

/// Provider
final localMusicStorageProvider =
    StateNotifierProvider<LocalMusicStorageNotifier, LocalMusicStorageState>(
  (ref) => LocalMusicStorageNotifier(),
);
