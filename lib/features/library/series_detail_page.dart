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

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../providers/library_provider.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/status_bar_manager.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../utils/app_route_observer.dart';
import '../../utils/theme_utils.dart';

// ✅ 获取剧集详情
final seriesProvider =
    FutureProvider.family<ItemInfo, String>((ref, seriesId) async {
  ref.watch(libraryRefreshTickerProvider);
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, seriesId);
});

// ✅ 获取剧集的季列表（不依赖 libraryRefreshTickerProvider，季列表不会因为观看状态变化而改变）
// 季的观看状态由 seasonWatchStatsProvider 单独管理，不需要重新加载整个季列表
final seasonsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, seriesId) async {
  // ✅ 不 watch libraryRefreshTickerProvider，避免按钮点击时重新加载整个季列表
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return const [];
  }
  final api = await EmbyApi.create();
  return api.getSeasons(userId: auth.userId!, seriesId: seriesId);
});

// ✅ 获取某个季的观看统计信息（不依赖 libraryRefreshTickerProvider）
// 只在观看按钮点击时手动刷新，收藏按钮不会触发刷新
final seasonWatchStatsProvider = FutureProvider.family<
    ({int totalEpisodes, int watchedEpisodes, bool allWatched}),
    (String seriesId, String seasonId)>((ref, params) async {
  // ✅ 不 watch libraryRefreshTickerProvider，避免收藏按钮触发不必要的刷新
  // 只在观看按钮点击时通过 ref.invalidate 手动刷新
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return (totalEpisodes: 0, watchedEpisodes: 0, allWatched: false);
  }
  try {
    final api = await EmbyApi.create();
    final episodes = await api.getEpisodes(
      userId: auth.userId!,
      seriesId: params.$1,
      seasonId: params.$2,
    );

    int watchedCount = 0;
    for (final episode in episodes) {
      final userData = episode.userData ?? {};
      final played = userData['Played'] == true;
      if (played) {
        watchedCount++;
      }
    }

    final total = episodes.length;
    final allWatched = total > 0 && watchedCount == total;

    return (
      totalEpisodes: total,
      watchedEpisodes: watchedCount,
      allWatched: allWatched,
    );
  } catch (e) {
    return (totalEpisodes: 0, watchedEpisodes: 0, allWatched: false);
  }
});

// ✅ 获取剧集的继续观看集数
final nextUpEpisodeProvider =
    FutureProvider.family<ItemInfo?, String>((ref, seriesId) async {
  ref.watch(libraryRefreshTickerProvider);
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return null;
  }
  try {
    final api = await EmbyApi.create();
    // 获取该剧集的所有集数，找到有播放进度且未完成的
    final episodes = await api.getItemsByParent(
      userId: auth.userId!,
      parentId: seriesId,
      includeItemTypes: 'Episode',
      limit: 1000,
      sortBy: 'DatePlayed',
      sortOrder: 'Descending',
    );

    // 找到第一个有播放进度且未完成的集数
    for (final episode in episodes) {
      final userData = episode.userData ?? {};
      final playbackTicks =
          (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
      final totalTicks = episode.runTimeTicks ?? 0;
      final played = userData['Played'] == true;

      if (!played && playbackTicks > 0 && playbackTicks < totalTicks) {
        return episode;
      }
    }
    return null;
  } catch (e) {
    return null;
  }
});

// ✅ 获取类似影片（不依赖 libraryRefreshTickerProvider，与演员逻辑一致）
final similarItemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, seriesId) async {
  // ✅ 不 watch libraryRefreshTickerProvider，避免按钮点击时重新请求
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return const [];
  }
  final api = await ref.read(embyApiProvider.future);
  final items = await api.getSimilarItems(auth.userId!, seriesId, limit: 12);
  return items;
});

class SeriesDetailPage extends ConsumerStatefulWidget {
  const SeriesDetailPage({required this.seriesId, super.key});
  final String seriesId;

  @override
  ConsumerState<SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends ConsumerState<SeriesDetailPage>
    with RouteAware {
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
  final Map<String, SystemUiOverlayStyle> _imageStyleCache = {};
  // ✅ 使用 ValueNotifier 来局部更新收藏和观看状态
  ValueNotifier<bool>? _isFavoriteNotifier;
  ValueNotifier<bool>? _isPlayedNotifier;
  ValueNotifier<Map<String, dynamic>?>? _userDataNotifier;
  static const Color _resumeButtonColor = Color(0xFFFFB74D);
  static const Color _playButtonColor = Color(0xFF3F8CFF);
  bool _showCollapsedNav = false;
  static const double _backdropHeight = 300;
  static const double _headerTopOffset = 250;
  static const double _headerBaseHeight = 180;
  static const double _heroBaseHeight = _backdropHeight +
      (_headerTopOffset + _headerBaseHeight - _backdropHeight);
  double _headerHeight = _headerBaseHeight;
  SystemUiOverlayStyle? _navSyncedStyle;
  late SystemUiOverlayStyle _appliedStatusStyle;
  StatusBarStyleController? _statusBarController;
  ModalRoute<dynamic>? _modalRoute;
  Animation<double>? _routeAnimation;
  bool _isRouteSubscribed = false; // ✅ 路由订阅状态
  ItemInfo? _cachedItemData; // ✅ 缓存item数据，避免重新加载时显示loading
  ItemInfo? _cachedNextUpEpisode; // ✅ 缓存下一集数据，避免刷新时闪烁

  @override
  void initState() {
    super.initState();
    // ✅ 初始化收藏和观看状态 ValueNotifier
    _isFavoriteNotifier = ValueNotifier<bool>(false);
    _isPlayedNotifier = ValueNotifier<bool>(false);
    _userDataNotifier = ValueNotifier<Map<String, dynamic>?>(null);
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _statusBarStyle = StatusBarManager.currentStyle ??
        _defaultStyleForBrightness(platformBrightness);
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncStatusBarWithNavigation(
          _scrollController.hasClients ? _scrollController.offset : 0.0);
    });
    _appliedStatusStyle = _statusBarStyle;
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
    // ✅ 订阅路由观察者，用于检测页面返回
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
    // ✅ 取消订阅路由观察者
    if (_isRouteSubscribed) {
      appRouteObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    // ✅ 释放 ValueNotifier
    _isFavoriteNotifier?.dispose();
    _isPlayedNotifier?.dispose();
    _userDataNotifier?.dispose();
    _statusBarController?.release();
    _statusBarController = null;
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _removeRouteListener();
    super.dispose();
  }

  // ✅ 当从其他页面返回时，seriesProvider 会自动重新加载
  @override
  void didPopNext() {
    super.didPopNext();
  }

  void _handleScroll() {
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final shouldShow = offset > 200;
    if (shouldShow != _showCollapsedNav) {
      setState(() {
        _showCollapsedNav = shouldShow;
      });
    }
    _syncStatusBarWithNavigation(offset);
  }

  // ✅ 防止在 API 调用期间被 whenData 覆盖状态
  bool _isUpdatingFavorite = false;
  bool _isUpdatingPlayed = false;

  @override
  Widget build(BuildContext context) {
    final series = ref.watch(seriesProvider(widget.seriesId));

    // ✅ 当 seriesProvider 重新加载数据时（比如从播放页面返回时）
    series.whenData((data) {
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
    });

    return StatusBarStyleScope(
      style: _statusBarStyle,
      child: Builder(
        builder: (context) {
          _statusBarController = StatusBarStyleScope.of(context);
          _statusBarController?.update(_navSyncedStyle ?? _statusBarStyle);
          return CupertinoPageScaffold(
            backgroundColor: CupertinoColors.systemBackground,
            child: series.maybeWhen(
              data: (data) => _buildContentArea(data),
              loading: () {
                // ✅ 如果有缓存数据，继续显示缓存数据，不显示loading（避免切换按钮时闪烁）
                if (_cachedItemData != null) {
                  return _buildContentArea(_cachedItemData!);
                }
                // ✅ 如果没有缓存数据，只显示导航栏，不显示loading
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildBlurNavigationBar(context, null),
                    ),
                  ],
                );
              },
              error: (e, _) => Stack(
                children: [
                  Center(child: Text('加载失败: $e')),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildBlurNavigationBar(context, null),
                  ),
                ],
              ),
              orElse: () {
                // ✅ 如果 series 还没有数据且没有缓存，只显示导航栏，不显示loading
                if (_cachedItemData == null) {
                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildBlurNavigationBar(context, null),
                      ),
                    ],
                  );
                }
                // ✅ 有缓存数据，显示缓存数据
                return _buildContentArea(_cachedItemData!);
              },
            ),
          );
        },
      ),
    );
  }

  /// ✅ 构建内容区域（避免在loading和orElse中重复代码）
  Widget _buildContentArea(ItemInfo data) {
    final isDark = isDarkModeFromContext(context, ref);
    final performers = data.performers ?? const <PerformerInfo>[];
    final externalLinks = _composeExternalLinks(data);
    // ✅ 使用 ref.read 而不是 ref.watch，避免因为 libraryRefreshTickerProvider 变化而重新构建
    // 与演员逻辑一致，只在首次加载时请求，不会因为按钮点击而重新请求
    final similarItems = ref.read(similarItemsProvider(widget.seriesId));
    final seasons = ref.watch(seasonsProvider(widget.seriesId));

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: _heroBaseHeight + (_headerHeight - _headerBaseHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: _backdropHeight,
                      child: _buildBackdropBackground(context, data),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _headerTopOffset,
                      child: seasons.when(
                        data: (seasonsList) => _buildHeaderCard(
                            context, data, isDark, seasonsList.length),
                        loading: () =>
                            _buildHeaderCard(context, data, isDark, null),
                        error: (_, __) =>
                            _buildHeaderCard(context, data, isDark, null),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ 季模块（始终显示，预留固定高度）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '季',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 175,
                        child: seasons.when(
                          data: (seasonsList) {
                            if (seasonsList.isEmpty) {
                              // 空状态：显示占位内容
                              return const SizedBox.shrink();
                            }
                            return ListView.builder(
                              padding: EdgeInsets.zero,
                              scrollDirection: Axis.horizontal,
                              itemCount: seasonsList.length,
                              itemBuilder: (context, index) {
                                final season = seasonsList[index];
                                final bool isFirst = index == 0;
                                final bool isLast =
                                    index == seasonsList.length - 1;
                                return Padding(
                                  key: ValueKey(
                                      'season_${season.id}'), // ✅ 使用稳定的 key，避免卡片重新创建
                                  padding: EdgeInsets.only(
                                    left: isFirst ? 20 : 12,
                                    right: isLast ? 20 : 0,
                                  ),
                                  child: _SeasonCard(
                                    key: ValueKey(
                                        'season_card_${season.id}'), // ✅ 使用稳定的 key，避免卡片重新创建
                                    season: season,
                                    seriesId: widget.seriesId,
                                    isDark: isDark,
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                  if (performers.isNotEmpty) ...[
                    const SizedBox(height: 24),
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
                        itemBuilder: (context, index) {
                          final card = _PerformerCard(
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
                  similarItems.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      // ✅ 所有卡片统一为90x140（2:3比例），与演员海报一致
                      final listHeight = 190.0;
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
                              itemBuilder: (context, index) {
                                final card = _SimilarCard(
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
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  if (externalLinks.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildExternalLinks(externalLinks, isDark),
                    ),
                  ],
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildBlurNavigationBar(context, data),
        ),
      ],
    );
  }

  Widget _buildBlurNavigationBar(
    BuildContext context,
    ItemInfo? data,
  ) {
    final brightness = getCurrentBrightnessFromContext(context, ref);
    final SystemUiOverlayStyle baseStyle = _appliedStatusStyle;
    final SystemUiOverlayStyle targetStyle =
        _navSyncedStyle ?? _appliedStatusStyle;

    final Color expandedColor = _colorForStatusStyle(baseStyle, brightness);
    final Color collapsedColor = _colorForStatusStyle(targetStyle, brightness);
    final Color currentColor = Color.lerp(
        expandedColor, collapsedColor, _showCollapsedNav ? 1.0 : 0.0)!;

    final actions =
        data != null ? _buildTopActions(data, currentColor) : const <Widget>[];

    final Widget leadingContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildBlurBackButton(context, color: currentColor),
        if (data != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            child: _showCollapsedNav
                ? Transform.translate(
                    key: const ValueKey('title-visible'),
                    offset: const Offset(-12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 220,
                          minHeight: 24,
                        ),
                        child: _CollapsedTitle(item: data),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('title-hidden')),
          ),
      ],
    );

    return BlurNavigationBar(
      forceBlur: false,
      scrollController: _scrollController,
      leading: leadingContent,
      middle: null,
      trailing: actions.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
      expandedForegroundColor: expandedColor,
      collapsedForegroundColor: collapsedColor,
      enableTransition: false,
      useDynamicOpacity: true,
      blurStart: 10.0,
      blurEnd: _headerTopOffset,
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

  SystemUiOverlayStyle _defaultStyleForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _lightStatusBar : _darkStatusBar;
  }

  Widget _buildBackdropBackground(BuildContext context, ItemInfo item) {
    final isDark = isDarkModeFromContext(context, ref);
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.id != null)
          FutureBuilder<EmbyApi>(
            future: EmbyApi.create(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container(color: CupertinoColors.systemGrey5);
              }
              final api = snapshot.data!;
              String? backdropUrl;

              if ((item.backdropImageTags?.isNotEmpty ?? false) ||
                  (item.parentBackdropImageTags?.isNotEmpty ?? false)) {
                backdropUrl = api.buildImageUrl(
                  itemId: item.id!,
                  type: 'Backdrop',
                  maxWidth: 1200,
                );
              }

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
                return Container(color: CupertinoColors.systemGrey5);
              }

              return EmbyFadeInImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                onImageReady: (image) =>
                    _handleBackdropImage(image, item.id ?? backdropUrl!),
              );
            },
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  bgColor.withOpacity(0.65),
                  bgColor,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
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

  Widget _buildHeaderCard(
      BuildContext context, ItemInfo item, bool isDark, int? seasonsCount) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    return _MeasureSize(
      onChange: (size) {
        if (size == null) return;
        final height = size.height;
        if (height <= 0) return;
        if ((_headerHeight - height).abs() > 0.5) {
          setState(() {
            _headerHeight = height;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFallbackTitleText(item.name, textColor),
            const SizedBox(height: 10),
            _buildMetaInfo(item, isDark, seasonsCount),
            const SizedBox(height: 10),
            _buildMediaInfo(item, isDark),
            const SizedBox(height: 18),
            _buildPlaySection(context, item, isDark),
            if ((item.overview ?? '').isNotEmpty) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => _showOverviewDialog(item),
                child: Text(
                  item.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackTitleText(String title, Color textColor) {
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: textColor,
        height: 1.2,
      ),
    );
  }

  Widget _buildMetaInfo(ItemInfo item, bool isDark, int? seasonsCount) {
    final List<String> metaItems = [];

    // 1. 评分（放在第一位）
    final rating = item.getRating();
    if (rating != null) {
      if (item.getRatingSource() == 'douban') {
        metaItems.add('豆 ${rating.toStringAsFixed(1)}');
      } else {
        metaItems.add('⭐ ${rating.toStringAsFixed(1)}');
      }
    }

    // 2. 来源（从providerIds获取，如果没有则显示"未知"）
    String source = '未知';
    if (item.providerIds != null && item.providerIds!.isNotEmpty) {
      // 优先显示豆瓣，其次IMDb，再次TMDb
      if (item.providerIds!.containsKey('Douban')) {
        source = '豆瓣';
      } else if (item.providerIds!.containsKey('Imdb')) {
        source = 'IMDb';
      } else if (item.providerIds!.containsKey('Tmdb')) {
        source = 'TMDb';
      } else {
        source = item.providerIds!.keys.first;
      }
    }
    metaItems.add(source);

    // 3. 年份（按照列表海报的显示格式）
    String? yearText;
    if (item.premiereDate != null && item.premiereDate!.isNotEmpty) {
      final startYear = int.tryParse(item.premiereDate!.substring(0, 4));
      if (startYear != null) {
        // ✅ 对于Series类型，根据Status和EndDate判断
        if (item.type == 'Series') {
          final status = item.status;
          if (status == 'Ended') {
            // ✅ Status 为 Ended
            if (item.endDate != null && item.endDate!.isNotEmpty) {
              // ✅ 存在 EndDate，显示 xxxx-xxxx
              final endYear = int.tryParse(item.endDate!.substring(0, 4));
              if (endYear != null && endYear != startYear) {
                yearText = '$startYear-$endYear';
              } else {
                yearText = '$startYear';
              }
            } else {
              // ✅ 不存在 EndDate，显示 xxxx
              yearText = '$startYear';
            }
          } else if (status == 'Continuing') {
            // ✅ Status 为 Continuing，显示 xxxx-现在
            yearText = '$startYear-现在';
          } else {
            // ✅ 其他状态，显示开始年份
            yearText = '$startYear';
          }
        } else {
          // ✅ 非Series类型，使用EndDate判断
          if (item.endDate != null && item.endDate!.isNotEmpty) {
            final endYear = int.tryParse(item.endDate!.substring(0, 4));
            if (endYear != null && endYear != startYear) {
              yearText = '$startYear-$endYear';
            } else {
              yearText = '$startYear';
            }
          } else {
            yearText = '$startYear';
          }
        }
      }
    } else if (item.productionYear != null) {
      // ✅ 如果没有 premiereDate，使用 productionYear
      final startYear = item.productionYear;
      if (item.type == 'Series') {
        // ✅ 对于Series类型，根据Status和EndDate判断
        final status = item.status;
        if (status == 'Ended') {
          // ✅ Status 为 Ended
          if (item.endDate != null && item.endDate!.isNotEmpty) {
            // ✅ 存在 EndDate，显示 xxxx-xxxx
            final endYear = int.tryParse(item.endDate!.substring(0, 4));
            if (endYear != null && endYear != startYear) {
              yearText = '$startYear-$endYear';
            } else {
              yearText = '$startYear';
            }
          } else {
            // ✅ 不存在 EndDate，显示 xxxx
            yearText = '$startYear';
          }
        } else if (status == 'Continuing') {
          // ✅ Status 为 Continuing，显示 xxxx-现在
          yearText = '$startYear-现在';
        } else {
          // ✅ 其他状态，显示开始年份
          yearText = '$startYear';
        }
      } else {
        // ✅ 非Series类型，直接显示年份
        yearText = '$startYear';
      }
    }
    if (yearText != null) {
      metaItems.add(yearText);
    }

    // 4. 分类（只显示第一个）
    if (item.genres != null && item.genres!.isNotEmpty) {
      metaItems.add(item.genres!.first);
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
    final textColor = isDark ? Colors.white : Colors.black87;
    final textStyle = TextStyle(color: textColor, fontSize: 13, height: 1.4);
    final widgets = <Widget>[];

    void addRow(String label, String value) {
      if (value.isEmpty) return;
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 6));
      }
      widgets.add(Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$label: ', style: textStyle),
          Expanded(
            child: Text(
              value,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ));
    }

    // 类型
    if (genres.isNotEmpty) {
      addRow('类型', genres.join(' / '));
    }

    // 工作室（从item的Studio字段获取，如果没有则从其他字段获取）
    // 注意：ItemInfo可能没有Studio字段，需要从API响应中获取
    // 这里先留空，如果需要可以从item的其他字段获取

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPlaySection(
      BuildContext context, ItemInfo item, bool isDarkBackground) {
    // ✅ 使用 Consumer 监听 nextUpEpisodeProvider，但只在数据变化时更新缓存
    // 这样可以避免因为 libraryRefreshTickerProvider 变化导致的频繁重建
    return Consumer(
      builder: (context, ref, _) {
        // ✅ 使用 ref.listen 监听 nextUpEpisodeProvider 的变化，更新缓存
        // 但不直接 watch，避免频繁重建
        final nextUpEpisodeAsync =
            ref.watch(nextUpEpisodeProvider(widget.seriesId));
        nextUpEpisodeAsync.whenData((episode) {
          // ✅ 缓存下一集数据，避免刷新时闪烁
          _cachedNextUpEpisode = episode;
        });

        // ✅ 使用 ValueListenableBuilder 来局部更新播放进度
        return ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: _userDataNotifier!,
          builder: (context, userData, _) {
            // ✅ 优先使用缓存的数据，避免刷新时的 loading 状态导致闪烁
            return nextUpEpisodeAsync.when(
              data: (episode) {
                // ✅ 如果有继续观看的集数，显示继续观看滚动条
                if (episode != null) {
                  // ✅ 使用缓存的 userData 更新 episode 的播放进度（如果 userData 更新了）
                  final updatedUserData =
                      userData != null && episode.userData != null
                          ? {...episode.userData!, ...userData}
                          : (userData ?? episode.userData);
                  // ✅ 创建新的 ItemInfo，只更新 userData
                  final updatedEpisode = updatedUserData != episode.userData
                      ? ItemInfo(
                          id: episode.id,
                          name: episode.name,
                          type: episode.type,
                          overview: episode.overview,
                          runTimeTicks: episode.runTimeTicks,
                          userData: updatedUserData,
                          seriesName: episode.seriesName,
                          parentIndexNumber: episode.parentIndexNumber,
                          indexNumber: episode.indexNumber,
                          seriesId: episode.seriesId,
                          seasonId: episode.seasonId,
                          seriesPrimaryImageTag: episode.seriesPrimaryImageTag,
                          seasonPrimaryImageTag: episode.seasonPrimaryImageTag,
                          imageTags: episode.imageTags,
                          backdropImageTags: episode.backdropImageTags,
                          parentThumbItemId: episode.parentThumbItemId,
                          parentThumbImageTag: episode.parentThumbImageTag,
                          parentBackdropItemId: episode.parentBackdropItemId,
                          parentBackdropImageTags:
                              episode.parentBackdropImageTags,
                          genres: episode.genres,
                          mediaSources: episode.mediaSources,
                          performers: episode.performers,
                          premiereDate: episode.premiereDate,
                          endDate: episode.endDate,
                          productionYear: episode.productionYear,
                          communityRating: episode.communityRating,
                          childCount: episode.childCount,
                          providerIds: episode.providerIds,
                          dateCreated: episode.dateCreated,
                          status: episode.status,
                          externalUrls: episode.externalUrls,
                        )
                      : episode;
                  return _buildResumeEpisodeSection(
                      context, updatedEpisode, isDarkBackground);
                }
                // ✅ 如果没有继续观看，显示播放按钮（从第一季第一集开始）
                return _buildPlayButton(context, item, isDarkBackground);
              },
              loading: () {
                // ✅ 如果有缓存的 episode，在 loading 时也显示它，避免闪烁
                if (_cachedNextUpEpisode != null) {
                  final episode = _cachedNextUpEpisode!;
                  final updatedUserData =
                      userData != null && episode.userData != null
                          ? {...episode.userData!, ...userData}
                          : (userData ?? episode.userData);
                  final updatedEpisode = updatedUserData != episode.userData
                      ? ItemInfo(
                          id: episode.id,
                          name: episode.name,
                          type: episode.type,
                          overview: episode.overview,
                          runTimeTicks: episode.runTimeTicks,
                          userData: updatedUserData,
                          seriesName: episode.seriesName,
                          parentIndexNumber: episode.parentIndexNumber,
                          indexNumber: episode.indexNumber,
                          seriesId: episode.seriesId,
                          seasonId: episode.seasonId,
                          seriesPrimaryImageTag: episode.seriesPrimaryImageTag,
                          seasonPrimaryImageTag: episode.seasonPrimaryImageTag,
                          imageTags: episode.imageTags,
                          backdropImageTags: episode.backdropImageTags,
                          parentThumbItemId: episode.parentThumbItemId,
                          parentThumbImageTag: episode.parentThumbImageTag,
                          parentBackdropItemId: episode.parentBackdropItemId,
                          parentBackdropImageTags:
                              episode.parentBackdropImageTags,
                          genres: episode.genres,
                          mediaSources: episode.mediaSources,
                          performers: episode.performers,
                          premiereDate: episode.premiereDate,
                          endDate: episode.endDate,
                          productionYear: episode.productionYear,
                          communityRating: episode.communityRating,
                          childCount: episode.childCount,
                          providerIds: episode.providerIds,
                          dateCreated: episode.dateCreated,
                          status: episode.status,
                          externalUrls: episode.externalUrls,
                        )
                      : episode;
                  return _buildResumeEpisodeSection(
                      context, updatedEpisode, isDarkBackground);
                }
                return _buildPlayButton(context, item, isDarkBackground);
              },
              error: (_, __) =>
                  _buildPlayButton(context, item, isDarkBackground),
            );
          },
        );
      },
    );
  }

  /// ✅ 构建继续观看集数滚动条
  Widget _buildResumeEpisodeSection(
      BuildContext context, ItemInfo episode, bool isDarkBackground) {
    final seasonNumber = episode.parentIndexNumber;
    final episodeNumber = episode.indexNumber;
    final episodeName = episode.name;

    // ✅ 构建标题文本
    String titleText;
    if (seasonNumber != null && seasonNumber > 1) {
      titleText = '第${seasonNumber}季 第${episodeNumber ?? 0}集';
    } else {
      titleText = '第${episodeNumber ?? 0}集';
    }

    // ✅ 如果"第x集"和剧集名称相同，只显示一个
    // 去除空格后比较，处理 "第3集" 和 "第 3 集" 的情况
    final String normalizedTitle = titleText.replaceAll(' ', '');
    final String normalizedName = episodeName.replaceAll(' ', '');
    final bool isTitleSameAsName = normalizedTitle == normalizedName;
    final String? displayEpisodeName = isTitleSameAsName ? null : episodeName;

    final progress =
        (episode.userData?['PlayedPercentage'] as num?)?.toDouble() ?? 0.0;
    final normalizedProgress = (progress / 100).clamp(0.0, 1.0);
    final positionTicks =
        (episode.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final totalTicks = episode.runTimeTicks ?? 0;
    final remainingTicks =
        totalTicks > positionTicks ? totalTicks - positionTicks : 0;
    final remainingDuration = totalTicks > 0
        ? Duration(microseconds: remainingTicks ~/ 10)
        : Duration.zero;

    String formatRemaining(Duration duration) {
      if (duration <= Duration.zero) return '0s';
      if (duration.inHours >= 1) {
        final minutes = duration.inMinutes.remainder(60);
        return minutes > 0
            ? '${duration.inHours}h ${minutes}m'
            : '${duration.inHours}h';
      }
      if (duration.inMinutes >= 1) {
        return '${duration.inMinutes}m';
      }
      return '${duration.inSeconds}s';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ 继续观看按钮
        Row(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: _resumeButtonColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: episode.id != null && episode.id!.isNotEmpty
                      ? () => _handlePlay(
                            context,
                            episode.id!,
                            fromBeginning: false,
                            resumePositionTicks:
                                positionTicks > 0 ? positionTicks : null,
                          )
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.play_fill, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '恢复播放',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // ✅ 第x集和剧集名称（放在恢复播放按键下面、进度条上面）
        if (displayEpisodeName != null || titleText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  displayEpisodeName != null
                      ? '$titleText $displayEpisodeName'
                      : titleText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkBackground ? Colors.white70 : Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        // ✅ 播放进度条
        if (normalizedProgress > 0 && normalizedProgress < 1) ...[
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
                      end: normalizedProgress.clamp(0.0, 1.0),
                    ),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (context, animatedValue, child) {
                      return LinearProgressIndicator(
                        value: animatedValue.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            (isDarkBackground ? Colors.white : Colors.black)
                                .withValues(alpha: 0.18),
                        valueColor: AlwaysStoppedAnimation(
                          _resumeButtonColor.withValues(alpha: 0.95),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '剩余 ${formatRemaining(remainingDuration)}',
                style: TextStyle(
                  color: isDarkBackground ? Colors.white70 : Colors.black54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// ✅ 构建播放按钮（从第一季第一集开始）
  Widget _buildPlayButton(
      BuildContext context, ItemInfo item, bool isDarkBackground) {
    final Color buttonColor = _playButtonColor;
    final Color textColor = Colors.white;
    final String buttonLabel = '播放';

    return Row(
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
                        fromBeginning: true,
                        resumePositionTicks: null,
                      )
                  : null,
              child: Row(
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
      ],
    );
  }

  Future<void> _handleBackdropImage(ui.Image image, String cacheKey) async {
    if (_imageStyleCache.containsKey(cacheKey)) {
      _applyStatusBarStyle(_imageStyleCache[cacheKey]!);
      return;
    }

    final bool isDark = await _isTopAreaDark(image);
    final style = isDark ? _lightStatusBar : _darkStatusBar;
    _imageStyleCache[cacheKey] = style;
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
    _navSyncedStyle = null;
    if (mounted) {
      _statusBarController?.update(style);
      setState(() {
        _appliedStatusStyle = style;
      });
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
    const double blurEnd = _headerTopOffset;
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
    if (_navSyncedStyle == targetStyle) {
      return;
    }
    _navSyncedStyle = targetStyle;
    if (mounted) {
      _statusBarController?.update(targetStyle);
      setState(() {
        _navSyncedStyle = targetStyle;
        _appliedStatusStyle = targetStyle;
      });
    } else {
      SystemChrome.setSystemUIOverlayStyle(targetStyle);
      _appliedStatusStyle = targetStyle;
    }
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _statusBarController?.release();
      _statusBarController = null;
    } else if (status == AnimationStatus.completed ||
        status == AnimationStatus.forward) {
      if (mounted) {
        _statusBarController?.update(_navSyncedStyle ?? _statusBarStyle);
      }
    }
  }

  void _removeRouteListener() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = null;
    _modalRoute = null;
  }

  void _handlePlay(
    BuildContext context,
    String itemId, {
    required bool fromBeginning,
    int? resumePositionTicks,
  }) {
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
    context.push(route);
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

        // ✅ 延迟触发全局刷新信号，刷新首页的继续观看和其他模块数据
        // 但不触发当前页面的 provider 重新加载（通过 _isUpdatingFavorite 标记阻止）
        // ✅ 收藏按钮不影响播放进度条和季海报状态标记，所以不刷新这些 provider
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            ref.read(libraryRefreshTickerProvider.notifier).state++;
          }
        });

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

        // ✅ 延迟触发全局刷新信号，刷新首页的继续观看和其他模块数据
        // 同时手动刷新季海报的状态标记和继续观看集数
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            // ✅ 通知全局刷新（首页等其他页面）
            ref.read(libraryRefreshTickerProvider.notifier).state++;

            // ✅ 手动刷新需要更新的 provider（季海报状态标记、继续观看集数）
            // 不刷新 seriesProvider 和 seasonsProvider，避免整个页面重新加载
            // 只刷新状态标记相关的 provider（seasonWatchStatsProvider）
            ref.invalidate(nextUpEpisodeProvider(widget.seriesId));
            // ✅ 刷新所有季的状态标记（由于 seasonsProvider 不 watch libraryRefreshTickerProvider，
            // 所以不会导致季列表重建，只会更新状态标记）
            final seasons = ref.read(seasonsProvider(widget.seriesId));
            seasons.whenData((seasonsList) {
              if (mounted) {
                for (final season in seasonsList) {
                  if (season.id != null && season.id!.isNotEmpty) {
                    ref.invalidate(seasonWatchStatsProvider(
                        (widget.seriesId, season.id!)));
                  }
                }
              }
            });
          }
        });

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
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final link = links[index];
              return DecoratedBox(
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
}

class _PerformerCard extends StatelessWidget {
  const _PerformerCard({required this.performer, required this.isDark});

  final PerformerInfo performer;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final theme = Theme.of(context);
    const double cardWidth = 95;
    const double cardHeight = 143;

    return SizedBox(
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
        return EmbyFadeInImage(
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
  const _SimilarCard({required this.item, required this.isDark});

  final ItemInfo item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    const double cardWidth = 95;
    const double cardHeight = 143;
    const double aspectRatio = 2 / 3;

    return SizedBox(
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
                height: cardHeight,
                width: cardWidth,
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _buildPoster(),
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
    );
  }

  Widget _buildPoster() {
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
            maxWidth: 320,
          );
        }

        if (url == null || url.isEmpty) {
          return Container(
            color: Colors.grey.withOpacity(0.1),
            child: const Center(child: Icon(CupertinoIcons.photo, size: 28)),
          );
        }

        return EmbyFadeInImage(
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
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    super.key,
    required this.season,
    required this.seriesId,
    required this.isDark,
  });

  final ItemInfo season;
  final String seriesId;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final seasonName = season.name;

    return SizedBox(
      width: 95,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ✅ 海报部分完全独立，不依赖 provider，不会重新加载
          RepaintBoundary(
            // ✅ 使用 RepaintBoundary 避免海报重新绘制
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ✅ 海报图片（提取为独立 widget，使用稳定的 key，避免重新加载）
                _SeasonPoster(
                  key: ValueKey('season_poster_${season.id}'),
                  season: season,
                  seriesId: seriesId,
                ),
                // ✅ 只有状态标记部分 watch provider，只刷新这一部分
                Positioned(
                  top: 4,
                  right: 4,
                  child: RepaintBoundary(
                    // ✅ 使用 RepaintBoundary 避免状态标记刷新时影响海报
                    child: Consumer(
                      builder: (context, ref, _) {
                        final stats = ref.watch(seasonWatchStatsProvider(
                            (seriesId, season.id ?? '')));
                        return stats.when(
                          data: (data) {
                            if (data.allWatched) {
                              // 已观看完成：绿色圆形背景，使用 CupertinoIcons.check_mark
                              return Container(
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
                              );
                            } else if (data.totalEpisodes > 0) {
                              // 显示未观看集数：红色背景，圆角10
                              final unwatched =
                                  data.totalEpisodes - data.watchedEpisodes;
                              if (unwatched > 0) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemRed,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$unwatched',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                ),
                // ✅ 点击按钮覆盖整个海报区域（只在需要时使用 Consumer）
                Positioned.fill(
                  child: season.id != null && season.id!.isNotEmpty
                      ? Consumer(
                          builder: (context, ref, _) {
                            return CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                final series =
                                    ref.read(seriesProvider(seriesId));
                                series.whenData((seriesData) {
                                  context.push(
                                    '/series/$seriesId/season/${season.id}?seriesName=${Uri.encodeComponent(seriesData.name)}&seasonName=${Uri.encodeComponent(seasonName)}',
                                  );
                                });
                              },
                              child: const SizedBox.shrink(),
                            );
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 季名称
          Text(
            seasonName,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ 季海报独立 widget，使用稳定的 key，避免重新加载
/// 当季海报缺失时，使用电视剧海报作为备用
class _SeasonPoster extends ConsumerWidget {
  const _SeasonPoster({
    super.key,
    required this.season,
    required this.seriesId,
  });

  final ItemInfo season;
  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ 检查季是否有 Primary 图片标签
    final seasonHasImage = season.imageTags?['Primary'] != null &&
        season.imageTags!['Primary']!.isNotEmpty;

    // ✅ 如果季有海报，直接使用
    if (seasonHasImage && season.id != null && season.id!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 95,
          height: 143,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: FutureBuilder<EmbyApi>(
              future: EmbyApi.create(),
              key: ValueKey('season_poster_future_${season.id}'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(color: Colors.grey.withOpacity(0.2));
                }
                final api = snapshot.data!;
                final posterUrl = api.buildImageUrl(
                  itemId: season.id!,
                  type: 'Primary',
                  maxWidth: 400,
                  tag: season.imageTags!['Primary'],
                );
                return EmbyFadeInImage(
                  key: ValueKey('season_poster_image_$posterUrl'),
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                );
              },
            ),
          ),
        ),
      );
    }

    // ✅ 季没有海报，使用电视剧海报作为备用
    final seriesAsync = ref.read(seriesProvider(seriesId));
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 95,
        height: 143,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: seriesAsync.when(
            data: (series) {
              final seriesHasImage = series.imageTags?['Primary'] != null &&
                  series.imageTags!['Primary']!.isNotEmpty;
              if (seriesHasImage) {
                return FutureBuilder<EmbyApi>(
                  future: EmbyApi.create(),
                  key: ValueKey('season_poster_future_series_$seriesId'),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Container(color: Colors.grey.withOpacity(0.2));
                    }
                    final api = snapshot.data!;
                    final posterUrl = api.buildImageUrl(
                      itemId: seriesId,
                      type: 'Primary',
                      maxWidth: 400,
                      tag: series.imageTags!['Primary'],
                    );
                    return EmbyFadeInImage(
                      key: ValueKey('season_poster_image_series_$posterUrl'),
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                    );
                  },
                );
              }
              // ✅ 如果都没有海报，显示占位符
              return Container(
                color: Colors.grey.withOpacity(0.2),
                child: const Icon(CupertinoIcons.photo, size: 28),
              );
            },
            loading: () => Container(color: Colors.grey.withOpacity(0.2)),
            error: (_, __) => Container(
              color: Colors.grey.withOpacity(0.2),
              child: const Icon(CupertinoIcons.photo, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.item});

  final ItemInfo item;

  @override
  Widget build(BuildContext context) {
    final logoTag = item.imageTags?['Logo']?.toString();
    if (item.id == null ||
        item.id!.isEmpty ||
        logoTag == null ||
        logoTag.isEmpty) {
      return _buildTextTitle(context);
    }
    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildTextTitle(context);
        }
        final api = snapshot.data!;
        final logoUrl = api.buildImageUrl(
          itemId: item.id!,
          type: 'Logo',
          tag: logoTag,
          maxWidth: 300,
        );
        if (logoUrl.isEmpty) {
          return _buildTextTitle(context);
        }
        return SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 0),
              child: SizedBox(
                height: 32,
                child: EmbyFadeInImage(
                  imageUrl: logoUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextTitle(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    return Text(
      item.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: baseStyle.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget child})
      : super(child: child);

  final ValueChanged<Size?> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size?> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final size = child?.size;
    if (_oldSize == size) return;
    _oldSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(size);
    });
  }
}
