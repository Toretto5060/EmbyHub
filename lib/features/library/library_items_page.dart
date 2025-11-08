import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';

final itemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  final auth = ref.read(authStateProvider).value;
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

class _LibraryItemsPageState extends ConsumerState<LibraryItemsPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _Poster(itemId: item.id, itemType: item.type),
                ),
                // 评分显示在右下角（优先豆瓣，否则IMDb等）
                if (item.getRating() != null)
                  Positioned(
                    bottom: 4,
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
              ],
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
