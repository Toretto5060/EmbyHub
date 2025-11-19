import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emby_api.dart';
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

// ✅ 公共 Provider：继续观看
final resumeProvider = FutureProvider.autoDispose<List<ItemInfo>>((ref) async {
  ref.watch(libraryRefreshTickerProvider);
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

  _libraryLog('resumeProvider: Fetching resume items for userId=$userId');
  final api = await EmbyApi.create();
  final items = await api.getResumeItems(userId);
  _libraryLog('resumeProvider: Got ${items.length} resume items');
  
  // ✅ 去重处理：对于同一电视剧（seriesId相同），只保留最近播放的那一集
  final Map<String, ItemInfo> seriesMap = {}; // seriesId -> 最近播放的集
  final List<ItemInfo> movies = []; // 电影（没有seriesId）
  
  for (final item in items) {
    final seriesId = item.seriesId;
    
    // 如果是电影（没有seriesId），直接添加
    if (seriesId == null || seriesId.isEmpty) {
      movies.add(item);
      continue;
    }
    
    // 如果是电视剧的集，检查是否已有该电视剧的记录
    if (!seriesMap.containsKey(seriesId)) {
      // 第一次遇到这个电视剧，直接添加
      seriesMap[seriesId] = item;
    } else {
      // 已有该电视剧的记录，比较播放日期，保留最近播放的
      final existingItem = seriesMap[seriesId]!;
      final existingDate = existingItem.userData?['LastPlayedDate'] as String?;
      final currentDate = item.userData?['LastPlayedDate'] as String?;
      
      // 如果当前集的播放日期更近，则替换
      if (currentDate != null && 
          (existingDate == null || currentDate.compareTo(existingDate) > 0)) {
        seriesMap[seriesId] = item;
      }
    }
  }
  
  // ✅ 合并结果：先显示电视剧（按播放日期排序），再显示电影
  final deduplicatedItems = [
    ...seriesMap.values,
    ...movies,
  ];
  
  // ✅ 按播放日期排序（最近的在前）
  deduplicatedItems.sort((a, b) {
    final aDate = a.userData?['LastPlayedDate'] as String?;
    final bDate = b.userData?['LastPlayedDate'] as String?;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate); // 降序：最近的在前
  });
  
  _libraryLog('resumeProvider: Deduplicated to ${deduplicatedItems.length} items');
  return deduplicatedItems;
});

// ✅ 公共 Provider：媒体库列表
final viewsProvider = FutureProvider.autoDispose<List<ViewInfo>>((ref) async {
  ref.watch(libraryRefreshTickerProvider);
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

  _libraryLog('viewsProvider: Fetching views for userId=$userId');
  final api = await EmbyApi.create();
  final views = await api.getUserViews(userId);
  _libraryLog('viewsProvider: Got ${views.length} views');
  return views;
});

// ✅ 公共 Provider：每个媒体库的最新内容
final latestByViewProvider = FutureProvider.autoDispose
    .family<List<ItemInfo>, String>((ref, viewId) async {
  ref.watch(libraryRefreshTickerProvider);
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

  _libraryLog(
      'latestByViewProvider: Fetching latest items for userId=$userId, viewId=$viewId');
  final api = await EmbyApi.create();
  final items = await api.getLatestItems(userId, parentId: viewId);
  _libraryLog(
      'latestByViewProvider: Got ${items.length} items for viewId=$viewId');
  return items;
});
