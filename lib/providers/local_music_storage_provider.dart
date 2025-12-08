import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/emby_api.dart';
import 'local_music_provider.dart';
import 'settings_provider.dart';

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

/// 播放队列缓存（用于切换模式时保存/恢复）
class PlayQueueCache {
  final LocalSong? currentSong;
  final List<LocalSong> playlist;
  final int currentIndex;
  final Duration position;

  const PlayQueueCache({
    this.currentSong,
    this.playlist = const [],
    this.currentIndex = 0,
    this.position = Duration.zero,
  });

  bool get isEmpty => currentSong == null && playlist.isEmpty;
}

/// 本地音乐数据状态
class LocalMusicStorageState {
  final List<LocalSong> songs; // 当前显示的歌曲列表（本地或服务器）
  final List<LocalSong> localSongs; // 本地扫描的歌曲（始终保留）
  final List<LocalSong> serverSongs; // 服务器音乐列表
  final List<MusicPlaylist> playlists;
  final bool isLoading;
  final bool isLoadingMore; // 是否正在加载更多
  final String? error;
  final MusicSourceMode sourceMode; // 当前数据来源模式
  final PlayQueueCache localPlayQueue; // 本地播放队列缓存
  final PlayQueueCache serverPlayQueue; // 服务器播放队列缓存
  final int serverTotalCount; // 服务器音乐总数
  final bool hasMoreServerSongs; // 是否还有更多服务器歌曲
  final String? currentServerId; // 当前服务器ID（用于区分存储）
  final String? currentLibraryId; // 当前媒体库ID

  const LocalMusicStorageState({
    this.songs = const [],
    this.localSongs = const [],
    this.serverSongs = const [],
    this.playlists = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.sourceMode = MusicSourceMode.local,
    this.localPlayQueue = const PlayQueueCache(),
    this.serverPlayQueue = const PlayQueueCache(),
    this.serverTotalCount = 0,
    this.hasMoreServerSongs = false,
    this.currentServerId,
    this.currentLibraryId,
  });

  LocalMusicStorageState copyWith({
    List<LocalSong>? songs,
    List<LocalSong>? localSongs,
    List<LocalSong>? serverSongs,
    List<MusicPlaylist>? playlists,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    MusicSourceMode? sourceMode,
    PlayQueueCache? localPlayQueue,
    PlayQueueCache? serverPlayQueue,
    int? serverTotalCount,
    bool? hasMoreServerSongs,
    String? currentServerId,
    String? currentLibraryId,
  }) {
    return LocalMusicStorageState(
      songs: songs ?? this.songs,
      localSongs: localSongs ?? this.localSongs,
      serverSongs: serverSongs ?? this.serverSongs,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
      sourceMode: sourceMode ?? this.sourceMode,
      localPlayQueue: localPlayQueue ?? this.localPlayQueue,
      serverPlayQueue: serverPlayQueue ?? this.serverPlayQueue,
      serverTotalCount: serverTotalCount ?? this.serverTotalCount,
      hasMoreServerSongs: hasMoreServerSongs ?? this.hasMoreServerSongs,
      currentServerId: currentServerId ?? this.currentServerId,
      currentLibraryId: currentLibraryId ?? this.currentLibraryId,
    );
  }
}

/// 本地音乐数据存储管理器
class LocalMusicStorageNotifier extends StateNotifier<LocalMusicStorageState> {
  LocalMusicStorageNotifier(this._ref)
      : super(const LocalMusicStorageState(isLoading: true)) {
    _initialize();
  }

  final Ref _ref;

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

      // 加载本地歌曲列表
      final songsJson = prefs.getString('${keyPrefix}_songs');
      List<LocalSong> localSongs = [];
      if (songsJson != null && songsJson.isNotEmpty) {
        final songsList = jsonDecode(songsJson) as List<dynamic>;
        localSongs = songsList.map((json) => _localSongFromJson(json)).toList();
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

      // 默认显示本地歌曲
      state = state.copyWith(
        songs: localSongs,
        localSongs: localSongs,
        playlists: playlists,
        isLoading: false,
        sourceMode: MusicSourceMode.local,
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

  /// 切换到本地模式
  Future<void> switchToLocalMode() async {
    final playerNotifier = _ref.read(localMusicPlayerProvider.notifier);
    final playerState = _ref.read(localMusicPlayerProvider);

    // 保存当前服务器播放队列
    final serverQueueCache = PlayQueueCache(
      currentSong: playerState.currentSong,
      playlist: playerState.playlist,
      currentIndex: playerState.currentIndex,
      position: playerState.position,
    );

    // 停止当前播放并清空状态
    await playerNotifier.clear();

    // 切换显示本地歌曲，并保存服务器播放队列
    state = state.copyWith(
      songs: state.localSongs,
      sourceMode: MusicSourceMode.local,
      serverPlayQueue: serverQueueCache,
    );

    // 更新全局模式
    _ref.read(musicSourceModeProvider.notifier).state = MusicSourceMode.local;

    // 恢复本地播放队列（如果有）
    if (!state.localPlayQueue.isEmpty) {
      await _restorePlayQueue(state.localPlayQueue);
    }
  }

  /// 切换到服务器模式并加载音乐
  Future<void> switchToServerMode(String libraryId) async {
    final playerNotifier = _ref.read(localMusicPlayerProvider.notifier);
    final playerState = _ref.read(localMusicPlayerProvider);

    // 保存当前本地播放队列
    final localQueueCache = PlayQueueCache(
      currentSong: playerState.currentSong,
      playlist: playerState.playlist,
      currentIndex: playerState.currentIndex,
      position: playerState.position,
    );

    // 停止当前播放并清空状态
    await playerNotifier.clear();

    // 获取服务器ID
    final prefs = await SharedPreferences.getInstance();
    final serverId = prefs.getString('emby_server_id') ?? 'default';

    // 设置加载状态，并保存本地播放队列
    state = state.copyWith(
      isLoading: true,
      sourceMode: MusicSourceMode.server,
      localPlayQueue: localQueueCache,
      currentServerId: serverId,
      currentLibraryId: libraryId,
    );

    // 更新全局模式
    _ref.read(musicSourceModeProvider.notifier).state = MusicSourceMode.server;

    try {
      // 先尝试从缓存加载
      final cachedData = await _loadServerMusicCache(serverId, libraryId);

      if (cachedData != null && cachedData.songs.isNotEmpty) {
        // 有缓存，直接显示全部缓存数据
        // 缓存数据已经是完整的，不需要上拉加载更多
        state = state.copyWith(
          songs: cachedData.songs,
          serverSongs: cachedData.songs,
          serverTotalCount: cachedData.totalCount,
          hasMoreServerSongs: false, // 缓存数据不需要上拉加载
          isLoading: false,
        );

        // 恢复服务器播放队列（如果有）
        if (!state.serverPlayQueue.isEmpty) {
          await _restorePlayQueue(state.serverPlayQueue);
        }
        // 不在这里后台刷新，而是在滚动时触发
      } else {
        // 没有缓存，从服务器获取（需要分页加载）
        await _fetchAndCacheServerMusic(libraryId, serverId);
      }
    } catch (e) {
      // 加载失败，回退到本地模式
      state = state.copyWith(
        songs: state.localSongs,
        sourceMode: MusicSourceMode.local,
        isLoading: false,
        error: '加载服务器音乐失败: $e',
        currentServerId: null,
        currentLibraryId: null,
      );
      _ref.read(musicSourceModeProvider.notifier).state = MusicSourceMode.local;
      // 恢复本地播放队列
      if (!localQueueCache.isEmpty) {
        await _restorePlayQueue(localQueueCache);
      }
    }
  }

  /// 从服务器获取并缓存音乐
  Future<void> _fetchAndCacheServerMusic(
      String libraryId, String serverId) async {
    final result = await _fetchServerMusicListWithTotal(libraryId, 0, 100);

    state = state.copyWith(
      songs: result.songs,
      serverSongs: result.songs,
      serverTotalCount: result.totalCount,
      hasMoreServerSongs: result.songs.length < result.totalCount,
      isLoading: false,
    );

    // 保存到缓存
    await _saveServerMusicCache(
        serverId, libraryId, result.songs, result.totalCount);

    // 恢复服务器播放队列（如果有）
    if (!state.serverPlayQueue.isEmpty) {
      await _restorePlayQueue(state.serverPlayQueue);
    }
  }

  // 是否正在后台刷新
  bool _isBackgroundRefreshing = false;

  /// 后台静默刷新服务器音乐数据（滚动时触发）
  /// 获取全部数据并与现有数据对比，有变化才更新
  Future<void> refreshServerMusicInBackground() async {
    if (state.sourceMode != MusicSourceMode.server) return;
    if (_isBackgroundRefreshing) return;

    final libraryId = state.currentLibraryId;
    final serverId = state.currentServerId;
    if (libraryId == null || serverId == null) return;

    _isBackgroundRefreshing = true;

    try {
      // 分批获取全部数据
      final allSongs = <LocalSong>[];
      int startIndex = 0;
      int totalCount = 0;
      const batchSize = 100;

      do {
        final result = await _fetchServerMusicListWithTotal(
            libraryId, startIndex, batchSize);
        totalCount = result.totalCount;
        allSongs.addAll(result.songs);
        startIndex += result.songs.length;

        // 如果获取的数量小于请求的数量，说明已经获取完毕
        if (result.songs.length < batchSize) break;
      } while (allSongs.length < totalCount);

      // 只有在仍然是服务器模式时才更新
      if (state.sourceMode == MusicSourceMode.server &&
          state.currentLibraryId == libraryId) {
        // 检查数据是否有变化
        final hasChanges = _hasDataChanges(state.serverSongs, allSongs);

        if (hasChanges) {
          state = state.copyWith(
            songs: allSongs,
            serverSongs: allSongs,
            serverTotalCount: totalCount,
            hasMoreServerSongs: false, // 已经获取全部数据
          );

          // 更新缓存
          await _saveServerMusicCache(
              serverId, libraryId, allSongs, totalCount);
        }
      }
    } catch (e) {
      // 后台刷新失败，静默处理
    } finally {
      _isBackgroundRefreshing = false;
    }
  }

  /// 检查数据是否有变化
  bool _hasDataChanges(List<LocalSong> oldSongs, List<LocalSong> newSongs) {
    if (oldSongs.length != newSongs.length) return true;

    // 简单比较：检查ID列表是否一致
    final oldIds = oldSongs.map((s) => s.id).toSet();
    final newIds = newSongs.map((s) => s.id).toSet();

    return !oldIds.containsAll(newIds) || !newIds.containsAll(oldIds);
  }

  /// 加载更多服务器音乐（首次加载时使用，有缓存时不需要）
  Future<void> loadMoreServerSongs() async {
    if (state.sourceMode != MusicSourceMode.server) return;
    if (state.isLoadingMore) return;
    if (!state.hasMoreServerSongs) return;

    final libraryId = state.currentLibraryId;
    final serverId = state.currentServerId;
    if (libraryId == null || serverId == null) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final currentCount = state.serverSongs.length;
      final result =
          await _fetchServerMusicListWithTotal(libraryId, currentCount, 100);

      final allServerSongs = [...state.serverSongs, ...result.songs];
      final hasMore = allServerSongs.length < result.totalCount;

      state = state.copyWith(
        songs: allServerSongs,
        serverSongs: allServerSongs,
        serverTotalCount: result.totalCount,
        hasMoreServerSongs: hasMore,
        isLoadingMore: false,
      );

      // 更新缓存
      await _saveServerMusicCache(
          serverId, libraryId, allServerSongs, result.totalCount);
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: '加载更多音乐失败: $e',
      );
    }
  }

  /// 从服务器获取音乐列表（带总数）
  Future<({List<LocalSong> songs, int totalCount})>
      _fetchServerMusicListWithTotal(
    String libraryId,
    int startIndex,
    int limit,
  ) async {
    final authAsync = _ref.read(authStateProvider);
    final auth = authAsync.value;
    if (auth == null || !auth.isLoggedIn || auth.userId == null) {
      throw Exception('未登录');
    }

    final api = await EmbyApi.create();

    final result = await api.getItemsByParentWithTotal(
      userId: auth.userId!,
      parentId: libraryId,
      includeItemTypes: 'Audio',
      sortBy: 'SortName',
      sortOrder: 'Ascending',
      startIndex: startIndex,
      limit: limit,
    );

    final songs = <LocalSong>[];
    for (final item in result.items) {
      final song = _convertItemInfoToLocalSong(item, api);
      songs.add(song);
    }

    return (songs: songs, totalCount: result.totalCount ?? 0);
  }

  /// 获取服务器音乐缓存的存储键
  String _getServerMusicCacheKey(String serverId, String libraryId) {
    return 'server_music_${serverId}_$libraryId';
  }

  /// 保存服务器音乐到缓存
  Future<void> _saveServerMusicCache(
    String serverId,
    String libraryId,
    List<LocalSong> songs,
    int totalCount,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getServerMusicCacheKey(serverId, libraryId);

      final cacheData = {
        'songs': songs.map((s) => _localSongToJson(s)).toList(),
        'totalCount': totalCount,
        'cachedAt': DateTime.now().toIso8601String(),
      };

      await prefs.setString(key, jsonEncode(cacheData));
    } catch (e) {
      // 缓存保存失败，静默处理
    }
  }

  /// 从缓存加载服务器音乐
  Future<({List<LocalSong> songs, int totalCount})?> _loadServerMusicCache(
    String serverId,
    String libraryId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getServerMusicCacheKey(serverId, libraryId);

      final cacheJson = prefs.getString(key);
      if (cacheJson == null || cacheJson.isEmpty) {
        return null;
      }

      final cacheData = jsonDecode(cacheJson) as Map<String, dynamic>;
      final songsList = cacheData['songs'] as List<dynamic>;
      final songs = songsList
          .map((json) => _localSongFromJson(json as Map<String, dynamic>))
          .toList();
      final totalCount = cacheData['totalCount'] as int? ?? 0;

      return (songs: songs, totalCount: totalCount);
    } catch (e) {
      return null;
    }
  }

  /// 恢复播放队列（不自动播放，只恢复状态）
  Future<void> _restorePlayQueue(PlayQueueCache cache) async {
    if (cache.isEmpty) return;

    final playerNotifier = _ref.read(localMusicPlayerProvider.notifier);

    // 恢复播放列表状态（不自动播放）
    // 直接设置播放器状态，而不是调用 setPlaylist（那会自动播放）
    await playerNotifier.restorePlayQueue(
      playlist: cache.playlist,
      currentIndex: cache.currentIndex,
      position: cache.position,
    );
  }

  /// 将 ItemInfo 转换为 LocalSong
  LocalSong _convertItemInfoToLocalSong(ItemInfo item, EmbyApi api) {
    // 获取时长（runTimeTicks 是 100纳秒为单位）
    Duration? duration;
    if (item.runTimeTicks != null) {
      duration = Duration(microseconds: item.runTimeTicks! ~/ 10);
    }

    // 获取艺术家（优先使用 artists 字段，其次 albumArtist，最后 performers）
    String artist = '未知艺术家';
    if (item.artists != null && item.artists!.isNotEmpty) {
      artist = item.artists!.join(', ');
    } else if (item.albumArtist != null && item.albumArtist!.isNotEmpty) {
      artist = item.albumArtist!;
    } else if (item.performers != null && item.performers!.isNotEmpty) {
      artist = item.performers!.map((p) => p.name).join(', ');
    }

    // 获取封面图片tag（用于缓存控制）
    String? imageTag;
    if (item.imageTags != null && item.imageTags!['Primary'] != null) {
      imageTag = item.imageTags!['Primary'];
    }

    // 获取专辑封面URL - 直接使用歌曲自己的ID
    // 小尺寸（80x80）用于歌曲列表和迷你播放器
    String? albumArt;
    // 大尺寸（300x300）用于全屏播放页面
    String? albumArtLarge;

    if (item.id != null) {
      albumArt = api.getMusicCoverUrl(item.id!, tag: imageTag);
      albumArtLarge = api.getMusicCoverUrlLarge(item.id!, tag: imageTag);
    }

    // 获取播放URL
    String? playUrl;
    if (item.id != null) {
      playUrl = api.getAudioStreamUrl(item.id!);
    }

    // 获取比特率
    int? bitrate;
    if (item.mediaSources != null && item.mediaSources!.isNotEmpty) {
      final mediaSource = item.mediaSources!.first;
      bitrate = (mediaSource['Bitrate'] as num?)?.toInt();
      if (bitrate != null) {
        bitrate = bitrate ~/ 1000; // 转换为 kbps
      }
    }

    return LocalSong(
      id: item.id ?? '',
      title: item.name,
      artist: artist,
      album: item.album, // 使用专辑字段
      albumArt: albumArt,
      albumArtLarge: albumArtLarge,
      duration: duration,
      path: playUrl,
      bitrate: bitrate,
    );
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
    'albumArtLarge': song.albumArtLarge,
    'lyrics': song.lyrics,
    'bitrate': song.bitrate,
    'bitDepth': song.bitDepth,
    'sampleRate': song.sampleRate,
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
    albumArtLarge: json['albumArtLarge'] as String?,
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

/// Provider
final localMusicStorageProvider =
    StateNotifierProvider<LocalMusicStorageNotifier, LocalMusicStorageState>(
  (ref) => LocalMusicStorageNotifier(ref),
);
