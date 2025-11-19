// 电视剧 季详情
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/theme_utils.dart';

// Provider 获取某一季的集列表
final episodesProvider = FutureProvider.autoDispose
    .family<List<ItemInfo>, (String seriesId, String seasonId)>(
        (ref, params) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  return api.getEpisodes(
    userId: auth.userId!,
    seriesId: params.$1,
    seasonId: params.$2,
  );
});

class SeasonEpisodesPage extends ConsumerStatefulWidget {
  const SeasonEpisodesPage({
    required this.seriesId,
    required this.seasonId,
    this.seriesName = '剧集',
    this.seasonName = '第一季',
    super.key,
  });

  final String seriesId;
  final String seasonId;
  final String seriesName;
  final String seasonName;

  @override
  ConsumerState<SeasonEpisodesPage> createState() => _SeasonEpisodesPageState();
}

class _SeasonEpisodesPageState extends ConsumerState<SeasonEpisodesPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodes = ref.watch(
      episodesProvider((widget.seriesId, widget.seasonId)),
    );
    final isDark = isDarkModeFromContext(context, ref);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      navigationBar: BlurNavigationBar(
        leading: buildBlurBackButton(context),
        scrollController: _scrollController,
        middle: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              child: Text(widget.seriesName),
            ),
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withOpacity(0.6)
                    : Colors.black.withOpacity(0.6),
              ),
              child: Text(widget.seasonName),
            ),
          ],
        ),
      ),
      child: episodes.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('此季暂无剧集'));
          }
          return RefreshIndicator(
            displacement: 20,
            edgeOffset: MediaQuery.of(context).padding.top + 44,
            onRefresh: () async {
              ref.invalidate(
                episodesProvider((widget.seriesId, widget.seasonId)),
              );
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
              itemCount: list.length,
              itemBuilder: (context, index) {
                final episode = list[index];
                return _EpisodeTile(episode: episode);
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
        error: (e, stack) => Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
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
                    child: const Text('加载集列表失败'),
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
                      'seriesId: ${widget.seriesId}\nseasonId: ${widget.seasonId}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CupertinoButton(
                    child: const Text('重试'),
                    onPressed: () {
                      ref.invalidate(
                        episodesProvider((widget.seriesId, widget.seasonId)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({required this.episode});
  final ItemInfo episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    String episodeNumber = '';
    if (episode.indexNumber != null) {
      episodeNumber = '第${episode.indexNumber}集';
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: episode.id != null && episode.id!.isNotEmpty
          ? () => context.push('/player/${episode.id}')
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark
              ? CupertinoColors.systemGrey6.darkColor
              : CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 集的缩略图
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: _EpisodeThumbnail(episodeId: episode.id),
            ),
            // 集信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (episodeNumber.isNotEmpty)
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.black.withOpacity(0.5),
                        ),
                        child: Text(episodeNumber),
                      ),
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      child: Text(
                        episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (episode.overview != null) ...[
                      const SizedBox(height: 6),
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withOpacity(0.6)
                              : Colors.black.withOpacity(0.6),
                          height: 1.4,
                        ),
                        child: Text(
                          episode.overview!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (episode.runTimeTicks != null) ...[
                      const SizedBox(height: 6),
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.black.withOpacity(0.5),
                        ),
                        child: Text(_formatDuration(episode.runTimeTicks!)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int ticks) {
    final duration = Duration(microseconds: ticks ~/ 10);
    final minutes = duration.inMinutes;
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final hours = duration.inHours;
    final mins = minutes % 60;
    return '$hours 小时 $mins 分钟';
  }
}

class _EpisodeThumbnail extends ConsumerWidget {
  const _EpisodeThumbnail({required this.episodeId});
  final String? episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (episodeId == null || episodeId!.isEmpty) {
      return Container(
        width: 140,
        height: 80,
        color: CupertinoColors.systemGrey4,
        child: const Center(
          child: Icon(CupertinoIcons.play_circle, size: 32),
        ),
      );
    }

    return FutureBuilder(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: 140,
            height: 80,
            color: CupertinoColors.systemGrey4,
          );
        }
        // 使用 Primary 类型获取集的缩略图
        final url = snapshot.data!
            .buildImageUrl(itemId: episodeId!, type: 'Primary', maxWidth: 280);
        return SizedBox(
          width: 140,
          height: 80,
          child: EmbyFadeInImage(
            imageUrl: url,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}
