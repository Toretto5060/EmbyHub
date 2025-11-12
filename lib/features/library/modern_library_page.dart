import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/account_history_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../widgets/home_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/app_route_observer.dart';

class ModernLibraryPage extends ConsumerStatefulWidget {
  const ModernLibraryPage({super.key});

  @override
  ConsumerState<ModernLibraryPage> createState() => _ModernLibraryPageState();
}

class _ModernLibraryPageState extends ConsumerState<ModernLibraryPage>
    with RouteAware {
  final _scrollController = ScrollController();
  bool _isRefreshing = false; // ✅ 独立的刷新状态
  bool _isRouteSubscribed = false;

  // 统一管理间距
  static const double _sectionTitleToContentSpacing = 5.0; // 模块标题距离下方卡片的高度
  static const double _sectionSpacing = 5.0; // 模块之间的距离

  // ✅ 获取服务器名称（优先从缓存）
  Future<String> _getServerName(String fallback) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('server_name');
      if (savedName != null && savedName.isNotEmpty) {
        return savedName;
      }

      // 缓存未命中，请求获取
      final api = await EmbyApi.create();
      final info = await api.systemInfo();
      final serverName = info['ServerName'] as String?;

      if (serverName != null && serverName.isNotEmpty) {
        await prefs.setString('server_name', serverName);
        return serverName;
      }
    } catch (e) {
      print('获取服务器名称失败: $e');
    }

    return fallback;
  }

  // ✅ 构建带 loading 的标题（标题固定居中，loading紧贴右侧）
  Widget _buildTitleWithLoading(String title, bool isLoading) {
    final titleWidget = buildHomeTitle(title);

    return Center(
      child: IntrinsicWidth(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 标题
            titleWidget,
            // loading 定位在标题右侧（使用 Positioned.fill 的技巧）
            if (isLoading)
              Positioned(
                left: null, // 不限制左侧
                right: -24, // 相对于标题右边缘向右24px（8px间距 + 16px loading）
                top: 0,
                bottom: 0,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: CupertinoActivityIndicator(radius: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ✅ 等待所有刷新请求完成（后台执行）
  Future<void> _waitForAllRefreshComplete(List<ViewInfo>? viewList) async {
    try {
      final futures = <Future>[
        ref.read(resumeProvider.future),
        ref.read(viewsProvider.future),
      ];

      if (viewList != null) {
        for (final view in viewList) {
          if (view.collectionType != 'livetv' &&
              view.collectionType != 'music' &&
              view.id != null) {
            futures.add(ref.read(latestByViewProvider(view.id!).future));
          }
        }
      }

      print('🔄 后台等待 ${futures.length} 个请求完成...');
      await Future.wait(futures);
      print('✅ 所有刷新请求已完成');

      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    } catch (e) {
      print('❌ 刷新请求出错: $e');
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_isRouteSubscribed && route != null) {
      appRouteObserver.subscribe(this, route);
      _isRouteSubscribed = true;
      _scheduleHomeRefresh();
    }
  }

  void _scheduleHomeRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(viewsProvider);
      ref.invalidate(resumeProvider);
      ref.invalidate(latestByViewProvider);
    });
  }

  @override
  void didPush() {
    _scheduleHomeRefresh();
  }

  @override
  void didPopNext() {
    _scheduleHomeRefresh();
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
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    final auth = ref.watch(authStateProvider);
    final server = ref.watch(serverSettingsProvider);

    // ✅ 从缓存读取（启动页已预加载）
    print('build: 📖 读取缓存数据: resumeProvider + viewsProvider');
    final resumeItems = ref.watch(resumeProvider);
    final views = ref.watch(viewsProvider);

    // ✅ 检测是否有任何请求正在加载（不包括下拉刷新）
    final isAnyLoading =
        !_isRefreshing && (resumeItems.isLoading || views.isLoading);

    // ✅ 第二波并行请求：预加载所有媒体库的最新内容
    // 当 views 有数据后，立即触发所有 latest 请求（不等待渲染）
    final viewIds = views.whenData((viewList) {
          return viewList
              .where((v) =>
                  v.collectionType != 'livetv' &&
                  v.collectionType != 'music' &&
                  v.id != null)
              .map((v) => v.id!)
              .toList();
        }).value ??
        [];

    // 立即触发所有媒体库的最新内容请求（并行）
    final latestProviders = <AsyncValue<List<ItemInfo>>>[];
    if (viewIds.isNotEmpty) {
      print('build: 🚀 并行请求所有媒体库最新内容: ${viewIds.length} 个');
      for (final viewId in viewIds) {
        final latestAsync = ref.watch(latestByViewProvider(viewId));
        latestProviders.add(latestAsync);
      }
    }

    // ✅ 检测是否有最新内容正在加载
    final isLatestLoading = latestProviders.any((p) => p.isLoading);

    // ✅ 综合加载状态（任何数据正在加载都显示 loading）
    final shouldShowLoading = _isRefreshing || isAnyLoading || isLatestLoading;

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: HomeNavigationBar(
        scrollController: _scrollController,
        title: server.when(
          data: (serverData) {
            return FutureBuilder<String>(
              future: _getServerName(serverData.host),
              builder: (context, snapshot) {
                final serverName = snapshot.data ?? serverData.host;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _EmbyLogo(size: 28),
                    const SizedBox(width: 6),
                    _buildTitleWithLoading(serverName, shouldShowLoading),
                  ],
                );
              },
            );
          },
          loading: () => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _EmbyLogo(size: 28),
              const SizedBox(width: 6),
              _buildTitleWithLoading('EmbyHub', shouldShowLoading),
            ],
          ),
          error: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _EmbyLogo(size: 28),
              const SizedBox(width: 6),
              _buildTitleWithLoading('EmbyHub', shouldShowLoading),
            ],
          ),
        ),
        // ✅ 右侧用户头像
        trailing: auth.when(
          data: (authData) => authData.userId != null
              ? _UserAvatarMenu(
                  key: ValueKey(authData.userId), // ✅ 添加 key 以确保切换用户后更新
                  userId: authData.userId!,
                  username: authData.userName ?? 'User',
                )
              : null,
          loading: () => null,
          error: (_, __) => null,
        ),
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
              print('🔄 下拉刷新：开始刷新所有数据');

              setState(() {
                _isRefreshing = true;
              });

              // ✅ 获取当前的媒体库列表（用于刷新最新内容）
              final currentViewList = ref.read(viewsProvider).value;

              // ✅ 刷新继续观看和媒体库列表
              ref.invalidate(resumeProvider);
              ref.invalidate(viewsProvider);

              // ✅ 刷新所有媒体库的最新内容（并行）
              if (currentViewList != null) {
                for (final view in currentViewList) {
                  if (view.collectionType != 'livetv' &&
                      view.collectionType != 'music' &&
                      view.id != null) {
                    ref.invalidate(latestByViewProvider(view.id!));
                    print('  - 刷新: ${view.name}');
                  }
                }
              }

              // ✅ 固定时间后结束下拉动画
              await Future.delayed(const Duration(milliseconds: 1000));
              print('✅ 下拉刷新：动画结束（后台继续加载）');

              // ✅ 在后台继续等待所有请求完成
              _waitForAllRefreshComplete(currentViewList);
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
                  error: (e, st) {
                    // 网络错误时显示错误提示和重试按钮
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.wifi_exclamationmark,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            DefaultTextStyle(
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.black.withValues(alpha: 0.7),
                              ),
                              child: const Text(
                                '加载媒体库失败\n请检查网络连接',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 24),
                            CupertinoButton.filled(
                              onPressed: () {
                                ref.invalidate(viewsProvider);
                                ref.invalidate(resumeProvider);
                              },
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
            SizedBox(
              height: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FutureBuilder<EmbyApi>(
                  future: EmbyApi.create(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || view.id == null) {
                      return _buildLibraryPlaceholder();
                    }

                    final url = snapshot.data!
                        .buildImageUrl(itemId: view.id!, type: 'Primary');
                    if (url.isEmpty) {
                      return _buildLibraryPlaceholder();
                    }

                    return EmbyFadeInImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: _buildLibraryPlaceholder(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
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

  Widget _buildLibraryPlaceholder() {
    return Container(
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
    final latestItems = ref.watch(latestByViewProvider(view.id ?? ''));

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
    final listHeight =
        items.isNotEmpty && items.every(_latestHasHorizontalArtwork)
            ? 190.0
            : 130.0;
    return SizedBox(
      height: listHeight,
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

    final hasBackdrop = _latestHasHorizontalArtwork(item);
    final aspectRatio = hasBackdrop ? 2 / 3 : 16 / 9;
    final cardWidth = hasBackdrop ? 100.0 : 160.0;

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
      width: cardWidth,
      margin: const EdgeInsets.only(left: 6, right: 6),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: item.id != null && item.id!.isNotEmpty
            ? () {
                if (item.type == 'Series') {
                  context.push(
                      '/series/${item.id}?name=${Uri.encodeComponent(item.name)}');
                } else if (item.type == 'Movie') {
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
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _buildLatestPoster(context, ref, item,
                      hasBackdrop: hasBackdrop),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
            Text(
              yearText ?? '',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
    final normalizedProgress = (progress / 100).clamp(0.0, 1.0);
    final positionTicks =
        (item.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final totalTicks = item.runTimeTicks ?? 0;
    final remainingTicks =
        totalTicks > positionTicks ? totalTicks - positionTicks : 0;
    final remainingDuration = totalTicks > 0
        ? Duration(microseconds: remainingTicks ~/ 10)
        : Duration.zero;

    String formatRemaining(Duration duration) {
      if (duration <= Duration.zero) return '0s';
      if (duration.inHours >= 1) {
        final minutes = duration.inMinutes.remainder(60);
        return minutes > 0
            ? '${duration.inHours}h ${minutes}m'
            : '${duration.inHours}h';
      }
      if (duration.inMinutes >= 1) {
        return '${duration.inMinutes}m';
      }
      return '${duration.inSeconds}s';
    }

    // 构建标题文本
    String titleText;
    String? subtitleText;

    try {
      titleText = item.seriesName ?? item.name;
      // 如果是剧集，添加季数信息（如果大于1季）
      if (item.seriesName != null &&
          item.parentIndexNumber != null &&
          item.parentIndexNumber! > 1) {
        titleText += ' 第${item.parentIndexNumber}季';
      }

      // 构建副标题文本（集数信息）
      if (item.seriesName != null && item.indexNumber != null) {
        final episodeName = item.name;
        final episodeNum = item.indexNumber!;
        // 检查集名是否和集数重复（例如："第6集")
        if (episodeName.contains('$episodeNum') ||
            episodeName.contains('${episodeNum}集')) {
          subtitleText = '第${episodeNum}集';
        } else {
          subtitleText = '第${episodeNum}集 $episodeName';
        }
      }
    } catch (e) {
      // 解析失败，显示原始格式
      titleText = item.seriesName ?? item.name;
      if (item.seriesName != null) {
        subtitleText =
            'S${item.parentIndexNumber ?? 0}E${item.indexNumber ?? 0} ${item.name}';
      }
    }

    final subtitle = subtitleText;

    return Container(
      width: 180,
      margin: const EdgeInsets.only(left: 6, right: 6),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: item.id != null && item.id!.isNotEmpty
            ? () async {
                final itemId = item.id!;
                if (item.type == 'Movie') {
                  context.push('/item/$itemId');
                  return;
                }

                final seriesId = item.seriesId;
                if (seriesId != null && seriesId.isNotEmpty) {
                  final userId = ref.read(currentUserIdProvider);
                  try {
                    if (userId != null) {
                      final api = await ref.read(embyApiProvider.future);
                      final seasons = await api.getSeasons(
                        userId: userId,
                        seriesId: seriesId,
                      );

                      final filteredSeasons =
                          seasons.where((season) => season.id != null).toList();

                      if (filteredSeasons.length <= 1) {
                        final seriesName = item.seriesName;
                        final uri = Uri(
                          path: '/series/$seriesId',
                          queryParameters:
                              (seriesName != null && seriesName.isNotEmpty)
                                  ? {'name': seriesName}
                                  : null,
                        );
                        context.push(uri.toString());
                        return;
                      }

                      final targetSeasonId = item.seasonId ??
                          (filteredSeasons.isNotEmpty
                              ? filteredSeasons.first.id
                              : null);

                      if (targetSeasonId != null) {
                        ItemInfo? matchedSeason;
                        for (final season in filteredSeasons) {
                          if (season.id == targetSeasonId) {
                            matchedSeason = season;
                            break;
                          }
                        }

                        String? seasonName = matchedSeason?.name;
                        seasonName ??= item.parentIndexNumber != null
                            ? '第${item.parentIndexNumber}季'
                            : null;

                        final queryParams = <String, String>{};
                        if ((item.seriesName ?? '').isNotEmpty) {
                          queryParams['seriesName'] = item.seriesName!;
                        }
                        if (seasonName != null && seasonName.isNotEmpty) {
                          queryParams['seasonName'] = seasonName;
                        }

                        final uri = Uri(
                          path: '/series/$seriesId/season/$targetSeasonId',
                          queryParameters:
                              queryParams.isEmpty ? null : queryParams,
                        );
                        context.push(uri.toString());
                        return;
                      }
                    }
                  } catch (e) {
                    print('Failed to resolve seasons for $seriesId: $e');
                  }

                  final seriesName = item.seriesName;
                  final fallbackUri = Uri(
                    path: '/series/$seriesId',
                    queryParameters:
                        (seriesName != null && seriesName.isNotEmpty)
                            ? {'name': seriesName}
                            : null,
                  );
                  context.push(fallbackUri.toString());
                  return;
                }
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildResumePoster(context, ref, item),
                    if (totalTicks > 0 && normalizedProgress > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.8),
                                Colors.black.withOpacity(0.0),
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '剩余 ${formatRemaining(remainingDuration)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: normalizedProgress,
                                  minHeight: 3,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                  valueColor: AlwaysStoppedAnimation(
                                      const Color(0xFFFFB74D)
                                          .withValues(alpha: 0.95)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                titleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (subtitle != null)
              Center(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumePoster(
      BuildContext context, WidgetRef ref, ItemInfo item) {
    final apiAsync = ref.watch(embyApiProvider);

    Widget placeholder() => Container(
          color: CupertinoColors.systemGrey5,
          child: const Center(
            child: Icon(CupertinoIcons.tv, size: 48),
          ),
        );

    final itemId = item.id;
    if (itemId == null || itemId.isEmpty) {
      return placeholder();
    }

    return apiAsync.when(
      data: (api) {
        final candidates = <_ImageCandidate>[];
        final seen = <String>{};

        void addCandidate({
          required String? id,
          required String type,
          String? tag,
          int? index,
          bool allowWithoutTag = false,
        }) {
          if (id == null || id.isEmpty) return;
          if (!allowWithoutTag && (tag == null || tag.isEmpty)) return;
          final key = '$id|$type|${tag ?? ''}|${index ?? -1}|$allowWithoutTag';
          if (seen.contains(key)) return;
          seen.add(key);
          candidates.add(_ImageCandidate(
            id: id,
            type: type,
            tag: tag?.isEmpty ?? true ? null : tag,
            index: index,
            allowWithoutTag: allowWithoutTag,
          ));
        }

        final imageTags = item.imageTags ?? const <String, String>{};
        final backdropTags = item.backdropImageTags ?? const <String>[];

        if (item.type == 'Episode' || item.type == 'Series') {
          addCandidate(
            id: item.id,
            type: 'Thumb',
            tag: imageTags['Thumb'],
          );
          if (backdropTags.isNotEmpty) {
            addCandidate(
              id: item.id,
              type: 'Backdrop',
              tag: backdropTags.first,
              index: 0,
            );
          }
          addCandidate(
            id: item.id,
            type: 'Primary',
            tag: imageTags['Primary'],
          );

          addCandidate(
            id: item.parentThumbItemId,
            type: 'Thumb',
            tag: item.parentThumbImageTag,
          );
          final parentBackdropTags =
              item.parentBackdropImageTags ?? const <String>[];
          if (item.parentBackdropItemId != null &&
              parentBackdropTags.isNotEmpty) {
            addCandidate(
              id: item.parentBackdropItemId,
              type: 'Backdrop',
              tag: parentBackdropTags.first,
              index: 0,
            );
          }

          addCandidate(
            id: item.seasonId,
            type: 'Primary',
            tag: item.seasonPrimaryImageTag,
          );
          if (item.seasonId != null) {
            addCandidate(
              id: item.seasonId,
              type: 'Primary',
              allowWithoutTag: true,
            );
          }

          addCandidate(
            id: item.seriesId,
            type: 'Primary',
            tag: item.seriesPrimaryImageTag,
          );
          if (item.seriesId != null) {
            addCandidate(
              id: item.seriesId,
              type: 'Primary',
              allowWithoutTag: true,
            );
          }

          addCandidate(
            id: item.id,
            type: 'Primary',
            allowWithoutTag: true,
          );
        } else {
          if (backdropTags.isNotEmpty) {
            addCandidate(
              id: item.id,
              type: 'Backdrop',
              tag: backdropTags.first,
              index: 0,
            );
          }
          addCandidate(
            id: item.id,
            type: 'Primary',
            tag: imageTags['Primary'],
          );
          addCandidate(
            id: item.id,
            type: 'Thumb',
            tag: imageTags['Thumb'],
          );
          addCandidate(
            id: item.id,
            type: 'Primary',
            allowWithoutTag: true,
          );
        }

        String? url;
        for (final candidate in candidates) {
          url = api.buildImageUrl(
            itemId: candidate.id,
            type: candidate.type,
            maxWidth: 720,
            imageIndex: candidate.index,
            tag: candidate.tag,
          );
          if (url.isNotEmpty) {
            break;
          }
        }

        if (url == null || url.isEmpty) {
          return placeholder();
        }

        return EmbyFadeInImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: placeholder(),
        );
      },
      loading: () => placeholder(),
      error: (_, __) => placeholder(),
    );
  }

  Widget _buildLatestPoster(BuildContext context, WidgetRef ref, ItemInfo item,
      {required bool hasBackdrop}) {
    final itemId = item.id;
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

        final api = snapshot.data!;
        final url = api.buildImageUrl(
          itemId: item.id!,
          type: 'Primary',
          maxWidth: hasBackdrop ? 720 : 300,
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

// ✅ Emby Logo 组件
class _EmbyLogo extends StatelessWidget {
  const _EmbyLogo({this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/emby_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

// ✅ 用户头像菜单组件
class _UserAvatarMenu extends ConsumerWidget {
  const _UserAvatarMenu({
    super.key,
    required this.userId,
    required this.username,
  });

  final String userId;
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showUserMenu(context, ref),
      child: FutureBuilder<EmbyApi>(
        future: EmbyApi.create(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return _buildDefaultAvatar();
          }

          final api = snapshot.data!;
          final avatarUrl = api.buildUserImageUrl(userId);

          return ClipOval(
            child: SizedBox(
              width: 28, // ✅ 缩小到 28
              height: 28,
              child: EmbyFadeInImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                placeholder: _buildDefaultAvatar(),
                fadeDuration: const Duration(milliseconds: 300),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      radius: 14, // ✅ 缩小到 14
      backgroundColor: Colors.blue.shade100,
      child: Text(
        username[0].toUpperCase(),
        style: TextStyle(
          color: Colors.blue.shade700,
          fontSize: 12, // ✅ 缩小字体
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _showUserMenu(BuildContext context, WidgetRef ref) async {
    print('👤 User avatar tapped');

    // ✅ 保存外部 context 和 ref
    final outerContext = context;
    final outerRef = ref;

    final server = ref.read(serverSettingsProvider).value;
    if (server == null) return;

    final serverUrl = '${server.protocol}://${server.host}:${server.port}';
    final allAccounts = ref.read(accountHistoryProvider);
    final accounts =
        allAccounts.where((a) => a.serverUrl == serverUrl).toList();

    // ✅ 如果只有1个账号，不显示下拉菜单
    if (accounts.length <= 1) {
      print('👤 Only one account, skip menu');
      return;
    }

    final currentUserId = userId;

    // ✅ 计算最长用户名的宽度
    double maxTextWidth = 0;
    final textStyle = const TextStyle(fontSize: 14); // 使用默认字体大小

    for (final account in accounts) {
      final textPainter = TextPainter(
        text: TextSpan(text: account.username, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      if (textPainter.width > maxTextWidth) {
        maxTextWidth = textPainter.width;
      }
    }

    // ✅ 计算菜单宽度：头像(28) + 间距(12) + 最长文字宽度 + 最小间距(8) + 对号(20) + PopupMenuItem左右padding(32)
    // PopupMenuItem 默认左右 padding 各 16px，共 32px
    // 对号靠右对齐，文字和对号之间至少有 8px 间距
    final contentWidth = 28 + 12 + maxTextWidth + 8 + 20; // 内容宽度
    final menuWidth = contentWidth + 20; // 加上 PopupMenuItem 的 padding

    // ✅ 显示用户下拉菜单（根据最长用户名动态计算宽度）
    await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - menuWidth, // ✅ 根据计算出的宽度定位
        MediaQuery.of(context).padding.top + 44, // 顶部导航栏下方
        16,
        0,
      ),
      constraints: BoxConstraints(
        minWidth: menuWidth, // ✅ 固定宽度
        maxWidth: menuWidth, // ✅ 固定宽度
      ),
      items: [
        ...accounts.map((account) {
          final isCurrent = account.userId == currentUserId;
          return PopupMenuItem(
            enabled: !isCurrent, // 当前用户禁用点击
            child: Row(
              children: [
                // 用户头像
                _UserAvatarSmall(
                  userId: account.userId,
                  username: account.username,
                ),
                const SizedBox(width: 12),
                // 用户名（左对齐）
                Text(
                  account.username,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const Spacer(), // ✅ 填充剩余空间，让对号靠右
                // 当前标识（靠右对齐）
                if (isCurrent)
                  const Icon(
                    Icons.check,
                    color: Colors.green,
                    size: 20,
                  ),
              ],
            ),
            onTap: isCurrent
                ? null
                : () {
                    // ✅ 菜单会自动关闭，延迟后用外部 context 切换
                    Future.delayed(const Duration(milliseconds: 300), () async {
                      if (outerContext.mounted) {
                        await _switchToAccount(outerContext, outerRef, account);
                      }
                    });
                  },
          );
        }),
      ],
    );
  }

  // ✅ 切换账号逻辑（从设置页复制）
  Future<void> _switchToAccount(
      BuildContext context, WidgetRef ref, AccountRecord account) async {
    print('🔄 [Menu] Switching to account: ${account.username}');

    // ✅ 显示居中loading，保存 dialog context
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx; // ✅ 保存 dialog 的 context
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在切换账号...'),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // ✅ 优先使用保存的 token 和 userId
      if (account.lastToken != null &&
          account.lastToken!.isNotEmpty &&
          account.userId != null &&
          account.userId!.isNotEmpty) {
        print('🔑 [Menu] Using saved token for ${account.username}');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('emby_token', account.lastToken!);
        await prefs.setString('emby_user_id', account.userId!);
        await prefs.setString('emby_user_name', account.username);

        // 验证 token
        final api = await EmbyApi.create();
        try {
          await api.getUserViews(account.userId!);

          print('✅ [Menu] Token valid, switching');

          // 使所有 provider 失效
          ref.invalidate(viewsProvider);
          ref.invalidate(resumeProvider);
          ref.invalidate(latestByViewProvider);

          await ref.read(authStateProvider.notifier).load();
          await Future.delayed(const Duration(milliseconds: 300));

          // ✅ 关闭 loading dialog
          if (dialogContext != null && dialogContext!.mounted) {
            Navigator.of(dialogContext!).pop();
          }

          if (context.mounted) {
            // ✅ 显示成功提示（简化版，1秒后自动消失）
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Text('已切换到 ${account.username}'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        } catch (e) {
          print('❌ [Menu] Token invalid: $e');
        }
      }

      // Token 失效，要求输入密码
      // ✅ 关闭第一个 loading dialog
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      if (context.mounted) {
        final password = await _showPasswordDialog(context, account.username);
        if (password == null || password.isEmpty) {
          return;
        }

        // ✅ 重新显示loading，保存新的 dialog context
        dialogContext = null;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            dialogContext = ctx; // ✅ 保存新的 dialog context
            return const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在登录...'),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        final api = await EmbyApi.create();
        final loginResult = await api.authenticate(
            username: account.username, password: password);

        // 更新账号历史
        await ref.read(accountHistoryProvider.notifier).addAccount(
              account.serverUrl,
              loginResult.userName,
              loginResult.token,
              userId: loginResult.userId,
            );

        // 使所有 provider 失效
        ref.invalidate(viewsProvider);
        ref.invalidate(resumeProvider);
        ref.invalidate(latestByViewProvider);

        await ref.read(authStateProvider.notifier).load();
        await Future.delayed(const Duration(milliseconds: 300));

        // ✅ 关闭 loading dialog
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.of(dialogContext!).pop();
        }

        if (context.mounted) {
          // ✅ 显示成功提示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('已切换到 ${loginResult.userName}'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e, stack) {
      print('❌ [Menu] Switch failed: $e');
      print('Stack: $stack');

      // ✅ 尝试关闭 loading dialog（如果还在显示）
      if (dialogContext != null && dialogContext!.mounted) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (_) {
          print('❌ Failed to close loading dialog');
        }
      }

      if (context.mounted) {
        // ✅ 显示错误（使用 SnackBar）
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('切换失败: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<String?> _showPasswordDialog(
      BuildContext context, String username) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入密码'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '${username} 的密码',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, passwordController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

// ✅ 小尺寸用户头像（用于下拉菜单）
class _UserAvatarSmall extends StatelessWidget {
  const _UserAvatarSmall({
    required this.username,
    this.userId,
  });

  final String? userId;
  final String username;

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty) {
      return _buildDefaultAvatar();
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildDefaultAvatar();
        }

        final api = snapshot.data!;
        final avatarUrl = api.buildUserImageUrl(userId!);

        return ClipOval(
          child: SizedBox(
            width: 28, // ✅ 与当前用户头像大小一致
            height: 28,
            child: EmbyFadeInImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              placeholder: _buildDefaultAvatar(),
              fadeDuration: const Duration(milliseconds: 300),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      radius: 14, // ✅ 28 / 2 = 14
      backgroundColor: Colors.blue.shade100,
      child: Text(
        username[0].toUpperCase(),
        style: TextStyle(
          color: Colors.blue.shade700,
          fontSize: 12, // ✅ 缩小字体
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ImageCandidate {
  const _ImageCandidate({
    required this.id,
    required this.type,
    this.tag,
    this.index,
    this.allowWithoutTag = false,
  });

  final String id;
  final String type;
  final String? tag;
  final int? index;
  final bool allowWithoutTag;
}

bool _latestHasHorizontalArtwork(ItemInfo item) {
  return (item.backdropImageTags?.isNotEmpty ?? false) ||
      (item.parentBackdropImageTags?.isNotEmpty ?? false);
}
