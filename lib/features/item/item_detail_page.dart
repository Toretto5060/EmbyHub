import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/status_bar_manager.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../utils/app_route_observer.dart';
import '../../utils/theme_utils.dart';
import '../../services/cache_service.dart';
import '../../utils/debounce_helper.dart';

final itemProvider =
    FutureProvider.family<ItemInfo, String>((ref, itemId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }

  // ✅ 先尝试从缓存加载
  final cachedItem = await CacheService.loadItemDetail(auth.userId!, itemId);
  if (cachedItem != null) {
    // ✅ 有缓存，立即返回，同时后台更新（不传 ref，避免循环依赖）
    _fetchAndCacheItemDetail(auth.userId!, itemId);
    return cachedItem;
  }

  // ✅ 无缓存，从 API 获取并保存
  final api = await EmbyApi.create();
  final item = await api.getItem(auth.userId!, itemId);
  await CacheService.saveItemDetail(auth.userId!, itemId, item);
  return item;
});

/// ✅ 后台获取并缓存详情数据
/// 注意：不使用 ref.invalidate，避免循环依赖
/// 缓存会在下次进入页面时自动使用最新数据
/// 使用防抖机制，避免频繁更新
Future<void> _fetchAndCacheItemDetail(String userId, String itemId) async {
  try {
    // ✅ 防抖：如果 10 秒内已经更新过，跳过
    final key = 'item_detail_${userId}_$itemId';
    if (!DebounceHelper.shouldExecute(key)) {
      return;
    }

    final api = await EmbyApi.create();
    final item = await api.getItem(userId, itemId);
    await CacheService.saveItemDetail(userId, itemId, item);
    // ✅ 不调用 invalidate，避免循环依赖
    // 缓存已更新，下次进入页面会自动使用新数据
  } catch (e) {
    // 后台更新失败不影响用户体验
  }
}

final similarItemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, itemId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return const [];
  }

  // ✅ 优化2：先尝试从缓存加载
  final cachedItems = await CacheService.loadSimilarItems(auth.userId!, itemId);
  if (cachedItems != null) {
    // ✅ 有缓存，立即返回，同时后台更新
    _fetchAndCacheSimilarItems(auth.userId!, itemId);
    return cachedItems;
  }

  // ✅ 无缓存，从 API 获取并保存
  final api = await ref.watch(embyApiProvider.future);
  final items = await api.getSimilarItems(auth.userId!, itemId, limit: 12);
  await CacheService.saveSimilarItems(auth.userId!, itemId, items);
  return items;
});

/// ✅ 后台获取并缓存相似影片数据
Future<void> _fetchAndCacheSimilarItems(String userId, String itemId) async {
  try {
    final key = 'similar_items_${userId}_$itemId';
    if (!DebounceHelper.shouldExecute(key)) {
      return;
    }

    final api = await EmbyApi.create();
    final items = await api.getSimilarItems(userId, itemId, limit: 12);
    await CacheService.saveSimilarItems(userId, itemId, items);
  } catch (e) {
    // 后台更新失败不影响用户体验
  }
}

// ✅ 获取合集内的影片
final collectionItemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, collectionId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return const [];
  }

  // ✅ 优化7：先尝试从缓存加载
  final cachedItems =
      await CacheService.loadCollectionItems(auth.userId!, collectionId);
  if (cachedItems != null) {
    // ✅ 有缓存，立即返回，同时后台更新
    _fetchAndCacheCollectionItems(auth.userId!, collectionId);
    return cachedItems;
  }

  // ✅ 无缓存，从 API 获取并保存
  final api = await ref.watch(embyApiProvider.future);
  try {
    final items = await api.getItemsByParent(
      userId: auth.userId!,
      parentId: collectionId,
      includeItemTypes: 'Movie',
      limit: 100,
    );
    await CacheService.saveCollectionItems(auth.userId!, collectionId, items);
    return items;
  } catch (e) {
    return const [];
  }
});

/// ✅ 后台获取并缓存合集影片数据
Future<void> _fetchAndCacheCollectionItems(
    String userId, String collectionId) async {
  try {
    final key = 'collection_items_${userId}_$collectionId';
    if (!DebounceHelper.shouldExecute(key)) {
      return;
    }

    final api = await EmbyApi.create();
    final items = await api.getItemsByParent(
      userId: userId,
      parentId: collectionId,
      includeItemTypes: 'Movie',
      limit: 100,
    );
    await CacheService.saveCollectionItems(userId, collectionId, items);
  } catch (e) {
    // 后台更新失败不影响用户体验
  }
}

class ItemDetailPage extends ConsumerStatefulWidget {
  const ItemDetailPage({required this.itemId, super.key});
  final String itemId;

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage>
    with RouteAware, WidgetsBindingObserver {
  final _scrollController = ScrollController();
  static const SystemUiOverlayStyle _lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );
  static const SystemUiOverlayStyle _darkStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  late SystemUiOverlayStyle _statusBarStyle;
  final _LRUCache<String, SystemUiOverlayStyle> _imageStyleCache =
      _LRUCache(50);
  late ValueNotifier<SystemUiOverlayStyle?> _navSyncedStyleNotifier;
  late ValueNotifier<double> _scrollOffsetNotifier; // ✅ 用于实时更新毛玻璃效果
  int? _selectedAudioStreamIndex;
  int? _selectedSubtitleStreamIndex;
  bool _hasManuallySelectedSubtitle = false; // ✅ 标记用户是否手动选择过字幕
  bool _hasManuallySelectedAudio = false; // ✅ 标记用户是否手动选择过音频
  // ✅ 使用 ValueNotifier 来局部更新字幕选择显示
  late final ValueNotifier<int?> _subtitleIndexNotifier;
  bool _isLoadingStreamSelections = false; // ✅ 标记是否正在加载保存的选择
  // ✅ 使用 ValueNotifier 来局部更新收藏和观看状态
  ValueNotifier<bool>? _isFavoriteNotifier;
  ValueNotifier<bool>? _isPlayedNotifier;
  ValueNotifier<Map<String, dynamic>?>? _userDataNotifier;
  final GlobalKey _resumeMenuAnchorKey = GlobalKey();
  static const Color _resumeButtonColor = Color(0xFFFFB74D);
  static const Color _playButtonColor = Color(0xFF3F8CFF);
  static const double _backdropHeight = 300;
  StatusBarStyleController? _statusBarController;
  ModalRoute<dynamic>? _modalRoute;
  Animation<double>? _routeAnimation;
  bool _isRouteSubscribed = false; // ✅ 路由订阅状态
  String? _lastItemDataHash; // ✅ 记录上次 item 数据的哈希，用于检测数据变化
  ItemInfo? _cachedItemData; // ✅ 缓存item数据，避免重新加载时显示loading

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ✅ 初始化字幕选择 ValueNotifier
    _subtitleIndexNotifier = ValueNotifier<int?>(null);
    // ✅ 初始化收藏和观看状态 ValueNotifier
    _isFavoriteNotifier = ValueNotifier<bool>(false);
    _isPlayedNotifier = ValueNotifier<bool>(false);
    _userDataNotifier = ValueNotifier<Map<String, dynamic>?>(null);
    // ✅ 初始化状态栏样式 ValueNotifier
    _navSyncedStyleNotifier = ValueNotifier<SystemUiOverlayStyle?>(null);
    // ✅ 初始化滚动偏移量 ValueNotifier
    _scrollOffsetNotifier = ValueNotifier<double>(0.0);
    // ✅ 默认使用亮色状态栏（白色字体），因为大多数背景图都比较暗
    // 等背景图加载完成后，会根据实际图片颜色动态调整
    _statusBarStyle = StatusBarManager.currentStyle ?? _lightStatusBar;
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncStatusBarWithNavigation(
          _scrollController.hasClients ? _scrollController.offset : 0.0);
    });
    // ✅ 加载保存的音频和字幕选择
    _loadStreamSelections();
  }

  /// ✅ 加载保存的音频和字幕选择
  Future<void> _loadStreamSelections() async {
    try {
      _isLoadingStreamSelections = true;
      final prefs = await SharedPreferences.getInstance();
      final hasManualAudio =
          prefs.getBool('item_${widget.itemId}_manual_audio') ?? false;
      final hasManualSubtitle =
          prefs.getBool('item_${widget.itemId}_manual_subtitle') ?? false;

      // ✅ 先设置标记，防止在加载完成前被覆盖
      if (mounted && hasManualSubtitle) {
        setState(() {
          _hasManuallySelectedSubtitle = true;
        });
      }
      if (mounted && hasManualAudio) {
        setState(() {
          _hasManuallySelectedAudio = true;
        });
      }

      // ✅ 只有手动选择过才加载保存的值
      final audioIndex =
          hasManualAudio ? prefs.getInt('item_${widget.itemId}_audio') : null;
      final subtitleIndex = prefs.getInt('item_${widget.itemId}_subtitle');

      if (mounted) {
        setState(() {
          _selectedAudioStreamIndex = audioIndex;
          _selectedSubtitleStreamIndex = subtitleIndex;
        });
        // ✅ 同时更新 ValueNotifier，触发局部更新
        _subtitleIndexNotifier.value = subtitleIndex;
      }
    } catch (e) {
    } finally {
      _isLoadingStreamSelections = false;
    }
  }

  /// ✅ 保存音频和字幕选择
  Future<void> _saveStreamSelections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedAudioStreamIndex != null) {
        await prefs.setInt(
            'item_${widget.itemId}_audio', _selectedAudioStreamIndex!);
      }
      if (_selectedSubtitleStreamIndex != null) {
        await prefs.setInt(
            'item_${widget.itemId}_subtitle', _selectedSubtitleStreamIndex!);
      }
      await prefs.setBool(
          'item_${widget.itemId}_manual_audio', _hasManuallySelectedAudio);
      await prefs.setBool('item_${widget.itemId}_manual_subtitle',
          _hasManuallySelectedSubtitle);
    } catch (e) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newRoute = ModalRoute.of(context);
    if (newRoute != _modalRoute) {
      _removeRouteListener();
      _modalRoute = newRoute;
      _routeAnimation = newRoute?.animation;
      _routeAnimation?.addStatusListener(_handleRouteAnimationStatus);
    }
    // ✅ 订阅路由观察者
    if (!_isRouteSubscribed && _modalRoute != null) {
      appRouteObserver.subscribe(this, _modalRoute!);
      _isRouteSubscribed = true;
    }
  }

  @override
  void deactivate() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _statusBarController?.release();
      _statusBarController = null;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ✅ 取消订阅路由观察者
    if (_isRouteSubscribed) {
      appRouteObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    // ✅ 释放 ValueNotifier
    _subtitleIndexNotifier.dispose();
    _isFavoriteNotifier?.dispose();
    _isPlayedNotifier?.dispose();
    _userDataNotifier?.dispose();
    _navSyncedStyleNotifier.dispose();
    _scrollOffsetNotifier.dispose();
    _statusBarController?.release();
    _statusBarController = null;
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _removeRouteListener();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // ✅ 当应用从后台切回前台时，刷新数据
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    // ✅ 使用 microtask 立即刷新，而不是等待下一帧
    Future.microtask(() async {
      if (!mounted) return;

      // ✅ 清除防抖记录，确保能立即刷新
      final auth = ref.read(authStateProvider).value;
      if (auth != null && auth.isLoggedIn) {
        DebounceHelper.clear('item_detail_${auth.userId}_${widget.itemId}');
        DebounceHelper.clear('similar_items_${auth.userId}_${widget.itemId}');

        // ✅ 清除缓存，强制从API获取最新数据
        await CacheService.saveItemDetail(
            auth.userId!,
            widget.itemId,
            await EmbyApi.create()
                .then((api) => api.getItem(auth.userId!, widget.itemId)));
      }

      // ✅ 使用 refresh 而不是 invalidate，确保立即重新加载
      // ignore: unused_result
      ref.refresh(itemProvider(widget.itemId));
      // ignore: unused_result
      ref.refresh(similarItemsProvider(widget.itemId));
      // ✅ 如果 item 是合集类型（BoxSet），也刷新 collectionItemsProvider
      final itemAsync = ref.read(itemProvider(widget.itemId));
      itemAsync.whenData((item) {
        if (item.type == 'BoxSet' && item.id != null && item.id!.isNotEmpty) {
          DebounceHelper.clear('collection_items_${auth?.userId}_${item.id}');
          // ignore: unused_result
          ref.refresh(collectionItemsProvider(item.id!));
        }
      });
    });
  }

  @override
  void didPush() {
    super.didPush();
    _scheduleRefresh();
  }

  // ✅ 当从其他页面返回时，刷新数据
  @override
  void didPopNext() {
    super.didPopNext();
  }

  /// ✅ 刷新字幕和音频选择（局部更新）
  Future<void> _refreshStreamSelections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ✅ 重新加载 SharedPreferences 确保获取最新值
      await prefs.reload();

      // ✅ 读取字幕选择
      int? subtitleIndex = prefs.getInt('item_${widget.itemId}_subtitle');
      bool hasManualSubtitle =
          prefs.getBool('item_${widget.itemId}_manual_subtitle') ?? false;

      // ✅ 读取音频选择
      bool hasManualAudio =
          prefs.getBool('item_${widget.itemId}_manual_audio') ?? false;
      int? audioIndex =
          hasManualAudio ? prefs.getInt('item_${widget.itemId}_audio') : null;

      // ✅ 如果第一次读取时没有找到值，可能是保存还没完成，重新加载一次
      if ((!hasManualSubtitle && subtitleIndex == null) ||
          (!hasManualAudio && audioIndex == null)) {
        await prefs.reload();
        subtitleIndex = prefs.getInt('item_${widget.itemId}_subtitle');
        hasManualSubtitle =
            prefs.getBool('item_${widget.itemId}_manual_subtitle') ?? false;
        hasManualAudio =
            prefs.getBool('item_${widget.itemId}_manual_audio') ?? false;
        audioIndex =
            hasManualAudio ? prefs.getInt('item_${widget.itemId}_audio') : null;
      }

      if (mounted) {
        // ✅ 更新字幕选择
        _hasManuallySelectedSubtitle = hasManualSubtitle;
        _selectedSubtitleStreamIndex = subtitleIndex;
        _subtitleIndexNotifier.value = subtitleIndex;

        // ✅ 更新音频选择
        _hasManuallySelectedAudio = hasManualAudio;
        _selectedAudioStreamIndex = audioIndex;

        // ✅ 触发 UI 更新（音频选择通过 setState 更新，字幕选择通过 ValueNotifier 更新）
        setState(() {
          // setState 会触发整个 _buildMediaInfo 重建，从而更新音频显示
        });
      }
    } catch (e) {}
  }

  void _handleScroll() {
    if (!mounted) return;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    // ✅ 更新滚动偏移量 ValueNotifier，触发毛玻璃效果更新
    _scrollOffsetNotifier.value = offset;
    // ✅ 使用节流，避免频繁更新状态栏
    _syncStatusBarWithNavigationThrottled(offset);
  }

  double? _lastSyncOffset;
  void _syncStatusBarWithNavigationThrottled(double offset) {
    // ✅ 如果偏移量变化小于10像素，跳过更新
    if (_lastSyncOffset != null && (offset - _lastSyncOffset!).abs() < 10) {
      return;
    }
    _lastSyncOffset = offset;
    _syncStatusBarWithNavigation(offset);
  }

  // ✅ 防止在 API 调用期间被 whenData 覆盖状态
  bool _isUpdatingFavorite = false;
  bool _isUpdatingPlayed = false;

  DateTime? _lastRefreshTime;
  bool _hasTriggeredReturnRefresh = false;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(itemProvider(widget.itemId));

    // ✅ 在 build 方法中检测路由是否重新变为当前（从其他页面返回）
    final route = ModalRoute.of(context);
    final isRouteCurrent = route?.isCurrent ?? false;

    // ✅ 检测是否从其他页面返回（路由变为当前，且距离上次刷新超过1秒）
    if (isRouteCurrent && _isRouteSubscribed) {
      final now = DateTime.now();
      if (_lastRefreshTime == null ||
          now.difference(_lastRefreshTime!) > const Duration(seconds: 1)) {
        // ✅ 检查是否真的从其他页面返回（通过检查路由动画状态）
        if (!_hasTriggeredReturnRefresh) {
          _hasTriggeredReturnRefresh = true;
          _lastRefreshTime = now;
          // ✅ 延迟刷新，确保屏幕旋转完成
          Future.delayed(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            _refreshStreamSelections();
            _scheduleRefresh();
            // ✅ 重置标记，允许下次检测
            Future.delayed(const Duration(seconds: 2), () {
              _hasTriggeredReturnRefresh = false;
            });
          });
        }
      }
    }

    // ✅ 当 itemProvider 重新加载数据时（比如从播放页面返回时），顺便刷新字幕和音频选择
    // 检测数据变化：当数据有值且与上次不同时，刷新字幕和音频选择
    item.whenData((data) {
      // ✅ 缓存数据，避免重新加载时显示loading
      _cachedItemData = data;

      // ✅ 同步更新 ValueNotifier（但在 API 调用期间不更新，避免覆盖用户操作）
      if (!_isUpdatingFavorite) {
        _isFavoriteNotifier?.value =
            (data.userData?['IsFavorite'] as bool?) ?? false;
      }
      if (!_isUpdatingPlayed) {
        _isPlayedNotifier?.value = (data.userData?['Played'] as bool?) ?? false;
        _userDataNotifier?.value = data.userData;
      }

      // ✅ 使用 userData 的播放进度作为数据变化的标识
      final playbackTicks =
          (data.userData?['PlaybackPositionTicks'] as num?)?.toInt();
      final currentHash = '${data.id}_${playbackTicks ?? 0}';

      // ✅ 如果数据发生变化（不是首次加载），立即刷新字幕和音频选择（不使用 postFrameCallback，减少延迟）
      if (_lastItemDataHash != null && _lastItemDataHash != currentHash) {
        // ✅ 直接调用，不使用 postFrameCallback，减少延迟
        _refreshStreamSelections();
      }

      // ✅ 更新哈希值
      _lastItemDataHash = currentHash;
      _lastItemDataHash = currentHash;
    });

    return StatusBarStyleScope(
      style: _statusBarStyle,
      child: Builder(
        builder: (context) {
          _statusBarController = StatusBarStyleScope.of(context);
          // ✅ 使用 addPostFrameCallback 延迟更新，避免在 build 期间调用 setState
          final styleToApply = _navSyncedStyleNotifier.value ?? _statusBarStyle;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _statusBarController?.update(styleToApply);
            }
          });
          return CupertinoPageScaffold(
            backgroundColor: CupertinoColors.systemBackground,
            // ✅ 不再显示整体 loading，直接构建内容区域
            child: _buildContentAreaWithBackdrop(item),
          );
        },
      ),
    );
  }

  /// ✅ 构建带背景图的内容区域（优先加载背景图）
  Widget _buildContentAreaWithBackdrop(AsyncValue<ItemInfo> itemAsync) {
    // ✅ 使用 Builder 获取 isDark
    return Builder(
      builder: (context) {
        final isDark = isDarkModeFromContext(context, ref);

        return CustomScrollView(
          controller: _scrollController,
          cacheExtent: 500,
          slivers: [
            // ✅ 背景图独立加载，不依赖 itemProvider
            ValueListenableBuilder<SystemUiOverlayStyle?>(
              valueListenable: _navSyncedStyleNotifier,
              builder: (context, navSyncedStyle, child) {
                return SliverAppBar(
                  expandedHeight: _backdropHeight - 40,
                  pinned: true,
                  stretch: true,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  systemOverlayStyle: navSyncedStyle ?? _statusBarStyle,
                  leading: LayoutBuilder(
                    builder: (context, constraints) {
                      final settings =
                          context.dependOnInheritedWidgetOfExactType<
                              FlexibleSpaceBarSettings>();
                      final deltaExtent = settings != null
                          ? settings.maxExtent - settings.minExtent
                          : 1.0;
                      final t = settings != null && deltaExtent > 0
                          ? (1.0 -
                                  (settings.currentExtent -
                                          settings.minExtent) /
                                      deltaExtent)
                              .clamp(0.0, 1.0)
                          : 0.0;

                      final brightness =
                          getCurrentBrightnessFromContext(context, ref);
                      final expandedStyle = _statusBarStyle;
                      final collapsedStyle =
                          _defaultStyleForBrightness(brightness);
                      final targetStyle =
                          t < 0.55 ? expandedStyle : collapsedStyle;
                      final iconColor =
                          _colorForStatusStyle(targetStyle, brightness);

                      return buildBlurBackButton(context, color: iconColor);
                    },
                  ),
                  actions: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final settings =
                            context.dependOnInheritedWidgetOfExactType<
                                FlexibleSpaceBarSettings>();
                        final deltaExtent = settings != null
                            ? settings.maxExtent - settings.minExtent
                            : 1.0;
                        final t = settings != null && deltaExtent > 0
                            ? (1.0 -
                                    (settings.currentExtent -
                                            settings.minExtent) /
                                        deltaExtent)
                                .clamp(0.0, 1.0)
                            : 0.0;

                        final brightness =
                            getCurrentBrightnessFromContext(context, ref);
                        final expandedStyle = _statusBarStyle;
                        final collapsedStyle =
                            _defaultStyleForBrightness(brightness);
                        final targetStyle =
                            t < 0.55 ? expandedStyle : collapsedStyle;
                        final iconColor =
                            _colorForStatusStyle(targetStyle, brightness);

                        // ✅ 如果数据还没加载完成，显示占位按钮
                        return itemAsync.maybeWhen(
                          data: (data) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _buildTopActions(data, iconColor),
                          ),
                          orElse: () => const SizedBox(width: 44, height: 44),
                        );
                      },
                    ),
                  ],
                  flexibleSpace:
                      _buildFlexibleSpaceWithBackdrop(itemAsync, isDark),
                );
              },
            ),
            // ✅ 主要内容区域（延迟加载）
            itemAsync.when(
              data: (data) => _buildMainContent(data, isDark),
              loading: () {
                // ✅ 如果有缓存数据，显示缓存数据
                if (_cachedItemData != null) {
                  return _buildMainContent(_cachedItemData!, isDark);
                }
                // ✅ 没有缓存数据，显示空白区域（不显示 loading）
                return const SliverToBoxAdapter(
                  child: SizedBox.shrink(),
                );
              },
              error: (e, _) => SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('加载失败: $e'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// ✅ 构建 FlexibleSpace（包含背景图、毛玻璃、标题）
  Widget _buildFlexibleSpaceWithBackdrop(
      AsyncValue<ItemInfo> itemAsync, bool isDark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ✅ 底层：FlexibleSpaceBar（背景图优先加载）
        FlexibleSpaceBar(
          collapseMode: CollapseMode.pin,
          titlePadding: EdgeInsets.zero,
          centerTitle: false,
          title: const SizedBox.shrink(),
          background: _buildBackdropBackgroundAsync(itemAsync),
        ),
        // ✅ 中层：毛玻璃效果
        ValueListenableBuilder<double>(
          valueListenable: _scrollOffsetNotifier,
          builder: (context, scrollOffset, child) {
            const double blurStart = 10.0;
            const double blurEnd = 250.0;
            final double blurProgress;
            if (scrollOffset <= blurStart) {
              blurProgress = 0.0;
            } else {
              final double effective =
                  (scrollOffset - blurStart).clamp(0.0, blurEnd - blurStart);
              blurProgress =
                  (effective / (blurEnd - blurStart)).clamp(0.0, 1.0);
            }
            final blurSigma = 30.0 * blurProgress;
            final bgOpacity = 0.7 * blurProgress;
            final baseColor =
                isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

            final statusBarHeight = MediaQuery.of(context).padding.top;
            final navBarHeight = kToolbarHeight;
            final totalHeight = statusBarHeight + navBarHeight;

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: totalHeight,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: baseColor.withOpacity(bgOpacity),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // ✅ 上层：标题
        itemAsync.maybeWhen(
          data: (data) => _buildTitleOverlay(data, isDark),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// ✅ 构建背景图（异步加载，不依赖完整的 item 数据）
  Widget _buildBackdropBackgroundAsync(AsyncValue<ItemInfo> itemAsync) {
    return RepaintBoundary(
      child: Builder(
        builder: (context) {
          // ✅ 获取系统背景色
          final isDark = isDarkModeFromContext(context, ref);
          final systemBgColor = isDark
              ? const Color(0xFF000000) // 深色模式：纯黑色
              : const Color(0xFFFFFFFF); // 浅色模式：纯白色

          return FutureBuilder<EmbyApi>(
            future: EmbyApi.create(),
            builder: (context, apiSnapshot) {
              if (!apiSnapshot.hasData) {
                // ✅ 使用系统背景色，而不是灰色
                return Container(color: systemBgColor);
              }

              final api = apiSnapshot.data!;

              // ✅ 优先使用缓存数据，如果没有则等待 itemAsync
              final item = _cachedItemData ?? itemAsync.valueOrNull;

              if (item == null || item.id == null) {
                // ✅ 使用系统背景色
                return Container(color: systemBgColor);
              }

              String? backdropUrl;

              // ✅ 使用 getBackdropUrl 方法，确保与预加载的 URL 一致
              backdropUrl = item.getBackdropUrl(api);

              if (backdropUrl == null || backdropUrl.isEmpty) {
                final primaryTag = item.imageTags?['Primary'] ?? '';
                if (primaryTag.isNotEmpty) {
                  backdropUrl = api.buildImageUrl(
                    itemId: item.id!,
                    type: 'Primary',
                    maxWidth: 800,
                  );
                }
              }

              if (backdropUrl == null || backdropUrl.isEmpty) {
                // ✅ 使用系统背景色
                return Container(color: systemBgColor);
              }

              final bottomColor = systemBgColor;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // ✅ 底层：系统背景色
                  Container(color: systemBgColor),
                  // ✅ 图片层
                  EmbyFadeInImage(
                    key: ValueKey('backdrop_${item.id}_$backdropUrl'),
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    onImageReady: (image) =>
                        _handleBackdropImage(image, item.id ?? backdropUrl!),
                  ),
                  // ✅ 渐变遮罩层
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            bottomColor.withOpacity(0.1),
                            bottomColor.withOpacity(0.2),
                            bottomColor.withOpacity(0.4),
                            bottomColor.withOpacity(0.6),
                            bottomColor.withOpacity(0.8),
                            bottomColor,
                          ],
                          stops: const [0.0, 0.2, 0.35, 0.5, 0.65, 0.85, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// ✅ 构建标题覆盖层
  Widget _buildTitleOverlay(ItemInfo data, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
        if (settings == null) {
          return const SizedBox.shrink();
        }
        final deltaExtent = settings.maxExtent - settings.minExtent;
        final t = deltaExtent > 0
            ? (1.0 -
                    (settings.currentExtent - settings.minExtent) / deltaExtent)
                .clamp(0.0, 1.0)
            : 1.0;

        final sizeProgress = Curves.easeInOut.transform(t);
        final fontSize = 28.0 - (28.0 - 17.0) * sizeProgress;

        final horizontalProgress = Curves.easeInOutCubic.transform(t);
        final verticalProgress = Curves.easeOut.transform(t);
        final leftPadding = 20.0 + (56.0 - 40.0) * horizontalProgress;
        final bottomPadding = 10 + 9.0 * verticalProgress;

        final titleColor = isDark ? Colors.white : Colors.black87;

        final hasLogo = data.imageTags?['Logo'] != null &&
            data.imageTags!['Logo']!.isNotEmpty;

        return Container(
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.only(
            left: leftPadding,
            right: 20,
            bottom: bottomPadding,
          ),
          child: hasLogo
              ? _buildLogoToTextTransition(data, t, fontSize, titleColor)
              : Text(
                  data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    height: 1.2,
                  ),
                ),
        );
      },
    );
  }

  /// ✅ 构建主要内容（演员、相似影片等）
  Widget _buildMainContent(ItemInfo data, bool isDark) {
    final performers = data.performers ?? const <PerformerInfo>[];
    final externalLinks = _composeExternalLinks(data);
    final similarItems = ref.watch(similarItemsProvider(widget.itemId));

    return SliverToBoxAdapter(
      child: Stack(
        children: [
          Container(
            color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 头部信息卡片
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetaInfo(data, isDark),
                      const SizedBox(height: 5),
                      _buildMediaInfo(data, isDark),
                      const SizedBox(height: 18),
                      _buildPlaySection(context, data, isDark),
                      if ((data.overview ?? '').isNotEmpty) ...[
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: () => _showOverviewDialog(data),
                          child: Text(
                            data.overview!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // ✅ 演员列表
                if (performers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '演员',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      scrollDirection: Axis.horizontal,
                      itemCount: performers.length,
                      cacheExtent: 300,
                      itemBuilder: (context, index) {
                        final card = _PerformerCard(
                          key: ValueKey(
                              'performer_card_${performers[index].id}'),
                          performer: performers[index],
                          isDark: isDark,
                        );
                        final bool isFirst = index == 0;
                        final bool isLast = index == performers.length - 1;
                        return Padding(
                          padding: EdgeInsets.only(
                            left: isFirst ? 20 : 12,
                            right: isLast ? 20 : 0,
                          ),
                          child: card,
                        );
                      },
                    ),
                  ),
                ],
                // ✅ 相似影片
                similarItems.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final allAre16x9 = items.every(
                        (item) => !_hasHorizontalArtworkForSimilar(item));
                    final listHeight = allAre16x9 ? 130.0 : 190.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            '其他类似影片',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: listHeight,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            cacheExtent: 300,
                            itemBuilder: (context, index) {
                              final card = _SimilarCard(
                                key:
                                    ValueKey('similar_card_${items[index].id}'),
                                item: items[index],
                                isDark: isDark,
                              );
                              final bool isFirst = index == 0;
                              final bool isLast = index == items.length - 1;
                              return Padding(
                                padding: EdgeInsets.only(
                                  left: isFirst ? 20 : 12,
                                  right: isLast ? 20 : 0,
                                ),
                                child: card,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CupertinoActivityIndicator(),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                // ✅ 外部链接
                if (externalLinks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildExternalLinks(externalLinks, isDark),
                  ),
                ],
                // ✅ 详细媒体信息
                const SizedBox(height: 24),
                _buildDetailedMediaModules(
                  data,
                  isDark,
                  horizontalPadding: 20,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SystemUiOverlayStyle _defaultStyleForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _lightStatusBar : _darkStatusBar;
  }

  /// ✅ 构建 Logo 到文字的酷炫过渡效果
  Widget _buildLogoToTextTransition(
      ItemInfo data, double t, double fontSize, Color titleColor) {
    final logoTag = data.imageTags?['Logo'];
    if (logoTag == null || logoTag.isEmpty || data.id == null) {
      return Text(
        data.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: titleColor,
          height: 1.2,
        ),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text(
            data.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: titleColor,
              height: 1.2,
            ),
          );
        }
        final api = snapshot.data!;
        // ✅ 使用 getLogoUrl 方法，确保与预加载的 URL 一致
        final logoUrl = data.getLogoUrl(api) ?? '';
        if (logoUrl.isEmpty) {
          return Text(
            data.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: titleColor,
              height: 1.2,
            ),
          );
        }

        // ✅ 过渡进度：0.0 = 完全展开(Logo)，1.0 = 完全折叠(文字)
        // 在 t=0.3 到 t=0.7 之间进行过渡
        final transitionStart = 0.3;
        final transitionEnd = 0.7;
        final transitionProgress =
            ((t - transitionStart) / (transitionEnd - transitionStart))
                .clamp(0.0, 1.0);

        // ✅ Logo 的透明度和缩放（淡出 + 缩小）
        final logoOpacity = (1.0 - transitionProgress).clamp(0.0, 1.0);
        final logoScale = (1.0 - transitionProgress * 0.3).clamp(0.7, 1.0);
        final logoHeight = 60.0 * logoScale;

        // ✅ 文字的透明度和位移（从下方淡入 + 上移）
        final textOpacity = transitionProgress.clamp(0.0, 1.0);
        final textOffset = 10.0 * (1.0 - transitionProgress);

        return Stack(
          alignment: Alignment.bottomLeft,
          children: [
            // ✅ Logo 层（淡出 + 缩小）
            if (logoOpacity > 0.01)
              Opacity(
                opacity: logoOpacity,
                child: Transform.scale(
                  scale: logoScale,
                  alignment: Alignment.bottomLeft,
                  child: SizedBox(
                    height: logoHeight.clamp(0.0, 60.0),
                    child: EmbyFadeInImage(
                      key: ValueKey('logo_${data.id}_$logoUrl'),
                      imageUrl: logoUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            // ✅ 文字层（从下方淡入 + 上移）
            if (textOpacity > 0.01)
              Transform.translate(
                offset: Offset(0, textOffset),
                child: Opacity(
                  opacity: textOpacity,
                  child: Text(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _colorForStatusStyle(
      SystemUiOverlayStyle style, Brightness fallbackBrightness) {
    final brightness = style.statusBarIconBrightness;
    if (brightness == Brightness.light) return Colors.white;
    if (brightness == Brightness.dark) return Colors.black87;
    return fallbackBrightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  List<Widget> _buildTopActions(ItemInfo item, Color iconColor) {
    // ✅ 使用 ValueListenableBuilder 来局部更新按钮状态
    return [
      // ✅ 已观看/未观看图标（常驻显示，根据状态改变）
      ValueListenableBuilder<bool>(
        valueListenable: _isPlayedNotifier!,
        builder: (context, isPlayed, _) {
          return CupertinoButton(
            padding: const EdgeInsets.all(8),
            minSize: 0,
            onPressed: item.id != null && item.id!.isNotEmpty
                ? () => _handlePlayedToggle(item)
                : null,
            child: Icon(
              isPlayed
                  ? Icons.check_circle_rounded
                  : Icons.play_circle_outline_rounded,
              color: iconColor,
              size: 22,
            ),
          );
        },
      ),
      // ✅ 收藏图标（常驻显示，根据状态改变）
      ValueListenableBuilder<bool>(
        valueListenable: _isFavoriteNotifier!,
        builder: (context, isFavorite, _) {
          return CupertinoButton(
            padding: const EdgeInsets.all(8),
            minSize: 0,
            onPressed: item.id != null && item.id!.isNotEmpty
                ? () => _handleFavoriteToggle(item)
                : null,
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? Colors.red : iconColor,
              size: 22,
            ),
          );
        },
      ),
      // ✅ 下载/已下载图标（替换原来的三个点，始终显示）
      // TODO: 根据实际下载状态显示 Icons.download_done_rounded 或 Icons.download_rounded
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        minSize: 0,
        onPressed: null,
        child: Icon(
          Icons.download_rounded, // 暂时只显示下载图标，后续根据 isDownloaded 状态切换
          color: iconColor,
          size: 22,
        ),
      ),
    ];
  }

  Widget _buildMetaInfo(ItemInfo item, bool isDark) {
    final List<String> metaItems = [];

    // 评分
    final rating = item.getRating();
    if (rating != null) {
      if (item.getRatingSource() == 'douban') {
        metaItems.add('豆 ${rating.toStringAsFixed(1)}');
      } else {
        metaItems.add('⭐ ${rating.toStringAsFixed(1)}');
      }
    }

    // 年份
    if (item.productionYear != null) {
      metaItems.add('${item.productionYear}');
    }

    // 时长
    if (item.runTimeTicks != null) {
      final duration =
          Duration(microseconds: (item.runTimeTicks! / 10).round());
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      metaItems.add('${hours}时${minutes}分');
    }

    final baseColor = isDark ? Colors.white : Colors.black87;
    return Text(
      metaItems.join(' · '),
      style: TextStyle(
        fontSize: 13,
        color: baseColor,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildMediaInfo(ItemInfo item, bool isDark) {
    final genres = item.genres ?? const [];
    final resolutionInfo = _formatResolutionInfo(_getPrimaryMediaSource(item));
    final audioStreams = _getAudioStreams(item);
    final subtitleStreams = _getSubtitleStreams(item);
    final selectedAudioIndex = _ensureAudioSelection(audioStreams);
    // ✅ 注意：selectedSubtitleIndex 只在 ValueNotifier 为 null 时作为后备值使用
    // ValueListenableBuilder 会优先使用 ValueNotifier 的值
    final selectedSubtitleIndex = _ensureSubtitleSelection(subtitleStreams);

    final textColor = isDark ? Colors.white : Colors.black87;
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final textStyle = TextStyle(color: textColor, fontSize: 13, height: 1.4);
    final widgets = <Widget>[];

    void addRow(String label, String value,
        {bool highlight = false,
        ValueChanged<BuildContext>? onTap,
        bool isDefault = false}) {
      if (value.isEmpty) return;
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 6));
      }

      final valueText =
          isDefault && !value.contains('默认') ? '$value (默认)' : value;
      widgets.add(Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$label: ', style: textStyle),
          if (highlight)
            Builder(
              builder: (context) {
                final key = GlobalKey();
                final child = Container(
                  key: key,
                  width: 280.0, // ✅ 固定宽度
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: highlightColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    valueText,
                    style: textStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
                if (onTap == null) return child;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(key.currentContext ?? context),
                  child: child,
                );
              },
            )
          else
            Text(
              valueText,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ));
    }

    if (genres.isNotEmpty) {
      addRow('类型', genres.join(' / '));
    }

    if (resolutionInfo != null) {
      addRow('视频', resolutionInfo);
    }

    if (audioStreams.isNotEmpty &&
        selectedAudioIndex >= 0 &&
        selectedAudioIndex < audioStreams.length) {
      final audioStream = audioStreams[selectedAudioIndex];
      // ✅ 选中项只显示 DisplayTitle，不显示 Title
      final displayTitle = audioStream['DisplayTitle']?.toString() ?? '';
      final audioLabel = displayTitle.isNotEmpty
          ? displayTitle
          : _formatAudioStream(audioStream);
      final hasMultiple = audioStreams.length > 1;

      addRow(
        '音频',
        audioLabel,
        highlight: hasMultiple,
        isDefault: (audioStream['IsDefault'] as bool?) == true,
        onTap: hasMultiple
            ? (ctx) => _showAudioSelectionMenu(
                  ctx,
                  audioStreams,
                  selectedAudioIndex,
                )
            : null,
      );
    }

    // ✅ 使用 ValueListenableBuilder 来局部更新字幕显示
    if (subtitleStreams.isNotEmpty) {
      // ✅ 添加与上方控件统一的间距
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 6));
      }
      widgets.add(ValueListenableBuilder<int?>(
        valueListenable: _subtitleIndexNotifier,
        builder: (context, subtitleIndexFromNotifier, _) {
          // ✅ 优先使用 ValueNotifier 的值（这是最新的值，包括从播放页面返回时刷新的值）
          // 如果 ValueNotifier 有值（包括 -1 表示不显示），直接使用它
          // 如果 ValueNotifier 为 null，使用 selectedSubtitleIndex 作为临时显示
          // 注意：subtitleIndexFromNotifier 可能为 null（表示未设置），也可能为 -1（表示不显示）
          final currentIndex = subtitleIndexFromNotifier != null
              ? subtitleIndexFromNotifier
              : selectedSubtitleIndex;

          // ✅ 如果选择了"不显示"（-1），显示"不显示"
          if (currentIndex == -1) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('字幕: ', style: textStyle),
                Builder(
                  builder: (context) {
                    final key = GlobalKey();
                    final child = Container(
                      key: key,
                      width: 280.0, // ✅ 固定宽度
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: highlightColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '不显示',
                        style: textStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showSubtitleSelectionMenu(
                        key.currentContext ?? context,
                        subtitleStreams,
                        currentIndex,
                      ),
                      child: child,
                    );
                  },
                ),
              ],
            );
          } else if (currentIndex >= 0 &&
              currentIndex < subtitleStreams.length) {
            final subtitleStream = subtitleStreams[currentIndex];
            // ✅ 选中项只显示 DisplayTitle，不显示 Title
            final displayTitle =
                subtitleStream['DisplayTitle']?.toString() ?? '';
            final subtitleLabel = displayTitle.isNotEmpty
                ? displayTitle
                : _formatSubtitleStream(subtitleStream);
            // ✅ 即使只有一个字幕，也要显示可点击的菜单（因为可以选择"不显示"）
            final isDefault = (subtitleStream['IsDefault'] as bool?) == true;
            final valueText = isDefault && !subtitleLabel.contains('默认')
                ? '$subtitleLabel (默认)'
                : subtitleLabel;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('字幕: ', style: textStyle),
                // ✅ 始终显示可点击的组件，即使只有一个字幕（可以选择"不显示"）
                Builder(
                  builder: (context) {
                    final key = GlobalKey();
                    final child = Container(
                      key: key,
                      width: 280.0, // ✅ 固定宽度
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: highlightColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        valueText,
                        style: textStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showSubtitleSelectionMenu(
                        key.currentContext ?? context,
                        subtitleStreams,
                        currentIndex,
                      ),
                      child: child,
                    );
                  },
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPlaySection(
      BuildContext context, ItemInfo item, bool isDarkBackground) {
    final int runtimeTicks = item.runTimeTicks ?? 0;
    final bool hasRuntime = runtimeTicks > 0;

    final ValueNotifier<bool> menuOpenNotifier = ValueNotifier(false);

    // ✅ 使用 ValueListenableBuilder 来局部更新播放进度
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: _userDataNotifier!,
      builder: (context, userData, _) {
        final played = (userData?['Played'] as bool?) ?? false;
        final playedTicks =
            (userData?['PlaybackPositionTicks'] as num?)?.toInt();
        // ✅ 如果已标记为已观看，不显示恢复播放按钮
        final bool canResume = !played &&
            hasRuntime &&
            playedTicks != null &&
            playedTicks > 0 &&
            playedTicks < runtimeTicks;

        Duration? totalDuration;
        Duration? playedDuration;
        Duration? remainingDuration;
        double? progress;
        if (hasRuntime) {
          totalDuration = Duration(microseconds: (runtimeTicks / 10).round());
          if (playedTicks != null) {
            playedDuration = Duration(microseconds: (playedTicks / 10).round());
            remainingDuration = totalDuration - playedDuration;
            progress = playedTicks / runtimeTicks;
          }
        }

        final Color buttonColor =
            canResume ? _resumeButtonColor : _playButtonColor;
        final Color textColor = Colors.white;
        final String buttonLabel = canResume ? '恢复播放' : '播放';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      onPressed: item.id != null && item.id!.isNotEmpty
                          ? () => _handlePlay(
                                context,
                                item.id!,
                                fromBeginning: !canResume,
                                resumePositionTicks:
                                    canResume ? playedTicks : null,
                              )
                          : null,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: Row(
                          key: ValueKey(buttonLabel),
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.play_fill, color: textColor),
                            const SizedBox(width: 8),
                            Text(
                              buttonLabel,
                              style: TextStyle(fontSize: 16, color: textColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // ✅ 使用 AnimatedSwitcher 替代 AnimatedSize，避免闪烁
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: canResume
                      ? Row(
                          key: const ValueKey('resume-menu'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 12),
                            ValueListenableBuilder<bool>(
                              valueListenable: menuOpenNotifier,
                              builder: (context, isOpen, _) {
                                return Builder(
                                  builder: (anchorContext) => GestureDetector(
                                    key: _resumeMenuAnchorKey,
                                    onTap: () async {
                                      menuOpenNotifier.value = true;
                                      await _showResumeMenu(
                                          anchorContext, item);
                                      menuOpenNotifier.value = false;
                                    },
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      curve: Curves.easeInOut,
                                      height: 44,
                                      width: 44,
                                      decoration: BoxDecoration(
                                        color: buttonColor,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      alignment: Alignment.center,
                                      child: AnimatedRotation(
                                        turns: isOpen ? 0.5 : 0.0,
                                        duration:
                                            const Duration(milliseconds: 200),
                                        child: Icon(
                                          CupertinoIcons.chevron_down,
                                          color: textColor,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('no-resume-menu')),
                ),
              ],
            ),
            // ✅ 使用 AnimatedSwitcher 替代 AnimatedSize，避免闪烁
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: canResume && progress != null && remainingDuration != null
                  ? Column(
                      key: const ValueKey('progress'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                clipBehavior: Clip.hardEdge,
                                borderRadius: BorderRadius.circular(4),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0.0,
                                    end: progress.clamp(0.0, 1.0),
                                  ),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, animatedValue, child) {
                                    return LinearProgressIndicator(
                                      value: animatedValue.clamp(0.0, 1.0),
                                      minHeight: 6,
                                      backgroundColor: (isDarkBackground
                                              ? Colors.white
                                              : Colors.black)
                                          .withValues(alpha: 0.18),
                                      valueColor: AlwaysStoppedAnimation(
                                        _resumeButtonColor.withValues(
                                            alpha: 0.95),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatDuration(remainingDuration),
                              style: TextStyle(
                                color: isDarkBackground
                                    ? Colors.white70
                                    : Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('no-progress')),
            ),
            // ✅ 如果是合集类型，显示合集内的影片
            if (item.type == 'BoxSet' && item.id != null) ...[
              const SizedBox(height: 24),
              _buildCollectionMovies(context, item.id!, isDarkBackground),
            ],
          ],
        );
      },
    );
  }

  Future<void> _handleBackdropImage(ui.Image image, String cacheKey) async {
    // ✅ 优化10：使用 LRU 缓存，避免内存泄漏
    final cachedStyle = _imageStyleCache.get(cacheKey);
    if (cachedStyle != null) {
      _applyStatusBarStyle(cachedStyle);
      return;
    }

    final bool isDark = await _isTopAreaDark(image);
    final style = isDark ? _lightStatusBar : _darkStatusBar;
    _imageStyleCache.put(cacheKey, style);
    _applyStatusBarStyle(style);
  }

  Future<bool> _isTopAreaDark(ui.Image image) async {
    try {
      final int width = image.width;
      final int height = image.height;
      if (width == 0 || height == 0) {
        return true;
      }

      final int sampleRows =
          math.max(1, math.min(height, (height * 0.25).round()));
      final int rowStep = math.max(1, sampleRows ~/ 25);
      final int colStep = math.max(1, width ~/ 40);

      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return true;
      }
      final Uint8List bytes = data.buffer.asUint8List();

      double totalLuminance = 0;
      int samples = 0;

      for (int y = 0; y < sampleRows; y += rowStep) {
        final int rowOffset = y * width;
        for (int x = 0; x < width; x += colStep) {
          final int index = (rowOffset + x) * 4;
          if (index + 3 >= bytes.length) {
            continue;
          }
          final int r = bytes[index];
          final int g = bytes[index + 1];
          final int b = bytes[index + 2];
          final double luminance =
              (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          totalLuminance += luminance;
          samples++;
        }
      }

      if (samples == 0) {
        return true;
      }

      final double avg = totalLuminance / samples;
      return avg < 0.5;
    } catch (e) {
      return true;
    }
  }

  void _applyStatusBarStyle(SystemUiOverlayStyle style) {
    if (!mounted || _statusBarStyle == style) {
      return;
    }
    _statusBarStyle = style;
    _navSyncedStyleNotifier.value = null;
    if (mounted) {
      _statusBarController?.update(style);
      setState(() {});
    } else {
      SystemChrome.setSystemUIOverlayStyle(style);
    }
    _syncStatusBarWithNavigation(
        _scrollController.hasClients ? _scrollController.offset : 0.0);
  }

  void _syncStatusBarWithNavigation(double offset) {
    if (!mounted) return;
    final brightness = getCurrentBrightnessFromContext(context, ref);
    final SystemUiOverlayStyle expandedStyle = _statusBarStyle;
    final SystemUiOverlayStyle collapsedStyle =
        _defaultStyleForBrightness(brightness);

    const double blurStart = 10.0;
    const double blurEnd = 250.0; // 使用固定值替代 _headerTopOffset
    final double progress;
    if (offset <= blurStart) {
      progress = 0.0;
    } else {
      final double effective =
          (offset - blurStart).clamp(0.0, blurEnd - blurStart);
      progress = (effective / (blurEnd - blurStart)).clamp(0.0, 1.0);
    }

    final SystemUiOverlayStyle targetStyle =
        progress < 0.55 ? expandedStyle : collapsedStyle;
    if (_navSyncedStyleNotifier.value == targetStyle) {
      return;
    }
    _navSyncedStyleNotifier.value = targetStyle;
    if (mounted) {
      _statusBarController?.update(targetStyle);
    } else {
      SystemChrome.setSystemUIOverlayStyle(targetStyle);
    }
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _statusBarController?.release();
      _statusBarController = null;
    } else if (status == AnimationStatus.completed ||
        status == AnimationStatus.forward) {
      if (mounted) {
        _statusBarController
            ?.update(_navSyncedStyleNotifier.value ?? _statusBarStyle);
      }
    }
  }

  void _removeRouteListener() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = null;
    _modalRoute = null;
  }

  Map<String, dynamic>? _getPrimaryMediaSource(ItemInfo item) {
    final sources = item.mediaSources;
    if (sources == null || sources.isEmpty) return null;
    return sources.first;
  }

  List<Map<String, dynamic>> _getAudioStreams(ItemInfo item) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) return const [];
    final streams = media['MediaStreams'];
    if (streams is List) {
      return streams
          .where((element) =>
              element is Map &&
              (element['Type'] as String?)?.toLowerCase() == 'audio')
          .map((element) => Map<String, dynamic>.from(
              (element as Map<dynamic, dynamic>)
                  .map((key, value) => MapEntry(key.toString(), value))))
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _getSubtitleStreams(ItemInfo item) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) return const [];
    final streams = media['MediaStreams'];
    if (streams is List) {
      return streams
          .where((element) =>
              element is Map &&
              (element['Type'] as String?)?.toLowerCase() == 'subtitle')
          .map((element) => Map<String, dynamic>.from(
              (element as Map<dynamic, dynamic>)
                  .map((key, value) => MapEntry(key.toString(), value))))
          .toList();
    }
    return const [];
  }

  int _ensureAudioSelection(List<Map<String, dynamic>> audioStreams) {
    if (audioStreams.isEmpty) return -1;

    final current = _selectedAudioStreamIndex;
    // ✅ 如果已有有效选择（手动选择过的），直接使用
    if (current != null && current >= 0 && current < audioStreams.length) {
      return current;
    }

    // ✅ 如果用户手动选择过，但值还是null（异步加载中），等待加载完成
    if (_hasManuallySelectedAudio) {
      // 返回默认值显示，但不设置state，避免覆盖即将加载的值
      final defaultIndex = audioStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      return defaultIndex != -1 ? defaultIndex : 0;
    }

    // ✅ 没有手动选择过，使用默认音频或第一个（不保存）
    final defaultIndex = audioStreams
        .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
    final fallback = defaultIndex != -1 ? defaultIndex : 0;

    Future.microtask(() {
      if (mounted && !_hasManuallySelectedAudio) {
        setState(() {
          _selectedAudioStreamIndex = fallback;
        });
        // ✅ 不保存，让每次都使用默认值
      }
    });
    return fallback;
  }

  int _ensureSubtitleSelection(List<Map<String, dynamic>> subtitleStreams) {
    if (subtitleStreams.isEmpty) return -1;

    final current = _selectedSubtitleStreamIndex;

    // ✅ 如果正在加载保存的选择，且用户手动选择过，等待加载完成
    if (_isLoadingStreamSelections && _hasManuallySelectedSubtitle) {
      // 返回一个临时值，等待加载完成后再更新
      final defaultIndex = subtitleStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);

      return defaultIndex != -1 ? defaultIndex : 0;
    }

    // ✅ 如果用户选择了"不显示"（-1），则保持不显示
    if (current == -1) {
      return -1;
    }
    // ✅ 如果已有有效选择，直接使用
    if (current != null && current >= 0 && current < subtitleStreams.length) {
      return current;
    }

    // ✅ 如果用户手动选择过，但值是-1（不显示），则保持不显示
    if (_hasManuallySelectedSubtitle) {
      if (current == -1) {
        return -1;
      }
      // ✅ 如果用户手动选择过，但当前值为 null（可能还在加载中），等待加载完成
      if (current == null) {
        // 如果正在加载，返回默认值作为临时显示，但不保存
        if (_isLoadingStreamSelections) {
          final defaultIndex = subtitleStreams
              .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
          return defaultIndex != -1 ? defaultIndex : 0;
        }
        // 如果加载完成但值为 null，说明没有保存的值，不应该覆盖
        // 返回默认值但不保存
        final defaultIndex = subtitleStreams
            .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
        return defaultIndex != -1 ? defaultIndex : 0;
      }
      // ✅ 如果当前值无效（超出范围），使用默认值但不覆盖保存的值
      if (current < 0 || current >= subtitleStreams.length) {
        final defaultIndex = subtitleStreams
            .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
        final fallback = defaultIndex != -1 ? defaultIndex : 0;
        // ✅ 不更新状态，因为用户已经手动选择过，应该等待加载完成
        return fallback;
      }
      // ✅ 当前值有效，直接返回
      return current;
    }

    // ✅ 智能中文字幕选择（只在用户没有手动选择过时执行）
    int selectedIndex = _findBestChineseSubtitle(subtitleStreams);

    // ✅ 如果没有找到中文字幕，使用默认或第一个
    if (selectedIndex == -1) {
      final defaultIndex = subtitleStreams
          .indexWhere((stream) => (stream['IsDefault'] as bool?) == true);
      selectedIndex = defaultIndex != -1 ? defaultIndex : 0;
    }

    Future.microtask(() {
      if (mounted) {
        // ✅ 再次检查：如果加载完成且用户手动选择过，不覆盖
        if (!_isLoadingStreamSelections && _hasManuallySelectedSubtitle) {
          return;
        }
        setState(() {
          _selectedSubtitleStreamIndex = selectedIndex;
        });
        // ✅ 更新 ValueNotifier
        _subtitleIndexNotifier.value = selectedIndex;
        _saveStreamSelections();
      }
    });
    return selectedIndex;
  }

  /// ✅ 查找最佳中文字幕
  /// 优先级：Chinese Simplified > Chinese Traditional > chinese
  int _findBestChineseSubtitle(List<Map<String, dynamic>> subtitleStreams) {
    // 1. 优先：Chinese Simplified（大小写均可）
    int index = subtitleStreams.indexWhere((stream) {
      final lang = stream['Language']?.toString() ?? '';
      final displayTitle = stream['DisplayTitle']?.toString() ?? '';
      final title = stream['Title']?.toString() ?? '';
      final combined = '$lang $displayTitle $title'.toLowerCase();
      return combined.contains('chinese') && combined.contains('simplified');
    });
    if (index != -1) return index;

    // 2. 其次：Chinese Traditional（大小写均可）
    index = subtitleStreams.indexWhere((stream) {
      final lang = stream['Language']?.toString() ?? '';
      final displayTitle = stream['DisplayTitle']?.toString() ?? '';
      final title = stream['Title']?.toString() ?? '';
      final combined = '$lang $displayTitle $title'.toLowerCase();
      return combined.contains('chinese') && combined.contains('traditional');
    });
    if (index != -1) return index;

    // 3. 再次：包含 chinese（任意大小写）
    index = subtitleStreams.indexWhere((stream) {
      final lang = stream['Language']?.toString() ?? '';
      final displayTitle = stream['DisplayTitle']?.toString() ?? '';
      final title = stream['Title']?.toString() ?? '';
      final combined = '$lang $displayTitle $title'.toLowerCase();
      return combined.contains('chinese');
    });
    if (index != -1) return index;

    // 4. 最后尝试：chi, zh, cn, chs, cht 等常见中文标识
    index = subtitleStreams.indexWhere((stream) {
      final lang = (stream['Language']?.toString() ?? '').toLowerCase();
      return lang == 'chi' ||
          lang == 'zh' ||
          lang == 'cn' ||
          lang == 'chs' ||
          lang == 'cht' ||
          lang == 'zh-cn' ||
          lang == 'zh-tw';
    });

    return index;
  }

  String? _formatResolutionInfo(Map<String, dynamic>? media) {
    if (media == null) return null;
    final width = (media['Width'] as num?)?.toInt();
    final height = (media['Height'] as num?)?.toInt();
    final videoStream = _getVideoStream(media);

    String? resolutionLabel;
    final sourceWidth = width ?? (videoStream?['Width'] as num?)?.toInt();
    final sourceHeight = height ?? (videoStream?['Height'] as num?)?.toInt();
    if (sourceWidth != null) {
      if (sourceWidth >= 3840) {
        resolutionLabel = '4K';
      } else if (sourceWidth >= 2560) {
        resolutionLabel = '2K';
      } else if (sourceWidth >= 1920) {
        resolutionLabel = '1080p';
      } else if (sourceWidth >= 1280) {
        resolutionLabel = '720p';
      } else if (sourceWidth >= 960) {
        resolutionLabel = '960p';
      } else if (sourceWidth >= 854) {
        resolutionLabel = '480p';
      }
    } else if (sourceHeight != null) {
      if (sourceHeight >= 2160) {
        resolutionLabel = '4K';
      } else if (sourceHeight >= 1440) {
        resolutionLabel = '2K';
      } else if (sourceHeight >= 1080) {
        resolutionLabel = '1080p';
      } else if (sourceHeight >= 720) {
        resolutionLabel = '720p';
      } else if (sourceHeight >= 540) {
        resolutionLabel = '540p';
      } else if (sourceHeight >= 480) {
        resolutionLabel = '480p';
      }
    }

    final codec = (videoStream?['Codec'] ?? media['VideoCodec'])
        ?.toString()
        .toUpperCase();
    final components = <String>[];
    if (resolutionLabel != null) components.add(resolutionLabel);
    if (codec != null && codec.isNotEmpty) components.add(codec);

    if (components.isEmpty && sourceWidth != null && sourceHeight != null) {
      components.add('${sourceWidth}x$sourceHeight');
    }

    return components.isEmpty ? null : components.join(' ');
  }

  String _formatAudioStream(Map<String, dynamic> stream) {
    final displayTitle = stream['DisplayTitle']?.toString() ?? '';

    // ✅ 如果有 DisplayTitle，直接使用
    if (displayTitle.isNotEmpty) {
      return displayTitle;
    }

    // ✅ 如果没有 DisplayTitle，尝试使用 Title
    final title = stream['Title']?.toString() ?? '';
    if (title.isNotEmpty) {
      return title;
    }

    // ✅ 如果都没有，回退到手动构建
    final codec = stream['Codec']?.toString().toUpperCase();
    final channels = (stream['Channels'] as num?)?.toInt();
    final language = stream['Language']?.toString();

    final parts = <String>[];
    if (language != null && language.isNotEmpty) {
      parts.add(language);
    }
    if (codec != null && codec.isNotEmpty) parts.add(codec);
    if (channels != null) {
      final channelLabel = channels == 2
          ? '2.0'
          : channels == 6
              ? '5.1'
              : channels.toString();
      parts.add(channelLabel);
    }

    return parts.isEmpty ? '未知' : parts.join(' ');
  }

  String _formatSubtitleStream(Map<String, dynamic> stream) {
    final displayTitle = stream['DisplayTitle']?.toString() ?? '';

    // ✅ 如果有 DisplayTitle，直接使用
    if (displayTitle.isNotEmpty) {
      return displayTitle;
    }

    // ✅ 如果没有 DisplayTitle，尝试使用 Title
    final title = stream['Title']?.toString() ?? '';
    if (title.isNotEmpty) {
      return title;
    }

    // ✅ 如果都没有，回退到手动构建
    final language = stream['Language']?.toString();
    final codec = stream['Codec']?.toString().toUpperCase();
    final isForced = stream['IsForced'] == true;

    final parts = <String>[];
    if (language != null && language.isNotEmpty) {
      parts.add(language);
    }
    if (codec != null && codec.isNotEmpty) {
      parts.add(codec);
    }
    if (isForced) {
      parts.add('强制');
    }

    return parts.isEmpty ? '未知字幕' : parts.join(' ');
  }

  Future<void> _showResumeMenu(BuildContext context, ItemInfo item) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height,
        overlay.size.width - origin.dx - box.size.width,
        overlay.size.height - origin.dy - box.size.height,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'restart',
          child: Row(
            children: const [
              Icon(CupertinoIcons.refresh, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('从头开始播放')),
            ],
          ),
        ),
      ],
    );

    if (result == 'restart' && item.id != null) {
      _handlePlay(context, item.id!,
          fromBeginning: true, resumePositionTicks: 0);
    }
  }

  Future<void> _showAudioSelectionMenu(
    BuildContext anchorContext,
    List<Map<String, dynamic>> audioStreams,
    int selected,
  ) async {
    if (audioStreams.isEmpty) return;

    final RenderBox? button = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay;
    final RenderBox? overlayBox =
        overlay?.context.findRenderObject() as RenderBox?;

    if (button == null || overlayBox == null) return;

    final Offset buttonOffset =
        button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Size overlaySize = overlayBox.size;

    double panelWidth = 280.0; // ✅ 增加宽度从 240 到 320
    const double maxHeight = 260.0;

    const double minLeftMargin = 16.0;
    const double rightMargin = 18.0;

    final double maxAllowedWidth =
        overlaySize.width - minLeftMargin - rightMargin;
    if (panelWidth > maxAllowedWidth) {
      panelWidth = maxAllowedWidth.clamp(120.0, panelWidth);
    }

    double left = buttonOffset.dx;
    final double maxLeft = overlaySize.width - panelWidth - rightMargin;

    if (maxLeft < minLeftMargin) {
      panelWidth = (overlaySize.width - minLeftMargin - rightMargin)
          .clamp(120.0, panelWidth);
      left = minLeftMargin;
    } else {
      left = left.clamp(minLeftMargin, maxLeft);
    }
    // ✅ 改为 top 定位，显示在按钮下方
    final double top = buttonOffset.dy - 10;

    final scrollController = ScrollController();
    final itemKeys = List.generate(
      audioStreams.length,
      (index) => GlobalKey(),
    );

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        // ✅ 使用延迟确保 ScrollView 已经完全构建后滚动到选中项
        if (selected >= 0 && selected < itemKeys.length) {
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              final key = itemKeys[selected];
              final keyContext = key.currentContext;
              if (keyContext != null) {
                Scrollable.ensureVisible(
                  keyContext,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: 0.0, // 0.0 = 顶部, 0.5 = 中间, 1.0 = 底部
                );
              }
            } catch (e) {
              // 忽略滚动错误
            }
          });
        }

        final isDark = isDarkModeFromContext(context, ref);
        final gradientColors = isDark
            ? [
                Colors.grey.shade900.withValues(alpha: 0.7),
                Colors.grey.shade800.withValues(alpha: 0.5),
              ]
            : [
                Colors.white.withValues(alpha: 0.25),
                Colors.white.withValues(alpha: 0.15),
              ];

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: panelWidth,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              audioStreams.length,
                              (index) {
                                final data = audioStreams[index];
                                final displayTitle =
                                    data['DisplayTitle']?.toString() ?? '';
                                final title = data['Title']?.toString() ?? '';
                                final isDefault =
                                    (data['IsDefault'] as bool?) == true;
                                final isSelected = index == selected;

                                // ✅ 主标题：优先使用 DisplayTitle
                                String mainLabel = displayTitle.isNotEmpty
                                    ? displayTitle
                                    : _formatAudioStream(data);

                                // ✅ 添加默认标记
                                if (isDefault && !mainLabel.contains('默认')) {
                                  mainLabel = '$mainLabel (默认)';
                                }

                                // ✅ 副标题：如果 Title 存在且不同于 DisplayTitle
                                final hasSubtitle = title.isNotEmpty &&
                                    title != displayTitle &&
                                    displayTitle.isNotEmpty;

                                return Material(
                                  key: itemKeys[index], // ✅ 添加 key 用于滚动定位
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogCtx).pop(index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  mainLabel,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                                if (hasSubtitle) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    title,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.6),
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    scrollController.dispose();

    if (result != null && result >= 0 && result < audioStreams.length) {
      setState(() {
        _selectedAudioStreamIndex = result;
        // ✅ 标记为手动选择
        _hasManuallySelectedAudio = true;
      });
      // ✅ 保存音频选择
      _saveStreamSelections();
    }
  }

  Future<void> _showSubtitleSelectionMenu(
    BuildContext anchorContext,
    List<Map<String, dynamic>> subtitleStreams,
    int selected,
  ) async {
    if (subtitleStreams.isEmpty) return;

    final RenderBox? button = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay;
    final RenderBox? overlayBox =
        overlay?.context.findRenderObject() as RenderBox?;

    if (button == null || overlayBox == null) return;

    final Offset buttonOffset =
        button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Size overlaySize = overlayBox.size;

    double panelWidth = 280.0; // ✅ 增加宽度从 240 到 320
    const double maxHeight = 260.0;

    const double minLeftMargin = 16.0;
    const double rightMargin = 18.0;

    final double maxAllowedWidth =
        overlaySize.width - minLeftMargin - rightMargin;
    if (panelWidth > maxAllowedWidth) {
      panelWidth = maxAllowedWidth.clamp(120.0, panelWidth);
    }

    double left = buttonOffset.dx;
    final double maxLeft = overlaySize.width - panelWidth - rightMargin;

    if (maxLeft < minLeftMargin) {
      panelWidth = (overlaySize.width - minLeftMargin - rightMargin)
          .clamp(120.0, panelWidth);
      left = minLeftMargin;
    } else {
      left = left.clamp(minLeftMargin, maxLeft);
    }
    // ✅ 改为 top 定位，显示在按钮下方
    final double top = buttonOffset.dy - 10;

    final scrollController = ScrollController();
    final itemKeys = List.generate(
      subtitleStreams.length,
      (index) => GlobalKey(),
    );

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        // ✅ 使用延迟确保 ScrollView 已经完全构建后滚动到选中项
        if (selected >= 0 && selected < itemKeys.length) {
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              final key = itemKeys[selected];
              final keyContext = key.currentContext;
              if (keyContext != null) {
                Scrollable.ensureVisible(
                  keyContext,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: 0.0, // 0.0 = 顶部, 0.5 = 中间, 1.0 = 底部
                );
              }
            } catch (e) {
              // 忽略滚动错误
            }
          });
        }

        final isDark = isDarkModeFromContext(context, ref);
        final gradientColors = isDark
            ? [
                Colors.grey.shade900.withValues(alpha: 0.7),
                Colors.grey.shade800.withValues(alpha: 0.5),
              ]
            : [
                Colors.white.withValues(alpha: 0.25),
                Colors.white.withValues(alpha: 0.15),
              ];

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: panelWidth,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ✅ "不显示"选项
                              if (subtitleStreams.isNotEmpty)
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogCtx).pop(-1),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '不显示',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: selected == -1
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          if (selected == -1)
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              // ✅ 字幕流列表
                              ...List.generate(
                                subtitleStreams.length,
                                (index) {
                                  final data = subtitleStreams[index];
                                  final displayTitle =
                                      data['DisplayTitle']?.toString() ?? '';
                                  final title = data['Title']?.toString() ?? '';
                                  final isDefault =
                                      (data['IsDefault'] as bool?) == true;
                                  final isSelected = index == selected;

                                  // ✅ 主标题：优先使用 DisplayTitle
                                  String mainLabel = displayTitle.isNotEmpty
                                      ? displayTitle
                                      : _formatSubtitleStream(data);

                                  // ✅ 添加默认标记
                                  if (isDefault && !mainLabel.contains('默认')) {
                                    mainLabel = '$mainLabel (默认)';
                                  }

                                  // ✅ 副标题：如果 Title 存在且不同于 DisplayTitle
                                  final hasSubtitle = title.isNotEmpty &&
                                      title != displayTitle &&
                                      displayTitle.isNotEmpty;

                                  return Material(
                                    key: itemKeys[index], // ✅ 添加 key 用于滚动定位
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () =>
                                          Navigator.of(dialogCtx).pop(index),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    mainLabel,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (hasSubtitle) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      title,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.6),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              const Icon(
                                                Icons.check_rounded,
                                                size: 20,
                                                color: Colors.white,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    scrollController.dispose();

    // ✅ 支持选择"不显示"（-1）或有效的字幕流索引
    if (result != null &&
        (result == -1 || (result >= 0 && result < subtitleStreams.length))) {
      setState(() {
        _selectedSubtitleStreamIndex = result;
        // ✅ 标记为手动选择
        _hasManuallySelectedSubtitle = true;
      });
      // ✅ 更新 ValueNotifier，触发局部更新
      _subtitleIndexNotifier.value = result;
      // ✅ 保存字幕选择
      _saveStreamSelections();
    }
  }

  void _handlePlay(
    BuildContext context,
    String itemId, {
    required bool fromBeginning,
    int? resumePositionTicks,
  }) async {
    final params = <String, String>{};
    if (fromBeginning) {
      params['fromStart'] = 'true';
    } else if (resumePositionTicks != null && resumePositionTicks > 0) {
      params['positionTicks'] = resumePositionTicks.toString();
    }
    final route = Uri(
      path: '/player/$itemId',
      queryParameters: params.isEmpty ? null : params,
    ).toString();

    // ✅ 获取当前 item 信息并传递给播放器页面
    final itemAsync = ref.read(itemProvider(widget.itemId));
    final item = itemAsync.value;

    // ✅ 构建背景图 URL 并尝试从缓存获取图片对象（逻辑必须与 _buildBackdropBackground 一致）
    String? backdropUrl;
    ui.Image? backdropImage;
    if (item != null) {
      final api = await EmbyApi.create();

      // ✅ 使用 getBackdropUrl 方法，确保与预加载的 URL 一致
      backdropUrl = item.getBackdropUrl(api);

      // Fallback 到 Primary（与详情页显示逻辑一致）
      if (backdropUrl == null || backdropUrl.isEmpty) {
        final primaryTag = item.imageTags?['Primary'] ?? '';
        if (primaryTag.isNotEmpty) {
          backdropUrl = api.buildImageUrl(
            itemId: itemId,
            type: 'Primary',
            maxWidth: 800,
          );
        }
      }

      // ✅ 尝试从缓存获取图片对象（立即显示，无需等待）
      if (backdropUrl != null && backdropUrl.isNotEmpty) {
        backdropImage = getCachedImage(backdropUrl);
      }
    }

    // ✅ 传递 extra 参数
    context.push(
      route,
      extra: {
        'itemInfo': item,
        'backdropUrl': backdropUrl,
        'backdropImage': backdropImage,
      },
    );
  }

  /// 处理收藏切换
  Future<void> _handleFavoriteToggle(ItemInfo item) async {
    if (item.id == null || item.id!.isEmpty) return;

    // ✅ 如果正在更新，防止重复点击
    if (_isUpdatingFavorite) return;

    final auth = ref.read(authStateProvider).value;
    if (auth == null || !auth.isLoggedIn) return;

    final currentFavorite = _isFavoriteNotifier?.value ??
        (item.userData?['IsFavorite'] as bool?) ??
        false;

    // ✅ 标记正在更新，防止 whenData 覆盖和重复点击
    _isUpdatingFavorite = true;

    try {
      final api = await ref.read(embyApiProvider.future);
      // ✅ 先调用 API，等待成功后再更新 UI
      if (currentFavorite) {
        await api.removeFavoriteItem(auth.userId!, item.id!);
      } else {
        await api.addFavoriteItem(auth.userId!, item.id!);
      }

      // ✅ API 成功后才更新 UI
      if (mounted) {
        final newFavorite = !currentFavorite;
        _isFavoriteNotifier?.value = newFavorite;

        // ✅ 更新 userData
        final currentUserData = Map<String, dynamic>.from(
            _userDataNotifier?.value ?? item.userData ?? {});
        currentUserData['IsFavorite'] = newFavorite;
        _userDataNotifier?.value = currentUserData;

        // ✅ 移除 libraryRefreshTickerProvider 的使用，全局刷新在页面生命周期时进行

        // ✅ 延迟解除标记，确保在 provider 刷新完成后再允许 whenData 更新
        Future.delayed(const Duration(milliseconds: 1000), () {
          _isUpdatingFavorite = false;
        });
      }
    } catch (e) {
      // ✅ 如果失败，立即解除标记
      _isUpdatingFavorite = false;
      if (mounted) {
        // TODO: 可以添加错误提示
      }
    }
  }

  /// 处理已观看切换
  Future<void> _handlePlayedToggle(ItemInfo item) async {
    if (item.id == null || item.id!.isEmpty) return;

    // ✅ 如果正在更新，防止重复点击
    if (_isUpdatingPlayed) return;

    final auth = ref.read(authStateProvider).value;
    if (auth == null || !auth.isLoggedIn) return;

    final currentPlayed = _isPlayedNotifier?.value ??
        (item.userData?['Played'] as bool?) ??
        false;

    // ✅ 标记正在更新，防止 whenData 覆盖和重复点击
    _isUpdatingPlayed = true;

    try {
      final api = await ref.read(embyApiProvider.future);
      // ✅ 先调用 API，等待成功后再更新 UI
      if (currentPlayed) {
        await api.unmarkAsPlayed(auth.userId!, item.id!);
      } else {
        await api.markAsPlayed(auth.userId!, item.id!);
      }

      // ✅ API 成功后才更新 UI
      if (mounted) {
        final newPlayed = !currentPlayed;
        _isPlayedNotifier?.value = newPlayed;

        // ✅ 更新 userData（如果标记为已观看，清除播放进度；如果取消已观看，恢复原始播放进度）
        final currentUserData = Map<String, dynamic>.from(
            _userDataNotifier?.value ?? item.userData ?? {});
        currentUserData['Played'] = newPlayed;
        if (newPlayed) {
          // ✅ 标记为已观看时，清除播放进度
          currentUserData['PlaybackPositionTicks'] = 0;
        } else {
          // ✅ 取消已观看时，恢复原始播放进度（如果有的话）
          final originalTicks = item.userData?['PlaybackPositionTicks'];
          if (originalTicks != null) {
            currentUserData['PlaybackPositionTicks'] = originalTicks;
          } else if (currentUserData['PlaybackPositionTicks'] == 0) {
            // ✅ 如果没有原始播放进度，清除 0 值（因为可能是从已观看状态切换过来的）
            currentUserData.remove('PlaybackPositionTicks');
          }
        }
        _userDataNotifier?.value = currentUserData;

        // ✅ 移除 libraryRefreshTickerProvider 的使用，全局刷新在页面生命周期时进行

        // ✅ 延迟解除标记，确保在 provider 刷新完成后再允许 whenData 更新
        // 这样可以避免 whenData 在刷新过程中拿到旧数据导致闪烁
        Future.delayed(const Duration(milliseconds: 1000), () {
          _isUpdatingPlayed = false;
        });
      }
    } catch (e) {
      // ✅ 如果失败，立即解除标记
      _isUpdatingPlayed = false;
      if (mounted) {
        // TODO: 可以添加错误提示
      }
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return minutes > 0 ? '${hours}时${minutes}分' : '${hours}小时';
    }
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return seconds > 0 ? '${minutes}分${seconds}秒' : '${minutes}分钟';
    }
    return '${duration.inSeconds}秒';
  }

  void _showOverviewDialog(ItemInfo item) {
    final overview = item.overview ?? '';
    if (overview.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 120,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: FutureBuilder<EmbyApi>(
                            future: EmbyApi.create(),
                            builder: (ctx2, snapshot) {
                              if (!snapshot.hasData || item.id == null) {
                                return Container(
                                    color: CupertinoColors.systemGrey5);
                              }
                              final posterUrl = snapshot.data!.buildImageUrl(
                                  itemId: item.id!,
                                  type: 'Primary',
                                  maxWidth: 400);
                              if (posterUrl.isEmpty) {
                                return Container(
                                    color: CupertinoColors.systemGrey5);
                              }
                              return EmbyFadeInImage(
                                imageUrl: posterUrl,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          if (item.productionYear != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                '${item.productionYear}',
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  overview,
                  style:
                      Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic>? _getVideoStream(Map<String, dynamic>? media) {
    if (media == null) return null;
    final streams = media['MediaStreams'];
    if (streams is List) {
      for (final stream in streams) {
        if (stream is Map &&
            (stream['Type'] as String?)?.toLowerCase() == 'video') {
          return stream.map((key, value) => MapEntry(key.toString(), value));
        }
      }
    }
    return null;
  }

  Widget _buildExternalLinks(List<ExternalUrlInfo> links, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = textColor.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '数据库链接',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            itemCount: links.length,
            // ✅ 添加 cacheExtent 提升横向列表性能
            cacheExtent: 200,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final link = links[index];
              // ✅ 使用 RepaintBoundary 隔离每个链接按钮的重绘
              return RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                    // boxShadow: [
                    //   BoxShadow(
                    //     color:
                    //         Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                    //     blurRadius: 12,
                    //     offset: const Offset(0, 6),
                    //   ),
                    // ],
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    minSize: 0,
                    onPressed: () => _openExternalLink(link.url),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.link,
                          size: 14,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          link.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openExternalLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {}
  }

  List<ExternalUrlInfo> _composeExternalLinks(ItemInfo item) {
    final List<ExternalUrlInfo> results = [];
    final seen = <String>{};

    void append(String name, String url) {
      if (name.isEmpty || url.isEmpty) return;
      final key = name.toLowerCase();
      if (seen.add(key)) {
        results.add(ExternalUrlInfo(name: name, url: url));
      }
    }

    for (final link in item.externalUrls ?? const <ExternalUrlInfo>[]) {
      if (link.isValid) {
        append(link.name, link.url);
      }
    }

    final providers = item.providerIds ?? const <String, dynamic>{};
    String? providerId(String key) {
      for (final entry in providers.entries) {
        if (entry.key.toString().toLowerCase() == key) {
          final value = entry.value?.toString() ?? '';
          if (value.isNotEmpty) return value;
        }
      }
      return null;
    }

    final type = item.type.toLowerCase();

    final imdbId = providerId('imdb');
    if (imdbId != null) {
      append('IMDb', 'https://www.imdb.com/title/$imdbId');
    }

    final tmdbId = providerId('tmdb');
    if (tmdbId != null) {
      final path = type == 'movie'
          ? 'movie'
          : (type == 'series' || type == 'season' || type == 'episode')
              ? 'tv'
              : 'movie';
      append('TMDb', 'https://www.themoviedb.org/$path/$tmdbId');
    }

    final traktId = providerId('trakt');
    if (traktId != null) {
      final path = type == 'movie'
          ? 'movies'
          : (type == 'series' || type == 'season' || type == 'episode')
              ? 'shows'
              : 'movies';
      append('Trakt', 'https://trakt.tv/$path/$traktId');
    }

    final tvdbId = providerId('tvdb');
    if (tvdbId != null) {
      append('TheTVDB', 'https://thetvdb.com/series/$tvdbId');
    }

    final doubanId = providerId('douban');
    if (doubanId != null) {
      append('豆瓣', 'https://movie.douban.com/subject/$doubanId/');
    }

    final anidbId = providerId('anidb');
    if (anidbId != null) {
      append('AniDB', 'https://anidb.net/anime/$anidbId');
    }

    return results;
  }

  Widget _buildDetailedMediaModules(ItemInfo item, bool isDark,
      {double horizontalPadding = 0}) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) {
      return const SizedBox.shrink();
    }

    final streams = (media['MediaStreams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];

    final resourcePath = media['Path']?.toString() ?? '';
    final resourceFormat = media['Container']?.toString() ?? '';
    final resourceSize = _formatBytes(media['Size']);
    final resourceDate =
        _formatDateTime(media['DateCreated'] ?? item.dateCreated);
    final resourceMeta =
        _mergeFormatSizeDate(resourceFormat, resourceSize, resourceDate);

    final modules = <_MediaDetailModule>[];

    final videoStreams = streams
        .where((stream) => stream['Type']?.toString().toLowerCase() == 'video')
        .toList();
    for (var i = 0; i < videoStreams.length; i++) {
      modules.add(_MediaDetailModule(
        title: '视频',
        fields: _buildVideoFields(videoStreams[i], i),
      ));
    }

    final audioStreams = streams
        .where((stream) => stream['Type']?.toString().toLowerCase() == 'audio')
        .toList();
    for (var i = 0; i < audioStreams.length; i++) {
      modules.add(_MediaDetailModule(
        title: '音频',
        fields: _buildAudioFields(audioStreams[i], i),
      ));
    }

    final subtitleStreams = streams
        .where(
            (stream) => stream['Type']?.toString().toLowerCase() == 'subtitle')
        .toList();
    for (var i = 0; i < subtitleStreams.length; i++) {
      modules.add(_MediaDetailModule(
        title: '字幕',
        fields: _buildSubtitleFields(subtitleStreams[i], i),
      ));
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = textColor.withValues(alpha: 0.08);
    final double edgePadding = horizontalPadding;
    const double betweenSpacing = 12;
    final EdgeInsets? textPadding = horizontalPadding > 0
        ? EdgeInsets.symmetric(horizontal: horizontalPadding)
        : null;

    final hasStreamModules =
        modules.any((module) => module.visibleFields.isNotEmpty);

    if (resourcePath.isEmpty && resourceMeta.isEmpty && !hasStreamModules) {
      return const SizedBox.shrink();
    }

    Widget buildTextSection() {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '媒体信息',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          if (resourcePath.isNotEmpty)
            SelectableText(
              resourcePath,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (resourceMeta.isNotEmpty) ...[
            if (resourcePath.isNotEmpty) const SizedBox(height: 6),
            Text(
              resourceMeta,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      );

      if (textPadding != null) {
        return Padding(padding: textPadding, child: content);
      }
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildTextSection(),
        if ((resourcePath.isNotEmpty || resourceMeta.isNotEmpty) &&
            hasStreamModules)
          const SizedBox(height: 16),
        if (hasStreamModules)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < modules.length; i++)
                  if (modules[i].visibleFields.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        left: _isFirstVisible(modules, i)
                            ? edgePadding
                            : betweenSpacing,
                        right: _nextVisibleIndex(modules, i) == null
                            ? edgePadding
                            : 0,
                      ),
                      // ✅ 使用 RepaintBoundary 隔离每个媒体卡片的重绘
                      child: RepaintBoundary(
                        child: _MediaModuleCard(
                          module: modules[i],
                          bgColor: bgColor,
                          borderColor: borderColor,
                          textColor: textColor,
                          isDark: isDark,
                        ),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  int? _nextVisibleIndex(List<_MediaDetailModule> modules, int current) {
    for (var i = current + 1; i < modules.length; i++) {
      if (modules[i].visibleFields.isNotEmpty) {
        return i;
      }
    }
    return null;
  }

  bool _isFirstVisible(List<_MediaDetailModule> modules, int current) {
    for (var i = 0; i < current; i++) {
      if (modules[i].visibleFields.isNotEmpty) {
        return false;
      }
    }
    return modules[current].visibleFields.isNotEmpty;
  }

  /// ✅ 判断影片是否有横向艺术图
  /// 用于判断"其他类似影片"列表的高度
  /// 注意：返回false表示是16:9（有Primary图片），返回true表示是2:3（有backdrop）
  bool _hasHorizontalArtworkForSimilar(ItemInfo item) {
    if (item.backdropImageTags != null && item.backdropImageTags!.isNotEmpty) {
      return true;
    }
    if (item.parentBackdropImageTags != null &&
        item.parentBackdropImageTags!.isNotEmpty) {
      return true;
    }
    if ((item.imageTags?['Primary'] ?? '').isEmpty) {
      return false;
    }
    return false;
  }

  /// ✅ 构建合集影片列表
  Widget _buildCollectionMovies(
      BuildContext context, String collectionId, bool isDark) {
    final collectionItems = ref.watch(collectionItemsProvider(collectionId));

    return collectionItems.when(
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '影片',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 218,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                // ✅ 添加 cacheExtent 提升横向列表性能
                cacheExtent: 300,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final bool isFirst = index == 0;
                  final bool isLast = index == items.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(
                      left: isFirst ? 0 : 12,
                      right: isLast ? 0 : 0,
                    ),
                    child: _CollectionMovieCard(
                      item: item,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 218,
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// ✅ 合集影片卡片
class _CollectionMovieCard extends ConsumerWidget {
  const _CollectionMovieCard({
    required this.item,
    required this.isDark,
  });

  final ItemInfo item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ 使用 RepaintBoundary 隔离每个合集影片卡片的重绘
    return RepaintBoundary(
      child: _buildCard(context, ref),
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref) {
    final textColor = isDark ? Colors.white : Colors.black87;
    const double cardWidth = 120.0;
    const double aspectRatio = 2 / 3;
    const double imageHeight = cardWidth / aspectRatio;

    // 计算播放进度
    final userData = item.userData ?? {};
    final totalTicks = item.runTimeTicks ?? 0;
    final playbackTicks =
        (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final played = userData['Played'] == true ||
        (totalTicks > 0 && playbackTicks >= totalTicks);
    final showProgress = !played && totalTicks > 0 && playbackTicks > 0;
    final progress = totalTicks > 0 ? playbackTicks / totalTicks : 0.0;
    final remainingTicks =
        totalTicks > playbackTicks ? totalTicks - playbackTicks : 0;
    final remainingDuration = Duration(microseconds: remainingTicks ~/ 10);

    String formatRemaining(Duration d) {
      if (d <= Duration.zero) {
        return '0s';
      }
      if (d.inHours >= 1) {
        final minutes = d.inMinutes.remainder(60);
        return minutes > 0 ? '${d.inHours}h ${minutes}m' : '${d.inHours}h';
      }
      if (d.inMinutes >= 1) {
        return '${d.inMinutes}m';
      }
      return '${d.inSeconds}s';
    }

    // 提取年份
    String? yearText;
    if (item.premiereDate != null && item.premiereDate!.isNotEmpty) {
      final startYear = int.tryParse(item.premiereDate!.substring(0, 4));
      if (startYear != null) {
        yearText = '$startYear';
      }
    } else if (item.productionYear != null) {
      yearText = '${item.productionYear}';
    }

    return SizedBox(
      width: cardWidth,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: item.id != null && item.id!.isNotEmpty
            ? () {
                context.push('/item/${item.id}');
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: imageHeight,
                width: cardWidth,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<EmbyApi>(
                      future: EmbyApi.create(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || item.id == null) {
                          return Container(
                            color: CupertinoColors.systemGrey5,
                            child: const Center(
                              child: Icon(
                                CupertinoIcons.film,
                                size: 32,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }
                        final api = snapshot.data!;
                        final url = api.buildImageUrl(
                          itemId: item.id!,
                          type: 'Primary',
                          maxWidth: 400,
                        );
                        if (url.isEmpty) {
                          return Container(
                            color: CupertinoColors.systemGrey5,
                            child: const Center(
                              child: Icon(
                                CupertinoIcons.film,
                                size: 32,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }
                        return EmbyFadeInImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            color: CupertinoColors.systemGrey5,
                            child: const Center(
                              child: CupertinoActivityIndicator(),
                            ),
                          ),
                        );
                      },
                    ),
                    // 播放完成标记
                    if (played)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.check_mark,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    // 播放进度
                    if (showProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.black.withValues(alpha: 0.0),
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '剩余 ${formatRemaining(remainingDuration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0.0,
                                    end: progress.clamp(0.0, 1.0),
                                  ),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, animatedValue, child) {
                                    return LinearProgressIndicator(
                                      value: animatedValue.clamp(0.0, 1.0),
                                      minHeight: 3,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        const Color(0xFFFFB74D)
                                            .withValues(alpha: 0.95),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: textColor,
              ),
            ),
            if (yearText != null) ...[
              const SizedBox(height: 2),
              Text(
                yearText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey : Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PerformerCard extends StatelessWidget {
  const _PerformerCard(
      {super.key, required this.performer, required this.isDark});

  final PerformerInfo performer;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final theme = Theme.of(context);
    const double cardWidth = 95;
    const double cardHeight = 143;

    // ✅ 使用 RepaintBoundary 隔离每个演员卡片的重绘
    return RepaintBoundary(
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: cardHeight,
                width: cardWidth,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _buildPerformerImage(context),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _extractChineseName(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _extractEnglishName(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformerImage(BuildContext context) {
    if (performer.id.isEmpty || performer.primaryImageTag == null) {
      return Container(
        color: Colors.grey.withOpacity(0.2),
        child: const Icon(CupertinoIcons.person, size: 36, color: Colors.grey),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(color: Colors.grey.withOpacity(0.2));
        }
        final url = snapshot.data!.buildImageUrl(
          itemId: performer.id,
          type: 'Primary',
          maxWidth: 300,
          tag: performer.primaryImageTag,
        );
        // ✅ 使用稳定的 key（基于 performer.id + URL），只有图片 URL 变化时才重新加载
        return EmbyFadeInImage(
          key: ValueKey('performer_image_${performer.id}_$url'),
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
    );
  }

  String _extractChineseName() {
    final name = performer.name.trim();
    final role = (performer.role ?? '').trim();

    final candidateFromDelimiters = _extractBeforeDelimiter(name);
    if (_containsChinese(candidateFromDelimiters)) {
      return candidateFromDelimiters;
    }

    final regex = RegExp(r'[\u4e00-\u9fa5]+');
    final fromName = regex.allMatches(name).map((m) => m.group(0)).join();
    if (fromName.isNotEmpty) {
      return fromName;
    }
    final fromRole = regex.allMatches(role).map((m) => m.group(0)).join();
    if (fromRole.isNotEmpty) {
      return fromRole;
    }
    return name.isNotEmpty ? name : role;
  }

  String _extractEnglishName() {
    final name = performer.name.trim();
    final role = (performer.role ?? '').trim();

    final fromParentheses = _extractInsideParentheses(name);
    if (_containsLatin(fromParentheses)) {
      return fromParentheses;
    }

    final fromDelimiter = _extractAfterDelimiter(name);
    if (_containsLatin(fromDelimiter)) {
      return fromDelimiter;
    }

    final englishFromName = _extractEnglishFrom(name);
    if (englishFromName.isNotEmpty) {
      return englishFromName;
    }
    final englishFromRole = _extractEnglishFrom(role);
    if (englishFromRole.isNotEmpty) {
      return englishFromRole;
    }
    if (!_containsChinese(name) && name.isNotEmpty) {
      return name;
    }
    return role.isNotEmpty ? role : '';
  }

  String _extractEnglishFrom(String source) {
    if (source.isEmpty) return '';
    final regex = RegExp(r'[A-Za-z][A-Za-z .]*');
    return regex
        .allMatches(source)
        .map((m) => (m.group(0) ?? '').trim())
        .where((segment) => segment.isNotEmpty)
        .join(' ')
        .trim();
  }

  bool _containsChinese(String source) {
    return RegExp(r'[\u4e00-\u9fa5]').hasMatch(source);
  }

  bool _containsLatin(String source) {
    return RegExp(r'[A-Za-z]').hasMatch(source);
  }

  String _extractInsideParentheses(String source) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(source);
    if (match != null) {
      return match.group(1)?.trim() ?? '';
    }
    return '';
  }

  String _extractBeforeDelimiter(String source) {
    for (final delimiter in const ['/', '|', '｜']) {
      final index = source.indexOf(delimiter);
      if (index > 0) {
        return source.substring(0, index).trim();
      }
    }
    return source;
  }

  String _extractAfterDelimiter(String source) {
    for (final delimiter in const ['/', '|', '｜']) {
      final index = source.indexOf(delimiter);
      if (index >= 0 && index + 1 < source.length) {
        return source.substring(index + 1).trim();
      }
    }
    return '';
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({super.key, required this.item, required this.isDark});

  final ItemInfo item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final hasHorizontalArtwork = _hasHorizontalArtwork(item);
    final double cardWidth = hasHorizontalArtwork ? 95 : 160;
    final double aspectRatio = hasHorizontalArtwork ? 2 / 3 : 16 / 9;
    final double imageHeight = cardWidth / aspectRatio;

    // ✅ 使用 RepaintBoundary 隔离每个类似影片卡片的重绘
    return RepaintBoundary(
      child: SizedBox(
        width: cardWidth,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: item.id != null && item.id!.isNotEmpty
              ? () => _handleTap(context)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: imageHeight,
                  width: cardWidth,
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: _buildPoster(
                        hasHorizontalArtwork: hasHorizontalArtwork),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _buildSubtitle(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoster({required bool hasHorizontalArtwork}) {
    if (item.id == null || item.id!.isEmpty) {
      return Container(
        color: Colors.grey.withOpacity(0.2),
        child: const Icon(CupertinoIcons.film, size: 32, color: Colors.grey),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: Colors.grey.withOpacity(0.1),
            child: const Center(child: CupertinoActivityIndicator()),
          );
        }
        final api = snapshot.data!;
        String? url;
        if ((item.imageTags?['Primary'] ?? '').isNotEmpty) {
          url = api.buildImageUrl(
            itemId: item.id!,
            type: 'Primary',
            maxWidth: hasHorizontalArtwork ? 480 : 320,
          );
        }

        if ((url == null || url.isEmpty) && hasHorizontalArtwork) {
          url = api.buildImageUrl(
            itemId: item.id!,
            type: 'Backdrop',
            maxWidth: 720,
          );
        }

        if (url == null || url.isEmpty) {
          return Container(
            color: Colors.grey.withOpacity(0.1),
            child: const Center(child: Icon(CupertinoIcons.photo, size: 28)),
          );
        }

        // ✅ 使用稳定的 key（基于 item.id + URL），只有图片 URL 变化时才重新加载
        return EmbyFadeInImage(
          key: ValueKey('similar_image_${item.id}_$url'),
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
    );
  }

  String _buildSubtitle() {
    final year = item.productionYear?.toString();
    if (year != null && year.isNotEmpty) {
      return year;
    }
    return item.type.isNotEmpty ? item.type : '推荐';
  }

  void _handleTap(BuildContext context) {
    final id = item.id;
    if (id == null || id.isEmpty) return;

    if (item.type == 'Series') {
      context.push('/series/$id?name=${Uri.encodeComponent(item.name)}');
    } else if (item.type == 'Movie') {
      context.push('/item/$id');
    } else {
      context.push('/player/$id');
    }
  }

  bool _hasHorizontalArtwork(ItemInfo item) {
    if (item.backdropImageTags != null && item.backdropImageTags!.isNotEmpty) {
      return true;
    }
    if (item.parentBackdropImageTags != null &&
        item.parentBackdropImageTags!.isNotEmpty) {
      return true;
    }
    if ((item.imageTags?['Primary'] ?? '').isEmpty) {
      return false;
    }
    return false;
  }
}

class _MediaFieldRow extends StatelessWidget {
  const _MediaFieldRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isDark
          ? Colors.white.withValues(alpha: 0.7)
          : Colors.black.withValues(alpha: 0.55),
      fontWeight: FontWeight.w500,
    );
    final valueStyle = TextStyle(
      fontSize: 11.5,
      color: isDark ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: labelStyle),
          TextSpan(text: value, style: valueStyle),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _MediaDetailModule {
  _MediaDetailModule({
    required this.title,
    required this.fields,
  });

  final String title;
  final List<_MediaDetailField> fields;

  List<_MediaDetailField> get visibleFields =>
      fields.where((field) => field.value.isNotEmpty).toList();
}

class _MediaDetailField {
  _MediaDetailField(this.label, this.value);

  final String label;
  final String value;
}

class _MediaModuleCard extends StatelessWidget {
  const _MediaModuleCard({
    required this.module,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.isDark,
  });

  final _MediaDetailModule module;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            module.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < module.visibleFields.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            _MediaFieldRow(
              label: module.visibleFields[i].label,
              value: module.visibleFields[i].value,
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }
}

List<_MediaDetailField> _buildVideoFields(
    Map<String, dynamic> stream, int index) {
  final fields = <_MediaDetailField>[];

  void add(String label, String? value) {
    if (value == null || value.isEmpty) return;
    fields.add(_MediaDetailField(label, value));
  }

  add('编号', '#${index + 1}');
  add('标题', stream['DisplayTitle']?.toString() ?? stream['Title']?.toString());
  add('语言', _formatLanguage(stream['Language']));
  add('编解码器', stream['Codec']?.toString().toUpperCase());
  add('配置', stream['Profile']?.toString());
  add('等级', stream['Level']?.toString());
  add('分辨率', _formatResolution(stream));
  add('宽高比', _formatAspectRatio(stream));
  add('隔行', _formatBoolFlag(stream['IsInterlaced']));
  add('帧率',
      _formatFrameRate(stream['RealFrameRate'] ?? stream['AverageFrameRate']));
  add('比特率', _formatBitrate(stream['BitRate']));
  add('基色',
      stream['ColorPrimaries']?.toString() ?? stream['ColorSpace']?.toString());
  add('深位度', _formatBitDepth(stream['BitDepth']));
  add('像素格式', stream['PixelFormat']?.toString());
  add('参考帧', stream['RefFrames']?.toString());
  add('基色范围', stream['VideoRange']?.toString());
  add('基色类型', stream['VideoRangeType']?.toString());

  return fields;
}

List<_MediaDetailField> _buildAudioFields(
    Map<String, dynamic> stream, int index) {
  final fields = <_MediaDetailField>[];

  void add(String label, String? value) {
    if (value == null || value.isEmpty) return;
    fields.add(_MediaDetailField(label, value));
  }

  add('编号', '#${index + 1}');
  add('标题', stream['DisplayTitle']?.toString() ?? stream['Title']?.toString());
  add('语言', _formatLanguage(stream['Language']));
  add('布局', stream['ChannelLayout']?.toString());
  add('频道', _formatChannels(stream['Channels']));
  add('采样率', _formatSampleRate(stream['SampleRate']));
  add('默认', _formatBoolFlag(stream['IsDefault']));
  add('编解码器', stream['Codec']?.toString().toUpperCase());
  add('配置', stream['Profile']?.toString());
  add('比特率', _formatBitrate(stream['BitRate']));
  add('位深', _formatBitDepth(stream['BitDepth']));
  add('等级', stream['Level']?.toString());

  return fields;
}

List<_MediaDetailField> _buildSubtitleFields(
    Map<String, dynamic> stream, int index) {
  final fields = <_MediaDetailField>[];

  void add(String label, String? value) {
    if (value == null || value.isEmpty) return;
    fields.add(_MediaDetailField(label, value));
  }

  add('编号', '#${index + 1}');
  add('标题', stream['DisplayTitle']?.toString() ?? stream['Title']?.toString());
  add('语言', _formatLanguage(stream['Language']));
  add('默认', _formatBoolFlag(stream['IsDefault']));
  add('强制', _formatBoolFlag(stream['IsForced']));
  add('听力障碍', _formatBoolFlag(stream['IsHearingImpaired']));
  add('外部', _formatBoolFlag(stream['IsExternal']));
  add('编解码器', stream['Codec']?.toString().toUpperCase());
  add('配置', stream['Profile']?.toString());
  add('比特率', _formatBitrate(stream['BitRate']));

  return fields;
}

String _formatResolution(Map<String, dynamic> stream) {
  final width = stream['Width'];
  final height = stream['Height'];
  if (width == null || height == null) return '';
  return '${width}x$height';
}

String _formatAspectRatio(Map<String, dynamic> stream) {
  final aspect = stream['AspectRatio']?.toString();
  if (aspect != null && aspect.isNotEmpty) return aspect;
  final width = (stream['Width'] as num?);
  final height = (stream['Height'] as num?);
  if (width != null && height != null && height != 0) {
    final ratio = width / height;
    return ratio.toStringAsFixed(2);
  }
  return '';
}

String _formatFrameRate(dynamic value) {
  if (value == null) return '';
  final rate = double.tryParse(value.toString());
  if (rate == null || rate <= 0) return '';
  return '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)} fps';
}

String _formatBitrate(dynamic value) {
  if (value == null) return '';
  final bitrate = int.tryParse(value.toString());
  if (bitrate == null || bitrate <= 0) return '';
  if (bitrate >= 1000000) {
    return '${(bitrate / 1000000).toStringAsFixed(2)} Mbps';
  }
  if (bitrate >= 1000) {
    return '${(bitrate / 1000).toStringAsFixed(1)} Kbps';
  }
  return '$bitrate bps';
}

String _formatBoolFlag(dynamic value) {
  if (value == null) return '';
  return (value == true || value == 'true') ? '是' : '否';
}

String _formatSampleRate(dynamic value) {
  if (value == null) return '';
  final rate = int.tryParse(value.toString());
  if (rate == null || rate <= 0) return '';
  if (rate >= 1000) {
    return '${(rate / 1000).toStringAsFixed(1)} kHz';
  }
  return '$rate Hz';
}

String _formatChannels(dynamic value) {
  if (value == null) return '';
  final channels = int.tryParse(value.toString());
  if (channels == null || channels <= 0) return '';
  return channels.toString();
}

String _formatBitDepth(dynamic value) {
  if (value == null) return '';
  final depth = int.tryParse(value.toString());
  if (depth == null || depth <= 0) return '';
  return '$depth-bit';
}

String _formatLanguage(dynamic value) {
  if (value == null) return '';
  final text = value.toString();
  if (text.isEmpty) return '';
  return text;
}

String _formatBytes(dynamic value) {
  if (value == null) return '';
  final size = int.tryParse(value.toString());
  if (size == null || size <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var currentSize = size.toDouble();
  var unitIndex = 0;
  while (currentSize >= 1024 && unitIndex < units.length - 1) {
    currentSize /= 1024;
    unitIndex++;
  }
  return '${currentSize.toStringAsFixed(currentSize >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

String _formatDateTime(dynamic value) {
  if (value == null) return '';
  DateTime? dateTime;
  if (value is DateTime) {
    dateTime = value;
  } else {
    dateTime = DateTime.tryParse(value.toString());
  }
  if (dateTime == null) return '';
  return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
}

String _mergeFormatSizeDate(String format, String size, String date) {
  final pieces = <String>[];
  if (format.isNotEmpty) pieces.add(format);
  if (size.isNotEmpty) pieces.add(size);
  if (date.isNotEmpty) pieces.add(date);
  return pieces.join(' · ');
}

/// ✅ 优化10：LRU 缓存，避免无限增长导致内存泄漏
class _LRUCache<K, V> {
  final int maxSize;
  final Map<K, V> _cache = {};
  final List<K> _keys = [];

  _LRUCache(this.maxSize);

  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // 移动到最前面（最近使用）
    _keys.remove(key);
    _keys.add(key);
    return _cache[key];
  }

  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      // 已存在，更新位置
      _keys.remove(key);
    } else if (_cache.length >= maxSize) {
      // 缓存满了，移除最旧的
      final oldestKey = _keys.removeAt(0);
      _cache.remove(oldestKey);
    }

    _cache[key] = value;
    _keys.add(key);
  }
}
