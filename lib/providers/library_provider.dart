import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emby_api.dart';
import 'settings_provider.dart';

// ✅ 缓存数据的 StateProvider（按用户ID分别缓存，不会自动 dispose）
final cachedViewsProvider = StateProvider<Map<String, List<ViewInfo>>>((ref) => {});
final cachedResumeProvider = StateProvider<Map<String, List<ItemInfo>>>((ref) => {});

// ✅ 当前用户ID的 Provider（自动跟踪authStateProvider的变化）
final currentUserIdProvider = Provider<String?>((ref) {
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  return auth?.userId;
});

// ✅ 公共 Provider：继续观看
final resumeProvider = FutureProvider.autoDispose<List<ItemInfo>>((ref) async {
  // ✅ 监听用户ID变化，当用户ID变化时此provider会自动重新构建
  final userId = ref.watch(currentUserIdProvider);
  
  if (userId == null) {
    print('resumeProvider: No userId');
    return <ItemInfo>[];
  }
  
  // 先检查该用户的缓存
  final cacheMap = ref.read(cachedResumeProvider);
  final cached = cacheMap[userId];
  if (cached != null) {
    print('resumeProvider: 使用缓存数据 for user $userId (${cached.length} items)');
    return cached;
  }
  

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    print('resumeProvider: Not logged in');
    return <ItemInfo>[];
  }

  print('resumeProvider: Fetching resume items for userId=$userId');
  final api = await EmbyApi.create();
  final items = await api.getResumeItems(userId);
  print('resumeProvider: Got ${items.length} resume items');
  
  // ✅ 保存到该用户的缓存
  final newCache = {...cacheMap};
  newCache[userId] = items;
  ref.read(cachedResumeProvider.notifier).state = newCache;
  
  // ✅ 保持数据在缓存中
  ref.keepAlive();
  
  return items;
});

// ✅ 公共 Provider：媒体库列表
final viewsProvider = FutureProvider.autoDispose<List<ViewInfo>>((ref) async {
  // ✅ 监听用户ID变化，当用户ID变化时此provider会自动重新构建
  final userId = ref.watch(currentUserIdProvider);
  
  if (userId == null) {
    print('viewsProvider: No userId');
    return <ViewInfo>[];
  }
  
  // 先检查该用户的缓存
  final cacheMap = ref.read(cachedViewsProvider);
  final cached = cacheMap[userId];
  if (cached != null) {
    print('viewsProvider: 使用缓存数据 for user $userId (${cached.length} views)');
    return cached;
  }
  

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    print('viewsProvider: Not logged in');
    return <ViewInfo>[];
  }

  print('viewsProvider: Fetching views for userId=$userId');
  final api = await EmbyApi.create();
  final views = await api.getUserViews(userId);
  print('viewsProvider: Got ${views.length} views');
  
  // ✅ 保存到该用户的缓存
  final newCache = {...cacheMap};
  newCache[userId] = views;
  ref.read(cachedViewsProvider.notifier).state = newCache;
  
  // ✅ 保持数据在缓存中
  ref.keepAlive();
  
  return views;
});

// ✅ 公共 Provider：每个媒体库的最新内容
final latestByViewProvider = FutureProvider.autoDispose
    .family<List<ItemInfo>, String>((ref, viewId) async {
  // ✅ 监听用户ID变化，当用户ID变化时此provider会自动重新构建
  final userId = ref.watch(currentUserIdProvider);
  
  if (userId == null) {
    print('latestByViewProvider: No userId for viewId=$viewId');
    return <ItemInfo>[];
  }
  
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    print('latestByViewProvider: Not logged in for viewId=$viewId');
    return <ItemInfo>[];
  }

  print('latestByViewProvider: Fetching latest items for userId=$userId, viewId=$viewId');
  final api = await EmbyApi.create();
  final items = await api.getLatestItems(userId, parentId: viewId);
  print('latestByViewProvider: Got ${items.length} items for viewId=$viewId');
  
  // ✅ 保持数据在缓存中
  ref.keepAlive();
  
  return items;
});

