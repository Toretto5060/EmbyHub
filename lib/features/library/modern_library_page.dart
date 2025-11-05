import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

final _resumeProvider = FutureProvider<List<ItemInfo>>((ref) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  return api.getResumeItems(auth.userId!);
});

final _viewsProvider = FutureProvider<List<ViewInfo>>((ref) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ViewInfo>[];
  final api = await EmbyApi.create();
  return api.getUserViews(auth.userId!);
});

final _latestByViewProvider = FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  return api.getLatestItems(auth.userId!, parentId: viewId);
});

class ModernLibraryPage extends ConsumerWidget {
  const ModernLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    final auth = ref.watch(authStateProvider);
    final resumeItems = ref.watch(_resumeProvider);
    final views = ref.watch(_viewsProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('媒体库'),
        backgroundColor: Color(0x00000000),
        border: null,
      ),
      child: SafeArea(
        top: false,
        child: auth.when(
          data: (authData) {
            if (!authData.isLoggedIn) {
              return _buildEmptyState(context, isLoggedIn: false);
            }
            return ListView(
              padding: const EdgeInsets.only(top: 60, bottom: 16),
              children: [
                // Continue Watching Section
                resumeItems.when(
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(context, '继续观看', null),
                        _buildResumeList(context, ref, items),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                // Libraries Sections
                views.when(
                  data: (viewList) {
                    if (viewList.isEmpty) {
                      return _buildEmptyState(context, isLoggedIn: true);
                    }
                    return Column(
                      children: viewList.map((view) {
                        return _buildLibrarySection(context, ref, view);
                      }).toList(),
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CupertinoActivityIndicator(),
                    ),
                  ),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                ),
              ],
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => _buildEmptyState(context, isLoggedIn: false),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, String? viewId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (viewId != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => context.go('/library/$viewId'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('更多', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 4),
                  Icon(CupertinoIcons.chevron_right, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumeList(BuildContext context, WidgetRef ref, List<ItemInfo> items) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildResumeCard(context, ref, item);
        },
      ),
    );
  }

  Widget _buildResumeCard(BuildContext context, WidgetRef ref, ItemInfo item) {
    final progress = (item.userData?['PlayedPercentage'] as num?)?.toDouble() ?? 0.0;
    final positionTicks = (item.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final totalTicks = item.runTimeTicks ?? 0;
    final remainingSeconds = totalTicks > 0 ? ((totalTicks - positionTicks) / 10000000).floor() : 0;
    final remainingMinutes = (remainingSeconds / 60).floor();
    final remainingSecondsDisplay = remainingSeconds % 60;

    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => context.go('/player/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: item.id != null
                        ? FutureBuilder<EmbyApi>(
                            future: ref.read(embyApiProvider.future),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return Container(
                                  color: CupertinoColors.systemGrey5,
                                  child: const Icon(CupertinoIcons.film),
                                );
                              }
                              return Image.network(
                                snapshot.data!.buildImageUrl(
                                  itemId: item.id!,
                                  type: 'Primary',
                                  maxWidth: 600,
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: CupertinoColors.systemGrey5,
                                  child: const Icon(CupertinoIcons.film),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: CupertinoColors.systemGrey5,
                            child: const Icon(CupertinoIcons.film),
                          ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (progress > 0)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress / 100,
                              minHeight: 4,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: const AlwaysStoppedAnimation(CupertinoColors.activeBlue),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '剩余 ${remainingMinutes}分${remainingSecondsDisplay}秒',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.seriesName ?? item.name ?? '未知',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.seriesName != null)
              Text(
                'S${item.parentIndexNumber ?? 0}E${item.indexNumber ?? 0} ${item.name ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibrarySection(BuildContext context, WidgetRef ref, ViewInfo view) {
    final latest = ref.watch(_latestByViewProvider(view.id ?? ''));

    return latest.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, view.name ?? '媒体库', view.id),
            _buildLatestGrid(context, ref, items),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              view.name ?? '加载中...',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Center(child: CupertinoActivityIndicator()),
          ],
        ),
      ),
      error: (e, stack) {
        print('Error loading library ${view.name}: $e');
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildLatestGrid(BuildContext context, WidgetRef ref, List<ItemInfo> items) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildMediaCard(context, ref, item);
        },
      ),
    );
  }

  Widget _buildMediaCard(BuildContext context, WidgetRef ref, ItemInfo item) {
    return Container(
      width: 130,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => context.go('/item/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: item.id != null
                    ? FutureBuilder<EmbyApi>(
                        future: ref.read(embyApiProvider.future),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Container(
                              color: CupertinoColors.systemGrey5,
                              child: const Icon(CupertinoIcons.film),
                            );
                          }
                          return Image.network(
                            snapshot.data!.buildImageUrl(
                              itemId: item.id!,
                              type: 'Primary',
                              maxWidth: 260,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: CupertinoColors.systemGrey5,
                              child: const Icon(CupertinoIcons.film),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: CupertinoColors.systemGrey5,
                        child: const Icon(CupertinoIcons.film),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.name ?? '未知',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isLoggedIn}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLoggedIn ? CupertinoIcons.folder : CupertinoIcons.person_crop_circle_badge_xmark,
              size: 80,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 24),
            Text(
              isLoggedIn ? '暂无媒体库' : '未登录',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isLoggedIn
                  ? '服务器上还没有可用的媒体库\n请在 Emby 服务器中添加媒体内容'
                  : '连接 Emby 服务器后即可浏览媒体库\n您也可以使用本地下载功能',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 32),
            if (!isLoggedIn)
              CupertinoButton.filled(
                onPressed: () => context.go('/connect'),
                child: const Text('去连接服务器'),
              ),
          ],
        ),
      ),
    );
  }
}

// Provider for EmbyApi instance
final embyApiProvider = FutureProvider<EmbyApi>((ref) => EmbyApi.create());

