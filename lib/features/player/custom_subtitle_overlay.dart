import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;

/// ✅ 自定义字幕覆盖层 - 优化版
/// 
/// 主要优化：
/// 1. 使用二分查找算法，提高字幕查找效率（O(log n) vs O(n)）
/// 2. 添加50ms提前量，补偿渲染延迟，确保字幕与画面同步
/// 3. 智能缓存机制，优先检查附近索引，适应顺序播放和跳跃场景
/// 4. 自动检测seek操作，重置缓存确保准确性
/// 5. HLS时间偏移自动检测和修正，解决HLS流时间戳不一致问题
/// 6. 减少不必要的日志输出，避免影响性能

/// ✅ 字幕条目，支持文本和图片字幕
class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;
  final Uint8List? imageData; // ✅ 支持图片字幕

  SubtitleEntry({
    required this.start,
    required this.end,
    required this.text,
    this.imageData,
  });

  /// ✅ 检查字幕是否在指定位置应该显示
  bool isActive(Duration position) {
    return position >= start && position < end;
  }
}

class CustomSubtitleOverlay extends StatefulWidget {
  const CustomSubtitleOverlay({
    required this.position,
    required this.subtitleUrl,
    this.isVisible = true,
    this.showControls = false,
    this.isLocked = false,
    super.key,
  });

  final Duration position;
  final String? subtitleUrl;
  final bool isVisible;
  final bool showControls; // ✅ 控制栏显示状态
  final bool isLocked; // ✅ 锁定状态

  @override
  State<CustomSubtitleOverlay> createState() => _CustomSubtitleOverlayState();
}

class _CustomSubtitleOverlayState extends State<CustomSubtitleOverlay> {
  List<SubtitleEntry> _subtitles = [];
  bool _isLoading = false;
  String? _error;
  int _lastFoundIndex = 0;
  bool _isImageSubtitle = false; // ✅ 标记是否为图片字幕
  Duration _lastPosition = Duration.zero; // ✅ 记录上次位置，用于检测大跳跃

  // ✅ 字幕同步容差：字幕提前50ms显示，补偿渲染延迟
  static const Duration _subtitleAdvance = Duration(milliseconds: 50);

  // ✅ HLS时间偏移：用于修正HLS流的时间戳差异
  Duration _timeOffset = Duration.zero;
  bool _timeOffsetCalculated = false;

  @override
  void initState() {
    super.initState();
    _loadSubtitles();
  }

  @override
  void didUpdateWidget(CustomSubtitleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitleUrl != widget.subtitleUrl) {
      _loadSubtitles();
      _timeOffsetCalculated = false; // ✅ 重置时间偏移计算
      _timeOffset = Duration.zero;
    }
    
    // ✅ 检测大幅度位置跳跃（seek），重置缓存和时间偏移
    final positionDiff = (widget.position - _lastPosition).abs();
    if (positionDiff > const Duration(seconds: 2)) {
      _lastFoundIndex = 0; // 重置缓存，强制重新查找
      _timeOffsetCalculated = false; // ✅ Seek后重新计算时间偏移
    }
    _lastPosition = widget.position;
  }

  Future<void> _loadSubtitles() async {
    if (widget.subtitleUrl == null || widget.subtitleUrl!.isEmpty) {
      setState(() {
        _subtitles = [];
        _isLoading = false;
        _error = null;
        _isImageSubtitle = false;
        _lastFoundIndex = 0;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final urls = widget.subtitleUrl!.split('|||');
    String? lastError;

    for (var i = 0; i < urls.length; i++) {
      final url = urls[i].trim();
      if (url.isEmpty) continue;

      try {
        final response = await http.get(Uri.parse(url));
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';

        if (response.statusCode == 200) {
          // ✅ 检测图片字幕 (PNG/JPEG)
          if (contentType.contains('image/png') ||
              contentType.contains('image/jpeg') ||
              contentType.contains('image/')) {
            // ✅ 图片字幕：创建一个占位条目，包含图片数据
            setState(() {
              _subtitles = [
                SubtitleEntry(
                  start: Duration.zero,
                  end: const Duration(hours: 99),
                  text: '',
                  imageData: response.bodyBytes,
                )
              ];
              _isLoading = false;
              _error = null;
              _lastFoundIndex = 0;
              _isImageSubtitle = true;
            });
            debugPrint(
                '✅ [Subtitle] Loaded image subtitle (${response.bodyBytes.length} bytes)');
            return;
          }

          // ✅ 文本字幕
          if (contentType.contains('text') ||
              contentType.contains('json') ||
              contentType.isEmpty) {
            final content = utf8.decode(response.bodyBytes);
            final subtitles = _parseVTT(content);

            setState(() {
              _subtitles = subtitles;
              _isLoading = false;
              _error = null;
              _lastFoundIndex = 0;
              _isImageSubtitle = false;
            });
            debugPrint('✅ [Subtitle] Loaded ${subtitles.length} text entries');
            return;
          }

          lastError = 'Unsupported content-type: $contentType';
        } else {
          lastError = 'HTTP ${response.statusCode}';
        }
      } catch (e) {
        lastError = '$e';
      }
    }

    setState(() {
      _isLoading = false;
      _error = '加载字幕失败: $lastError';
    });
    debugPrint('❌ [Subtitle] Failed to load subtitles: $lastError');
  }

  /// ✅ 支持多种 VTT 时间格式：HH:MM:SS.mmm 或 MM:SS.mmm
  List<SubtitleEntry> _parseVTT(String content) {
    final entries = <SubtitleEntry>[];
    final lines = content.split('\n');

    String? currentText;
    Duration? startTime;
    Duration? endTime;

    // ✅ 时间戳可使用 "." 或 "," 作为毫秒分隔符（兼容 WebVTT、SRT）
    final timePatternWithHours = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[.,](\d{3})(?:\s+.*)?',
    );
    final timePatternNoHours = RegExp(
      r'(\d{1,2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{1,2}):(\d{2})[.,](\d{3})(?:\s+.*)?',
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.isEmpty ||
          line.startsWith('WEBVTT') ||
          line.startsWith('NOTE') ||
          line.startsWith('STYLE')) {
        continue;
      }

      var match = timePatternWithHours.firstMatch(line);
      if (match != null) {
        // 保存之前的条目
        if (startTime != null && endTime != null && currentText != null) {
          entries.add(SubtitleEntry(
            start: startTime,
            end: endTime,
            text: _normalizeSubtitleText(currentText),
          ));
        }

        // 含小时格式
        startTime = Duration(
          hours: int.parse(match.group(1)!),
          minutes: int.parse(match.group(2)!),
          seconds: int.parse(match.group(3)!),
          milliseconds: int.parse(match.group(4)!),
        );
        endTime = Duration(
          hours: int.parse(match.group(5)!),
          minutes: int.parse(match.group(6)!),
          seconds: int.parse(match.group(7)!),
          milliseconds: int.parse(match.group(8)!),
        );
        currentText = '';
        continue;
      }

      match = timePatternNoHours.firstMatch(line);
      if (match != null) {
        // 保存之前的条目
        if (startTime != null && endTime != null && currentText != null) {
          entries.add(SubtitleEntry(
            start: startTime,
            end: endTime,
            text: _normalizeSubtitleText(currentText),
          ));
        }

        // 不含小时格式
        startTime = Duration(
          minutes: int.parse(match.group(1)!),
          seconds: int.parse(match.group(2)!),
          milliseconds: int.parse(match.group(3)!),
        );
        endTime = Duration(
          minutes: int.parse(match.group(4)!),
          seconds: int.parse(match.group(5)!),
          milliseconds: int.parse(match.group(6)!),
        );
        currentText = '';
        continue;
      }

      // 文本行（支持多行）
      if (startTime != null && endTime != null) {
        if (currentText != null && currentText.isNotEmpty) {
          currentText += '\n$line';
        } else {
          currentText = line;
        }
      }
    }

    // 保存最后一个条目
    if (startTime != null &&
        endTime != null &&
        currentText != null &&
        currentText.isNotEmpty) {
      entries.add(SubtitleEntry(
        start: startTime,
        end: endTime,
        text: _normalizeSubtitleText(currentText),
      ));
    }

    return entries;
  }

  String _normalizeSubtitleText(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    text = text.replaceAll(RegExp(r'\r\n?'), '\n');
    text = text.replaceAll(RegExp(r'\{\\[^}]+\}'), '');
    final hasHtmlTags = RegExp(r'<[^>]+>').hasMatch(text);
    if (!hasHtmlTags) {
      text = text.replaceAll('\n', '<br/>');
    } else {
      text = text.replaceAllMapped(
        RegExp(r'<br\s*/?>', caseSensitive: false),
        (_) => '<br/>',
      );
    }

    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': '\'',
    };
    entities.forEach((entity, value) {
      text = text.replaceAll(entity, value);
    });

    return text;
  }

  /// ✅ 优化字幕查找算法：使用二分查找 + 容差补偿 + HLS时间偏移自动检测
  SubtitleEntry? _getCurrentSubtitle() {
    if (!widget.isVisible || _subtitles.isEmpty) {
      return null;
    }

    // ✅ 应用提前量，补偿渲染延迟
    var adjustedPos = widget.position + _subtitleAdvance;

    // ✅ HLS时间偏移自动检测和修正
    // 如果播放位置 > 10秒且还没有找到任何字幕，尝试自动检测时间偏移
    if (!_timeOffsetCalculated && 
        widget.position > const Duration(seconds: 10) && 
        _subtitles.isNotEmpty) {
      _calculateTimeOffset(adjustedPos);
    }

    // ✅ 应用时间偏移（如果有）
    adjustedPos = adjustedPos + _timeOffset;

    // ✅ 快速路径：检查上次找到的索引附近（±2范围）
    if (_lastFoundIndex < _subtitles.length) {
      // 检查当前索引
      if (_subtitles[_lastFoundIndex].isActive(adjustedPos)) {
        return _subtitles[_lastFoundIndex];
      }

      // 检查下一个（最常见：顺序播放）
      if (_lastFoundIndex + 1 < _subtitles.length &&
          _subtitles[_lastFoundIndex + 1].isActive(adjustedPos)) {
        _lastFoundIndex = _lastFoundIndex + 1;
        return _subtitles[_lastFoundIndex];
      }

      // 检查前一个
      if (_lastFoundIndex > 0 &&
          _subtitles[_lastFoundIndex - 1].isActive(adjustedPos)) {
        _lastFoundIndex = _lastFoundIndex - 1;
        return _subtitles[_lastFoundIndex];
      }

      // 检查下两个（快速跳跃场景）
      if (_lastFoundIndex + 2 < _subtitles.length &&
          _subtitles[_lastFoundIndex + 2].isActive(adjustedPos)) {
        _lastFoundIndex = _lastFoundIndex + 2;
        return _subtitles[_lastFoundIndex];
      }
    }

    // ✅ 二分查找：找到第一个 start <= adjustedPos 的字幕
    int left = 0;
    int right = _subtitles.length - 1;
    int result = -1;

    while (left <= right) {
      final mid = (left + right) ~/ 2;
      final entry = _subtitles[mid];

      if (entry.start <= adjustedPos) {
        result = mid;
        left = mid + 1; // 继续找更靠后的
      } else {
        right = mid - 1;
      }
    }

    // ✅ 从找到的位置向前检查（最多检查3个），找到活跃的字幕
    if (result >= 0) {
      for (int i = result; i >= 0 && i > result - 3; i--) {
        if (_subtitles[i].isActive(adjustedPos)) {
          _lastFoundIndex = i;
          return _subtitles[i];
        }
      }
    }

    return null;
  }

  /// ✅ 智能计算HLS时间偏移
  /// 
  /// HLS流常见的时间戳问题：
  /// 1. ExoPlayer的currentPosition从0开始，但字幕时间戳可能从视频的实际时间开始
  /// 2. 转码后的HLS流可能重置时间戳，导致字幕与视频不同步
  /// 3. 部分HLS流使用PTS（Presentation Time Stamp），可能有偏移
  /// 
  /// 检测策略：
  /// 1. 找到当前播放位置附近应该出现的字幕
  /// 2. 如果找不到，尝试在字幕列表中搜索最接近的条目
  /// 3. 计算时间差作为偏移量
  void _calculateTimeOffset(Duration currentPosition) {
    if (_subtitles.isEmpty) return;

    debugPrint(
        '🔍 [Subtitle] Calculating time offset... Video position: ${currentPosition.inSeconds}s');

    // ✅ 策略1：查找当前位置附近（±5秒）是否有字幕
    SubtitleEntry? nearbySubtitle;
    for (final subtitle in _subtitles) {
      final diff = (subtitle.start - currentPosition).abs();
      if (diff < const Duration(seconds: 5)) {
        nearbySubtitle = subtitle;
        break;
      }
    }

    if (nearbySubtitle != null) {
      // ✅ 找到了附近的字幕，时间轴基本一致
      _timeOffset = Duration.zero;
      debugPrint(
          '✅ [Subtitle] Time sync OK - Found subtitle near current position (${nearbySubtitle.start.inSeconds}s)');
      _timeOffsetCalculated = true;
      return;
    }

    // ✅ 策略2：没找到附近的字幕，检查是否需要偏移
    // 找到第一个字幕和最后一个字幕，判断当前位置在哪个范围
    final firstSubtitle = _subtitles.first;
    final lastSubtitle = _subtitles.last;

    debugPrint(
        '📊 [Subtitle] Subtitle range: ${firstSubtitle.start.inSeconds}s - ${lastSubtitle.end.inSeconds}s');

    // ✅ 情况1：当前位置在第一个字幕之前很久（>30秒）
    // 说明字幕时间轴比视频快，需要负偏移
    if (currentPosition < firstSubtitle.start - const Duration(seconds: 30)) {
      _timeOffset = firstSubtitle.start - currentPosition;
      debugPrint(
          '⚠️ [Subtitle] Detected POSITIVE offset: +${_timeOffset.inSeconds}s (subtitles start later)');
      _timeOffsetCalculated = true;
      return;
    }

    // ✅ 情况2：当前位置在最后一个字幕之后很久（>30秒）
    // 可能是视频已经播放很久了，字幕还没开始
    if (currentPosition > lastSubtitle.end + const Duration(seconds: 30)) {
      // ✅ 尝试找到最接近当前位置的字幕
      SubtitleEntry? closestSubtitle;
      Duration minDiff = const Duration(days: 1);
      
      for (final subtitle in _subtitles) {
        final diff = (subtitle.start - currentPosition).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestSubtitle = subtitle;
        }
      }

      if (closestSubtitle != null && minDiff < const Duration(minutes: 5)) {
        _timeOffset = closestSubtitle.start - currentPosition;
        debugPrint(
            '⚠️ [Subtitle] Detected offset from closest subtitle: ${_timeOffset.inSeconds}s (diff: ${minDiff.inSeconds}s)');
        _timeOffsetCalculated = true;
        return;
      }
    }

    // ✅ 情况3：当前位置在字幕范围内，但找不到匹配的字幕
    // 可能是字幕时间轴整体偏移了
    if (currentPosition >= firstSubtitle.start &&
        currentPosition <= lastSubtitle.end) {
      // ✅ 使用二分查找找到最接近的字幕
      int left = 0;
      int right = _subtitles.length - 1;
      SubtitleEntry? closestBefore;
      SubtitleEntry? closestAfter;

      while (left <= right) {
        final mid = (left + right) ~/ 2;
        final entry = _subtitles[mid];

        if (entry.start <= currentPosition) {
          closestBefore = entry;
          left = mid + 1;
        } else {
          closestAfter = entry;
          right = mid - 1;
        }
      }

      // ✅ 计算前后字幕的时间差
      if (closestBefore != null && closestAfter != null) {
        final gapBefore = currentPosition - closestBefore.end;
        final gapAfter = closestAfter.start - currentPosition;

        // ✅ 如果间隙很大（>2分钟），说明可能有偏移
        if (gapBefore > const Duration(minutes: 2) &&
            gapAfter > const Duration(minutes: 2)) {
          // ✅ 使用第一个字幕的开始时间作为参考
          _timeOffset = firstSubtitle.start - currentPosition;
          debugPrint(
              '⚠️ [Subtitle] Detected offset from gap analysis: ${_timeOffset.inSeconds}s');
          _timeOffsetCalculated = true;
          return;
        }
      }
    }

    // ✅ 默认：不需要偏移
    _timeOffset = Duration.zero;
    debugPrint('✅ [Subtitle] No time offset detected, using zero offset');
    _timeOffsetCalculated = true;
  }


  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible ||
        widget.subtitleUrl == null ||
        widget.subtitleUrl!.isEmpty ||
        _isLoading ||
        _error != null) {
      return const SizedBox.shrink();
    }

    final currentSubtitle = _getCurrentSubtitle();

    // ✅ 调试信息：每30秒输出一次时间同步状态
    if (kDebugMode && 
        _timeOffsetCalculated && 
        widget.position.inSeconds % 30 == 0 &&
        widget.position.inSeconds > 0) {
      final adjustedPos = widget.position + _timeOffset;
      final hasSubtitle = currentSubtitle != null;
      debugPrint(
          '🕐 [Subtitle] Sync status - Offset: ${_timeOffset.inSeconds}s | Video: ${widget.position.inSeconds}s | Adjusted: ${adjustedPos.inSeconds}s | Has subtitle: $hasSubtitle');
    }

    // ✅ 图片字幕显示
    if (_isImageSubtitle && currentSubtitle?.imageData != null) {
      final bottomOffset =
          (widget.showControls && !widget.isLocked) ? 85.0 : 20.0;

      return AnimatedPositioned(
        key: const ValueKey('subtitle-overlay-image'),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        bottom: bottomOffset,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Image.memory(
                currentSubtitle!.imageData!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('🎬 [Subtitle] Image decode error: $error');
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
    }

    // ✅ 文本字幕显示
    final displayText = currentSubtitle?.text ?? '';
    if (displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    final bottomOffset =
        (widget.showControls && !widget.isLocked) ? 85.0 : 20.0;

    return AnimatedPositioned(
      key: const ValueKey('subtitle-overlay-text'),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: bottomOffset,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Html(
              data: displayText,
              style: {
                '#root': Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                ),
                'body': Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  textAlign: TextAlign.center,
                  color: Colors.white,
                  fontSize: FontSize(18),
                  fontWeight: FontWeight.w500,
                  lineHeight: LineHeight.number(1.4),
                  whiteSpace: WhiteSpace.pre,
                  textShadow: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 1.0),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                'p': Style(
                  margin: Margins.only(bottom: 6),
                  whiteSpace: WhiteSpace.pre,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}
