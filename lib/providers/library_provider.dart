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
  return items;
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
