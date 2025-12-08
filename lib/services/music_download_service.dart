import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../providers/local_music_provider.dart';
import '../providers/local_music_matcher_provider.dart';

/// 音乐下载服务
/// 实现边下边播功能，将服务器音乐下载到本地
class MusicDownloadService {
  MusicDownloadService(this._ref);

  final Ref _ref;

  /// 当前正在下载的歌曲ID集合
  final Set<String> _downloadingIds = {};

  /// 下载完成的回调
  final _downloadCompleteController = StreamController<LocalSong>.broadcast();
  Stream<LocalSong> get onDownloadComplete =>
      _downloadCompleteController.stream;

  /// 检查是否正在下载
  bool isDownloading(String songId) => _downloadingIds.contains(songId);

  /// 开始边下边播下载
  /// 在播放服务器音乐时调用，如果开启了边下边播且歌曲没有本地文件，则开始下载
  Future<void> startProgressiveDownload(LocalSong song) async {
    // 检查是否已经有本地文件
    if (song.hasLocalFile) {
      print('🎵 [Download] Song already has local file: ${song.title}');
      return;
    }

    // 检查是否为服务器音乐
    if (!song.isServerMusic || song.path == null) {
      print('🎵 [Download] Not a server song or no path: ${song.title}');
      return;
    }

    // 检查边下边播是否启用
    final matcherState = _ref.read(localMusicMatcherProvider);
    if (!matcherState.progressiveDownloadEnabled) {
      print('🎵 [Download] Progressive download disabled');
      return;
    }

    // 检查是否有扫描目录
    if (matcherState.scanDirectories.isEmpty) {
      print('🎵 [Download] No scan directories configured');
      return;
    }

    // 检查是否已经在下载
    if (_downloadingIds.contains(song.id)) {
      print('🎵 [Download] Already downloading: ${song.title}');
      return;
    }

    // 获取下载目录
    final downloadDir = await _ref
        .read(localMusicMatcherProvider.notifier)
        .getDownloadDirectory();
    if (downloadDir == null) {
      print('⚠️ [Download] Failed to get download directory');
      return;
    }

    // 生成下载文件名
    final fileName =
        _ref.read(localMusicMatcherProvider.notifier).generateDownloadFileName(
              song.title,
              song.artist,
              song.container,
            );
    final filePath = path.join(downloadDir, fileName);

    // 检查文件是否已存在
    if (await File(filePath).exists()) {
      print('🎵 [Download] File already exists: $filePath');
      // 刷新本地文件索引
      await _ref.read(localMusicMatcherProvider.notifier).refresh();
      return;
    }

    // 开始下载
    _downloadingIds.add(song.id);
    print('🎵 [Download] Starting download: ${song.title} -> $filePath');

    try {
      await _downloadFile(song.path!, filePath);

      print('🎵 [Download] Download complete: ${song.title}');

      // 下载完成后刷新本地文件索引
      await _ref.read(localMusicMatcherProvider.notifier).refresh();

      // 通知下载完成
      _downloadCompleteController.add(song);
    } catch (e) {
      print('⚠️ [Download] Download failed: ${song.title}, error: $e');
      // 删除可能不完整的文件
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    } finally {
      _downloadingIds.remove(song.id);
    }
  }

  /// 下载文件
  Future<void> _downloadFile(String url, String savePath) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed with status: ${response.statusCode}');
    }

    final file = File(savePath);
    final sink = file.openWrite();

    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  /// 批量下载（后台静默下载播放列表中没有本地文件的歌曲）
  Future<void> downloadPlaylist(List<LocalSong> songs) async {
    final matcherState = _ref.read(localMusicMatcherProvider);
    if (!matcherState.progressiveDownloadEnabled) return;
    if (matcherState.scanDirectories.isEmpty) return;

    for (final song in songs) {
      if (!song.hasLocalFile && song.isServerMusic && song.path != null) {
        // 使用延迟避免同时下载太多
        await Future.delayed(const Duration(milliseconds: 500));
        await startProgressiveDownload(song);
      }
    }
  }

  void dispose() {
    _downloadCompleteController.close();
  }
}

/// Provider
final musicDownloadServiceProvider = Provider<MusicDownloadService>((ref) {
  final service = MusicDownloadService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
