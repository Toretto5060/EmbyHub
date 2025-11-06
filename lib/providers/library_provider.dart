import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emby_api.dart';
import 'settings_provider.dart';

// ✅ 缓存数据的 StateProvider（不会自动 dispose）
final cachedViewsProvider = StateProvider<List<ViewInfo>?>((ref) => null);
final cachedResumeProvider = StateProvider<List<ItemInfo>?>((ref) => null);

// ✅ 公共 Provider：继续观看
final resumeProvider = FutureProvider.autoDispose<List<ItemInfo>>((ref) async {
  // 先检查缓存
  final cached = ref.read(cachedResumeProvider);
  if (cached != null) {
    print('resumeProvider: 使用缓存数据 (${cached.length} items)');
    return cached;
  }
  

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    print('resumeProvider: Not logged in');
    return <ItemInfo>[];
  }

  print('resumeProvider: Fetching resume items for userId=${auth.userId}');
  final api = await EmbyApi.create();
  final items = await api.getResumeItems(auth.userId!);
  print('resumeProvider: Got ${items.length} resume items');
  
  // ✅ 保存到缓存
  ref.read(cachedResumeProvider.notifier).state = items;
  
  // ✅ 保持数据在缓存中
  ref.keepAlive();
  
  return items;
});

// ✅ 公共 Provider：媒体库列表
final viewsProvider = FutureProvider.autoDispose<List<ViewInfo>>((ref) async {
  // 先检查缓存
  final cached = ref.read(cachedViewsProvider);
  if (cached != null) {
    print('viewsProvider: 使用缓存数据 (${cached.length} views)');
    return cached;
  }
  

  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    print('viewsProvider: Not logged in');
    return <ViewInfo>[];
  }

  print('viewsProvider: Fetching views for userId=${auth.userId}');
  final api = await EmbyApi.create();
  final views = await api.getUserViews(auth.userId!);
  print('viewsProvider: Got ${views.length} views');
  
  // ✅ 保存到缓存
  ref.read(cachedViewsProvider.notifier).state = views;
  
  // ✅ 保持数据在缓存中
  ref.keepAlive();
  
  return views;
});

// ✅ 公共 Provider：每个媒体库的最新内容
final latestByViewProvider = FutureProvider.autoDispose
    .family<List<ItemInfo>, String>((ref, viewId) async {
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  if (auth == null || !auth.isLoggedIn) {
    print('latestByViewProvider: Not logged in for viewId=$viewId');
    return <ItemInfo>[];
  }

  print('latestByViewProvider: Fetching latest items for viewId=$viewId');
  final api = await EmbyApi.create();
  final items = await api.getLatestItems(auth.userId!, parentId: viewId);
  print('latestByViewProvider: Got ${items.length} items for viewId=$viewId');
  
  // ✅ 保持数据在缓存中
  ref.keepAlive();
  
  return items;
});

