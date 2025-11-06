import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

final _resumeProvider = FutureProvider.autoDispose<List<ItemInfo>>((ref) async {
  // Watch authStateProvider so this provider rebuilds when auth changes
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  
  if (auth == null || !auth.isLoggedIn) {
    print('_resumeProvider: Not logged in');
    return <ItemInfo>[];
  }
  
  print('_resumeProvider: Fetching resume items for userId=${auth.userId}');
  final api = await EmbyApi.create();
  final items = await api.getResumeItems(auth.userId!);
  print('_resumeProvider: Got ${items.length} resume items');
  return items;
});

final _viewsProvider = FutureProvider.autoDispose<List<ViewInfo>>((ref) async {
  // Watch authStateProvider so this provider rebuilds when auth changes
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  
  if (auth == null || !auth.isLoggedIn) {
    print('_viewsProvider: Not logged in');
    return <ViewInfo>[];
  }
  
  print('_viewsProvider: Fetching views for userId=${auth.userId}');
  final api = await EmbyApi.create();
  final views = await api.getUserViews(auth.userId!);
  print('_viewsProvider: Got ${views.length} views');
  for (final view in views) {
    print('  View: id=${view.id}, name=${view.name}, type=${view.collectionType}');
  }
  return views;
});

final _latestByViewProvider = FutureProvider.autoDispose.family<List<ItemInfo>, String>((ref, viewId) async {
  // Watch authStateProvider so this provider rebuilds when auth changes
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;
  
  if (auth == null || !auth.isLoggedIn) {
    print('_latestByViewProvider: Not logged in for viewId=$viewId');
    return <ItemInfo>[];
  }
  
  print('_latestByViewProvider: Fetching latest items for viewId=$viewId');
  final api = await EmbyApi.create();
  final items = await api.getLatestItems(auth.userId!, parentId: viewId);
  print('_latestByViewProvider: Got ${items.length} items for viewId=$viewId');
  return items;
});

class ModernLibraryPage extends ConsumerWidget {
  const ModernLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    ));

    final auth = ref.watch(authStateProvider);
    final server = ref.watch(serverSettingsProvider);
    final resumeItems = ref.watch(_resumeProvider);
    final views = ref.watch(_viewsProvider);

    return CupertinoPageScaffold(
      child: SafeArea(
        top: true,
        bottom: false,
        child: auth.when(
          data: (authData) {
            if (!authData.isLoggedIn) {
              return _buildEmptyState(context, isLoggedIn: false);
            }
            return RefreshIndicator(
              onRefresh: () async {
                // Invalidate providers to refresh data
                ref.invalidate(_resumeProvider);
                ref.invalidate(_viewsProvider);
                // Wait a bit for the refresh to complete
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: ListView(
                padding: EdgeInsets.zero,
              children: [
                  // Server name header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: server.when(
                      data: (serverData) {
                        return FutureBuilder<EmbyApi>(
                          future: EmbyApi.create(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return DefaultTextStyle(
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                child: const Text(
                                  'EmbyHub',
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            return FutureBuilder<Map<String, dynamic>>(
                              future: snapshot.data!.systemInfo(),
                              builder: (context, infoSnapshot) {
                                final serverName = (infoSnapshot.data?['ServerName'] as String?) ?? 
                                                 serverData.host;
                                return DefaultTextStyle(
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  child: Text(
                                    serverName,
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                      loading: () => DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        child: const Text(
                          'EmbyHub',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      error: (_, __) => DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        child: const Text(
                          'EmbyHub',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                // Continue Watching Section
                resumeItems.when(
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          _buildSectionHeader(context, '继续观看'),
                        _buildResumeList(context, ref, items),
                          const SizedBox(height: 32),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                  // My Libraries Section
                views.when(
                  data: (viewList) {
                    if (viewList.isEmpty) {
                      return _buildEmptyState(context, isLoggedIn: true);
                    }
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(context, '我的媒体'),
                          const SizedBox(height: 8),
                          _buildLibraryGrid(context, viewList),
                          const SizedBox(height: 16),
                        ],
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
              ),
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => _buildEmptyState(context, isLoggedIn: false),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 20,
              fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
        child: Text(title),
      ),
    );
  }

  Widget _buildLibraryGrid(BuildContext context, List<ViewInfo> views) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: views.length,
        itemBuilder: (context, index) {
          final view = views[index];
          return _buildLibraryCard(context, view);
        },
      ),
    );
  }

  Widget _buildLibraryCard(BuildContext context, ViewInfo view) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 12),
      child: CupertinoButton(
              padding: EdgeInsets.zero,
        onPressed: view.id != null && view.id!.isNotEmpty
            ? () => context.go('/library/${view.id}?name=${Uri.encodeComponent(view.name)}')
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
                children: [
              // Background image from Emby - try Primary type for library views
              if (view.id != null && view.id!.isNotEmpty)
                FutureBuilder<EmbyApi>(
                  future: EmbyApi.create(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Container(
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade300,
                              Colors.purple.shade400,
                            ],
                          ),
                        ),
                      );
                    }
                    print('Loading library image for ${view.name} (${view.id}), type: Primary');
                    // Try Primary type first
                    final imageUrl = snapshot.data!.buildImageUrl(
                      itemId: view.id!,
                      type: 'Primary',
                      maxWidth: 240,
                    );
                    print('Image URL: $imageUrl');
                    return Image.network(
                      imageUrl,
                      height: 100,
                      width: 150,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 100,
                          color: CupertinoColors.systemGrey5,
                          child: const Center(
                            child: CupertinoActivityIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        print('Error loading image for ${view.name}: $error');
                        // Fallback to gradient background
                        return Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.blue.shade300,
                                Colors.purple.shade400,
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                )
              else
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade300,
                        Colors.purple.shade400,
                      ],
                    ),
                  ),
                ),
              // Gradient overlay
              Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity( 0.2),
                      Colors.black.withOpacity( 0.6),
                    ],
                  ),
                ),
              ),
              // Title
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    view.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ),
            ),
        ],
          ),
        ),
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
                          Colors.black.withOpacity( 0.7),
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
                              backgroundColor: Colors.white.withOpacity( 0.3),
                              valueColor: const AlwaysStoppedAnimation(CupertinoColors.activeBlue),
                            ),
                          ),
                        const SizedBox(height: 4),
                        DefaultTextStyle(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                          child: Text(
                            '剩余 ${remainingMinutes}分${remainingSecondsDisplay}秒',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
              child: Text(
                item.seriesName ?? item.name ?? '未知',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.seriesName != null)
              DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
                child: Text(
                  'S${item.parentIndexNumber ?? 0}E${item.indexNumber ?? 0} ${item.name ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

