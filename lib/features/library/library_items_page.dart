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
  premiereDate('PremiereDate', '首映日期'),
  dateCreated('DateCreated', '创建日期'),
  communityRating('CommunityRating', '公众评分'),
  name('SortName', '标题'),
  officialRating('OfficialRating', '官方分级'),
  productionYear('ProductionYear', '出品年份');

  const SortOption(this.value, this.label);
  final String value;
  final String label;
}

// 排序状态
class SortState {
  final SortOption sortBy;
  final bool ascending; // true=正序, false=倒序

  const SortState({
    this.sortBy = SortOption.premiereDate,
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

final itemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  ref.watch(libraryRefreshTickerProvider);
  final sortState = ref.watch(sortStateProvider(viewId));
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await ref.read(embyApiProvider.future);
  // 对于电视剧库，只获取 Series，不获取单集
  return api.getItemsByParent(
    userId: auth.userId!,
    parentId: viewId,
    includeItemTypes: 'Movie,Series,BoxSet,Video', // 不包含 Episode
    sortBy: sortState.sortBy.value,
    sortOrder: sortState.ascending ? 'Ascending' : 'Descending',
  );
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
  final _scrollController = ScrollController();
  bool _isRouteSubscribed = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider(widget.viewId));
    final sortState = ref.watch(sortStateProvider(widget.viewId));

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      navigationBar: BlurNavigationBar(
        leading: buildBlurBackButton(context),
        middle: buildNavTitle(widget.viewName, context),
        trailing: _SortButton(
          viewId: widget.viewId,
          sortState: sortState,
        ),
        scrollController: _scrollController,
      ),
      child: items.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 44,
                ),
                child: const Text('此分类暂无内容'),
              ),
            );
          }
          final rows = _buildRows(list);

          return RefreshIndicator(
            displacement: 20,
            edgeOffset: MediaQuery.of(context).padding.top + 44,
            onRefresh: () async {
              ref.invalidate(itemsProvider(widget.viewId));
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 44 + 12,
                left: 12,
                right: 12,
                bottom: 12,
              ),
              itemCount: rows.length,
              itemBuilder: (context, rowIndex) {
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
                      final cardWidth =
                          (availableWidth - totalSpacing) / columns;

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
        },
        loading: () => Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
            child: const CupertinoActivityIndicator(),
          ),
        ),
        error: (e, _) => Center(
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

    // 提取年份信息（与首页逻辑一致）
    String? yearText;
    if (item.premiereDate != null && item.premiereDate!.isNotEmpty) {
      final startYear = int.tryParse(item.premiereDate!.substring(0, 4));
      if (startYear != null) {
        if (item.endDate != null && item.endDate!.isNotEmpty) {
          final endYear = int.tryParse(item.endDate!.substring(0, 4));
          if (endYear != null && endYear != startYear) {
            yearText = '$startYear-$endYear';
          } else {
            yearText = '$startYear';
          }
        } else if (item.type == 'Series') {
          yearText = '$startYear-现在';
        } else {
          yearText = '$startYear';
        }
      }
    } else if (item.productionYear != null) {
      yearText = '${item.productionYear}';
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
          AspectRatio(
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
                          final unplayedCount =
                              (item.userData!['UnplayedItemCount'] as num?)
                                  ?.toInt();
                          if (unplayedCount != null && unplayedCount > 0) {
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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

// 排序按钮组件
class _SortButton extends ConsumerWidget {
  const _SortButton({
    required this.viewId,
    required this.sortState,
  });

  final String viewId;
  final SortState sortState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showSortMenu(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.sort_down,
              size: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 4),
            Text(
              sortState.sortBy.label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              sortState.ascending
                  ? CupertinoIcons.arrow_up
                  : CupertinoIcons.arrow_down,
              size: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }

  void _showSortMenu(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    final textColor = isDark ? Colors.white : Colors.black87;
    final selectedColor = CupertinoColors.activeBlue;

    // 获取按钮位置
    final RenderBox? buttonBox = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlay == null) return;

    final buttonPosition = buttonBox.localToGlobal(Offset.zero);
    final buttonSize = buttonBox.size;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Stack(
        children: [
          // 半透明背景
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(dialogContext),
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
          // 下拉菜单
          Positioned(
            top: buttonPosition.dy + buttonSize.height + 8,
            right: MediaQuery.of(context).size.width - buttonPosition.dx - buttonSize.width,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < SortOption.values.length; i++) ...[
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
                              final notifier = ref.read(sortStateProvider(viewId).notifier);
                              final currentState = ref.read(sortStateProvider(viewId));
                              if (currentState.sortBy == SortOption.values[i]) {
                                // 相同选项，切换正序/倒序
                                notifier.updateState(
                                  currentState.copyWith(ascending: !currentState.ascending),
                                );
                              } else {
                                // 不同选项，切换到新选项（默认倒序）
                                notifier.updateState(
                                  SortState(sortBy: SortOption.values[i], ascending: false),
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
                                      SortOption.values[i].label,
                                      style: TextStyle(
                                        color: sortState.sortBy == SortOption.values[i]
                                            ? selectedColor
                                            : textColor,
                                        fontSize: 15,
                                        fontWeight: sortState.sortBy == SortOption.values[i]
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (sortState.sortBy == SortOption.values[i]) ...[
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
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
