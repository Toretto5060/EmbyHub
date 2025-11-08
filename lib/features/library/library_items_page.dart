import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_route_observer.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';

final itemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  // 对于电视剧库，只获取 Series，不获取单集
  return api.getItemsByParent(
    userId: auth.userId!,
    parentId: viewId,
    includeItemTypes: 'Movie,Series,BoxSet,Video', // 不包含 Episode
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

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      navigationBar: BlurNavigationBar(
        leading: buildBlurBackButton(context),
        middle: buildNavTitle(widget.viewName, context),
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
          return RefreshIndicator(
            displacement: 20,
            edgeOffset: MediaQuery.of(context).padding.top + 44,
            onRefresh: () async {
              ref.invalidate(itemsProvider(widget.viewId));
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 44 + 12,
                left: 12,
                right: 12,
                bottom: 12,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.58,  // 调整比例以适应标题+年份
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 12),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final item = list[index];
                return _ItemTile(item: item);
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

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});
  final ItemInfo item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    
    // 提取年份信息（与首页逻辑一致）
    String? yearText;
    if (item.premiereDate != null && item.premiereDate!.isNotEmpty) {
      final startYear =
          int.tryParse(item.premiereDate!.substring(0, 4));
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
    final playbackTicks = (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final playedTicks = clampTicks(playbackTicks, totalTicks);
    final played = userData['Played'] == true || (totalTicks > 0 && playedTicks >= totalTicks);
    final showProgress = item.type == 'Movie' && !played && totalTicks > 0 && playedTicks > 0;
    final progress = totalTicks > 0 ? playedTicks / totalTicks : 0.0;
    final remainingTicks = totalTicks > playedTicks ? totalTicks - playedTicks : 0;
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
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.18 : 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _Poster(itemId: item.id, itemType: item.type),
                  ),
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
                  // 评分显示在右下角（优先豆瓣，否则IMDb等）
                  if (item.getRating() != null)
                    Positioned(
                      bottom: showProgress ? 26 : 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 根据评分来源显示不同图标
                            if (item.getRatingSource() == 'douban')
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
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
                            Text(
                              '剩余 ${formatRemaining(remainingDuration)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 4),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: 0,
                                end: progress.clamp(0.0, 1.0),
                              ),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: value,
                                    minHeight: 4,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.2),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.blueAccent.withValues(alpha: 0.9),
                                    ),
                                  ),
                                );
                              },
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

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _PosterSkeleton(itemType: itemType);
        }

        // 使用 Primary 类型获取海报
        final url =
            snapshot.data!.buildImageUrl(itemId: itemId!, type: 'Primary');

        return SizedBox.expand(
          child: EmbyFadeInImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: _PosterSkeleton(itemType: itemType),
          ),
        );
      },
    );
  }
}

class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton({this.itemType});
  final String? itemType;

  IconData get _icon =>
      (itemType == 'Series' || itemType == 'Episode')
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
