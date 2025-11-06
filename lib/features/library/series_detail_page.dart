import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

// Provider 获取剧集的季列表
final seasonsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, seriesId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  return api.getSeasons(userId: auth.userId!, seriesId: seriesId);
});

// Provider 获取剧集详情
final seriesProvider =
    FutureProvider.family<ItemInfo, String>((ref, seriesId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('Not logged in');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, seriesId);
});

class SeriesDetailPage extends ConsumerWidget {
  const SeriesDetailPage({
    required this.seriesId,
    this.seriesName = '剧集详情',
    super.key,
  });

  final String seriesId;
  final String seriesName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(seriesProvider(seriesId));
    final seasonsAsync = ref.watch(seasonsProvider(seriesId));
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: CupertinoNavigationBarBackButton(
            color: isDark ? Colors.white : Colors.black87,
            onPressed: () => context.pop(),
          ),
          middle: Text(
            seriesName,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          backgroundColor: CupertinoColors.systemBackground,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity( 0.1)
                  : Colors.black.withOpacity( 0.1),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(seriesProvider(seriesId));
              ref.invalidate(seasonsProvider(seriesId));
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 剧集基本信息
                seriesAsync.when(
                  data: (series) => _buildSeriesInfo(context, series, isDark),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CupertinoActivityIndicator(),
                    ),
                  ),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                ),
                const SizedBox(height: 24),
                // 季列表
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  child: const Text('季'),
                ),
                const SizedBox(height: 12),
                seasonsAsync.when(
                  data: (seasons) {
                    print('🎬 Seasons loaded: ${seasons.length} seasons');
                    if (seasons.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(CupertinoIcons.tv, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              DefaultTextStyle(
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? Colors.white.withOpacity( 0.7) : Colors.black.withOpacity( 0.7),
                                ),
                                child: const Text('暂无季信息'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: seasons
                          .map((season) => _SeasonTile(
                                season: season,
                                seriesId: seriesId,
                                seriesName: seriesName,
                              ))
                          .toList(),
                    );
                  },
                  loading: () {
                    print('⏳ Loading seasons for series: $seriesId');
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CupertinoActivityIndicator(),
                            const SizedBox(height: 16),
                            DefaultTextStyle(
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white.withOpacity( 0.7) : Colors.black.withOpacity( 0.7),
                              ),
                              child: const Text('正在加载季列表...'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  error: (e, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          DefaultTextStyle(
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            child: const Text('加载季列表失败'),
                          ),
                          const SizedBox(height: 8),
                          DefaultTextStyle(
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white.withOpacity( 0.7) : Colors.black.withOpacity( 0.7),
                            ),
                            child: Text(
                              '错误信息: ${e.toString()}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DefaultTextStyle(
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white.withOpacity( 0.5) : Colors.black.withOpacity( 0.5),
                            ),
                            child: Text(
                              'seriesId: $seriesId',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CupertinoButton(
                            child: const Text('重试'),
                            onPressed: () {
                              ref.invalidate(seasonsProvider(seriesId));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildSeriesInfo(BuildContext context, ItemInfo series, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 海报
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _SeriesPoster(seriesId: seriesId),
        ),
        const SizedBox(width: 16),
        // 简介
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                child: Text(series.name),
              ),
              if (series.overview != null) ...[
                const SizedBox(height: 8),
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? Colors.white.withOpacity( 0.7)
                        : Colors.black.withOpacity( 0.7),
                    height: 1.5,
                  ),
                  child: Text(
                    series.overview!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SeriesPoster extends ConsumerWidget {
  const _SeriesPoster({required this.seriesId});
  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: 120,
            height: 180,
            color: CupertinoColors.systemGrey4,
          );
        }
        final url =
            snapshot.data!.buildImageUrl(itemId: seriesId, type: 'Primary');
        return Image.network(
          url,
          width: 120,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 120,
            height: 180,
            color: CupertinoColors.systemGrey4,
            child: const Center(
              child: Icon(CupertinoIcons.tv, size: 48),
            ),
          ),
        );
      },
    );
  }
}

class _SeasonTile extends ConsumerWidget {
  const _SeasonTile({
    required this.season,
    required this.seriesId,
    required this.seriesName,
  });

  final ItemInfo season;
  final String seriesId;
  final String seriesName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: season.id != null && season.id!.isNotEmpty
          ? () {
              context.go(
                '/series/$seriesId/season/${season.id}?seriesName=${Uri.encodeComponent(seriesName)}&seasonName=${Uri.encodeComponent(season.name)}',
              );
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? CupertinoColors.systemGrey6.darkColor
              : CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 季海报（缩略图）
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _SeasonThumbnail(seasonId: season.id),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    child: Text(season.name),
                  ),
                  if (season.overview != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withOpacity( 0.6)
                            : Colors.black.withOpacity( 0.6),
                      ),
                      child: Text(
                        season.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 20,
              color: isDark
                  ? Colors.white.withOpacity( 0.5)
                  : Colors.black.withOpacity( 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonThumbnail extends ConsumerWidget {
  const _SeasonThumbnail({required this.seasonId});
  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (seasonId == null || seasonId!.isEmpty) {
      return Container(
        width: 80,
        height: 120,
        color: CupertinoColors.systemGrey4,
        child: const Center(
          child: Icon(CupertinoIcons.tv, size: 32),
        ),
      );
    }

    return FutureBuilder(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: 80,
            height: 120,
            color: CupertinoColors.systemGrey4,
          );
        }
        final url = snapshot.data!
            .buildImageUrl(itemId: seasonId!, type: 'Primary', maxWidth: 160);
        return Image.network(
          url,
          width: 80,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 80,
            height: 120,
            color: CupertinoColors.systemGrey4,
            child: const Center(
              child: Icon(CupertinoIcons.tv, size: 32),
            ),
          ),
        );
      },
    );
  }
}

