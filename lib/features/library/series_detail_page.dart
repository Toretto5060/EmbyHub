import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/theme_utils.dart';

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

class SeriesDetailPage extends ConsumerStatefulWidget {
  const SeriesDetailPage({
    required this.seriesId,
    this.seriesName = '剧集详情',
    super.key,
  });

  final String seriesId;
  final String seriesName;

  @override
  ConsumerState<SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends ConsumerState<SeriesDetailPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seriesAsync = ref.watch(seriesProvider(widget.seriesId));
    final seasonsAsync = ref.watch(seasonsProvider(widget.seriesId));
    final isDark = isDarkModeFromContext(context, ref);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      navigationBar: BlurNavigationBar(
        leading: buildBlurBackButton(context),
        middle: buildNavTitle(widget.seriesName, context),
        scrollController: _scrollController,
      ),
      child: RefreshIndicator(
        displacement: 20,
        edgeOffset: MediaQuery.of(context).padding.top + 44,
        onRefresh: () async {
          ref.invalidate(seriesProvider(widget.seriesId));
          ref.invalidate(seasonsProvider(widget.seriesId));
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 44 + 16,
            left: 16,
            right: 16,
            bottom: 16,
          ),
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
                if (seasons.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.tv,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          DefaultTextStyle(
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.black.withOpacity(0.7),
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
                            seriesId: widget.seriesId,
                            seriesName: widget.seriesName,
                          ))
                      .toList(),
                );
              },
              loading: () {
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
                            color: isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.black.withOpacity(0.7),
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
                      const Icon(CupertinoIcons.exclamationmark_triangle,
                          size: 48, color: Colors.red),
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
                          color: isDark
                              ? Colors.white.withOpacity(0.7)
                              : Colors.black.withOpacity(0.7),
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
                          color: isDark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.black.withOpacity(0.5),
                        ),
                        child: Text(
                          'seriesId: ${widget.seriesId}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton(
                        child: const Text('重试'),
                        onPressed: () {
                          ref.invalidate(seasonsProvider(widget.seriesId));
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
    );
  }

  Widget _buildSeriesInfo(BuildContext context, ItemInfo series, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 海报
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _SeriesPoster(seriesId: widget.seriesId),
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
                        ? Colors.white.withOpacity(0.7)
                        : Colors.black.withOpacity(0.7),
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
        return SizedBox(
          width: 120,
          height: 180,
          child: EmbyFadeInImage(
            imageUrl: url,
            fit: BoxFit.cover,
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
    final isDark = isDarkModeFromContext(context, ref);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: season.id != null && season.id!.isNotEmpty
          ? () {
              context.push(
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
              child: _SeasonThumbnail(
                seasonId: season.id,
                seriesId: seriesId,
              ),
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
                            ? Colors.white.withOpacity(0.6)
                            : Colors.black.withOpacity(0.6),
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
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonThumbnail extends ConsumerStatefulWidget {
  const _SeasonThumbnail({
    required this.seasonId,
    required this.seriesId,
  });
  final String? seasonId;
  final String seriesId;

  @override
  ConsumerState<_SeasonThumbnail> createState() => _SeasonThumbnailState();
}

class _SeasonThumbnailState extends ConsumerState<_SeasonThumbnail> {
  bool _useFallback = false;

  @override
  Widget build(BuildContext context) {
    if (widget.seasonId == null || widget.seasonId!.isEmpty) {
      // 如果没有季ID，直接使用电视剧海报
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
              .buildImageUrl(itemId: widget.seriesId, type: 'Primary', maxWidth: 160);
          return SizedBox(
            width: 80,
            height: 120,
            child: EmbyFadeInImage(
              imageUrl: url,
              fit: BoxFit.cover,
            ),
          );
        },
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
        final api = snapshot.data!;
        
        // 如果使用备用图片，显示电视剧海报
        if (_useFallback) {
          final fallbackUrl = api.buildImageUrl(
            itemId: widget.seriesId,
            type: 'Primary',
            maxWidth: 160,
          );
          return SizedBox(
            width: 80,
            height: 120,
            child: EmbyFadeInImage(
              imageUrl: fallbackUrl,
              fit: BoxFit.cover,
            ),
          );
        }
        
        // 先尝试加载季图片
        final seasonUrl = api.buildImageUrl(
          itemId: widget.seasonId!,
          type: 'Primary',
          maxWidth: 160,
        );
        return SizedBox(
          width: 80,
          height: 120,
          child: _FallbackImage(
            primaryUrl: seasonUrl,
            fallbackUrl: api.buildImageUrl(
              itemId: widget.seriesId,
              type: 'Primary',
              maxWidth: 160,
            ),
            onFallback: () {
              if (mounted) {
                setState(() {
                  _useFallback = true;
                });
              }
            },
          ),
        );
      },
    );
  }
}

class _FallbackImage extends StatefulWidget {
  const _FallbackImage({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.onFallback,
  });

  final String primaryUrl;
  final String fallbackUrl;
  final VoidCallback onFallback;

  @override
  State<_FallbackImage> createState() => _FallbackImageState();
}

class _FallbackImageState extends State<_FallbackImage> {
  bool _useFallback = false;
  bool _isChecking = true;

  @override
  Widget build(BuildContext context) {
    // 如果主图片不存在，使用备用图片
    if (_useFallback) {
      return EmbyFadeInImage(
        imageUrl: widget.fallbackUrl,
        fit: BoxFit.cover,
      );
    }

    // 尝试加载主图片
    return EmbyFadeInImage(
      imageUrl: widget.primaryUrl,
      fit: BoxFit.cover,
      placeholder: _isChecking ? const SizedBox() : null,
    );
  }

  @override
  void initState() {
    super.initState();
    // 检查主图片是否存在
    _checkImageExists();
  }

  Future<void> _checkImageExists() async {
    try {
      // 使用 HEAD 请求检查图片是否存在（更高效，不下载完整图片）
      final response = await http
          .head(Uri.parse(widget.primaryUrl))
          .timeout(const Duration(seconds: 3));
      
      if (mounted) {
        if (response.statusCode == 200) {
          // 图片存在，继续加载主图片
          setState(() {
            _isChecking = false;
          });
        } else {
          // 图片不存在（404等），直接使用备用图片
          setState(() {
            _useFallback = true;
            _isChecking = false;
          });
          widget.onFallback();
        }
      }
    } catch (e) {
      // 如果检查失败（超时或网络错误），先尝试加载主图片
      // 给主图片一些时间加载，如果加载失败会由 EmbyFadeInImage 处理
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
        // 等待一段时间，如果主图片加载失败，则切换到备用图片
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted && !_useFallback) {
            // 如果主图片还没加载成功，切换到备用图片
            setState(() {
              _useFallback = true;
            });
            widget.onFallback();
          }
        });
      }
    }
  }
}
