import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../utils/app_route_observer.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';
import '../../providers/library_provider.dart';

// 排序选项
enum SortOption {
  // 电影和电视剧通用选项
  imdbRating('CommunityRating', 'IMDB评分'),
  resolution('Resolution', '分辨率'),
  dateAdded('DateCreated', '加入日期'),
  premiereDate('ProductionYear,PremiereDate', '发行日期'),
  // container('Container', '媒体容器'),
  officialRating('OfficialRating', '分级限制'),
  // director('Director', '导演'),
  frameRate('FrameRate', '帧率'),
  productionYear('ProductionYear', '年份'),
  // criticRating('CriticRating', '影评人评分'),
  datePlayed('DatePlayed', '播放日期'),
  runtime('Runtime', '影片时长'),
  playCount('PlayCount', '播放次数'),
  // fileName('FileName', '文件名'),
  size('Size', '文件大小'),
  name('SortName', '标题'),
  bitrate('MediaBitrate', '比特率'),
  // videoCodec('VideoCodec', '视频编解码器'),
  random('Random', '随机'),
  // 电视剧专用选项
  lastContentPremiereDate('LastContentPremiereDate', '最新更新'),
  dateLastContentAdded('DateLastContentAdded', '最新添加');

  const SortOption(this.value, this.label);
  final String value;
  final String label;

  // ✅ 根据libraryType获取排序选项列表
  static List<SortOption> getSortOptionsForType(String? libraryType) {
    if (libraryType == 'Movie') {
      // 电影类型：IMDB评分、分辨率、加入日期、发行日期、媒体容器、家长评分、导演、帧率、年份、播放日期、播放时长、播放次数、文件尺寸、标题、比特率、随机
      return [
        SortOption.imdbRating,
        SortOption.resolution,
        SortOption.dateAdded,
        SortOption.premiereDate,
        // SortOption.container,
        SortOption.officialRating,
        // SortOption.director,
        SortOption.frameRate,
        SortOption.productionYear,
        SortOption.datePlayed,
        SortOption.runtime,
        SortOption.playCount,
        SortOption.size,
        SortOption.name,
        SortOption.bitrate,
        SortOption.random,
      ];
    } else if (libraryType == 'Series') {
      // 电视剧类型：IMBD评分、加入日期、发行日期、家长评分、导演、年份、播放日期、播放时长、最后一集发行日期、最后一集添加日期、标题、随机
      return [
        SortOption.imdbRating,
        SortOption.dateAdded,
        SortOption.premiereDate,
        SortOption.officialRating,
        // SortOption.director,
        SortOption.productionYear,
        SortOption.datePlayed,
        SortOption.runtime,
        SortOption.lastContentPremiereDate,
        SortOption.dateLastContentAdded,
        SortOption.name,
        SortOption.random,
      ];
    } else {
      // 默认返回所有选项
      return SortOption.values;
    }
  }
}

// 排序状态
class SortState {
  final SortOption sortBy;
  final bool ascending; // true=正序, false=倒序

  const SortState({
    this.sortBy = SortOption.premiereDate, // 默认使用发行日期（电影和电视剧都支持）
    this.ascending = false, // 默认倒序（最新的在前）
  });

  SortState copyWith({
    SortOption? sortBy,
    bool? ascending,
  }) {
    return SortState(
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
    );
  }
}

// 排序状态 Provider（每个 viewId 独立，支持持久化）
final sortStateProvider =
    StateNotifierProvider.family<SortStateNotifier, SortState, String>(
  (ref, viewId) => SortStateNotifier(viewId),
);

class SortStateNotifier extends StateNotifier<SortState> {
  SortStateNotifier(this.viewId) : super(const SortState()) {
    _loadState();
  }

  final String viewId;
  static const String _prefsKeyPrefix = 'sort_state_';

  String get _prefsKey => '$_prefsKeyPrefix$viewId';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sortByValue = prefs.getString('${_prefsKey}_sortBy');
      final ascending = prefs.getBool('${_prefsKey}_ascending');

      if (sortByValue != null) {
        final sortBy = SortOption.values.firstWhere(
          (option) => option.value == sortByValue,
          orElse: () => SortOption.premiereDate,
        );
        state = SortState(
          sortBy: sortBy,
          ascending: ascending ?? false,
        );
      }
    } catch (e) {
      // 如果加载失败，使用默认值
      state = const SortState();
    }
  }

  Future<void> updateState(SortState newState) async {
    state = newState;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_prefsKey}_sortBy', newState.sortBy.value);
      await prefs.setBool('${_prefsKey}_ascending', newState.ascending);
    } catch (e) {
      // 保存失败不影响状态更新
    }
  }
}

// ✅ 筛选状态（用于tab筛选）
class FilterState {
  final String?
      filterType; // 'all', 'resume', 'favorite', 'collection', 'genre'
  final String? genreId; // 类型ID（当filterType为'genre'时使用）

  const FilterState({
    this.filterType,
    this.genreId,
  });

  FilterState copyWith({
    String? filterType,
    String? genreId,
  }) {
    return FilterState(
      filterType: filterType ?? this.filterType,
      genreId: genreId ?? this.genreId,
    );
  }
}

// ✅ 筛选状态 Provider（每个 viewId 独立，支持持久化）
final filterStateProvider =
    StateNotifierProvider.family<FilterStateNotifier, FilterState, String>(
  (ref, viewId) => FilterStateNotifier(viewId),
);

class FilterStateNotifier extends StateNotifier<FilterState> {
  FilterStateNotifier(this.viewId) : super(const FilterState()) {
    _loadState();
  }

  final String viewId;
  static const String _prefsKeyPrefix = 'filter_state_';

  String get _prefsKey => '$_prefsKeyPrefix$viewId';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filterType = prefs.getString('${_prefsKey}_filterType');
      final genreId = prefs.getString('${_prefsKey}_genreId');
      if (filterType != null) {
        state = FilterState(
          filterType: filterType,
          genreId: genreId,
        );
      }
    } catch (e) {
      state = const FilterState();
    }
  }

  Future<void> updateState(FilterState newState) async {
    state = newState;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (newState.filterType != null) {
        await prefs.setString('${_prefsKey}_filterType', newState.filterType!);
      }
      if (newState.genreId != null) {
        await prefs.setString('${_prefsKey}_genreId', newState.genreId!);
      }
    } catch (e) {
      // 保存失败不影响状态更新
    }
  }
}

final itemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  ref.watch(libraryRefreshTickerProvider);
  final sortState = ref.watch(sortStateProvider(viewId));
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await ref.read(embyApiProvider.future);

  // ✅ 先获取少量数据来判断库类型
  final sampleItems = await api.getItemsByParent(
    userId: auth.userId!,
    parentId: viewId,
    includeItemTypes: 'Movie,Series,BoxSet,Video',
    limit: 10,
  );

  // ✅ 判断库类型
  String? libraryType;
  if (sampleItems.isNotEmpty) {
    final movieCount = sampleItems.where((item) => item.type == 'Movie').length;
    final seriesCount =
        sampleItems.where((item) => item.type == 'Series').length;
    libraryType = movieCount > seriesCount ? 'Movie' : 'Series';
  }

  // ✅ 获取适用于当前类型的排序选项列表
  final availableSortOptions = SortOption.getSortOptionsForType(libraryType);

  // ✅ 检查当前排序字段是否适用于当前类型，如果不适用则映射或使用默认值
  SortOption currentSortOption = sortState.sortBy;
  bool ascending = sortState.ascending;

  if (!availableSortOptions.contains(sortState.sortBy)) {
    // ✅ 向后兼容：对于不支持的字段，使用新列表中的第一个选项作为默认值
    if (libraryType == 'Series') {
      // ✅ 对于Series，使用新列表中的第一个选项（IMDB评分）
      currentSortOption = availableSortOptions.isNotEmpty
          ? availableSortOptions.first
          : SortOption.premiereDate;
    } else {
      // ✅ 对于Movie类型，使用新列表中的第一个选项（电影类型）
      currentSortOption = availableSortOptions.isNotEmpty
          ? availableSortOptions.first
          : SortOption.premiereDate;
    }
    ascending = false;
    // ✅ 更新状态以保存新的排序字段
    ref.read(sortStateProvider(viewId).notifier).updateState(
          SortState(sortBy: currentSortOption, ascending: false),
        );
  }

  // ✅ 构建排序字段，给所有排序增加副排序字段 SortName（除了标题排序、随机排序）
  String sortBy = currentSortOption.value;
  if (currentSortOption != SortOption.name &&
      currentSortOption != SortOption.random) {
    sortBy = '$sortBy,${SortOption.name.value}';
  }

  // 对于电视剧库，只获取 Series，不获取单集
  // ✅ 对于Series和Movie类型，直接使用选择的排序字段
  if (libraryType == 'Series') {
    try {
      return await api.getItemsByParent(
        userId: auth.userId!,
        parentId: viewId,
        includeItemTypes: 'Movie,Series,BoxSet,Video',
        sortBy: sortBy,
        sortOrder: ascending ? 'Ascending' : 'Descending',
      );
    } catch (e) {
      // ✅ 如果排序失败，使用新列表中的第一个选项作为默认排序
      final fallbackOption = availableSortOptions.isNotEmpty
          ? availableSortOptions.first
          : SortOption.premiereDate;
      // ✅ 给 fallback 排序也添加 SortName（除了标题排序、随机排序）
      String fallbackSortBy = fallbackOption.value;
      if (fallbackOption != SortOption.name &&
          fallbackOption != SortOption.random) {
        fallbackSortBy = '$fallbackSortBy,${SortOption.name.value}';
      }
      return await api.getItemsByParent(
        userId: auth.userId!,
        parentId: viewId,
        includeItemTypes: 'Movie,Series,BoxSet,Video',
        sortBy: fallbackSortBy,
        sortOrder: 'Descending',
      );
    }
  } else {
    // ✅ 对于Movie类型，直接使用选择的排序字段，并启用合集合并
    try {
      return await api.getItemsByParent(
        userId: auth.userId!,
        parentId: viewId,
        includeItemTypes: 'Movie,Series,BoxSet,Video',
        sortBy: sortBy,
        sortOrder: ascending ? 'Ascending' : 'Descending',
        groupItemsIntoCollections: true, // 启动合集
      );
    } catch (e) {
      // ✅ 如果排序失败，使用PremiereDate作为默认排序
      // ✅ 给 fallback 排序也添加 SortName
      String fallbackSortBy =
          '${SortOption.premiereDate.value},${SortOption.name.value}';
      return await api.getItemsByParent(
        userId: auth.userId!,
        parentId: viewId,
        includeItemTypes: 'Movie,Series,BoxSet,Video',
        sortBy: fallbackSortBy,
        sortOrder: 'Descending',
        groupItemsIntoCollections: true,
      );
    }
  }
});

class LibraryItemsPage extends ConsumerStatefulWidget {
  const LibraryItemsPage({
    required this.viewId,
    this.viewName = '媒体库',
    super.key,
  });

  final String viewId;
  final String viewName;

  @override
  ConsumerState<LibraryItemsPage> createState() => _LibraryItemsPageState();
}

class _LibraryItemsPageState extends ConsumerState<LibraryItemsPage>
    with RouteAware {
  final _scrollController =
      ScrollController(); // ✅ 用于loading/error状态的BlurNavigationBar
  bool _isRouteSubscribed = false;
  int _selectedTab = 0; // ✅ 当前选中的 tab
  late final PageController _pageController; // ✅ PageView控制器
  final Map<int, ScrollController> _pageScrollControllers =
      {}; // ✅ 每个页面的ScrollController
  bool _isSortMenuOpen = false; // ✅ 排序菜单是否打开
  List<ItemInfo>? _cachedItemsList; // ✅ 缓存itemsList，避免重新加载时闪烁

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  bool _hasHorizontalArtwork(ItemInfo item) {
    final hasBackdrop = (item.backdropImageTags?.isNotEmpty ?? false) ||
        (item.parentBackdropImageTags?.isNotEmpty ?? false);
    if (hasBackdrop) return true;

    final imageTags = item.imageTags ?? const <String, String>{};
    final primaryTag = imageTags['Primary'];
    if (primaryTag == null || primaryTag.isEmpty) {
      return false;
    }
    // 如果缺少壁纸但存在 Primary 图，就将其作为竖向海报处理
    return false;
  }

  List<List<_RowEntry>> _buildRows(List<ItemInfo> items) {
    final rows = <List<_RowEntry>>[];
    var index = 0;

    while (index < items.length) {
      final current = items[index];
      final currentHorizontal = _hasHorizontalArtwork(current);

      if (!currentHorizontal) {
        final row = <_RowEntry>[_RowEntry(current, currentHorizontal)];
        index++;
        if (index < items.length) {
          final next = items[index];
          row.add(_RowEntry(next, _hasHorizontalArtwork(next)));
          index++;
        }
        rows.add(row);
        continue;
      }

      final row = <_RowEntry>[];
      while (index < items.length && row.length < 3) {
        final candidate = items[index];
        final candidateHorizontal = _hasHorizontalArtwork(candidate);
        if (!candidateHorizontal) {
          break;
        }
        row.add(_RowEntry(candidate, candidateHorizontal));
        index++;
      }

      if (row.isEmpty) {
        // fallback: treat as vertical row
        rows.add([_RowEntry(current, currentHorizontal)]);
        index++;
      } else {
        rows.add(row);
      }
    }

    return rows;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_isRouteSubscribed && route != null) {
      appRouteObserver.subscribe(this, route);
      _isRouteSubscribed = true;
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(itemsProvider(widget.viewId));
    });
  }

  @override
  void didPush() {
    _scheduleRefresh();
  }

  @override
  void didPopNext() {
    _scheduleRefresh();
  }

  @override
  void dispose() {
    if (_isRouteSubscribed) {
      appRouteObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    _scrollController.dispose();
    _pageController.dispose(); // ✅ 释放PageController
    // ✅ 释放所有页面的ScrollController
    for (final controller in _pageScrollControllers.values) {
      controller.dispose();
    }
    _pageScrollControllers.clear();
    super.dispose();
  }

  // ✅ 根据类型获取 tab 选项
  List<String> _getTabsForType(String? libraryType, List<ItemInfo> items) {
    // 如果没有明确类型，根据 items 判断
    if (libraryType == null && items.isNotEmpty) {
      final movieCount = items.where((item) => item.type == 'Movie').length;
      final seriesCount = items.where((item) => item.type == 'Series').length;
      libraryType = movieCount > seriesCount ? 'Movie' : 'Series';
    }

    if (libraryType == 'Movie') {
      return ['影片', '继续播放', '收藏', '合集', '类型'];
    } else if (libraryType == 'Series') {
      return [
        '节目',
        '继续播放',
        '收藏',
        '类型',
      ];
    }
    // 默认返回电影类型的 tabs
    return ['显示影片', '继续播放', '收藏', '合集', '类型'];
  }

  // ✅ 判断库类型
  String? _getLibraryType(List<ItemInfo> items) {
    if (items.isEmpty) return null;
    final movieCount = items.where((item) => item.type == 'Movie').length;
    final seriesCount = items.where((item) => item.type == 'Series').length;
    return movieCount > seriesCount ? 'Movie' : 'Series';
  }

  // ✅ 同步指定页面的ScrollController到BlurNavigationBar
  // 现在直接使用当前页面的ScrollController，所以这个方法主要用于触发重建
  void _syncScrollControllerForPage(int pageIndex) {
    // 触发重建，让BlurNavigationBar使用新的ScrollController
    if (mounted) {
      setState(() {});
    }
  }

  // ✅ 根据tab筛选数据
  List<ItemInfo> _filterItems(
      List<ItemInfo> items, String tab, String? libraryType, WidgetRef ref) {
    if (tab == '影片' || tab == '节目') {
      // 显示所有影片/节目
      return items;
    } else if (tab == '继续播放') {
      // 显示有播放进度的项目
      return items.where((item) {
        final userData = item.userData ?? {};
        final playbackTicks =
            (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
        final totalTicks = item.runTimeTicks ?? 0;
        return playbackTicks > 0 && playbackTicks < totalTicks;
      }).toList();
    } else if (tab == '收藏') {
      // 显示收藏的项目
      return items.where((item) {
        final userData = item.userData ?? {};
        return userData['IsFavorite'] == true;
      }).toList();
    } else if (tab == '合集') {
      // 显示合集
      return items.where((item) => item.type == 'BoxSet').toList();
    } else if (tab == '类型') {
      // 显示类型筛选（需要从filterState获取）
      final filterState = ref.read(filterStateProvider(widget.viewId));
      if (filterState.genreId != null) {
        return items.where((item) {
          final genres = item.genres ?? [];
          return genres.contains(filterState.genreId);
        }).toList();
      }
      return items;
    }
    return items;
  }

  // ✅ 构建tab内容页面
  Widget _buildTabContent(BuildContext context, WidgetRef ref,
      List<ItemInfo> items, String tab, int pageIndex) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 44,
          ),
          child: const Text('此分类暂无内容'),
        ),
      );
    }

    // ✅ 为每个页面创建独立的ScrollController
    if (!_pageScrollControllers.containsKey(pageIndex)) {
      // ✅ 每个tab都从顶部开始，不使用保存的滚动位置
      final controller = ScrollController(initialScrollOffset: 0.0);
      _pageScrollControllers[pageIndex] = controller;

      // ✅ 如果这是当前选中的页面，触发重建以更新BlurNavigationBar
      if (pageIndex == _selectedTab && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    }
    final pageScrollController = _pageScrollControllers[pageIndex]!;

    // ✅ 计算header高度
    // BlurNavigationBar的preferredSize是 100.0 + 36(tab) + 36(信息栏) = 172
    // 其中100包含了statusBar(44)和基础导航栏(44)，所以实际header高度是172
    // 由于navigationBar是ObstructingPreferredSizeWidget，内容会自动在下方
    // 但是我们需要在padding中加上header的实际高度，让内容正确显示在header下方
    final headerHeight =
        100.0 + 36.0 + 36.0; // ✅ BlurNavigationBar的preferredSize（tab高度改为36）

    return RefreshIndicator(
      displacement: 20,
      // ✅ 下拉刷新的位置应该在内容的最上面（header下方）
      // edgeOffset是从屏幕顶部到下拉刷新触发位置的距离
      // 由于navigationBar是ObstructingPreferredSizeWidget，内容会自动在navigationBar下方
      // 内容从 statusBarHeight + headerHeight 开始，所以edgeOffset应该是这个值
      // 下拉刷新会在内容的顶部触发（在padding内部）
      edgeOffset: headerHeight,
      onRefresh: () async {
        ref.invalidate(itemsProvider(widget.viewId));
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        controller: pageScrollController,
        // ✅ padding顶部需要加上header的完整高度（180），让内容在header下方显示
        // 减少顶部间距，让内容更靠近筛选行
        padding: EdgeInsets.only(
          top: headerHeight + 6, // ✅ 从12改为6，让内容更靠近筛选行
          left: 12,
          right: 12,
          bottom: 12,
        ),
        itemCount: _buildRows(items).length,
        itemBuilder: (context, rowIndex) {
          final rows = _buildRows(items);
          final row = rows[rowIndex];
          return Padding(
            padding: EdgeInsets.only(
              bottom: rowIndex == rows.length - 1 ? 0 : 16,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasHorizontal =
                    row.any((entry) => entry.hasHorizontalArtwork);
                final columns = hasHorizontal ? 3 : 2;
                final spacing = columns > 1 ? 16.0 : 0.0;
                final availableWidth = constraints.maxWidth;
                final totalSpacing = spacing * (columns - 1);
                final cardWidth = (availableWidth - totalSpacing) / columns;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) SizedBox(width: spacing),
                      SizedBox(
                        width: cardWidth,
                        child: i < row.length
                            ? _ItemTile(
                                item: row[i].item,
                                hasHorizontalArtwork:
                                    row[i].hasHorizontalArtwork,
                                cardWidth: cardWidth,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ✅ 显示排序下拉菜单（类似_SortButton的实现）
  void _showSortMenu(BuildContext context, WidgetRef ref, SortState sortState) {
    // ✅ 打开菜单时更新状态
    setState(() {
      _isSortMenuOpen = true;
    });

    // ✅ 获取libraryType，用于确定排序选项列表
    final itemsAsync = ref.read(itemsProvider(widget.viewId));
    final itemsList = itemsAsync.valueOrNull ?? _cachedItemsList;
    final libraryType = itemsList != null ? _getLibraryType(itemsList) : null;
    final sortOptions = SortOption.getSortOptionsForType(libraryType);

    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? Colors.white : Colors.black87;
    final selectedColor = CupertinoColors.activeBlue;

    // 获取按钮位置（从导航栏的排序按钮位置）
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // 计算菜单位置（右上角）
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final menuTop = statusBarHeight + 44 + 36 + 8; // 导航栏 + tab + 信息栏 + 间距

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Stack(
        children: [
          // 半透明背景
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                Navigator.pop(dialogContext);
                // ✅ 关闭菜单时更新状态
                setState(() {
                  _isSortMenuOpen = false;
                });
              },
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
          // 下拉菜单
          Positioned(
            top: menuTop,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: 180,
                    constraints: const BoxConstraints(
                      maxHeight: 400,
                    ),
                    decoration: BoxDecoration(
                      color: baseColor.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.1),
                        width: 0.5,
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        // ✅ 创建ScrollController，用于滚动到选中项
                        final scrollController = ScrollController();
                        // ✅ 计算每个选项的高度（包括divider）
                        const itemHeight =
                            48.0; // Container padding(12*2) + 文本高度约24
                        const dividerHeight = 1.0;

                        // ✅ 找到当前选中项的索引
                        final selectedIndex = sortOptions.indexWhere(
                          (option) => option == sortState.sortBy,
                        );

                        // ✅ 在显示后滚动到选中项
                        if (selectedIndex >= 0) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (scrollController.hasClients) {
                              final targetOffset =
                                  selectedIndex * (itemHeight + dividerHeight);
                              final maxScroll =
                                  scrollController.position.maxScrollExtent;
                              final viewportHeight =
                                  scrollController.position.viewportDimension;
                              // ✅ 滚动到选中项，让它在视口中间
                              final scrollOffset = (targetOffset -
                                      viewportHeight / 2 +
                                      itemHeight / 2)
                                  .clamp(0.0, maxScroll);
                              scrollController.animateTo(
                                scrollOffset,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          });
                        }

                        return SingleChildScrollView(
                          controller: scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < sortOptions.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.1),
                                  ),
                                InkWell(
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    // ✅ 关闭菜单时更新状态
                                    setState(() {
                                      _isSortMenuOpen = false;
                                    });
                                    final notifier = ref.read(
                                        sortStateProvider(widget.viewId)
                                            .notifier);
                                    final currentState = ref
                                        .read(sortStateProvider(widget.viewId));
                                    if (currentState.sortBy == sortOptions[i]) {
                                      // 相同选项，切换正序/倒序
                                      notifier.updateState(
                                        currentState.copyWith(
                                            ascending: !currentState.ascending),
                                      );
                                    } else {
                                      // 不同选项，切换到新选项（默认倒序）
                                      notifier.updateState(
                                        SortState(
                                          sortBy: sortOptions[i],
                                          ascending: false,
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            sortOptions[i].label,
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: sortState.sortBy ==
                                                      sortOptions[i]
                                                  ? selectedColor
                                                  : textColor,
                                              fontWeight: sortState.sortBy ==
                                                      sortOptions[i]
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        if (sortState.sortBy ==
                                            sortOptions[i]) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            sortState.ascending
                                                ? CupertinoIcons.arrow_up
                                                : CupertinoIcons.arrow_down,
                                            size: 14,
                                            color: selectedColor,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 构建导航栏（独立方法，避免依赖itemsProvider的变化）
  ObstructingPreferredSizeWidget _buildNavigationBar(BuildContext context,
      WidgetRef ref, List<ItemInfo> itemsList, int filteredCount) {
    final sortState = ref.watch(sortStateProvider(widget.viewId));
    final libraryType = _getLibraryType(itemsList);
    final tabs = _getTabsForType(libraryType, itemsList);
    final sortLabel = sortState.sortBy.label;

    // ✅ 确保当前页面的ScrollController已创建
    final currentScrollController =
        _pageScrollControllers.containsKey(_selectedTab)
            ? _pageScrollControllers[_selectedTab]!
            : null;

    return BlurNavigationBar(
      // ✅ 使用稳定的key，只包含viewId和selectedTab，不包含sortState，避免排序改变时重建
      key: ValueKey('nav_${widget.viewId}_$_selectedTab'),
      leading: buildBlurBackButton(context),
      middle: buildNavTitle(widget.viewName, context),
      scrollController: currentScrollController,
      libraryType: libraryType,
      tabs: tabs,
      selectedTab: _selectedTab,
      onTabChanged: (index) {
        // ✅ 切换tab时，将之前tab的滚动位置归零
        if (_pageScrollControllers.containsKey(_selectedTab)) {
          final previousController = _pageScrollControllers[_selectedTab]!;
          if (previousController.hasClients) {
            previousController.jumpTo(0.0);
          }
        }

        setState(() {
          _selectedTab = index;
        });

        // ✅ 同步PageView
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }

        // ✅ 确保新tab的ScrollController已创建并触发重建
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncScrollControllerForPage(index);
          }
        });
      },
      itemCount: filteredCount,
      sortLabel: sortLabel,
      sortAscending: sortState.ascending,
      isSortMenuOpen: _isSortMenuOpen,
      onSortTap: () {
        _showSortMenu(context, ref, sortState);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider(widget.viewId));

    // ✅ 使用valueOrNull来获取当前值，如果有值就使用，避免loading状态导致的闪烁
    // 当sortState改变时，itemsProvider会重新获取数据，但valueOrNull会保留之前的值
    final itemsList = items.valueOrNull;

    // ✅ 如果有新数据，更新缓存；如果没有新数据但缓存存在，使用缓存
    if (itemsList != null) {
      _cachedItemsList = itemsList;
    }

    // ✅ 使用缓存的数据（如果有），避免重新加载时闪烁
    final displayItemsList = itemsList ?? _cachedItemsList;

    // ✅ 如果有数据，直接显示；如果没有数据且正在加载，显示loading；如果出错，显示错误
    if (displayItemsList != null) {
      final libraryType = _getLibraryType(displayItemsList);
      final tabs = _getTabsForType(libraryType, displayItemsList);

      // ✅ 根据当前tab筛选数据
      final filteredItems =
          _filterItems(displayItemsList, tabs[_selectedTab], libraryType, ref);
      final filteredCount = filteredItems.length;

      return CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemBackground,
        navigationBar:
            _buildNavigationBar(context, ref, displayItemsList, filteredCount),
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            // ✅ 切换页面时，将之前页面的滚动位置归零
            if (_pageScrollControllers.containsKey(_selectedTab)) {
              final previousController = _pageScrollControllers[_selectedTab]!;
              if (previousController.hasClients) {
                previousController.jumpTo(0.0);
              }
            }

            setState(() {
              _selectedTab = index;
            });

            // ✅ 确保新页面的ScrollController已创建并触发重建
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _syncScrollControllerForPage(index);
              }
            });
          },
          itemCount: tabs.length,
          itemBuilder: (context, pageIndex) {
            // ✅ 根据tab筛选数据
            final pageItems = _filterItems(
                displayItemsList, tabs[pageIndex], libraryType, ref);
            return _buildTabContent(
                context, ref, pageItems, tabs[pageIndex], pageIndex);
          },
        ),
      );
    }

    // ✅ 如果没有数据，显示loading或error
    return items.when(
      data: (itemsList) {
        // 这个分支理论上不会执行，因为上面已经处理了
        final libraryType = _getLibraryType(itemsList);
        final tabs = _getTabsForType(libraryType, itemsList);
        final filteredItems =
            _filterItems(itemsList, tabs[_selectedTab], libraryType, ref);
        final filteredCount = filteredItems.length;
        return CupertinoPageScaffold(
          backgroundColor: CupertinoColors.systemBackground,
          navigationBar:
              _buildNavigationBar(context, ref, itemsList, filteredCount),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              if (_pageScrollControllers.containsKey(_selectedTab)) {
                final previousController =
                    _pageScrollControllers[_selectedTab]!;
                if (previousController.hasClients) {
                  previousController.jumpTo(0.0);
                }
              }
              setState(() {
                _selectedTab = index;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _syncScrollControllerForPage(index);
                }
              });
            },
            itemCount: tabs.length,
            itemBuilder: (context, pageIndex) {
              final pageItems =
                  _filterItems(itemsList, tabs[pageIndex], libraryType, ref);
              return _buildTabContent(
                  context, ref, pageItems, tabs[pageIndex], pageIndex);
            },
          ),
        );
      },
      loading: () => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemBackground,
        navigationBar: BlurNavigationBar(
          leading: buildBlurBackButton(context),
          middle: buildNavTitle(widget.viewName, context),
          scrollController: _scrollController,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
            child: const CupertinoActivityIndicator(),
          ),
        ),
      ),
      error: (e, _) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemBackground,
        navigationBar: BlurNavigationBar(
          leading: buildBlurBackButton(context),
          middle: buildNavTitle(widget.viewName, context),
          scrollController: _scrollController,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
            child: Text('加载失败: $e'),
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends ConsumerStatefulWidget {
  const _ItemTile({
    required this.item,
    required this.hasHorizontalArtwork,
    required this.cardWidth,
  });
  final ItemInfo item;
  final bool hasHorizontalArtwork;
  final double cardWidth;

  @override
  ConsumerState<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends ConsumerState<_ItemTile>
    with AutomaticKeepAliveClientMixin {
  ItemInfo get item => widget.item;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    // 提取年份信息
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

    int clampTicks(int value, int max) {
      if (value < 0) return 0;
      if (max <= 0) return value;
      if (value > max) return max;
      return value;
    }

    final userData = item.userData ?? {};
    final totalTicks = item.runTimeTicks ?? 0;
    final playbackTicks =
        (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final playedTicks = clampTicks(playbackTicks, totalTicks);
    final played = userData['Played'] == true ||
        (totalTicks > 0 && playedTicks >= totalTicks);
    final showProgress =
        item.type == 'Movie' && !played && totalTicks > 0 && playedTicks > 0;
    final progress = totalTicks > 0 ? playedTicks / totalTicks : 0.0;
    final remainingTicks =
        totalTicks > playedTicks ? totalTicks - playedTicks : 0;
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

    Widget? buildRatingChip() {
      if (item.getRating() == null) {
        return null;
      }
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.getRatingSource() == 'douban')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: const Text(
                  '豆',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Icon(
                CupertinoIcons.star_fill,
                color: Colors.amber,
                size: 12,
              ),
            const SizedBox(width: 2),
            Text(
              item.getRating()!.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final ratingChip = buildRatingChip();
    final aspectRatio = widget.hasHorizontalArtwork ? 9 / 14 : 16 / 9;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: item.id != null && item.id!.isNotEmpty
          ? () {
              // Series 类型跳转到剧集详情页，其他类型跳转到普通详情页
              if (item.type == 'Series') {
                context.push(
                    '/series/${item.id}?name=${Uri.encodeComponent(item.name)}');
              } else {
                context.push('/item/${item.id}');
              }
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ✅ 如果是16:9的，使用固定高度，宽度自适应
          // 如果不是16:9的，使用AspectRatio固定宽高比
          widget.hasHorizontalArtwork
              ? AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Container(
                    width: widget.cardWidth,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Poster(itemId: item.id, itemType: item.type),
                          // 电影播放完成标记
                          if (item.type == 'Movie' && played)
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
                          // 剧集未看集数显示在右上角
                          if (item.type == 'Series' && item.userData != null)
                            Builder(
                              builder: (context) {
                                final unplayedCount = (item
                                        .userData!['UnplayedItemCount'] as num?)
                                    ?.toInt();
                                if (unplayedCount != null &&
                                    unplayedCount > 0) {
                                  return Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.systemRed,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$unplayedCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          // 电影播放进度
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '剩余 ${formatRemaining(remainingDuration)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (ratingChip != null) ratingChip,
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0.0,
                                          end: progress.clamp(0.0, 1.0),
                                        ),
                                        duration:
                                            const Duration(milliseconds: 600),
                                        curve: Curves.easeOut,
                                        builder:
                                            (context, animatedValue, child) {
                                          return LinearProgressIndicator(
                                            value:
                                                animatedValue.clamp(0.0, 1.0),
                                            minHeight: 3,
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.2),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
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
                          // 当没有进度条时仍显示评分
                          if (!showProgress && ratingChip != null)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: ratingChip,
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              // ✅ 16:9的情况：固定高度，宽度自适应
              : SizedBox(
                  height: 100, // 固定高度（缩小为原来的75%）
                  child: Container(
                    width: widget.cardWidth * 0.75 * 16 / 9, // 宽度根据16:9比例自适应
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Poster(itemId: item.id, itemType: item.type),
                          // 电影播放完成标记
                          if (item.type == 'Movie' && played)
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
                          // 剧集未看集数显示在右上角
                          if (item.type == 'Series' && item.userData != null)
                            Builder(
                              builder: (context) {
                                final unplayedCount = (item
                                        .userData!['UnplayedItemCount'] as num?)
                                    ?.toInt();
                                if (unplayedCount != null &&
                                    unplayedCount > 0) {
                                  return Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.systemRed,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$unplayedCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          // 电影播放进度
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '剩余 ${formatRemaining(remainingDuration)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (ratingChip != null) ratingChip,
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0.0,
                                          end: progress.clamp(0.0, 1.0),
                                        ),
                                        duration:
                                            const Duration(milliseconds: 600),
                                        curve: Curves.easeOut,
                                        builder:
                                            (context, animatedValue, child) {
                                          return LinearProgressIndicator(
                                            value:
                                                animatedValue.clamp(0.0, 1.0),
                                            minHeight: 3,
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.2),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
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
                          // 当没有进度条时仍显示评分
                          if (!showProgress && ratingChip != null)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: ratingChip,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Opacity(
            opacity: yearText == null ? 0.0 : 1.0,
            child: Text(
              yearText ?? '0000',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Poster extends ConsumerWidget {
  const _Poster({required this.itemId, this.itemType});
  final String? itemId;
  final String? itemType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null || itemId!.isEmpty) {
      return _PosterSkeleton(itemType: itemType);
    }

    final apiAsync = ref.watch(embyApiProvider);

    return apiAsync.when(
      data: (api) {
        final url = api.buildImageUrl(itemId: itemId!, type: 'Primary');
        if (url.isEmpty) {
          return _PosterSkeleton(itemType: itemType);
        }
        return SizedBox.expand(
          child: EmbyFadeInImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: _PosterSkeleton(itemType: itemType),
          ),
        );
      },
      loading: () => _PosterSkeleton(itemType: itemType),
      error: (_, __) => _PosterSkeleton(itemType: itemType),
    );
  }
}

class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton({this.itemType});
  final String? itemType;

  IconData get _icon => (itemType == 'Series' || itemType == 'Episode')
      ? CupertinoIcons.tv
      : CupertinoIcons.film;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: CupertinoColors.systemGrey4,
        child: Center(
          child: Icon(
            _icon,
            color: CupertinoColors.systemGrey2,
            size: 48,
          ),
        ),
      ),
    );
  }
}

class _RowEntry {
  const _RowEntry(this.item, this.hasHorizontalArtwork);

  final ItemInfo item;
  final bool hasHorizontalArtwork;
}
