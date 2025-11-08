import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
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
  final GlobalKey _detailsSectionKey = GlobalKey();
  double _detailsSectionHeight = 160;
  static const double _detailsOverlayTopOffset = 90;
  static const double _detailsContentGap = 24;
  final GlobalKey _resumeMenuAnchorKey = GlobalKey();
  bool _hasLoggedPerformers = false;

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
            if (kDebugMode && performers.isNotEmpty && !_hasLoggedPerformers) {
              _hasLoggedPerformers = true;
            }
            _scheduleDetailsHeightMeasurement();

            return Stack(
              children: [
                // 背景和可滚动内容
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // 顶部背景图片区域（从状态栏开始）
                    SliverToBoxAdapter(
                      child: _buildBackdropHeader(context, data, isPlayed),
                    ),
                    // 占位空间（预留给悬浮的内容卡片）
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: math.max(
                          0,
                          _detailsSectionHeight + _detailsContentGap - _detailsOverlayTopOffset,
                        ),
                      ),
                    ),
                    // 后续内容（剧情简介等）
                    SliverToBoxAdapter(
                      child: Container(
                        color: CupertinoColors.systemBackground.resolveFrom(context),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            // 剧情简介
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
                              Text(
                                '演员',
                              style: const TextStyle(
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // 悬浮的内容（无背景，左对齐）
                Positioned(
                  top: 350 - 90,
                  left: 20,
                  right: 20,
                  child: Column(
                    key: _detailsSectionKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        data.name,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 评分、年份、时长等信息
                      _buildMetaInfo(data, isDark),
                      const SizedBox(height: 8),
                      _buildMediaInfo(data, isDark),
                const SizedBox(height: 16),
                      // 播放按钮
                      _buildPlaySection(context, data, isDark),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
      ),
    );
  }

  Widget _buildBackdropHeader(
      BuildContext context, ItemInfo item, bool isPlayed) {
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
          // 顶部浮动栏（返回按钮 + 右上角图标）
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 返回按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.pop(),
                    child: const Icon(
                      CupertinoIcons.back,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  // 右上角图标组
                  Row(
                    children: [
                      // 投屏图标（预留）
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: null,
                        child: Icon(
                          CupertinoIcons.tv,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
                        ),
                      ),
                      // 已观看标记
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
                      // 收藏图标（预留）
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: null,
                        child: Icon(
                          CupertinoIcons.heart,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
                        ),
                      ),
                      // 更多选项图标（预留）
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: null,
                        child: Icon(
                          CupertinoIcons.ellipsis,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

      final valueText = isDefault ? '$value (默认)' : value;
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
        canResume ? const Color(0xFF3F8CFF) : const Color(0xFF4A90E2);
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
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor:
                        (isDarkBackground ? Colors.white : Colors.black)
                            .withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(buttonColor),
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

  @override
  void didUpdateWidget(covariant ItemDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleDetailsHeightMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleDetailsHeightMeasurement();
  }

  void _scheduleDetailsHeightMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _detailsSectionKey.currentContext;
      if (context == null) return;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox) {
        final height = renderObject.size.height;
        if ((height - _detailsSectionHeight).abs() > 1.0) {
          setState(() {
            _detailsSectionHeight = height;
          });
        }
      }
    });
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
