import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emby_api.dart';
import '../services/cache_service.dart';
import 'settings_provider.dart';

const bool _kLibraryProviderLogging = false;
void _libraryLog(String message) {
  if (_kLibraryProviderLogging) {}
}

// ✅ 全局刷新信号：每次媒体状态发生变动时 +1
final libraryRefreshTickerProvider = StateProvider<int>((ref) => 0);

// ✅ 当前用户ID的 Provider（自动跟踪authStateProvider的变化）
final currentUserIdProvider = Provider<String?>((ref) {
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  return auth?.userId;
});

// ✅ 公共 Provider：继续观看（带缓存 + 后台刷新）
final resumeProvider = FutureProvider.autoDispose<List<ItemInfo>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    _libraryLog('resumeProvider: No userId');
    return <ItemInfo>[];
  }

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    _libraryLog('resumeProvider: Not logged in');
    return <ItemInfo>[];
  }

  // ✅ 先尝试从缓存加载
  final cachedItems = await CacheService.loadResumeItems(userId);
  if (cachedItems != null && cachedItems.isNotEmpty) {
    _libraryLog(
        'resumeProvider: ✅ Loaded ${cachedItems.length} items from cache');

    // ✅ 后台更新数据（异步执行，不阻塞）
    _fetchAndCacheResumeItems(userId).then((freshItems) {
      _libraryLog(
          'resumeProvider: 🔄 Fresh data received (${freshItems.length} items), invalidating provider');
      // ✅ 使用 invalidateSelf 触发重新加载
      try {
        ref.invalidateSelf();
      } catch (e) {
        _libraryLog('resumeProvider: ⚠️ Failed to invalidate: $e');
      }
    }).catchError((e) {
      _libraryLog('resumeProvider: ❌ Background fetch failed: $e');
    });

    return cachedItems;
  }

  // ✅ 缓存未命中，直接请求
  _libraryLog('resumeProvider: ❌ Cache miss, fetching from API');
  return await _fetchAndCacheResumeItems(userId);
});

// ✅ 获取并缓存继续观看数据
Future<List<ItemInfo>> _fetchAndCacheResumeItems(String userId) async {
  final api = await EmbyApi.create();
  final items = await api.getResumeItems(userId);
  _libraryLog('resumeProvider: Got ${items.length} resume items from API');

  // ✅ 去重处理：对于同一电视剧（seriesId相同），只保留最近播放的那一集
  final Map<String, ItemInfo> seriesMap = {};
  final List<ItemInfo> movies = [];

  for (final item in items) {
    final seriesId = item.seriesId;

    if (seriesId == null || seriesId.isEmpty) {
      movies.add(item);
      continue;
    }

    if (!seriesMap.containsKey(seriesId)) {
      seriesMap[seriesId] = item;
    } else {
      final existingItem = seriesMap[seriesId]!;
      final existingDate = existingItem.userData?['LastPlayedDate'] as String?;
      final currentDate = item.userData?['LastPlayedDate'] as String?;

      if (currentDate != null &&
          (existingDate == null || currentDate.compareTo(existingDate) > 0)) {
        seriesMap[seriesId] = item;
      }
    }
  }

  final deduplicatedItems = [
    ...seriesMap.values,
    ...movies,
  ];

  deduplicatedItems.sort((a, b) {
    final aDate = a.userData?['LastPlayedDate'] as String?;
    final bDate = b.userData?['LastPlayedDate'] as String?;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });

  _libraryLog(
      'resumeProvider: Deduplicated to ${deduplicatedItems.length} items');

  // ✅ 保存到缓存
  await CacheService.saveResumeItems(userId, deduplicatedItems);

  return deduplicatedItems;
}

// ✅ 公共 Provider：媒体库列表（带缓存 + 后台刷新）
final viewsProvider = FutureProvider.autoDispose<List<ViewInfo>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    _libraryLog('viewsProvider: No userId');
    return <ViewInfo>[];
  }

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    _libraryLog('viewsProvider: Not logged in');
    return <ViewInfo>[];
  }

  // ✅ 先尝试从缓存加载
  final cachedViews = await CacheService.loadViews(userId);
  if (cachedViews != null && cachedViews.isNotEmpty) {
    _libraryLog(
        'viewsProvider: ✅ Loaded ${cachedViews.length} views from cache');

    // ✅ 后台更新数据（异步执行，不阻塞）
    _fetchAndCacheViews(userId).then((freshViews) {
      _libraryLog(
          'viewsProvider: 🔄 Fresh data received (${freshViews.length} views), invalidating provider');
      try {
        ref.invalidateSelf();
      } catch (e) {
        _libraryLog('viewsProvider: ⚠️ Failed to invalidate: $e');
      }
    }).catchError((e) {
      _libraryLog('viewsProvider: ❌ Background fetch failed: $e');
    });

    return cachedViews;
  }

  // ✅ 缓存未命中，直接请求
  _libraryLog('viewsProvider: ❌ Cache miss, fetching from API');
  return await _fetchAndCacheViews(userId);
});

// ✅ 获取并缓存媒体库列表
Future<List<ViewInfo>> _fetchAndCacheViews(String userId) async {
  final api = await EmbyApi.create();
  final views = await api.getUserViews(userId);
  _libraryLog('viewsProvider: Got ${views.length} views from API');

  // ✅ 保存到缓存
  await CacheService.saveViews(userId, views);

  return views;
}

// ✅ 公共 Provider：每个媒体库的最新内容（带缓存 + 后台刷新）
final latestByViewProvider = FutureProvider.autoDispose
    .family<List<ItemInfo>, String>((ref, viewId) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    _libraryLog('latestByViewProvider: No userId for viewId=$viewId');
    return <ItemInfo>[];
  }

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    _libraryLog('latestByViewProvider: Not logged in for viewId=$viewId');
    return <ItemInfo>[];
  }

  // ✅ 先尝试从缓存加载
  final cachedItems = await CacheService.loadLatestItems(userId, viewId);
  if (cachedItems != null && cachedItems.isNotEmpty) {
    _libraryLog(
        'latestByViewProvider: ✅ Loaded ${cachedItems.length} items from cache for viewId=$viewId');

    // ✅ 后台更新数据（异步执行，不阻塞）
    _fetchAndCacheLatestItems(userId, viewId).then((freshItems) {
      _libraryLog(
          'latestByViewProvider: 🔄 Fresh data received (${freshItems.length} items) for viewId=$viewId, invalidating provider');
      try {
        ref.invalidateSelf();
      } catch (e) {
        _libraryLog('latestByViewProvider: ⚠️ Failed to invalidate: $e');
      }
    }).catchError((e) {
      _libraryLog(
          'latestByViewProvider: ❌ Background fetch failed for viewId=$viewId: $e');
    });

    return cachedItems;
  }

  // ✅ 缓存未命中，直接请求
  _libraryLog(
      'latestByViewProvider: ❌ Cache miss for viewId=$viewId, fetching from API');
  return await _fetchAndCacheLatestItems(userId, viewId);
});

// ✅ 获取并缓存最新内容
Future<List<ItemInfo>> _fetchAndCacheLatestItems(
    String userId, String viewId) async {
  final api = await EmbyApi.create();
  final items = await api.getLatestItems(userId, parentId: viewId);
  _libraryLog(
      'latestByViewProvider: Got ${items.length} items from API for viewId=$viewId');

  // ✅ 保存到缓存
  await CacheService.saveLatestItems(userId, viewId, items);

  return items;
}
