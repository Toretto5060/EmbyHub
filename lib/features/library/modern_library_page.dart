import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/home_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';

final _resumeProvider = FutureProvider.autoDispose<List<ItemInfo>>((ref) async {
  // Watch authStateProvider so this provider rebuilds when auth changes
  final authAsync = ref.watch(authStateProvider);
  final auth = authAsync.value;

  print('=== _resumeProvider 调试 ===');
  print('authAsync.hasValue: ${authAsync.hasValue}');
  print('auth: $auth');
  print('auth?.isLoggedIn: ${auth?.isLoggedIn}');

  if (auth == null || !auth.isLoggedIn) {
    print('_resumeProvider: Not logged in, returning empty list');
    return <ItemInfo>[];
  }

  print('_resumeProvider: Fetching resume items for userId=${auth.userId}');
  final api = await EmbyApi.create();
  final items = await api.getResumeItems(auth.userId!);
  print('_resumeProvider: Got ${items.length} resume items');
  for (var i = 0; i < items.length && i < 3; i++) {
    print('  - ${items[i].name} (${items[i].type})');
  }
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

  final api = await EmbyApi.create();
  final views = await api.getUserViews(auth.userId!);
  // for (final view in views) {
  //   print(
  //       '  View: id=${view.id}, name=${view.name}, type=${view.collectionType}');
  // }
  return views;
});

final _latestByViewProvider = FutureProvider.autoDispose
    .family<List<ItemInfo>, String>((ref, viewId) async {
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

class ModernLibraryPage extends ConsumerStatefulWidget {
  const ModernLibraryPage({super.key});

  @override
  ConsumerState<ModernLibraryPage> createState() => _ModernLibraryPageState();
}

class _ModernLibraryPageState extends ConsumerState<ModernLibraryPage> {
  final _scrollController = ScrollController();

  // 统一管理间距
  static const double _sectionTitleToContentSpacing = 5.0; // 模块标题距离下方卡片的高度
  static const double _sectionSpacing = 5.0; // 模块之间的距离

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    ));

    final auth = ref.watch(authStateProvider);
    final server = ref.watch(serverSettingsProvider);
    print('build: 开始 watch _resumeProvider');
    final resumeItems = ref.watch(_resumeProvider);
    print('build: resumeItems 状态: ${resumeItems.runtimeType}');
    final views = ref.watch(_viewsProvider);

    return CupertinoPageScaffold(
      navigationBar: HomeNavigationBar(
        scrollController: _scrollController,
        title: server.when(
          data: (serverData) {
            return FutureBuilder<EmbyApi>(
              future: EmbyApi.create(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return buildHomeTitle('EmbyHub');
                }
                return FutureBuilder<Map<String, dynamic>>(
                  future: snapshot.data!.systemInfo(),
                  builder: (context, infoSnapshot) {
                    final serverName =
                        (infoSnapshot.data?['ServerName'] as String?) ??
                            serverData.host;
                    return buildHomeTitle(serverName);
                  },
                );
              },
            );
          },
          loading: () => buildHomeTitle('EmbyHub'),
          error: (_, __) => buildHomeTitle('EmbyHub'),
        ),
        // trailing 预留给将来的功能，如搜索、设置等
        trailing: null,
      ),
      child: auth.when(
        data: (authData) {
          if (!authData.isLoggedIn) {
            return _buildEmptyState(context, isLoggedIn: false);
          }
          return RefreshIndicator(
            displacement: 20,
            edgeOffset: MediaQuery.of(context).padding.top + 44,
            onRefresh: () async {
              // Invalidate providers to refresh data
              ref.invalidate(_resumeProvider);
              ref.invalidate(_viewsProvider);
              // Wait a bit for the refresh to complete
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 44,
              ),
              children: [
                // My Libraries Section
                views.when(
                  data: (viewList) {
                    if (viewList.isEmpty) {
                      return _buildEmptyState(context, isLoggedIn: true);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 我的媒体模块
                        _buildMyLibrariesSection(context, viewList),
                        // 继续观看模块（放在我的媒体之后）
                        resumeItems.when(
                          data: (items) {
                            if (items.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader(context, '继续观看'),
                                const SizedBox(
                                    height: _sectionTitleToContentSpacing),
                                _buildResumeList(context, ref, items),
                                const SizedBox(height: _sectionSpacing),
                              ],
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (e, st) => const SizedBox.shrink(),
                        ),
                        // 显示各个媒体库的最新内容（每个section内部已有底部间距）
                        ...viewList
                            .where((v) =>
                                v.collectionType != 'livetv' &&
                                v.collectionType != 'music')
                            .map((view) =>
                                _buildLatestSection(context, ref, view)),
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
                  error: (e, _) => const Center(child: Text('加载失败')),
                ),
              ],
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
        error: (_, __) => Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
            child: _buildEmptyState(context, isLoggedIn: false),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    // 根据标题选择合适的 icon
    IconData? icon;
    if (title == '我的媒体') {
      icon = CupertinoIcons.collections;
    } else if (title == '继续观看') {
      icon = CupertinoIcons.play_circle;
    } else if (title.contains('电影')) {
      icon = CupertinoIcons.film;
    } else if (title.contains('动漫')) {
      icon = CupertinoIcons.sparkles;
    } else if (title.contains('电视剧')) {
      icon = CupertinoIcons.tv;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 22,
              color: isDark ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 8),
          ],
          DefaultTextStyle(
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white : Colors.black87,
            ),
            child: Text(title),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryGrid(BuildContext context, List<ViewInfo> views) {
    return SizedBox(
      height: 125,
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

    return GestureDetector(
      onTap: view.id != null && view.id!.isNotEmpty
          ? () {
              // 根据媒体库类型跳转到不同页面
              if (view.collectionType == 'livetv') {
                context.push(
                    '/livetv/${view.id}?name=${Uri.encodeComponent(view.name)}');
              } else if (view.collectionType == 'music') {
                context.push(
                    '/music/${view.id}?name=${Uri.encodeComponent(view.name)}');
              } else {
                context.push(
                    '/library/${view.id}?name=${Uri.encodeComponent(view.name)}');
              }
            }
          : null,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(left: 6, right: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
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
                        final imageUrl = snapshot.data!.buildImageUrl(
                          itemId: view.id!,
                          type: 'Primary',
                          maxWidth: 400,
                        );
                        if (imageUrl.isEmpty) {
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
                        return SizedBox(
                          height: 100,
                          width: 150,
                          child: EmbyFadeInImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    )
                  else
                    Container(
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
                    ),
                ],
              ),
            ),
            // 标题显示在图片下方，居中
            const SizedBox(height: 4),
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.white : Colors.black87,
              ),
              child: Text(
                view.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyLibrariesSection(
      BuildContext context, List<ViewInfo> viewList) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, '我的媒体'),
        const SizedBox(height: _sectionTitleToContentSpacing),
        _buildLibraryGrid(context, viewList),
        const SizedBox(height: _sectionSpacing),
      ],
    );
  }

  Widget _buildLatestSection(
      BuildContext context, WidgetRef ref, ViewInfo view) {
    final latestItems = ref.watch(_latestByViewProvider(view.id ?? ''));

    return latestItems.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, view.name),
            const SizedBox(height: _sectionTitleToContentSpacing),
            _buildLatestList(context, ref, items),
            const SizedBox(height: _sectionSpacing),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLatestList(
      BuildContext context, WidgetRef ref, List<ItemInfo> items) {
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildLatestCard(context, ref, item);
        },
      ),
    );
  }

  Widget _buildLatestCard(BuildContext context, WidgetRef ref, ItemInfo item) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    // 构建年份显示文本
    String? yearText;
    if (item.premiereDate != null || item.productionYear != null) {
      final startYear = item.premiereDate != null
          ? DateTime.tryParse(item.premiereDate!)?.year
          : item.productionYear;

      if (startYear != null) {
        if (item.endDate != null) {
          final endYear = DateTime.tryParse(item.endDate!)?.year;
          if (endYear != null && endYear != startYear) {
            yearText = '$startYear-$endYear';
          } else {
            yearText = '$startYear';
          }
        } else if (item.type == 'Series') {
          // 电视剧如果没有结束日期，显示"开始年份-现在"
          yearText = '$startYear-现在';
        } else {
          yearText = '$startYear';
        }
      }
    }

    return Container(
      width: 100,
      margin: const EdgeInsets.only(left: 6, right: 6),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: item.id != null && item.id!.isNotEmpty
            ? () {
                if (item.type == 'Series') {
                  context.push(
                      '/series/${item.id}?name=${Uri.encodeComponent(item.name)}');
                } else if (item.type == 'Movie') {
                  // 电影类型跳转到详情页
                  context.push('/item/${item.id}');
                } else {
                  context.push('/player/${item.id}');
                }
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: _buildLatestPoster(context, ref, item.id),
                  ),
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
                        color: Colors.black.withOpacity(0.7),
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
                      if (unplayedCount == null || unplayedCount == 0) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CupertinoColors.destructiveRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unplayedCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
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
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey : Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResumeList(
      BuildContext context, WidgetRef ref, List<ItemInfo> items) {
    return SizedBox(
      height: 141,
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
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    final progress =
        (item.userData?['PlayedPercentage'] as num?)?.toDouble() ?? 0.0;
    final positionTicks =
        (item.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final totalTicks = item.runTimeTicks ?? 0;
    final remainingSeconds =
        totalTicks > 0 ? ((totalTicks - positionTicks) / 10000000).floor() : 0;
    final remainingMinutes = (remainingSeconds / 60).floor();
    final remainingSecondsDisplay = remainingSeconds % 60;

    // 构建标题文本
    String titleText;
    String? subtitleText;

    try {
      titleText = item.seriesName ?? item.name ?? '未知';
      // 如果是剧集，添加季数信息（如果大于1季）
      if (item.seriesName != null &&
          item.parentIndexNumber != null &&
          item.parentIndexNumber! > 1) {
        titleText += ' 第${item.parentIndexNumber}季';
      }

      // 构建副标题文本（集数信息）
      if (item.seriesName != null && item.indexNumber != null) {
        final episodeName = item.name ?? '';
        final episodeNum = item.indexNumber!;
        // 检查集名是否和集数重复（例如："第6集"）
        if (episodeName.contains('$episodeNum') ||
            episodeName.contains('${episodeNum}集')) {
          subtitleText = '第${episodeNum}集';
        } else {
          subtitleText = '第${episodeNum}集 $episodeName';
        }
      }
    } catch (e) {
      // 解析失败，显示原始格式
      titleText = item.seriesName ?? item.name ?? '未知';
      if (item.seriesName != null) {
        subtitleText =
            'S${item.parentIndexNumber ?? 0}E${item.indexNumber ?? 0} ${item.name ?? ''}';
      }
    }

    return Container(
      width: 180,
      margin: const EdgeInsets.only(left: 6, right: 6),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: item.id != null && item.id!.isNotEmpty
            ? () {
                if (item.type == 'Movie') {
                  // 电影类型跳转到详情页
                  context.push('/item/${item.id}');
                } else {
                  // 其他类型（剧集等）跳转到播放器
                  context.push('/player/${item.id}');
                }
              }
            : null,
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
                              final imageUrl = snapshot.data!.buildImageUrl(
                                itemId: item.id!,
                                type: 'Primary',
                                maxWidth: 600,
                              );
                              if (imageUrl.isEmpty) {
                                return Container(
                                  color: CupertinoColors.systemGrey5,
                                  child: const Icon(CupertinoIcons.film),
                                );
                              }
                              return EmbyFadeInImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                              );
                            },
                          )
                        : Container(
                            color: CupertinoColors.systemGrey5,
                            child: const Icon(CupertinoIcons.film),
                          ),
                  ),
                ),
                // 剩余时间文字显示在左下角
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                      child: Text(
                        '剩余 ${remainingMinutes}分${remainingSecondsDisplay}秒',
                      ),
                    ),
                  ),
                ),
                // 进度条显示在图片底部（缩小宽度，避开圆角，居中）
                if (progress > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 160, // 缩小宽度，避开圆角
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(
                                'progress_${item.id}'), // 使用唯一key避免重复动画
                            duration: const Duration(seconds: 1),
                            curve: Curves.easeOutCubic,
                            tween: Tween<double>(begin: 0, end: progress / 100),
                            builder: (context, value, child) {
                              return LinearProgressIndicator(
                                value: value,
                                minHeight: 3,
                                backgroundColor: Colors.black.withOpacity(0.3),
                                valueColor: const AlwaysStoppedAnimation(
                                    CupertinoColors.activeBlue),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.white : Colors.black87,
              ),
              child: Text(
                titleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (subtitleText != null)
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey : Colors.grey.shade600,
                ),
                child: Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestPoster(
      BuildContext context, WidgetRef ref, String? itemId) {
    if (itemId == null || itemId.isEmpty) {
      return Container(
        color: CupertinoColors.systemGrey5,
        child: const Center(
          child: Icon(CupertinoIcons.film, size: 48),
        ),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(color: CupertinoColors.systemGrey5);
        }
        final url = snapshot.data!.buildImageUrl(
          itemId: itemId,
          type: 'Primary',
          maxWidth: 300,
        );
        if (url.isEmpty) {
          return Container(
            color: CupertinoColors.systemGrey5,
            child: const Icon(CupertinoIcons.photo, size: 32),
          );
        }
        return EmbyFadeInImage(
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
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
              isLoggedIn
                  ? CupertinoIcons.folder
                  : CupertinoIcons.person_crop_circle_badge_xmark,
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
