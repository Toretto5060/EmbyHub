// 电视剧 季详情
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/status_bar_manager.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../utils/app_route_observer.dart';
import '../../utils/theme_utils.dart';

// ✅ 获取季详情
final seasonProvider =
    FutureProvider.family<ItemInfo, (String seriesId, String seasonId)>(
        (ref, params) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, params.$2);
});

// ✅ 获取某一季的集列表
final episodesProvider =
    FutureProvider.family<List<ItemInfo>, (String seriesId, String seasonId)>(
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

// ✅ 获取季的继续观看集数
final seasonResumeEpisodeProvider =
    FutureProvider.family<ItemInfo?, (String seriesId, String seasonId)>(
        (ref, params) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    return null;
  }
  try {
    final api = await EmbyApi.create();
    // 获取该季的所有集数，找到有播放进度且未完成的
    final episodes = await api.getItemsByParent(
      userId: auth.userId!,
      parentId: params.$2,
      includeItemTypes: 'Episode',
      limit: 1000,
      sortBy: 'DatePlayed',
      sortOrder: 'Descending',
    );

    // 找到第一个有播放进度且未完成的集数
    for (final episode in episodes) {
      final userData = episode.userData ?? {};
      final playbackTicks =
          (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
      final totalTicks = episode.runTimeTicks ?? 0;
      final played = userData['Played'] == true;

      if (!played && playbackTicks > 0 && playbackTicks < totalTicks) {
        return episode;
      }
    }
    return null;
  } catch (e) {
    return null;
  }
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

class _SeasonEpisodesPageState extends ConsumerState<SeasonEpisodesPage>
    with RouteAware, WidgetsBindingObserver {
  final _scrollController = ScrollController();
  static const SystemUiOverlayStyle _lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );
  static const SystemUiOverlayStyle _darkStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  late SystemUiOverlayStyle _statusBarStyle;
  final Map<String, SystemUiOverlayStyle> _imageStyleCache = {};
  static const double _backdropHeight = 300;
  static const double _headerTopOffset = 250;
  static const double _headerBaseHeight = 180;
  static const double _heroBaseHeight = _backdropHeight +
      (_headerTopOffset + _headerBaseHeight - _backdropHeight);
  double _headerHeight = _headerBaseHeight;
  SystemUiOverlayStyle? _navSyncedStyle;
  late SystemUiOverlayStyle _appliedStatusStyle;
  StatusBarStyleController? _statusBarController;
  ModalRoute<dynamic>? _modalRoute;
  Animation<double>? _routeAnimation;
  bool _isRouteSubscribed = false;
  ItemInfo? _cachedSeasonData;
  DateTime? _lastRefreshTime;
  bool _hasTriggeredReturnRefresh = false;
  bool _isUpdatingPlayed = false;
  ValueNotifier<bool>? _isPlayedNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isPlayedNotifier = ValueNotifier<bool>(false);
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _statusBarStyle = StatusBarManager.currentStyle ??
        _defaultStyleForBrightness(platformBrightness);
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncStatusBarWithNavigation(
          _scrollController.hasClients ? _scrollController.offset : 0.0);
    });
    _appliedStatusStyle = _statusBarStyle;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newRoute = ModalRoute.of(context);
    if (newRoute != _modalRoute) {
      _removeRouteListener();
      _modalRoute = newRoute;
      _routeAnimation = newRoute?.animation;
      _routeAnimation?.addStatusListener(_handleRouteAnimationStatus);
    }
    if (!_isRouteSubscribed && _modalRoute != null) {
      appRouteObserver.subscribe(this, _modalRoute!);
      _isRouteSubscribed = true;
      _scheduleRefresh();
    }
  }

  @override
  void deactivate() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _statusBarController?.release();
      _statusBarController = null;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isRouteSubscribed) {
      appRouteObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    _isPlayedNotifier?.dispose();
    _statusBarController?.release();
    _statusBarController = null;
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _removeRouteListener();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
    }
  }

  @override
  void didPush() {
    super.didPush();
    _scheduleRefresh();
  }

  @override
  void didPopNext() {
    super.didPopNext();
  }

  void _scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: unused_result
      ref.refresh(seasonProvider((widget.seriesId, widget.seasonId)));
      // ignore: unused_result
      ref.refresh(episodesProvider((widget.seriesId, widget.seasonId)));
      // ignore: unused_result
      ref.refresh(
          seasonResumeEpisodeProvider((widget.seriesId, widget.seasonId)));
    });
  }

  void _handleScroll() {
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    _syncStatusBarWithNavigation(offset);
  }

  SystemUiOverlayStyle _defaultStyleForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _lightStatusBar : _darkStatusBar;
  }

  void _syncStatusBarWithNavigation(double offset) {
    if (!mounted) return;
    final brightness = getCurrentBrightnessFromContext(context, ref);
    final SystemUiOverlayStyle expandedStyle = _statusBarStyle;
    final SystemUiOverlayStyle collapsedStyle =
        _defaultStyleForBrightness(brightness);

    const double blurStart = 10.0;
    const double blurEnd = _headerTopOffset;
    final double progress;
    if (offset <= blurStart) {
      progress = 0.0;
    } else {
      final double effective =
          (offset - blurStart).clamp(0.0, blurEnd - blurStart);
      progress = (effective / (blurEnd - blurStart)).clamp(0.0, 1.0);
    }

    final SystemUiOverlayStyle targetStyle =
        progress < 0.55 ? expandedStyle : collapsedStyle;
    if (_navSyncedStyle == targetStyle) {
      return;
    }
    _navSyncedStyle = targetStyle;
    if (mounted) {
      _statusBarController?.update(targetStyle);
      setState(() {
        _navSyncedStyle = targetStyle;
        _appliedStatusStyle = targetStyle;
      });
    } else {
      SystemChrome.setSystemUIOverlayStyle(targetStyle);
      _appliedStatusStyle = targetStyle;
    }
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _statusBarController?.release();
      _statusBarController = null;
    } else if (status == AnimationStatus.completed ||
        status == AnimationStatus.forward) {
      if (mounted) {
        _statusBarController?.update(_navSyncedStyle ?? _statusBarStyle);
      }
    }
  }

  void _removeRouteListener() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = null;
    _modalRoute = null;
  }

  @override
  Widget build(BuildContext context) {
    final season =
        ref.watch(seasonProvider((widget.seriesId, widget.seasonId)));

    // ✅ 在 build 方法中检测路由是否重新变为当前（从其他页面返回）
    final route = ModalRoute.of(context);
    final isRouteCurrent = route?.isCurrent ?? false;

    // ✅ 检测是否从其他页面返回
    if (isRouteCurrent && _isRouteSubscribed) {
      final now = DateTime.now();
      if (_lastRefreshTime == null ||
          now.difference(_lastRefreshTime!) > const Duration(seconds: 1)) {
        if (!_hasTriggeredReturnRefresh) {
          _hasTriggeredReturnRefresh = true;
          _lastRefreshTime = now;
          Future.delayed(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            _scheduleRefresh();
            Future.delayed(const Duration(seconds: 2), () {
              _hasTriggeredReturnRefresh = false;
            });
          });
        }
      }
    }

    // ✅ 缓存季数据
    season.whenData((data) {
      _cachedSeasonData = data;
      if (!_isUpdatingPlayed) {
        _isPlayedNotifier?.value = (data.userData?['Played'] as bool?) ?? false;
      }
    });

    return StatusBarStyleScope(
      style: _statusBarStyle,
      child: Builder(
        builder: (context) {
          _statusBarController = StatusBarStyleScope.of(context);
          _statusBarController?.update(_navSyncedStyle ?? _statusBarStyle);
          return CupertinoPageScaffold(
            backgroundColor: CupertinoColors.systemBackground,
            child: season.maybeWhen(
              data: (data) => _buildContentArea(data),
              loading: () {
                if (_cachedSeasonData != null) {
                  return _buildContentArea(_cachedSeasonData!);
                }
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildBlurNavigationBar(context, null),
                    ),
                  ],
                );
              },
              error: (e, _) => Stack(
                children: [
                  Center(child: Text('加载失败: $e')),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildBlurNavigationBar(context, null),
                  ),
                ],
              ),
              orElse: () {
                if (_cachedSeasonData == null) {
                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildBlurNavigationBar(context, null),
                      ),
                    ],
                  );
                }
                return _buildContentArea(_cachedSeasonData!);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildContentArea(ItemInfo season) {
    final isDark = isDarkModeFromContext(context, ref);
    final episodes = ref.watch(
      episodesProvider((widget.seriesId, widget.seasonId)),
    );

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: _heroBaseHeight + (_headerHeight - _headerBaseHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: _backdropHeight,
                      child: _buildBackdropBackground(context, season),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _headerTopOffset,
                      child: _buildHeaderCard(context, season, isDark),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: episodes.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '共${list.length}集',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...list.map((episode) => _EpisodeTile(
                            key: ValueKey('episode_${episode.id}'),
                            episode: episode,
                            isDark: isDark,
                            seriesId: widget.seriesId,
                            seasonId: widget.seasonId,
                          )),
                      const SizedBox(height: 20),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildBlurNavigationBar(context, season),
        ),
      ],
    );
  }

  Widget _buildBlurNavigationBar(
    BuildContext context,
    ItemInfo? season,
  ) {
    final brightness = getCurrentBrightnessFromContext(context, ref);
    final SystemUiOverlayStyle baseStyle = _appliedStatusStyle;
    final SystemUiOverlayStyle targetStyle =
        _navSyncedStyle ?? _appliedStatusStyle;

    final Color expandedColor = _colorForStatusStyle(baseStyle, brightness);
    final Color collapsedColor = _colorForStatusStyle(targetStyle, brightness);
    final double scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final double navProgress = (scrollOffset > 200) ? 1.0 : 0.0;
    final Color currentColor =
        Color.lerp(expandedColor, collapsedColor, navProgress)!;

    final actions = season != null
        ? _buildTopActions(season, currentColor)
        : const <Widget>[];

    return BlurNavigationBar(
      forceBlur: false,
      scrollController: _scrollController,
      leading: buildBlurBackButton(context, color: currentColor),
      middle: season != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: currentColor,
                  ),
                  child: Text(widget.seasonName),
                ),
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 12,
                    color: currentColor.withOpacity(0.6),
                  ),
                  child: Text(widget.seriesName),
                ),
              ],
            )
          : null,
      trailing: actions.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
      expandedForegroundColor: expandedColor,
      collapsedForegroundColor: collapsedColor,
      enableTransition: false,
      useDynamicOpacity: true,
      blurStart: 10.0,
      blurEnd: _headerTopOffset,
    );
  }

  Color _colorForStatusStyle(
      SystemUiOverlayStyle style, Brightness fallbackBrightness) {
    final brightness = style.statusBarIconBrightness;
    if (brightness == Brightness.light) return Colors.white;
    if (brightness == Brightness.dark) return Colors.black87;
    return fallbackBrightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  List<Widget> _buildTopActions(ItemInfo season, Color iconColor) {
    return [
      ValueListenableBuilder<bool>(
        valueListenable: _isPlayedNotifier!,
        builder: (context, isPlayed, _) {
          return CupertinoButton(
            padding: const EdgeInsets.all(8),
            minSize: 0,
            onPressed: season.id != null && season.id!.isNotEmpty
                ? () => _handlePlayedToggle(season)
                : null,
            child: Icon(
              isPlayed
                  ? Icons.check_circle_rounded
                  : Icons.play_circle_outline_rounded,
              color: iconColor,
              size: 22,
            ),
          );
        },
      ),
    ];
  }

  Widget _buildBackdropBackground(BuildContext context, ItemInfo season) {
    final isDark = isDarkModeFromContext(context, ref);
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (season.id != null)
          FutureBuilder<EmbyApi>(
            future: EmbyApi.create(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container(color: CupertinoColors.systemGrey5);
              }
              final api = snapshot.data!;
              String? backdropUrl;

              // ✅ 优先使用季的背景图
              if ((season.backdropImageTags?.isNotEmpty ?? false)) {
                backdropUrl = api.buildImageUrl(
                  itemId: season.id!,
                  type: 'Backdrop',
                  maxWidth: 1200,
                );
              }

              // ✅ 如果没有季的背景图，使用系列的背景图
              if (backdropUrl == null || backdropUrl.isEmpty) {
                final seriesAsync = ref.read(seriesProvider(widget.seriesId));
                return seriesAsync.when(
                  data: (series) {
                    if ((series.backdropImageTags?.isNotEmpty ?? false) ||
                        (series.parentBackdropImageTags?.isNotEmpty ?? false)) {
                      backdropUrl = api.buildImageUrl(
                        itemId: widget.seriesId,
                        type: 'Backdrop',
                        maxWidth: 1200,
                      );
                    }
                    if (backdropUrl == null || (backdropUrl?.isEmpty ?? true)) {
                      final primaryTag = series.imageTags?['Primary'] ?? '';
                      if (primaryTag.isNotEmpty) {
                        backdropUrl = api.buildImageUrl(
                          itemId: widget.seriesId,
                          type: 'Primary',
                          maxWidth: 800,
                        );
                      }
                    }
                    if (backdropUrl == null || (backdropUrl?.isEmpty ?? true)) {
                      final seasonPrimaryTag =
                          season.imageTags?['Primary'] ?? '';
                      if (seasonPrimaryTag.isNotEmpty) {
                        backdropUrl = api.buildImageUrl(
                          itemId: season.id!,
                          type: 'Primary',
                          maxWidth: 800,
                        );
                      }
                    }
                    if (backdropUrl == null || (backdropUrl?.isEmpty ?? true)) {
                      return Container(color: CupertinoColors.systemGrey5);
                    }
                    final finalBackdropUrl = backdropUrl!;
                    return EmbyFadeInImage(
                      key: ValueKey('backdrop_${season.id}_$finalBackdropUrl'),
                      imageUrl: finalBackdropUrl,
                      fit: BoxFit.cover,
                      onImageReady: (image) => _handleBackdropImage(
                          image, season.id ?? finalBackdropUrl),
                    );
                  },
                  loading: () => Container(color: CupertinoColors.systemGrey5),
                  error: (_, __) =>
                      Container(color: CupertinoColors.systemGrey5),
                );
              }

              return EmbyFadeInImage(
                key: ValueKey('backdrop_${season.id}_$backdropUrl'),
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                onImageReady: (image) =>
                    _handleBackdropImage(image, season.id ?? backdropUrl!),
              );
            },
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  bgColor.withOpacity(0.65),
                  bgColor,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleBackdropImage(ui.Image image, String cacheKey) async {
    if (_imageStyleCache.containsKey(cacheKey)) {
      _applyStatusBarStyle(_imageStyleCache[cacheKey]!);
      return;
    }

    final bool isDark = await _isTopAreaDark(image);
    final style = isDark ? _lightStatusBar : _darkStatusBar;
    _imageStyleCache[cacheKey] = style;
    _applyStatusBarStyle(style);
  }

  Future<bool> _isTopAreaDark(ui.Image image) async {
    try {
      final int width = image.width;
      final int height = image.height;
      if (width == 0 || height == 0) {
        return true;
      }

      final int sampleRows =
          math.max(1, math.min(height, (height * 0.25).round()));
      final int rowStep = math.max(1, sampleRows ~/ 25);
      final int colStep = math.max(1, width ~/ 40);

      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return true;
      }
      final Uint8List bytes = data.buffer.asUint8List();

      double totalLuminance = 0;
      int samples = 0;

      for (int y = 0; y < sampleRows; y += rowStep) {
        final int rowOffset = y * width;
        for (int x = 0; x < width; x += colStep) {
          final int index = (rowOffset + x) * 4;
          if (index + 3 >= bytes.length) {
            continue;
          }
          final int r = bytes[index];
          final int g = bytes[index + 1];
          final int b = bytes[index + 2];
          final double luminance =
              (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          totalLuminance += luminance;
          samples++;
        }
      }

      if (samples == 0) {
        return true;
      }

      final double avg = totalLuminance / samples;
      return avg < 0.5;
    } catch (e) {
      return true;
    }
  }

  void _applyStatusBarStyle(SystemUiOverlayStyle style) {
    if (!mounted || _statusBarStyle == style) {
      return;
    }
    _statusBarStyle = style;
    _navSyncedStyle = null;
    if (mounted) {
      _statusBarController?.update(style);
      setState(() {
        _appliedStatusStyle = style;
      });
    } else {
      SystemChrome.setSystemUIOverlayStyle(style);
    }
    _syncStatusBarWithNavigation(
        _scrollController.hasClients ? _scrollController.offset : 0.0);
  }

  Widget _buildHeaderCard(BuildContext context, ItemInfo season, bool isDark) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final episodes = ref.watch(
      episodesProvider((widget.seriesId, widget.seasonId)),
    );
    final episodeCount = episodes.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    return _MeasureSize(
      onChange: (size) {
        if (size == null) return;
        final height = size.height;
        if (height <= 0) return;
        if ((_headerHeight - height).abs() > 0.5) {
          setState(() {
            _headerHeight = height;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 季名称（大标题）
            Text(
              widget.seasonName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: textColor,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            // ✅ 系列名称（副标题）
            Text(
              widget.seriesName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                color: textColor.withOpacity(0.7),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            _buildPlaySection(context, season, isDark),
            if ((season.overview ?? '').isNotEmpty) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => _showOverviewDialog(season),
                child: Text(
                  season.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaySection(
      BuildContext context, ItemInfo season, bool isDarkBackground) {
    return Consumer(
      builder: (context, ref, _) {
        final resumeEpisodeAsync = ref.watch(
            seasonResumeEpisodeProvider((widget.seriesId, widget.seasonId)));
        final episodesAsync =
            ref.watch(episodesProvider((widget.seriesId, widget.seasonId)));

        return resumeEpisodeAsync.when(
          data: (resumeEpisode) {
            if (resumeEpisode != null) {
              return _buildResumeButton(
                  context, resumeEpisode, isDarkBackground);
            }
            // ✅ 如果没有恢复播放的，找第一集
            return episodesAsync.when(
              data: (episodes) {
                if (episodes.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _buildPlayButton(
                    context, episodes.first, isDarkBackground);
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildResumeButton(
      BuildContext context, ItemInfo episode, bool isDarkBackground) {
    final positionTicks =
        (episode.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final totalTicks = episode.runTimeTicks ?? 0;
    final remainingTicks =
        totalTicks > positionTicks ? totalTicks - positionTicks : 0;
    final remainingDuration = totalTicks > 0
        ? Duration(microseconds: remainingTicks ~/ 10)
        : Duration.zero;
    final progress = totalTicks > 0 ? positionTicks / totalTicks : 0.0;

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

    final episodeNumber = episode.indexNumber ?? 0;
    final episodeName = episode.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB74D),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: episode.id != null && episode.id!.isNotEmpty
                      ? () => _handlePlay(
                            context,
                            episode.id!,
                            fromBeginning: false,
                            resumePositionTicks:
                                positionTicks > 0 ? positionTicks : null,
                          )
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.play_fill, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        '恢复播放',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (episodeNumber > 0 || episodeName.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '$episodeNumber. $episodeName',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDarkBackground ? Colors.white70 : Colors.black54,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (progress > 0 && progress < 1) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  clipBehavior: Clip.hardEdge,
                  borderRadius: BorderRadius.circular(4),
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
                        minHeight: 6,
                        backgroundColor:
                            (isDarkBackground ? Colors.white : Colors.black)
                                .withValues(alpha: 0.18),
                        valueColor: AlwaysStoppedAnimation(
                          const Color(0xFFFFB74D).withValues(alpha: 0.95),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '剩余 ${formatRemaining(remainingDuration)}',
                style: TextStyle(
                  color: isDarkBackground ? Colors.white70 : Colors.black54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPlayButton(
      BuildContext context, ItemInfo episode, bool isDarkBackground) {
    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: const Color(0xFF3F8CFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              onPressed: episode.id != null && episode.id!.isNotEmpty
                  ? () => _handlePlay(
                        context,
                        episode.id!,
                        fromBeginning: true,
                        resumePositionTicks: null,
                      )
                  : null,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.play_fill, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    '播放',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handlePlay(
    BuildContext context,
    String itemId, {
    required bool fromBeginning,
    int? resumePositionTicks,
  }) {
    final params = <String, String>{};
    if (fromBeginning) {
      params['fromStart'] = 'true';
    } else if (resumePositionTicks != null && resumePositionTicks > 0) {
      params['positionTicks'] = resumePositionTicks.toString();
    }
    final route = Uri(
      path: '/player/$itemId',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    context.push(route);
  }

  Future<void> _handlePlayedToggle(ItemInfo season) async {
    if (season.id == null || season.id!.isEmpty) return;
    if (_isUpdatingPlayed) return;

    final auth = ref.read(authStateProvider).value;
    if (auth == null || !auth.isLoggedIn) return;

    final currentPlayed = _isPlayedNotifier?.value ??
        (season.userData?['Played'] as bool?) ??
        false;

    _isUpdatingPlayed = true;

    try {
      final api = await ref.read(embyApiProvider.future);
      if (currentPlayed) {
        await api.unmarkAsPlayed(auth.userId!, season.id!);
      } else {
        await api.markAsPlayed(auth.userId!, season.id!);
      }

      if (mounted) {
        final newPlayed = !currentPlayed;
        _isPlayedNotifier?.value = newPlayed;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _scheduleRefresh();
          }
        });
        Future.delayed(const Duration(milliseconds: 1000), () {
          _isUpdatingPlayed = false;
        });
      }
    } catch (e) {
      _isUpdatingPlayed = false;
    }
  }

  void _showOverviewDialog(ItemInfo season) {
    final overview = season.overview ?? '';
    if (overview.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.seasonName,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  overview,
                  style:
                      Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ✅ 添加 seriesProvider 引用
final seriesProvider =
    FutureProvider.family<ItemInfo, String>((ref, seriesId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, seriesId);
});

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    super.key,
    required this.episode,
    required this.isDark,
    required this.seriesId,
    required this.seasonId,
  });
  final ItemInfo episode;
  final bool isDark;
  final String seriesId;
  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodeNumber = episode.indexNumber ?? 0;
    final episodeName = episode.name;
    final userData = episode.userData ?? {};
    final played = userData['Played'] == true;
    final positionTicks =
        (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final totalTicks = episode.runTimeTicks ?? 0;
    final remainingTicks =
        totalTicks > positionTicks ? totalTicks - positionTicks : 0;
    final remainingDuration = totalTicks > 0
        ? Duration(microseconds: remainingTicks ~/ 10)
        : Duration.zero;
    final progress = totalTicks > 0 ? positionTicks / totalTicks : 0.0;
    final showProgress = !played && progress > 0 && progress < 1;

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

    String formatDuration(int ticks) {
      final duration = Duration(microseconds: ticks ~/ 10);
      final minutes = duration.inMinutes;
      if (minutes < 60) {
        return '$minutes 分钟';
      }
      final hours = duration.inHours;
      final mins = minutes % 60;
      return '$hours 小时 $mins 分钟';
    }

    String? premiereDateText;
    if (episode.premiereDate != null && episode.premiereDate!.isNotEmpty) {
      try {
        final date = DateTime.parse(episode.premiereDate!);
        premiereDateText =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (e) {
        premiereDateText = episode.premiereDate;
      }
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: episode.id != null && episode.id!.isNotEmpty
          ? () => context.push('/player/${episode.id}')
          : null,
      onLongPress: episode.id != null && episode.id!.isNotEmpty
          ? () => _showEpisodeOptions(context, ref, episode)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 上部分：左侧图片，右侧信息
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 左侧图片
                SizedBox(
                  width: 150,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _EpisodeThumbnail(episodeId: episode.id),
                        ),
                      ),
                      // ✅ 已播标志
                      if (played)
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
                      // ✅ 图片底部：剩余时间（上）+ 进度条（下）
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ✅ 右侧信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ 集数+标题（换行）
                      Text(
                        '$episodeNumber. $episodeName',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // ✅ 播放时间（换行）
                      if (episode.runTimeTicks != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          formatDuration(episode.runTimeTicks!),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white.withOpacity(0.6)
                                : Colors.black.withOpacity(0.6),
                          ),
                        ),
                      ],
                      // ✅ 上映时间（换行）
                      if (premiereDateText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          premiereDateText,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white.withOpacity(0.6)
                                : Colors.black.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // ✅ 下部分：整行显示集简介（不设置高度限制）
            if (episode.overview != null && episode.overview!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                episode.overview!,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withOpacity(0.7)
                      : Colors.black.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  void _showEpisodeOptions(
      BuildContext context, WidgetRef ref, ItemInfo episode) {
    final userData = episode.userData ?? {};
    final played = userData['Played'] == true;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _handleEpisodePlayedToggle(context, ref, episode, !played);
            },
            child: Text(played ? '标记为未观看' : '标记为已观看'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _handleEpisodePlayedToggle(
    BuildContext context,
    WidgetRef ref,
    ItemInfo episode,
    bool newPlayed,
  ) async {
    if (episode.id == null || episode.id!.isEmpty) return;

    final auth = ref.read(authStateProvider).value;
    if (auth == null || !auth.isLoggedIn) return;

    try {
      final api = await ref.read(embyApiProvider.future);
      if (newPlayed) {
        await api.markAsPlayed(auth.userId!, episode.id!);
      } else {
        await api.unmarkAsPlayed(auth.userId!, episode.id!);
      }

      Future.delayed(const Duration(milliseconds: 500), () {
        if (context.mounted) {
          // ignore: unused_result
          ref.refresh(episodesProvider((seriesId, seasonId)));
        }
      });
    } catch (e) {
      // TODO: 错误提示
    }
  }
}

class _EpisodeThumbnail extends ConsumerWidget {
  const _EpisodeThumbnail({required this.episodeId});
  final String? episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (episodeId == null || episodeId!.isEmpty) {
      return Container(
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
          return Container(color: CupertinoColors.systemGrey4);
        }
        final url = snapshot.data!
            .buildImageUrl(itemId: episodeId!, type: 'Primary', maxWidth: 400);
        return EmbyFadeInImage(
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget child})
      : super(child: child);

  final ValueChanged<Size?> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size?> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final size = child?.size;
    if (_oldSize == size) return;
    _oldSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(size);
    });
  }
}
