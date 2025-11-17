import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;

  SubtitleEntry({
    required this.start,
    required this.end,
    required this.text,
  });

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
    super.key,
  });

  final Duration position;
  final String? subtitleUrl;
  final bool isVisible;
  final bool showControls; // ✅ 控制栏显示状态

  @override
  State<CustomSubtitleOverlay> createState() => _CustomSubtitleOverlayState();
}

class _CustomSubtitleOverlayState extends State<CustomSubtitleOverlay> {
  List<SubtitleEntry> _subtitles = [];
  bool _isLoading = false;
  String? _error;
  int _lastFoundIndex = 0;

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
    }
    // ✅ 移除手动 setState，Flutter 会自动重建（widget.position 变化时）
  }

  Future<void> _loadSubtitles() async {
    if (widget.subtitleUrl == null || widget.subtitleUrl!.isEmpty) {
      setState(() {
        _subtitles = [];
        _isLoading = false;
        _error = null;
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

        if (response.statusCode == 200) {
          final content = utf8.decode(response.bodyBytes);
          final subtitles = _parseVTT(content);

          // ✅ 不归零，使用原始时间戳
          setState(() {
            _subtitles = subtitles;
            _isLoading = false;
            _error = null;
            _lastFoundIndex = 0;
          });
          return;
        } else {
          lastError = '${response.statusCode}';
        }
      } catch (e) {
        lastError = '$e';
      }
    }

    setState(() {
      _isLoading = false;
      _error = '加载字幕失败: $lastError';
    });
  }

  /// ✅ 支持多种 VTT 时间格式：HH:MM:SS.mmm 或 MM:SS.mmm
  List<SubtitleEntry> _parseVTT(String content) {
    final entries = <SubtitleEntry>[];
    final lines = content.split('\n');

    String? currentText;
    Duration? startTime;
    Duration? endTime;

    // ✅ 支持含小时和不含小时的格式
    // 格式1: HH:MM:SS.mmm --> HH:MM:SS.mmm (或 H:MM:SS.mmm)
    // 格式2: MM:SS.mmm --> MM:SS.mmm (或 M:SS.mmm)
    final timePatternWithHours = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})\.(\d{3})',
    );
    final timePatternNoHours = RegExp(
      r'(\d{1,2}):(\d{2})\.(\d{3})\s*-->\s*(\d{1,2}):(\d{2})\.(\d{3})',
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
            text: currentText.trim(),
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
            text: currentText.trim(),
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
        text: currentText.trim(),
      ));
    }

    return entries;
  }

  SubtitleEntry? _getCurrentSubtitle() {
    if (!widget.isVisible || _subtitles.isEmpty) {
      return null;
    }

    final videoPos = widget.position;

    // ✅ 优化：如果位置差距 > 5秒，直接全表扫描（处理拖拽情况）
    if (_lastFoundIndex < _subtitles.length) {
      final lastEntry = _subtitles[_lastFoundIndex];
      final timeDiff = (videoPos - lastEntry.start).abs();

      if (timeDiff > const Duration(seconds: 5)) {
        // 位置差距大，全表扫描
        for (int i = 0; i < _subtitles.length; i++) {
          final entry = _subtitles[i];
          if (entry.isActive(videoPos)) {
            _lastFoundIndex = i;
            return entry;
          }
        }
        return null;
      }

      // 否则在附近查找（±1）
      if (lastEntry.isActive(videoPos)) {
        return lastEntry;
      }

      if (_lastFoundIndex + 1 < _subtitles.length) {
        final nextEntry = _subtitles[_lastFoundIndex + 1];
        if (nextEntry.isActive(videoPos)) {
          _lastFoundIndex = _lastFoundIndex + 1;
          return nextEntry;
        }
      }

      if (_lastFoundIndex > 0) {
        final prevEntry = _subtitles[_lastFoundIndex - 1];
        if (prevEntry.isActive(videoPos)) {
          _lastFoundIndex = _lastFoundIndex - 1;
          return prevEntry;
        }
      }
    }

    // 全表扫描
    for (int i = 0; i < _subtitles.length; i++) {
      final entry = _subtitles[i];
      if (entry.isActive(videoPos)) {
        _lastFoundIndex = i;
        return entry;
      }
    }

    return null;
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
    final displayText = currentSubtitle?.text ?? '';

    if (displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    // ✅ 根据控制栏显示状态调整位置
    // 默认位置：距离底部 20
    // 控制栏显示时：距离底部 100（控制栏高度约 80 + 间距 20，更靠近控制栏）
    final bottomOffset = widget.showControls ? 85.0 : 20.0;

    // ✅ 移除时间戳显示，只显示字幕内容
    // ✅ 使用固定 key 确保组件复用
    // ✅ 使用 AnimatedPositioned 添加平滑的上移下移动画
    return AnimatedPositioned(
      key: const ValueKey('subtitle-overlay'),
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
            // ✅ 去除背景装饰
            child: Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.4,
                // ✅ 轻量字体阴影，确保文字清晰可见
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
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
