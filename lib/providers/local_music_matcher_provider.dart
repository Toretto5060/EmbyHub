import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

import 'local_music_provider.dart';

/// 本地音乐文件匹配服务
/// 用于将服务器媒体库音乐与本地扫描的文件进行匹配

/// 边下边播设置存储键
const String _progressiveDownloadEnabledKey =
    'music_progressive_download_enabled';

/// 下载文件夹名称
const String _downloadFolderName = 'Embyhub_Music_Download';

/// 支持的音频文件扩展名
const List<String> _supportedExtensions = [
  '.mp3',
  '.flac',
  '.wav',
  '.aac',
  '.ogg',
  '.m4a',
  '.wma',
];

/// 本地文件匹配结果
class LocalFileMatch {
  /// 是否存在本地文件
  final bool hasLocalFile;

  /// 本地文件路径（如果存在）
  final String? localFilePath;

  /// 本地歌词路径（如果存在）
  final String? localLyricsPath;

  const LocalFileMatch({
    this.hasLocalFile = false,
    this.localFilePath,
    this.localLyricsPath,
  });
}

/// 本地音乐匹配器状态
class LocalMusicMatcherState {
  /// 本地文件名到路径的映射（不含扩展名的文件名 -> 完整路径）
  final Map<String, String> localFileMap;

  /// 本地歌词文件映射（不含扩展名的文件名 -> .lrc路径）
  final Map<String, String> localLyricsMap;

  /// 是否已初始化
  final bool isInitialized;

  /// 扫描目录列表
  final List<String> scanDirectories;

  /// 边下边播是否启用
  final bool progressiveDownloadEnabled;

  const LocalMusicMatcherState({
    this.localFileMap = const {},
    this.localLyricsMap = const {},
    this.isInitialized = false,
    this.scanDirectories = const [],
    this.progressiveDownloadEnabled = false,
  });

  LocalMusicMatcherState copyWith({
    Map<String, String>? localFileMap,
    Map<String, String>? localLyricsMap,
    bool? isInitialized,
    List<String>? scanDirectories,
    bool? progressiveDownloadEnabled,
  }) {
    return LocalMusicMatcherState(
      localFileMap: localFileMap ?? this.localFileMap,
      localLyricsMap: localLyricsMap ?? this.localLyricsMap,
      isInitialized: isInitialized ?? this.isInitialized,
      scanDirectories: scanDirectories ?? this.scanDirectories,
      progressiveDownloadEnabled:
          progressiveDownloadEnabled ?? this.progressiveDownloadEnabled,
    );
  }
}

/// 本地音乐匹配器
class LocalMusicMatcherNotifier extends StateNotifier<LocalMusicMatcherState> {
  LocalMusicMatcherNotifier() : super(const LocalMusicMatcherState()) {
    _initialize();
  }

  /// 初始化
  Future<void> _initialize() async {
    await _loadSettings();
    await buildLocalFileIndex();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final directories = prefs.getStringList('music_scan_directories') ?? [];
    final progressiveDownloadEnabled =
        prefs.getBool(_progressiveDownloadEnabledKey) ?? false;

    state = state.copyWith(
      scanDirectories: directories,
      progressiveDownloadEnabled: progressiveDownloadEnabled,
    );
  }

  /// 设置边下边播开关
  Future<void> setProgressiveDownloadEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_progressiveDownloadEnabledKey, enabled);
    state = state.copyWith(progressiveDownloadEnabled: enabled);
  }

  /// 构建本地文件索引
  /// 扫描所有配置的目录，建立文件名到路径的映射
  Future<void> buildLocalFileIndex() async {
    if (state.scanDirectories.isEmpty) {
      state = state.copyWith(
        localFileMap: {},
        localLyricsMap: {},
        isInitialized: true,
      );
      return;
    }

    final fileMap = <String, String>{};
    final lyricsMap = <String, String>{};

    for (final dirPath in state.scanDirectories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final filePath = entity.path;
            final fileName = path.basenameWithoutExtension(filePath);
            final ext = path.extension(filePath).toLowerCase();

            // 音频文件
            if (_supportedExtensions.contains(ext)) {
              // 使用标准化的文件名作为key（去除可能的特殊字符）
              final normalizedName = _normalizeString(fileName);
              fileMap[normalizedName] = filePath;
            }

            // 歌词文件
            if (ext == '.lrc') {
              final normalizedName = _normalizeString(fileName);
              lyricsMap[normalizedName] = filePath;
            }
          }
        }
      } catch (e) {
        // 扫描失败，静默处理
        print(
            '⚠️ [LocalMusicMatcher] Failed to scan directory: $dirPath, error: $e');
      }
    }

    state = state.copyWith(
      localFileMap: fileMap,
      localLyricsMap: lyricsMap,
      isInitialized: true,
    );

    print(
        '🎵 [LocalMusicMatcher] Built index: ${fileMap.length} audio files, ${lyricsMap.length} lyrics files');
  }

  /// 标准化字符串（用于匹配）
  /// 去除特殊字符、多余空格，转小写
  String _normalizeString(String str) {
    return str
        .toLowerCase()
        .trim()
        // 将全角字符转换为半角
        .replaceAll('　', ' ')
        .replaceAll('－', '-')
        .replaceAll('—', '-')
        // 去除多余空格
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 根据歌曲信息生成可能的文件名列表
  List<String> _generatePossibleFileNames(String title, String artist) {
    final normalizedTitle = _normalizeString(title);
    final normalizedArtist = _normalizeString(artist);

    // 生成各种可能的文件名格式
    final patterns = <String>[
      // 艺术家 - 标题 格式（最常见）
      '$normalizedArtist - $normalizedTitle',
      '$normalizedArtist-$normalizedTitle',
      '${normalizedArtist}_$normalizedTitle',
      '$normalizedArtist.$normalizedTitle',
      // 标题 - 艺术家 格式
      '$normalizedTitle - $normalizedArtist',
      '$normalizedTitle-$normalizedArtist',
      '${normalizedTitle}_$normalizedArtist',
      // 仅标题
      normalizedTitle,
      // 仅艺术家（不太可能，但以防万一）
      normalizedArtist,
    ];

    // 如果艺术家包含多个（用逗号分隔），也尝试第一个艺术家
    if (normalizedArtist.contains(',')) {
      final firstArtist = normalizedArtist.split(',').first.trim();
      patterns.addAll([
        '$firstArtist - $normalizedTitle',
        '$firstArtist-$normalizedTitle',
        '$normalizedTitle - $firstArtist',
      ]);
    }

    return patterns;
  }

  /// 匹配本地文件
  /// 根据歌曲标题和艺术家查找本地是否存在对应文件
  /// 使用多种匹配策略：精确匹配 -> 模糊匹配
  LocalFileMatch matchLocalFile(String title, String artist) {
    if (!state.isInitialized || state.localFileMap.isEmpty) {
      return const LocalFileMatch();
    }

    final possibleNames = _generatePossibleFileNames(title, artist);

    // 尝试匹配音频文件
    String? matchedFilePath;
    String? matchedLyricsPath;

    // 策略1：精确匹配
    for (final name in possibleNames) {
      if (state.localFileMap.containsKey(name)) {
        matchedFilePath = state.localFileMap[name];
        break;
      }
    }

    // 策略2：如果精确匹配失败，尝试模糊匹配（包含关系）
    if (matchedFilePath == null) {
      final normalizedTitle = _normalizeString(title);
      final normalizedArtist = _normalizeString(artist);

      for (final entry in state.localFileMap.entries) {
        final fileName = entry.key;
        // 检查文件名是否同时包含标题和艺术家
        if (fileName.contains(normalizedTitle) &&
            fileName.contains(normalizedArtist)) {
          matchedFilePath = entry.value;
          break;
        }
      }
    }

    // 策略3：如果还是失败，只匹配标题（适用于文件名只有标题的情况）
    if (matchedFilePath == null) {
      final normalizedTitle = _normalizeString(title);
      for (final entry in state.localFileMap.entries) {
        final fileName = entry.key;
        // 文件名完全等于标题，或以标题开头/结尾
        if (fileName == normalizedTitle ||
            fileName.startsWith('$normalizedTitle -') ||
            fileName.startsWith('$normalizedTitle-') ||
            fileName.endsWith('- $normalizedTitle') ||
            fileName.endsWith('-$normalizedTitle')) {
          matchedFilePath = entry.value;
          break;
        }
      }
    }

    // 尝试匹配歌词文件（使用相同的策略）
    for (final name in possibleNames) {
      if (state.localLyricsMap.containsKey(name)) {
        matchedLyricsPath = state.localLyricsMap[name];
        break;
      }
    }

    // 如果找到了音频文件，也检查同目录下的歌词文件
    if (matchedFilePath != null && matchedLyricsPath == null) {
      final audioDir = path.dirname(matchedFilePath);
      final audioBaseName = path.basenameWithoutExtension(matchedFilePath);
      final possibleLrcPath = path.join(audioDir, '$audioBaseName.lrc');
      if (File(possibleLrcPath).existsSync()) {
        matchedLyricsPath = possibleLrcPath;
      }
    }

    if (matchedFilePath != null) {
      print('🎵 [Matcher] Matched "$title" by "$artist" -> $matchedFilePath');
    }

    return LocalFileMatch(
      hasLocalFile: matchedFilePath != null,
      localFilePath: matchedFilePath,
      localLyricsPath: matchedLyricsPath,
    );
  }

  /// 获取下载目录路径
  /// 如果不存在则创建
  Future<String?> getDownloadDirectory() async {
    if (state.scanDirectories.isEmpty) return null;

    // 使用第一个扫描目录作为下载目录的父目录
    final parentDir = state.scanDirectories.first;
    final downloadDir = path.join(parentDir, _downloadFolderName);

    final dir = Directory(downloadDir);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
        print(
            '🎵 [LocalMusicMatcher] Created download directory: $downloadDir');
      } catch (e) {
        print('⚠️ [LocalMusicMatcher] Failed to create download directory: $e');
        return null;
      }
    }

    return downloadDir;
  }

  /// 生成下载文件名
  /// 格式：艺术家-标题.扩展名
  String generateDownloadFileName(
      String title, String artist, String? container) {
    // 清理文件名中的非法字符
    final cleanTitle = _cleanFileName(title);
    final cleanArtist = _cleanFileName(artist);
    final ext = container?.toLowerCase() ?? 'mp3';

    return '$cleanArtist-$cleanTitle.$ext';
  }

  /// 清理文件名中的非法字符
  String _cleanFileName(String name) {
    // 替换非法字符
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 刷新本地文件索引
  Future<void> refresh() async {
    await _loadSettings();
    await buildLocalFileIndex();
  }
}

/// Provider
final localMusicMatcherProvider =
    StateNotifierProvider<LocalMusicMatcherNotifier, LocalMusicMatcherState>(
  (ref) => LocalMusicMatcherNotifier(),
);

/// 便捷方法：检查歌曲是否有本地文件
final hasLocalFileProvider = Provider.family<bool, LocalSong>((ref, song) {
  final matcher = ref.watch(localMusicMatcherProvider);
  if (!matcher.isInitialized) return false;

  final match = ref.read(localMusicMatcherProvider.notifier).matchLocalFile(
        song.title,
        song.artist,
      );
  return match.hasLocalFile;
});

/// 便捷方法：获取歌曲的本地文件匹配结果
final localFileMatchProvider =
    Provider.family<LocalFileMatch, LocalSong>((ref, song) {
  final matcher = ref.watch(localMusicMatcherProvider);
  if (!matcher.isInitialized) return const LocalFileMatch();

  return ref.read(localMusicMatcherProvider.notifier).matchLocalFile(
        song.title,
        song.artist,
      );
});
