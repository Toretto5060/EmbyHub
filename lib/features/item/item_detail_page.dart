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
import 'package:url_launcher/url_launcher.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../widgets/fade_in_image.dart';
import '../../utils/status_bar_manager.dart';

final itemProvider =
    FutureProvider.family<ItemInfo, String>((ref, itemId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, itemId);
});

final similarItemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, itemId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    debugPrint('[Similar] skipped: not logged in');
    return const [];
  }
  final api = await ref.watch(embyApiProvider.future);
  final items =
      await api.getSimilarItems(auth.userId!, itemId, limit: 12);
  debugPrint('[Similar] fetched ${items.length} items for $itemId');
  return items;
});

class ItemDetailPage extends ConsumerStatefulWidget {
  const ItemDetailPage({required this.itemId, super.key});
  final String itemId;

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage> {
  final _scrollController = ScrollController();
  static const SystemUiOverlayStyle _lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
  static const SystemUiOverlayStyle _darkStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  SystemUiOverlayStyle _statusBarStyle = _lightStatusBar;
  final Map<String, SystemUiOverlayStyle> _imageStyleCache = {};
  int? _selectedAudioStreamIndex;
  int? _selectedSubtitleStreamIndex;
  final GlobalKey _resumeMenuAnchorKey = GlobalKey();
  static const Color _resumeButtonColor = Color(0xFFFFB74D);
  static const Color _playButtonColor = Color(0xFF3F8CFF);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(itemProvider(widget.itemId));

    return StatusBarStyleScope(
      style: _statusBarStyle,
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemBackground,
        child: item.when(
          data: (data) {
            final isPlayed = (data.userData?['Played'] as bool?) ?? false;
            final isDark =
                MediaQuery.of(context).platformBrightness == Brightness.dark;
            final performers = data.performers ?? const <PerformerInfo>[];
            final externalLinks = _composeExternalLinks(data);
            final similarItems = ref.watch(similarItemsProvider(widget.itemId));

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 350,
                  backgroundColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  leadingWidth: 60,
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => context.pop(),
                      child: Icon(
                        CupertinoIcons.back,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 28,
                      ),
                    ),
                  ),
                  actions: _buildTopActions(isDark, isPlayed),
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final collapsedHeight =
                          MediaQuery.of(context).padding.top + kToolbarHeight;
                      final isCollapsed =
                          constraints.maxHeight <= collapsedHeight + 8;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildBackdropBackground(context, data),
                          if (isCollapsed)
                            ClipRect(
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 12,
                                  sigmaY: 12,
                                ),
                                child: Container(
                                  color: (isDark
                                          ? Colors.black
                                          : Colors.white)
                                      .withOpacity(isDark ? 0.35 : 0.4),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  systemOverlayStyle: isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                ),
                // 后续内容（剧情简介等）
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -60),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground.resolveFrom(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.name,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                              shadows: isDark
                                  ? const [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildMetaInfo(data, isDark),
                          const SizedBox(height: 8),
                          _buildMediaInfo(data, isDark),
                          const SizedBox(height: 16),
                          _buildPlaySection(context, data, isDark),
                          const SizedBox(height: 24),
                          if ((data.overview ?? '').isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _showOverviewDialog(data),
                              child: Text(
                                data.overview!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, height: 1.4),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (performers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text(
                              '演员',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 190,
                              child: ListView.separated(
                                padding: const EdgeInsets.only(right: 12),
                                scrollDirection: Axis.horizontal,
                                itemCount: performers.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  return _PerformerCard(
                                    performer: performers[index],
                                    isDark: isDark,
                                  );
                                },
                              ),
                            ),
                          ],
                          similarItems.when(
                            data: (items) {
                              if (items.isEmpty) {
                                debugPrint('[Similar] no items to display');
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 24),
                                  const Text(
                                    '其他类似影片',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: 190,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.only(right: 12),
                                      scrollDirection: Axis.horizontal,
                                      itemCount: items.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 12),
                                      itemBuilder: (context, index) {
                                        return _SimilarCard(
                                          item: items[index],
                                          isDark: isDark,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: CupertinoActivityIndicator(),
                              ),
                            ),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                          if (externalLinks.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildExternalLinks(externalLinks, isDark),
                            const SizedBox(height: 24),
                            _buildDetailedMediaModules(data, isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
      ),
    );
  }

  Widget _buildBackdropBackground(BuildContext context, ItemInfo item) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return SizedBox(
      height: 350,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图片（从顶部开始，包含状态栏区域）
          if (item.id != null)
            FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
                  return Container(color: CupertinoColors.systemGrey5);
                }
                final url = snapshot.data!.buildImageUrl(
                  itemId: item.id!,
                  type: 'Backdrop',
                  maxWidth: 800,
                );
                return EmbyFadeInImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  onImageReady: (image) => _handleBackdropImage(image, item.id ?? url),
                );
              },
            ),
          // 底部虚化渐变（轻微虚化，自然过渡）
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 180,
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
      ),
    );
  }

  List<Widget> _buildTopActions(bool isDark, bool isPlayed) {
    final Color iconColor = isDark ? Colors.white : Colors.black87;
    return [
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        minSize: 0,
        onPressed: null,
        child: Icon(
          CupertinoIcons.tv,
          color: iconColor.withOpacity(0.7),
          size: 22,
        ),
      ),
      if (isPlayed)
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          minSize: 0,
          onPressed: null,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: CupertinoColors.activeGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.check_mark,
              color: Colors.white,
              size: 14,
            ),
          ),
        ),
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        minSize: 0,
        onPressed: null,
        child: Icon(
          CupertinoIcons.heart,
          color: iconColor.withOpacity(0.7),
          size: 22,
        ),
      ),
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        minSize: 0,
        onPressed: null,
        child: Icon(
          CupertinoIcons.ellipsis,
          color: iconColor.withOpacity(0.7),
          size: 22,
        ),
      ),
    ];
  }

  Widget _buildMetaInfo(ItemInfo item, bool isDark) {
    final List<String> metaItems = [];

    // 评分
    final rating = item.getRating();
    if (rating != null) {
      if (item.getRatingSource() == 'douban') {
        metaItems.add('豆 ${rating.toStringAsFixed(1)}');
      } else {
        metaItems.add('⭐ ${rating.toStringAsFixed(1)}');
      }
    }

    // 年份
    if (item.productionYear != null) {
      metaItems.add('${item.productionYear}');
    }

    // 时长
    if (item.runTimeTicks != null) {
      final duration =
          Duration(microseconds: (item.runTimeTicks! / 10).round());
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      metaItems.add('${hours}时${minutes}分');
    }

    final baseColor = isDark ? Colors.white : Colors.black87;
    return Text(
      metaItems.join(' · '),
      style: TextStyle(
        fontSize: 13,
        color: baseColor,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildMediaInfo(ItemInfo item, bool isDark) {
    final genres = item.genres ?? const [];
    final resolutionInfo = _formatResolutionInfo(_getPrimaryMediaSource(item));
    final audioStreams = _getAudioStreams(item);
    final subtitleStreams = _getSubtitleStreams(item);
    final selectedAudioIndex = _ensureAudioSelection(audioStreams);
    final selectedSubtitleIndex = _ensureSubtitleSelection(subtitleStreams);

    final textColor = isDark ? Colors.white : Colors.black87;
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final textStyle = TextStyle(color: textColor, fontSize: 13, height: 1.4);
    final widgets = <Widget>[];

    void addRow(String label, String value,
        {bool highlight = false,
        ValueChanged<BuildContext>? onTap,
        bool isDefault = false}) {
      if (value.isEmpty) return;
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 6));
      }

      final valueText = isDefault && !value.contains('默认')
          ? '$value (默认)'
          : value;
      widgets.add(Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$label: ', style: textStyle),
          Expanded(
            child: highlight
                ? Builder(
                    builder: (context) {
                      final key = GlobalKey();
                      final child = Container(
                        key: key,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          valueText,
                          style: textStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                      if (onTap == null) return child;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(key.currentContext ?? context),
                        child: child,
                      );
                    },
                  )
                : Text(
                    valueText,
                    style: textStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ));
    }

    if (genres.isNotEmpty) {
      addRow('类型', genres.join(' / '));
    }

    if (resolutionInfo != null) {
      addRow('视频', resolutionInfo);
    }

    if (audioStreams.isNotEmpty &&
        selectedAudioIndex >= 0 &&
        selectedAudioIndex < audioStreams.length) {
      final audioStream = audioStreams[selectedAudioIndex];
      final audioLabel = _formatAudioStream(audioStream);
      final hasMultiple = audioStreams.length > 1;

      addRow(
        '音频',
        audioLabel,
        highlight: hasMultiple,
        isDefault: (audioStream['IsDefault'] as bool?) == true,
        onTap: hasMultiple
            ? (ctx) => _showAudioSelectionMenu(
                  ctx,
                  audioStreams,
                  selectedAudioIndex,
                )
            : null,
      );
    }

    if (subtitleStreams.isNotEmpty &&
        selectedSubtitleIndex >= 0 &&
        selectedSubtitleIndex < subtitleStreams.length) {
      final subtitleStream = subtitleStreams[selectedSubtitleIndex];
      final subtitleLabel = _formatSubtitleStream(subtitleStream);
      final hasMultiple = subtitleStreams.length > 1;

      addRow(
        '字幕',
        subtitleLabel,
        highlight: hasMultiple,
        isDefault: (subtitleStream['IsDefault'] as bool?) == true,
        onTap: hasMultiple
            ? (ctx) => _showSubtitleSelectionMenu(
                  ctx,
                  subtitleStreams,
                  selectedSubtitleIndex,
                )
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPlaySection(
      BuildContext context, ItemInfo item, bool isDarkBackground) {
    final int runtimeTicks = item.runTimeTicks ?? 0;
    final playedTicks =
        (item.userData?['PlaybackPositionTicks'] as num?)?.toInt();
    final bool hasRuntime = runtimeTicks > 0;
    final bool canResume = hasRuntime &&
        playedTicks != null &&
        playedTicks > 0 &&
        playedTicks < runtimeTicks;

    Duration? totalDuration;
    Duration? playedDuration;
    Duration? remainingDuration;
    double? progress;
    if (hasRuntime) {
      totalDuration = Duration(microseconds: (runtimeTicks / 10).round());
      if (playedTicks != null) {
        playedDuration =
            Duration(microseconds: (playedTicks / 10).round());
        remainingDuration = totalDuration - playedDuration;
        progress = playedTicks / runtimeTicks;
      }
    }

    final Color buttonColor =
        canResume ? _resumeButtonColor : _playButtonColor;
    final Color textColor = Colors.white;
    final String buttonLabel = canResume ? '恢复播放' : '播放';

    final ValueNotifier<bool> menuOpenNotifier = ValueNotifier(false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: buttonColor,
                borderRadius: BorderRadius.circular(14),
                onPressed: item.id != null && item.id!.isNotEmpty
                    ? () => _handlePlay(context, item.id!, fromBeginning: false)
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.play_fill, color: textColor),
                    const SizedBox(width: 8),
                    Text(
                      buttonLabel,
                      style: TextStyle(fontSize: 16, color: textColor),
                    ),
                  ],
                ),
              ),
            ),
            if (canResume) ...[
              const SizedBox(width: 12),
              ValueListenableBuilder<bool>(
                valueListenable: menuOpenNotifier,
                builder: (context, isOpen, _) {
                  return Builder(
                    builder: (anchorContext) => GestureDetector(
                      key: _resumeMenuAnchorKey,
                      onTap: () async {
                        menuOpenNotifier.value = true;
                        await _showResumeMenu(anchorContext, item);
                        menuOpenNotifier.value = false;
                      },
                      child: Container(
                         height: 44,
                         width: 44,
                         decoration: BoxDecoration(
                           color: buttonColor,
                           borderRadius: BorderRadius.circular(14),
                         ),
                        alignment: Alignment.center,
                        child: AnimatedRotation(
                          turns: isOpen ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            color: textColor,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
        if (canResume && progress != null && remainingDuration != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  clipBehavior: Clip.hardEdge,
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: (isDarkBackground
                            ? Colors.white
                            : Colors.black)
                        .withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation(
                      _resumeButtonColor.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDuration(remainingDuration),
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

      final int sampleRows = math.max(1, math.min(height, (height * 0.25).round()));
      final int rowStep = math.max(1, sampleRows ~/ 25);
      final int colStep = math.max(1, width ~/ 40);

      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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
          final double luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
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
      debugPrint('Failed to analyze image brightness: $e');
      return true;
    }
  }

  void _applyStatusBarStyle(SystemUiOverlayStyle style) {
    if (!mounted || _statusBarStyle == style) {
      return;
    }
    _statusBarStyle = style;
    StatusBarStyleScope.of(context)?.update(style);
    setState(() {});
  }

  Map<String, dynamic>? _getPrimaryMediaSource(ItemInfo item) {
    final sources = item.mediaSources;
    if (sources == null || sources.isEmpty) return null;
    return sources.first;
  }

  List<Map<String, dynamic>> _getAudioStreams(ItemInfo item) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) return const [];
    final streams = media['MediaStreams'];
    if (streams is List) {
      return streams
          .where((element) =>
              element is Map &&
              (element['Type'] as String?)?.toLowerCase() == 'audio')
          .map((element) => Map<String, dynamic>.from(
              (element as Map<dynamic, dynamic>).map((key, value) =>
                  MapEntry(key.toString(), value))))
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _getSubtitleStreams(ItemInfo item) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) return const [];
    final streams = media['MediaStreams'];
    if (streams is List) {
      return streams
          .where((element) =>
              element is Map &&
              (element['Type'] as String?)?.toLowerCase() == 'subtitle')
          .map((element) => Map<String, dynamic>.from(
              (element as Map<dynamic, dynamic>).map((key, value) =>
                  MapEntry(key.toString(), value))))
          .toList();
    }
    return const [];
  }

  int _ensureAudioSelection(List<Map<String, dynamic>> audioStreams) {
    if (audioStreams.isEmpty) return -1;
    final defaultIndex = audioStreams.indexWhere(
        (stream) => (stream['IsDefault'] as bool?) == true);
    final fallback = defaultIndex != -1 ? defaultIndex : 0;
    final current = _selectedAudioStreamIndex;
    if (current == null || current >= audioStreams.length) {
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _selectedAudioStreamIndex = fallback;
          });
        }
      });
      return fallback;
    }
    return current;
  }

  int _ensureSubtitleSelection(List<Map<String, dynamic>> subtitleStreams) {
    if (subtitleStreams.isEmpty) return -1;
    final defaultIndex = subtitleStreams.indexWhere(
        (stream) => (stream['IsDefault'] as bool?) == true);
    final fallback = defaultIndex != -1 ? defaultIndex : 0;
    final current = _selectedSubtitleStreamIndex;
    if (current == null || current >= subtitleStreams.length) {
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _selectedSubtitleStreamIndex = fallback;
          });
        }
      });
      return fallback;
    }
    return current;
  }

  String? _formatResolutionInfo(Map<String, dynamic>? media) {
    if (media == null) return null;
    final width = (media['Width'] as num?)?.toInt();
    final height = (media['Height'] as num?)?.toInt();
    final videoStream = _getVideoStream(media);

    String? resolutionLabel;
    final sourceWidth = width ?? (videoStream?['Width'] as num?)?.toInt();
    final sourceHeight = height ?? (videoStream?['Height'] as num?)?.toInt();
    if (sourceWidth != null) {
      if (sourceWidth >= 3840) {
        resolutionLabel = '4K';
      } else if (sourceWidth >= 2560) {
        resolutionLabel = '2K';
      } else if (sourceWidth >= 1920) {
        resolutionLabel = '1080p';
      } else if (sourceWidth >= 1280) {
        resolutionLabel = '720p';
      } else if (sourceWidth >= 960) {
        resolutionLabel = '960p';
      } else if (sourceWidth >= 854) {
        resolutionLabel = '480p';
      }
    } else if (sourceHeight != null) {
      if (sourceHeight >= 2160) {
        resolutionLabel = '4K';
      } else if (sourceHeight >= 1440) {
        resolutionLabel = '2K';
      } else if (sourceHeight >= 1080) {
        resolutionLabel = '1080p';
      } else if (sourceHeight >= 720) {
        resolutionLabel = '720p';
      } else if (sourceHeight >= 540) {
        resolutionLabel = '540p';
      } else if (sourceHeight >= 480) {
        resolutionLabel = '480p';
      }
    }

    final codec = (videoStream?['Codec'] ?? media['VideoCodec'])
        ?.toString()
        .toUpperCase();
    final components = <String>[];
    if (resolutionLabel != null) components.add(resolutionLabel);
    if (codec != null && codec.isNotEmpty) components.add(codec);

    if (components.isEmpty && sourceWidth != null && sourceHeight != null) {
      components.add('${sourceWidth}x$sourceHeight');
    }

    return components.isEmpty ? null : components.join(' ');
  }

  String _formatAudioStream(Map<String, dynamic> stream) {
    final codec = stream['Codec']?.toString().toUpperCase();
    final channels = (stream['Channels'] as num?)?.toInt();
    final language = stream['Language']?.toString();

    final displayTitle = stream['DisplayTitle']?.toString();
    if (displayTitle != null && displayTitle.isNotEmpty) {
      return displayTitle;
    }

    final parts = <String>[];
    if (language != null && language.isNotEmpty) {
      parts.add(language);
    }
    if (codec != null && codec.isNotEmpty) parts.add(codec);
    if (channels != null) {
      final channelLabel = channels == 2
          ? '2.0'
          : channels == 6
              ? '5.1'
              : channels.toString();
      parts.add(channelLabel);
    }

    return parts.isEmpty ? '未知' : parts.join(' ');
  }

  String _formatSubtitleStream(Map<String, dynamic> stream) {
    final displayTitle = stream['DisplayTitle']?.toString();
    if (displayTitle != null && displayTitle.isNotEmpty) {
      return displayTitle;
    }

    final language = stream['Language']?.toString();
    final codec = stream['Codec']?.toString().toUpperCase();
    final isForced = stream['IsForced'] == true;

    final parts = <String>[];
    if (language != null && language.isNotEmpty) {
      parts.add(language);
    }
    if (codec != null && codec.isNotEmpty) {
      parts.add(codec);
    }
    if (isForced) {
      parts.add('强制');
    }

    return parts.isEmpty ? '未知字幕' : parts.join(' ');
  }

  Future<void> _showResumeMenu(BuildContext context, ItemInfo item) async {
     final overlay =
         Overlay.of(context).context.findRenderObject() as RenderBox;
     final box = context.findRenderObject() as RenderBox;
     final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
 
     final result = await showMenu<String>(
       context: context,
       position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height,
        overlay.size.width - origin.dx - box.size.width,
        overlay.size.height - origin.dy - box.size.height,
       ),
       items: [
         PopupMenuItem<String>(
           value: 'restart',
           child: Row(
             children: const [
               Icon(CupertinoIcons.refresh, size: 18),
               SizedBox(width: 8),
               Expanded(child: Text('从头开始播放')),
             ],
           ),
         ),
       ],
     );
 
     if (result == 'restart' && item.id != null) {
       _handlePlay(context, item.id!, fromBeginning: true);
     }
   }

  Future<void> _showAudioSelectionMenu(
    BuildContext anchorContext,
    List<Map<String, dynamic>> audioStreams,
    int selected,
  ) async {
    final overlay = Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height,
      overlay.size.width - origin.dx,
      overlay.size.height - origin.dy - box.size.height,
    );

    final result = await showMenu<int>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.35,
      ),
      items: List.generate(audioStreams.length, (index) {
        final data = audioStreams[index];
        final label = _formatAudioStream(data);
        final isDefault = (data['IsDefault'] as bool?) == true;
        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Expanded(child: Text(isDefault ? '$label (默认)' : label)),
              if (index == selected)
                const Icon(Icons.check, size: 18, color: Colors.blue),
            ],
          ),
        );
      }),
    );

    if (result != null && result >= 0 && result < audioStreams.length) {
      setState(() {
        _selectedAudioStreamIndex = result;
      });
    }
  }

  Future<void> _showSubtitleSelectionMenu(
    BuildContext anchorContext,
    List<Map<String, dynamic>> subtitleStreams,
    int selected,
  ) async {
    final overlay = Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height,
      overlay.size.width - origin.dx,
      overlay.size.height - origin.dy - box.size.height,
    );

    final result = await showMenu<int>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.35,
      ),
      items: List.generate(subtitleStreams.length, (index) {
        final label = _formatSubtitleStream(subtitleStreams[index]);
        final isDefault = (subtitleStreams[index]['IsDefault'] as bool?) == true;
        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Expanded(child: Text(isDefault ? '$label (默认)' : label)),
              if (index == selected)
                const Icon(Icons.check, size: 18, color: Colors.blue),
            ],
          ),
        );
      }),
    );

    if (result != null && result >= 0 && result < subtitleStreams.length) {
      setState(() {
        _selectedSubtitleStreamIndex = result;
      });
    }
  }

  void _handlePlay(BuildContext context, String itemId,
      {required bool fromBeginning}) {
    final route = fromBeginning
        ? Uri(
            path: '/player/$itemId',
            queryParameters: const {'fromStart': 'true'},
          ).toString()
        : '/player/$itemId';
    context.push(route);
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return minutes > 0 ? '${hours}时${minutes}分' : '${hours}小时';
    }
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return seconds > 0 ? '${minutes}分${seconds}秒' : '${minutes}分钟';
    }
    return '${duration.inSeconds}秒';
  }

  void _showOverviewDialog(ItemInfo item) {
    final overview = item.overview ?? '';
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 120,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: FutureBuilder<EmbyApi>(
                            future: EmbyApi.create(),
                            builder: (ctx2, snapshot) {
                              if (!snapshot.hasData || item.id == null) {
                                return Container(
                                    color: CupertinoColors.systemGrey5);
                              }
                              final posterUrl = snapshot.data!
                                  .buildImageUrl(
                                      itemId: item.id!, type: 'Primary', maxWidth: 400);
                              if (posterUrl.isEmpty) {
                                return Container(
                                    color: CupertinoColors.systemGrey5);
                              }
                              return EmbyFadeInImage(
                                imageUrl: posterUrl,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          if (item.productionYear != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                '${item.productionYear}',
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
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

  Map<String, dynamic>? _getVideoStream(Map<String, dynamic>? media) {
    if (media == null) return null;
    final streams = media['MediaStreams'];
    if (streams is List) {
      for (final stream in streams) {
        if (stream is Map &&
            (stream['Type'] as String?)?.toLowerCase() == 'video') {
          return stream.map((key, value) => MapEntry(key.toString(), value));
        }
      }
    }
    return null;
  }

  Widget _buildExternalLinks(List<ExternalUrlInfo> links, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = textColor.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '数据库链接',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            itemCount: links.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final link = links[index];
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  minSize: 0,
                  onPressed: () => _openExternalLink(link.url),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.link,
                        size: 14,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        link.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openExternalLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('[ExternalLink] Invalid URL: $url');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      debugPrint('[ExternalLink] Failed to launch $url');
    }
  }

  List<ExternalUrlInfo> _composeExternalLinks(ItemInfo item) {
    final List<ExternalUrlInfo> results = [];
    final seen = <String>{};

    void append(String name, String url) {
      if (name.isEmpty || url.isEmpty) return;
      final key = name.toLowerCase();
      if (seen.add(key)) {
        results.add(ExternalUrlInfo(name: name, url: url));
      }
    }

    for (final link in item.externalUrls ?? const <ExternalUrlInfo>[]) {
      if (link.isValid) {
        append(link.name, link.url);
      }
    }

    final providers = item.providerIds ?? const <String, dynamic>{};
    String? providerId(String key) {
      for (final entry in providers.entries) {
        if (entry.key.toString().toLowerCase() == key) {
          final value = entry.value?.toString() ?? '';
          if (value.isNotEmpty) return value;
        }
      }
      return null;
    }

    final type = item.type.toLowerCase();

    final imdbId = providerId('imdb');
    if (imdbId != null) {
      append('IMDb', 'https://www.imdb.com/title/$imdbId');
    }

    final tmdbId = providerId('tmdb');
    if (tmdbId != null) {
      final path = type == 'movie'
          ? 'movie'
          : (type == 'series' || type == 'season' || type == 'episode')
              ? 'tv'
              : 'movie';
      append('TMDb', 'https://www.themoviedb.org/$path/$tmdbId');
    }

    final traktId = providerId('trakt');
    if (traktId != null) {
      final path = type == 'movie'
          ? 'movies'
          : (type == 'series' || type == 'season' || type == 'episode')
              ? 'shows'
              : 'movies';
      append('Trakt', 'https://trakt.tv/$path/$traktId');
    }

    final tvdbId = providerId('tvdb');
    if (tvdbId != null) {
      append('TheTVDB', 'https://thetvdb.com/series/$tvdbId');
    }

    final doubanId = providerId('douban');
    if (doubanId != null) {
      append('豆瓣', 'https://movie.douban.com/subject/$doubanId/');
    }

    final anidbId = providerId('anidb');
    if (anidbId != null) {
      append('AniDB', 'https://anidb.net/anime/$anidbId');
    }

    return results;
  }

  Widget _buildDetailedMediaModules(ItemInfo item, bool isDark) {
    final media = _getPrimaryMediaSource(item);
    if (media == null) {
      return const SizedBox.shrink();
    }

    final streams = (media['MediaStreams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];

    final resourcePath = media['Path']?.toString() ?? '';
    final resourceFormat = media['Container']?.toString() ?? '';
    final resourceSize = _formatBytes(media['Size']);
    final resourceDate =
        _formatDateTime(media['DateCreated'] ?? item.dateCreated);
    final resourceMeta =
        _mergeFormatSizeDate(resourceFormat, resourceSize, resourceDate);

    final modules = <_MediaDetailModule>[];

    final videoStreams = streams
        .where((stream) => stream['Type']?.toString().toLowerCase() == 'video')
        .toList();
    for (var i = 0; i < videoStreams.length; i++) {
      modules.add(_MediaDetailModule(
        title: '视频',
        fields: _buildVideoFields(videoStreams[i], i),
      ));
    }

    final audioStreams = streams
        .where((stream) => stream['Type']?.toString().toLowerCase() == 'audio')
        .toList();
    for (var i = 0; i < audioStreams.length; i++) {
      modules.add(_MediaDetailModule(
        title: '音频',
        fields: _buildAudioFields(audioStreams[i], i),
      ));
    }

    final subtitleStreams = streams
        .where((stream) => stream['Type']?.toString().toLowerCase() == 'subtitle')
        .toList();
    for (var i = 0; i < subtitleStreams.length; i++) {
      modules.add(_MediaDetailModule(
        title: '字幕',
        fields: _buildSubtitleFields(subtitleStreams[i], i),
      ));
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = textColor.withValues(alpha: 0.08);

    final hasStreamModules =
        modules.any((module) => module.visibleFields.isNotEmpty);

    if (resourcePath.isEmpty && resourceMeta.isEmpty && !hasStreamModules) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '媒体信息',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        if (resourcePath.isNotEmpty)
          SelectableText(
            resourcePath,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (resourceMeta.isNotEmpty) ...[
          if (resourcePath.isNotEmpty) const SizedBox(height: 6),
          Text(
            resourceMeta,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if ((resourcePath.isNotEmpty || resourceMeta.isNotEmpty) &&
            hasStreamModules)
          const SizedBox(height: 16),
        if (hasStreamModules)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < modules.length; i++)
                if (modules[i].visibleFields.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      left: _isFirstVisible(modules, i) ? 0 : 12,
                      right: _nextVisibleIndex(modules, i) == null ? 0 : 12,
                    ),
                    child: _MediaModuleCard(
                      module: modules[i],
                      bgColor: bgColor,
                      borderColor: borderColor,
                      textColor: textColor,
                      isDark: isDark,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  int? _nextVisibleIndex(List<_MediaDetailModule> modules, int current) {
    for (var i = current + 1; i < modules.length; i++) {
      if (modules[i].visibleFields.isNotEmpty) {
        return i;
      }
    }
    return null;
  }

  bool _isFirstVisible(List<_MediaDetailModule> modules, int current) {
    for (var i = 0; i < current; i++) {
      if (modules[i].visibleFields.isNotEmpty) {
        return false;
      }
    }
    return modules[current].visibleFields.isNotEmpty;
  }
}

class _PerformerCard extends StatelessWidget {
  const _PerformerCard({required this.performer, required this.isDark});

  final PerformerInfo performer;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final theme = Theme.of(context);
    const double cardWidth = 90;
    const double cardHeight = 140;

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: cardHeight,
              width: cardWidth,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: _buildPerformerImage(context),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _extractChineseName(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _extractEnglishName(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformerImage(BuildContext context) {
    if (performer.id.isEmpty || performer.primaryImageTag == null) {
      return Container(
        color: Colors.grey.withOpacity(0.2),
        child: const Icon(CupertinoIcons.person, size: 36, color: Colors.grey),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(color: Colors.grey.withOpacity(0.2));
        }
        final url = snapshot.data!.buildImageUrl(
          itemId: performer.id,
          type: 'Primary',
          maxWidth: 300,
          tag: performer.primaryImageTag,
        );
        return EmbyFadeInImage(
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
    );
  }

  String _extractChineseName() {
    final name = performer.name.trim();
    final role = (performer.role ?? '').trim();

    final candidateFromDelimiters = _extractBeforeDelimiter(name);
    if (_containsChinese(candidateFromDelimiters)) {
      return candidateFromDelimiters;
    }

    final regex = RegExp(r'[\u4e00-\u9fa5]+');
    final fromName = regex.allMatches(name).map((m) => m.group(0)).join();
    if (fromName.isNotEmpty) {
      return fromName;
    }
    final fromRole = regex.allMatches(role).map((m) => m.group(0)).join();
    if (fromRole.isNotEmpty) {
      return fromRole;
    }
    return name.isNotEmpty ? name : role;
  }
 
  String _extractEnglishName() {
    final name = performer.name.trim();
    final role = (performer.role ?? '').trim();

    final fromParentheses = _extractInsideParentheses(name);
    if (_containsLatin(fromParentheses)) {
      return fromParentheses;
    }

    final fromDelimiter = _extractAfterDelimiter(name);
    if (_containsLatin(fromDelimiter)) {
      return fromDelimiter;
    }

    final englishFromName = _extractEnglishFrom(name);
    if (englishFromName.isNotEmpty) {
      return englishFromName;
    }
    final englishFromRole = _extractEnglishFrom(role);
    if (englishFromRole.isNotEmpty) {
      return englishFromRole;
    }
    if (!_containsChinese(name) && name.isNotEmpty) {
      return name;
    }
    return role.isNotEmpty ? role : '';
  }
 
   String _extractEnglishFrom(String source) {
     if (source.isEmpty) return '';
     final regex = RegExp(r'[A-Za-z][A-Za-z .]*');
     return regex
         .allMatches(source)
         .map((m) => (m.group(0) ?? '').trim())
         .where((segment) => segment.isNotEmpty)
         .join(' ')
         .trim();
   }
 
   bool _containsChinese(String source) {
     return RegExp(r'[\u4e00-\u9fa5]').hasMatch(source);
   }

  bool _containsLatin(String source) {
    return RegExp(r'[A-Za-z]').hasMatch(source);
  }

  String _extractInsideParentheses(String source) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(source);
    if (match != null) {
      return match.group(1)?.trim() ?? '';
    }
    return '';
  }

  String _extractBeforeDelimiter(String source) {
    for (final delimiter in const ['/', '|', '｜']) {
      final index = source.indexOf(delimiter);
      if (index > 0) {
        return source.substring(0, index).trim();
      }
    }
    return source;
  }

  String _extractAfterDelimiter(String source) {
    for (final delimiter in const ['/', '|', '｜']) {
      final index = source.indexOf(delimiter);
      if (index >= 0 && index + 1 < source.length) {
        return source.substring(index + 1).trim();
      }
    }
    return '';
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.item, required this.isDark});

  final ItemInfo item;
  final bool isDark;

  static const double _cardWidth = 90;
  static const double _cardHeight = 140;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return SizedBox(
      width: _cardWidth,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: item.id != null && item.id!.isNotEmpty
            ? () => _handleTap(context)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: _cardHeight,
                width: _cardWidth,
                child: _buildPoster(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _buildSubtitle(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoster() {
    if (item.id == null || item.id!.isEmpty) {
      return Container(
        color: Colors.grey.withOpacity(0.2),
        child: const Icon(CupertinoIcons.film, size: 32, color: Colors.grey),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: Colors.grey.withOpacity(0.1),
            child: const Center(child: CupertinoActivityIndicator()),
          );
        }
        final url = snapshot.data!.buildImageUrl(
          itemId: item.id!,
          type: 'Primary',
          maxWidth: 320,
        );
        return EmbyFadeInImage(
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
    );
  }

  String _buildSubtitle() {
    final year = item.productionYear?.toString();
    if (year != null && year.isNotEmpty) {
      return year;
    }
    return item.type.isNotEmpty ? item.type : '推荐';
  }

  void _handleTap(BuildContext context) {
    final id = item.id;
    if (id == null || id.isEmpty) return;

    if (item.type == 'Series') {
      context.push('/series/$id?name=${Uri.encodeComponent(item.name)}');
    } else if (item.type == 'Movie') {
      context.push('/item/$id');
    } else {
      context.push('/player/$id');
    }
  }
}

class _MediaFieldRow extends StatelessWidget {
   const _MediaFieldRow({
     required this.label,
     required this.value,
     required this.isDark,
   });
 
   final String label;
   final String value;
   final bool isDark;
 
   @override
   Widget build(BuildContext context) {
     final labelStyle = TextStyle(
       fontSize: 11,
       color: isDark
           ? Colors.white.withValues(alpha: 0.7)
           : Colors.black.withValues(alpha: 0.55),
       fontWeight: FontWeight.w500,
     );
     final valueStyle = TextStyle(
       fontSize: 11.5,
       color: isDark ? Colors.white : Colors.black87,
       fontWeight: FontWeight.w500,
       height: 1.3,
     );
 
     return Text.rich(
       TextSpan(
         children: [
           TextSpan(text: '$label: ', style: labelStyle),
           TextSpan(text: value, style: valueStyle),
         ],
       ),
       maxLines: 3,
       overflow: TextOverflow.ellipsis,
     );
   }
 }
 
 class _MediaDetailModule {
   _MediaDetailModule({
     required this.title,
     required this.fields,
   });
 
   final String title;
   final List<_MediaDetailField> fields;
 
   List<_MediaDetailField> get visibleFields =>
       fields.where((field) => field.value.isNotEmpty).toList();
 }
 
 class _MediaDetailField {
   _MediaDetailField(this.label, this.value);
 
   final String label;
   final String value;
 }
 
 class _MediaModuleCard extends StatelessWidget {
   const _MediaModuleCard({
     required this.module,
     required this.bgColor,
     required this.borderColor,
     required this.textColor,
     required this.isDark,
   });
 
   final _MediaDetailModule module;
   final Color bgColor;
   final Color borderColor;
   final Color textColor;
   final bool isDark;
 
   @override
   Widget build(BuildContext context) {
     return Container(
       constraints: const BoxConstraints(minWidth: 200),
       padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
       decoration: BoxDecoration(
         color: bgColor,
         borderRadius: BorderRadius.circular(18),
         border: Border.all(color: borderColor),
       ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         mainAxisSize: MainAxisSize.min,
         children: [
           Text(
             module.title,
             style: TextStyle(
               fontSize: 14.5,
               fontWeight: FontWeight.w600,
               color: textColor,
             ),
           ),
           const SizedBox(height: 8),
           for (var i = 0; i < module.visibleFields.length; i++) ...[
             if (i != 0) const SizedBox(height: 6),
             _MediaFieldRow(
               label: module.visibleFields[i].label,
               value: module.visibleFields[i].value,
               isDark: isDark,
             ),
           ],
         ],
       ),
     );
   }
 }
 
 List<_MediaDetailField> _buildVideoFields(
     Map<String, dynamic> stream, int index) {
   final fields = <_MediaDetailField>[];
 
   void add(String label, String? value) {
     if (value == null || value.isEmpty) return;
     fields.add(_MediaDetailField(label, value));
   }
 
   add('编号', '#${index + 1}');
   add('标题', stream['DisplayTitle']?.toString() ?? stream['Title']?.toString());
   add('语言', _formatLanguage(stream['Language']));
   add('编解码器', stream['Codec']?.toString().toUpperCase());
   add('配置', stream['Profile']?.toString());
   add('等级', stream['Level']?.toString());
   add('分辨率', _formatResolution(stream));
   add('宽高比', _formatAspectRatio(stream));
   add('隔行', _formatBoolFlag(stream['IsInterlaced']));
   add('帧率', _formatFrameRate(stream['RealFrameRate'] ?? stream['AverageFrameRate']));
   add('比特率', _formatBitrate(stream['BitRate']));
   add('基色', stream['ColorPrimaries']?.toString() ?? stream['ColorSpace']?.toString());
   add('深位度', _formatBitDepth(stream['BitDepth']));
   add('像素格式', stream['PixelFormat']?.toString());
   add('参考帧', stream['RefFrames']?.toString());
   add('基色范围', stream['VideoRange']?.toString());
   add('基色类型', stream['VideoRangeType']?.toString());
 
   return fields;
 }
 
 List<_MediaDetailField> _buildAudioFields(
     Map<String, dynamic> stream, int index) {
   final fields = <_MediaDetailField>[];
 
   void add(String label, String? value) {
     if (value == null || value.isEmpty) return;
     fields.add(_MediaDetailField(label, value));
   }
 
   add('编号', '#${index + 1}');
   add('标题', stream['DisplayTitle']?.toString() ?? stream['Title']?.toString());
   add('语言', _formatLanguage(stream['Language']));
   add('布局', stream['ChannelLayout']?.toString());
   add('频道', _formatChannels(stream['Channels']));
   add('采样率', _formatSampleRate(stream['SampleRate']));
   add('默认', _formatBoolFlag(stream['IsDefault']));
   add('编解码器', stream['Codec']?.toString().toUpperCase());
   add('配置', stream['Profile']?.toString());
   add('比特率', _formatBitrate(stream['BitRate']));
   add('位深', _formatBitDepth(stream['BitDepth']));
   add('等级', stream['Level']?.toString());
 
   return fields;
 }
 
 List<_MediaDetailField> _buildSubtitleFields(
     Map<String, dynamic> stream, int index) {
   final fields = <_MediaDetailField>[];
 
   void add(String label, String? value) {
     if (value == null || value.isEmpty) return;
     fields.add(_MediaDetailField(label, value));
   }
 
   add('编号', '#${index + 1}');
   add('标题', stream['DisplayTitle']?.toString() ?? stream['Title']?.toString());
   add('语言', _formatLanguage(stream['Language']));
   add('默认', _formatBoolFlag(stream['IsDefault']));
   add('强制', _formatBoolFlag(stream['IsForced']));
   add('听力障碍', _formatBoolFlag(stream['IsHearingImpaired']));
   add('外部', _formatBoolFlag(stream['IsExternal']));
   add('编解码器', stream['Codec']?.toString().toUpperCase());
   add('配置', stream['Profile']?.toString());
   add('比特率', _formatBitrate(stream['BitRate']));
 
   return fields;
 }
 
 String _formatResolution(Map<String, dynamic> stream) {
   final width = stream['Width'];
   final height = stream['Height'];
   if (width == null || height == null) return '';
   return '${width}x$height';
 }
 
 String _formatAspectRatio(Map<String, dynamic> stream) {
   final aspect = stream['AspectRatio']?.toString();
   if (aspect != null && aspect.isNotEmpty) return aspect;
   final width = (stream['Width'] as num?);
   final height = (stream['Height'] as num?);
   if (width != null && height != null && height != 0) {
     final ratio = width / height;
     return ratio.toStringAsFixed(2);
   }
   return '';
 }
 
 String _formatFrameRate(dynamic value) {
   if (value == null) return '';
   final rate = double.tryParse(value.toString());
   if (rate == null || rate <= 0) return '';
   return '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)} fps';
 }
 
 String _formatBitrate(dynamic value) {
   if (value == null) return '';
   final bitrate = int.tryParse(value.toString());
   if (bitrate == null || bitrate <= 0) return '';
   if (bitrate >= 1000000) {
     return '${(bitrate / 1000000).toStringAsFixed(2)} Mbps';
   }
   if (bitrate >= 1000) {
     return '${(bitrate / 1000).toStringAsFixed(1)} Kbps';
   }
   return '$bitrate bps';
 }
 
 String _formatBoolFlag(dynamic value) {
   if (value == null) return '';
   return (value == true || value == 'true') ? '是' : '否';
 }
 
 String _formatSampleRate(dynamic value) {
   if (value == null) return '';
   final rate = int.tryParse(value.toString());
   if (rate == null || rate <= 0) return '';
   if (rate >= 1000) {
     return '${(rate / 1000).toStringAsFixed(1)} kHz';
   }
   return '$rate Hz';
 }
 
 String _formatChannels(dynamic value) {
   if (value == null) return '';
   final channels = int.tryParse(value.toString());
   if (channels == null || channels <= 0) return '';
   return channels.toString();
 }
 
 String _formatBitDepth(dynamic value) {
   if (value == null) return '';
   final depth = int.tryParse(value.toString());
   if (depth == null || depth <= 0) return '';
   return '$depth-bit';
 }
 
 String _formatLanguage(dynamic value) {
   if (value == null) return '';
   final text = value.toString();
   if (text.isEmpty) return '';
   return text;
 }
 
 String _formatBytes(dynamic value) {
   if (value == null) return '';
   final size = int.tryParse(value.toString());
   if (size == null || size <= 0) return '';
   const units = ['B', 'KB', 'MB', 'GB', 'TB'];
   var currentSize = size.toDouble();
   var unitIndex = 0;
   while (currentSize >= 1024 && unitIndex < units.length - 1) {
     currentSize /= 1024;
     unitIndex++;
   }
   return '${currentSize.toStringAsFixed(currentSize >= 10 ? 1 : 2)} ${units[unitIndex]}';
 }
 
 String _formatDateTime(dynamic value) {
   if (value == null) return '';
   DateTime? dateTime;
   if (value is DateTime) {
     dateTime = value;
   } else {
     dateTime = DateTime.tryParse(value.toString());
   }
   if (dateTime == null) return '';
   return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
 }

String _mergeFormatSizeDate(String format, String size, String date) {
  final pieces = <String>[];
  if (format.isNotEmpty) pieces.add(format);
  if (size.isNotEmpty) pieces.add(size);
  if (date.isNotEmpty) pieces.add(date);
  return pieces.join(' · ');
}
