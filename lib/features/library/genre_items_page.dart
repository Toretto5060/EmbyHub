// 分类 列表页面
import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../utils/app_route_observer.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';
import '../../providers/library_provider.dart';
import '../../utils/theme_utils.dart';
import 'library_items_page.dart'; // 复用排序相关的代码

// ✅ 获取指定类型的内容
final genreItemsProvider =
    FutureProvider.family<List<ItemInfo>, GenreItemsParams>(
  (ref, params) async {
    ref.watch(libraryRefreshTickerProvider);
    final sortState = ref.watch(sortStateProvider(params.viewId));
    final authAsync = ref.watch(authStateProvider);
    final auth = authAsync.value;
    if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];

    final api = await ref.read(embyApiProvider.future);

    try {
      // ✅ 先获取少量数据来判断库类型
      final sampleItems = await api.getItemsByParent(
        userId: auth.userId!,
        parentId: params.viewId,
        includeItemTypes: 'Movie,Series,BoxSet,Video',
        limit: 10,
      );

      // ✅ 判断库类型
      String? libraryType;
      if (sampleItems.isNotEmpty) {
        final movieCount =
            sampleItems.where((item) => item.type == 'Movie').length;
        final seriesCount =
            sampleItems.where((item) => item.type == 'Series').length;
        libraryType = movieCount > seriesCount ? 'Movie' : 'Series';
      }

      // ✅ 获取适用于当前类型的排序选项列表
      final availableSortOptions =
          SortOption.getSortOptionsForType(libraryType);

      // ✅ 检查当前排序字段是否适用于当前类型
      SortOption currentSortOption = sortState.sortBy;
      bool ascending = sortState.ascending;

      if (!availableSortOptions.contains(sortState.sortBy)) {
        currentSortOption = availableSortOptions.isNotEmpty
            ? availableSortOptions.first
            : SortOption.premiereDate;
        ascending = false;
      }

      final sortBy = currentSortOption.value;
      final sortOrder = ascending ? 'Ascending' : 'Descending';

      // ✅ 获取指定类型的内容
      if (libraryType == 'Series') {
        return await api.getItemsByParent(
          userId: auth.userId!,
          parentId: params.viewId,
          includeItemTypes: 'Movie,Series,BoxSet,Video',
          sortBy: sortBy,
          sortOrder: sortOrder,
          genres: params.genreName, // ✅ 使用类型筛选
        );
      } else {
        return await api.getItemsByParent(
          userId: auth.userId!,
          parentId: params.viewId,
          includeItemTypes: 'Movie,Series,BoxSet,Video',
          sortBy: sortBy,
          sortOrder: sortOrder,
          groupItemsIntoCollections: true,
          genres: params.genreName, // ✅ 使用类型筛选
        );
      }
    } catch (e) {
      return <ItemInfo>[];
    }
  },
);

class GenreItemsParams {
  final String viewId;
  final String genreName;

  GenreItemsParams({
    required this.viewId,
    required this.genreName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenreItemsParams &&
          runtimeType == other.runtimeType &&
          viewId == other.viewId &&
          genreName == other.genreName;

  @override
  int get hashCode => viewId.hashCode ^ genreName.hashCode;
}

class GenreItemsPage extends ConsumerStatefulWidget {
  const GenreItemsPage({
    required this.viewId,
    required this.genreName,
    super.key,
  });

  final String viewId;
  final String genreName;

  @override
  ConsumerState<GenreItemsPage> createState() => _GenreItemsPageState();
}

class _GenreItemsPageState extends ConsumerState<GenreItemsPage>
    with RouteAware {
  final _scrollController = ScrollController();
  bool _isRouteSubscribed = false;
  bool _isSortMenuOpen = false;
  List<ItemInfo>? _cachedItemsList;

  bool _wasRouteCurrent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final isRouteCurrent = route?.isCurrent ?? false;

    // ✅ 检测路由是否重新变为当前路由（从其他页面返回）
    if (!_wasRouteCurrent && isRouteCurrent && _isRouteSubscribed) {
      // 路由重新变为当前路由，说明从其他页面返回了
      debugPrint('🔄 [GenreItemsPage] 路由重新变为当前路由，刷新数据');
      _scheduleRefresh();
    }
    _wasRouteCurrent = isRouteCurrent;

    if (!_isRouteSubscribed && route != null) {
      appRouteObserver.subscribe(this, route);
      _isRouteSubscribed = true;
      _wasRouteCurrent = route.isCurrent;
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ✅ 使用 refresh 而不是 invalidate，确保立即重新加载数据
      // ignore: unused_result
      ref.refresh(genreItemsProvider(GenreItemsParams(
        viewId: widget.viewId,
        genreName: widget.genreName,
      )));
    });
  }

  @override
  void didPush() {
    _scheduleRefresh();
  }

  @override
  void didPopNext() {
    debugPrint('🔄 [GenreItemsPage] didPopNext 被调用，刷新数据');
    _scheduleRefresh();
  }

  @override
  void dispose() {
    if (_isRouteSubscribed) {
      appRouteObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ✅ 判断库类型
  String? _getLibraryType(List<ItemInfo> items) {
    if (items.isEmpty) return null;
    final movieCount = items.where((item) => item.type == 'Movie').length;
    final seriesCount = items.where((item) => item.type == 'Series').length;
    return movieCount > seriesCount ? 'Movie' : 'Series';
  }

  // ✅ 判断是否有横向图片（与library_items_page一致）
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

  // ✅ 构建行数据（与library_items_page一致）
  List<List<_ItemEntry>> _buildRows(List<ItemInfo> items) {
    final rows = <List<_ItemEntry>>[];
    var index = 0;

    while (index < items.length) {
      final current = items[index];
      final currentHorizontal = _hasHorizontalArtwork(current);

      if (!currentHorizontal) {
        final row = <_ItemEntry>[_ItemEntry(current, currentHorizontal)];
        index++;
        if (index < items.length) {
          final next = items[index];
          row.add(_ItemEntry(next, _hasHorizontalArtwork(next)));
          index++;
        }
        rows.add(row);
        continue;
      }

      final row = <_ItemEntry>[];
      while (index < items.length && row.length < 3) {
        final candidate = items[index];
        final candidateHorizontal = _hasHorizontalArtwork(candidate);
        if (!candidateHorizontal) {
          break;
        }
        row.add(_ItemEntry(candidate, candidateHorizontal));
        index++;
      }

      if (row.isEmpty) {
        // fallback: treat as vertical row
        rows.add([_ItemEntry(current, currentHorizontal)]);
        index++;
      } else {
        rows.add(row);
      }
    }

    return rows;
  }

  // ✅ 显示排序菜单（与library_items_page一致）
  void _showSortMenu(BuildContext context, WidgetRef ref, SortState sortState) {
    // ✅ 获取libraryType，用于确定排序选项列表
    final itemsAsync = ref.read(genreItemsProvider(GenreItemsParams(
      viewId: widget.viewId,
      genreName: widget.genreName,
    )));
    final itemsList = itemsAsync.valueOrNull ?? _cachedItemsList;
    final libraryType = itemsList != null ? _getLibraryType(itemsList) : null;
    final sortOptions = SortOption.getSortOptionsForType(libraryType);

    final isDark = isDarkModeFromContext(context, ref);
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
    // ✅ 调整菜单位置，更靠近排序按钮（导航栏44，减去一些间距）
    final menuTop = statusBarHeight + 44 - 2; // 导航栏 - 2（更贴近）

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      useSafeArea: false, // ✅ 不使用安全区域，让遮罩覆盖状态栏
      builder: (dialogContext) => MediaQuery.removePadding(
        context: dialogContext,
        removeTop: true, // ✅ 移除顶部padding，让遮罩从屏幕顶部开始
        child: Stack(
          children: [
            // 半透明背景 - 覆盖整个屏幕包括状态栏
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
                                final targetOffset = selectedIndex *
                                    (itemHeight + dividerHeight);
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

                          return ListView.separated(
                            controller: scrollController,
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: sortOptions.length,
                            separatorBuilder: (context, index) => Divider(
                              height: dividerHeight,
                              thickness: dividerHeight,
                              color: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.black.withOpacity(0.1),
                              indent: 12,
                              endIndent: 12,
                            ),
                            itemBuilder: (context, index) {
                              final option = sortOptions[index];
                              final isSelected = sortState.sortBy == option;

                              return InkWell(
                                onTap: () {
                                  final newAscending =
                                      isSelected && !sortState.ascending
                                          ? !sortState.ascending
                                          : sortState.ascending;
                                  ref
                                      .read(sortStateProvider(widget.viewId)
                                          .notifier)
                                      .updateState(
                                        SortState(
                                            sortBy: option,
                                            ascending: newAscending),
                                      );
                                  Navigator.pop(dialogContext);
                                  setState(() {
                                    _isSortMenuOpen = false;
                                  });
                                },
                                child: Container(
                                  height: itemHeight,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          option.label,
                                          style: TextStyle(
                                            color: isSelected
                                                ? selectedColor
                                                : textColor,
                                            fontSize: 15,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          sortState.ascending
                                              ? CupertinoIcons.arrow_up
                                              : CupertinoIcons.arrow_down,
                                          size: 16,
                                          color: selectedColor,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
      ),
    );
  }

  // ✅ 构建导航栏
  ObstructingPreferredSizeWidget _buildNavigationBar(
      BuildContext context, WidgetRef ref, int itemCount) {
    final sortState = ref.watch(sortStateProvider(widget.viewId));
    final sortLabel = sortState.sortBy.label;

    return BlurNavigationBar(
      leading: buildBlurBackButton(context),
      middle: buildNavTitle(widget.genreName, context),
      scrollController: _scrollController,
      itemCount: itemCount,
      sortLabel: sortLabel,
      sortAscending: sortState.ascending,
      isSortMenuOpen: _isSortMenuOpen,
      onSortTap: () {
        setState(() {
          _isSortMenuOpen = true;
        });
        _showSortMenu(context, ref, sortState);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(genreItemsProvider(GenreItemsParams(
      viewId: widget.viewId,
      genreName: widget.genreName,
    )));

    // ✅ 使用valueOrNull来获取当前值，如果有值就使用，避免loading状态导致的闪烁
    final itemsList = items.valueOrNull;

    // ✅ 如果有新数据，更新缓存；如果没有新数据但缓存存在，使用缓存
    if (itemsList != null) {
      _cachedItemsList = itemsList;
    }

    return items.when(
      data: (itemsList) {
        final itemCount = itemsList.length;

        return CupertinoPageScaffold(
          backgroundColor: CupertinoColors.systemBackground,
          navigationBar: _buildNavigationBar(context, ref, itemCount),
          child: _buildContentList(context, ref, itemsList),
        );
      },
      loading: () => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemBackground,
        navigationBar: BlurNavigationBar(
          leading: buildBlurBackButton(context),
          middle: buildNavTitle(widget.genreName, context),
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
          middle: buildNavTitle(widget.genreName, context),
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

  // ✅ 构建内容列表
  Widget _buildContentList(
      BuildContext context, WidgetRef ref, List<ItemInfo> items) {
    final headerHeight = 100.0; // ✅ BlurNavigationBar的preferredSize（没有tab）

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

    return RefreshIndicator(
      displacement: 20,
      edgeOffset: headerHeight,
      onRefresh: () async {
        ref.invalidate(genreItemsProvider(GenreItemsParams(
          viewId: widget.viewId,
          genreName: widget.genreName,
        )));
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: headerHeight + 6,
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
}

// ✅ 项目条目（与library_items_page一致）
class _ItemEntry {
  const _ItemEntry(this.item, this.hasHorizontalArtwork);

  final ItemInfo item;
  final bool hasHorizontalArtwork;
}

// ✅ 项目卡片（与library_items_page一致）
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
    final isDark = isDarkModeFromContext(context, ref);

    // 提取年份信息
    String? yearText;
    if (item.premiereDate != null && item.premiereDate!.isNotEmpty) {
      final startYear = int.tryParse(item.premiereDate!.substring(0, 4));
      if (startYear != null) {
        if (item.type == 'Series') {
          final status = item.status;
          if (status == 'Ended') {
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
          } else if (status == 'Continuing') {
            yearText = '$startYear-现在';
          } else {
            yearText = '$startYear';
          }
        } else {
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
      final startYear = item.productionYear;
      if (item.type == 'Series') {
        final status = item.status;
        if (status == 'Ended') {
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
        } else if (status == 'Continuing') {
          yearText = '$startYear-现在';
        } else {
          yearText = '$startYear';
        }
      } else {
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
              : SizedBox(
                  height: 100,
                  child: Container(
                    width: widget.cardWidth * 0.75 * 16 / 9,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Poster(itemId: item.id, itemType: item.type),
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

// ✅ 海报组件（与library_items_page一致）
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

// ✅ 海报占位符（与library_items_page一致）
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
