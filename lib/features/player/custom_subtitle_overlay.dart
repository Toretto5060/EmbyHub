import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// ✅ 字幕条目
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

/// ✅ 自定义字幕显示组件
class CustomSubtitleOverlay extends StatefulWidget {
  const CustomSubtitleOverlay({
    required this.position,
    required this.subtitleUrl,
    this.isVisible = true,
    super.key,
  });

  final Duration position;
  final String? subtitleUrl;
  final bool isVisible;

  @override
  State<CustomSubtitleOverlay> createState() => _CustomSubtitleOverlayState();
}

class _CustomSubtitleOverlayState extends State<CustomSubtitleOverlay> {
  List<SubtitleEntry> _subtitles = [];
  bool _isLoading = false;
  String? _error;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _loadSubtitles();
    // ✅ 定时更新字幕显示（每100ms检查一次）
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(CustomSubtitleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitleUrl != widget.subtitleUrl) {
      _loadSubtitles();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  /// ✅ 加载字幕文件
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

    try {
      final response = await http.get(Uri.parse(widget.subtitleUrl!));
      if (response.statusCode == 200) {
        final content = response.body;
        final subtitles = _parseVTT(content);
        setState(() {
          _subtitles = subtitles;
          _isLoading = false;
          _error = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = '加载字幕失败: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '加载字幕失败: $e';
      });
    }
  }

  /// ✅ 解析 VTT 格式字幕
  List<SubtitleEntry> _parseVTT(String content) {
    final entries = <SubtitleEntry>[];
    final lines = content.split('\n');

    String? currentText;
    Duration? startTime;
    Duration? endTime;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 跳过空行和注释
      if (line.isEmpty ||
          line.startsWith('WEBVTT') ||
          line.startsWith('NOTE')) {
        continue;
      }

      // 检查是否是时间戳行（格式: 00:00:00.000 --> 00:00:02.000）
      final timeMatch = RegExp(
              r'(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})')
          .firstMatch(line);
      if (timeMatch != null) {
        // 如果有之前的条目，先保存
        if (startTime != null && endTime != null && currentText != null) {
          entries.add(SubtitleEntry(
            start: startTime,
            end: endTime,
            text: currentText.trim(),
          ));
        }

        // 解析新的时间戳
        startTime = Duration(
          hours: int.parse(timeMatch.group(1)!),
          minutes: int.parse(timeMatch.group(2)!),
          seconds: int.parse(timeMatch.group(3)!),
          milliseconds: int.parse(timeMatch.group(4)!),
        );
        endTime = Duration(
          hours: int.parse(timeMatch.group(5)!),
          minutes: int.parse(timeMatch.group(6)!),
          seconds: int.parse(timeMatch.group(7)!),
          milliseconds: int.parse(timeMatch.group(8)!),
        );
        currentText = '';
        continue;
      }

      // 如果是文本行
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

  /// ✅ 获取当前应该显示的字幕
  SubtitleEntry? _getCurrentSubtitle() {
    if (!widget.isVisible || _subtitles.isEmpty) {
      return null;
    }

    for (final entry in _subtitles) {
      if (entry.isActive(widget.position)) {
        return entry;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 调试信息：检查字幕层状态
    if (widget.subtitleUrl != null && widget.subtitleUrl!.isNotEmpty) {
      debugPrint('🎬 [Subtitle] URL: ${widget.subtitleUrl}');
      debugPrint('🎬 [Subtitle] Position: ${widget.position.inSeconds}s');
      debugPrint('🎬 [Subtitle] Subtitles count: ${_subtitles.length}');
      debugPrint('🎬 [Subtitle] Loading: $_isLoading, Error: $_error');
    }

    if (!widget.isVisible ||
        widget.subtitleUrl == null ||
        widget.subtitleUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_error != null) {
      // ✅ 显示错误信息（调试用）
      debugPrint('🎬 [Subtitle] Error: $_error');
      return const SizedBox.shrink();
    }

    final currentSubtitle = _getCurrentSubtitle();
    if (currentSubtitle == null) {
      return const SizedBox.shrink();
    }

    debugPrint('🎬 [Subtitle] Current subtitle: ${currentSubtitle.text}');

    // ✅ 字幕显示在底部中央，带背景和阴影
    // 使用 IgnorePointer 确保字幕不阻挡视频交互，避免影响视频渲染
    return Positioned(
      bottom: 80, // 在底部控制栏上方
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 800, // 最大宽度
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7), // 半透明黑色背景
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              currentSubtitle.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.4,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 4,
                    offset: Offset(0, 1),
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
