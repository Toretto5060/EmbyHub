import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path_provider/path_provider.dart';

import '../../../providers/local_music_provider.dart';
import '../../../providers/local_music_storage_provider.dart';
import '../../../utils/theme_utils.dart';

/// 扫描设置存储键
const String _scanDirectoriesKey = 'music_scan_directories';
const String _minDurationKey = 'music_scan_min_duration';
const String _lastScanTimeKey = 'music_last_scan_time';
const String _lastScanCountKey = 'music_last_scan_count';

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

class MusicScanPage extends ConsumerStatefulWidget {
  const MusicScanPage({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<MusicScanPage> createState() => _MusicScanPageState();
}

class _MusicScanPageState extends ConsumerState<MusicScanPage> {
  bool _isScanning = false;
  int _scannedCount = 0;
  List<String> _scanDirectories = [];
  int _minDurationSeconds = 30; // 默认30秒

  // 扫描结果状态（持久化）
  DateTime? _lastScanTime;
  int _lastScanCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final directories = prefs.getStringList(_scanDirectoriesKey) ?? [];
    final minDuration = prefs.getInt(_minDurationKey) ?? 30;
    final lastScanTimeStr = prefs.getString(_lastScanTimeKey);
    final lastScanCount = prefs.getInt(_lastScanCountKey) ?? 0;

    setState(() {
      _scanDirectories = directories;
      _minDurationSeconds = minDuration;
      _lastScanTime =
          lastScanTimeStr != null ? DateTime.tryParse(lastScanTimeStr) : null;
      _lastScanCount = lastScanCount;
    });
  }

  /// 保存扫描结果
  Future<void> _saveScanResult(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_lastScanTimeKey, now.toIso8601String());
    await prefs.setInt(_lastScanCountKey, count);

    setState(() {
      _lastScanTime = now;
      _lastScanCount = count;
    });
  }

  /// 格式化扫描时间
  String _formatScanTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      // 超过7天显示具体日期
      return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 保存扫描目录
  Future<void> _saveScanDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scanDirectoriesKey, _scanDirectories);
  }

  /// 保存最小时长
  Future<void> _saveMinDuration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minDurationKey, _minDurationSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);

    // 顶部安全区域 + 标题栏高度
    final topPadding = MediaQuery.of(context).padding.top + 56;
    // 迷你播放器高度
    const miniPlayerHeight = 72.0;

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
          top: topPadding + 20,
          left: 20,
          right: 20,
          bottom: miniPlayerHeight + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 扫描状态卡片
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  _isScanning
                      ? CupertinoIcons.radiowaves_left
                      : CupertinoIcons.double_music_note,
                  size: 64,
                  color: CupertinoColors.activeBlue,
                ),
                const SizedBox(height: 16),
                Text(
                  _isScanning ? '正在扫描...' : '扫描本地音乐',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                // 显示扫描状态或结果 - 固定高度避免布局跳动
                SizedBox(
                  height: 40,
                  child: Center(
                    child: _isScanning
                        ? Text(
                            '已发现 $_scannedCount 首歌曲',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          )
                        : _lastScanTime != null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _lastScanCount > 0
                                            ? CupertinoIcons
                                                .checkmark_circle_fill
                                            : CupertinoIcons.info_circle_fill,
                                        size: 16,
                                        color: _lastScanCount > 0
                                            ? CupertinoColors.activeGreen
                                            : CupertinoColors.systemGrey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _lastScanCount > 0
                                            ? '已扫描 $_lastScanCount 首歌曲'
                                            : '未发现音乐文件',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '上次扫描：${_formatScanTime(_lastScanTime!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                '扫描设备上的音乐文件',
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _isScanning ? null : _startScan,
                    child: Text(_isScanning ? '扫描中...' : '开始扫描'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 扫描设置
          Text(
            '扫描设置',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            icon: CupertinoIcons.folder,
            title: '扫描目录',
            subtitle: _scanDirectories.isEmpty
                ? '点击添加扫描目录'
                : '${_scanDirectories.length} 个目录',
            isDark: isDark,
            onTap: _showScanDirectoriesDialog,
          ),
          _buildSettingItem(
            icon: CupertinoIcons.clock,
            title: '不扫描 $_minDurationSeconds 秒以下音频',
            subtitle:
                _minDurationSeconds == 0 ? '不过滤' : '$_minDurationSeconds 秒',
            isDark: isDark,
            onTap: () => _showMinDurationInputDialog(isDark),
          ),
          // 显示已选目录列表
          if (_scanDirectories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '已选目录',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            ..._scanDirectories.map((dir) => _buildDirectoryItem(dir, isDark)),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建目录项
  Widget _buildDirectoryItem(String directory, bool isDark) {
    // 获取目录名称（最后一个路径段）
    final dirName = directory.split(Platform.pathSeparator).last;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.folder_fill,
              size: 18,
              color: CupertinoColors.systemYellow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dirName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    directory,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 32,
              onPressed: () => _removeDirectory(directory),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 20,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示扫描目录设置对话框
  Future<void> _showScanDirectoriesDialog() async {
    // 请求存储权限
    final permissionResult = await _requestStoragePermission();

    if (permissionResult == true) {
      // 有权限，选择目录
      await _pickDirectory();
    } else if (permissionResult == false) {
      // 用户永久拒绝，需要去设置
      if (mounted) {
        _showPermissionDeniedDialog();
      }
    }
    // permissionResult == null 表示用户临时拒绝，不做任何操作，用户可以再次点击
  }

  /// 请求存储权限
  /// 返回值：true 表示有权限，false 表示无权限且用户永久拒绝（需要去设置）
  /// 返回 null 表示用户临时拒绝（可以重新请求）
  Future<bool?> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // 获取 Android SDK 版本
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = deviceInfo.version.sdkInt;

      // Android 13+ (API 33+) 使用 READ_MEDIA_AUDIO 权限
      if (sdkInt >= 33) {
        final audioStatus = await Permission.audio.status;
        if (audioStatus.isGranted) {
          return true;
        }
        if (audioStatus.isPermanentlyDenied) {
          return false;
        }
        final result = await Permission.audio.request();
        if (result.isGranted) {
          return true;
        }
        if (result.isPermanentlyDenied) {
          return false;
        }
        return null;
      }

      // Android 11-12 (API 30-32) 使用 MANAGE_EXTERNAL_STORAGE 权限
      if (sdkInt >= 30) {
        final manageStatus = await Permission.manageExternalStorage.status;
        if (manageStatus.isGranted) {
          return true;
        }
        if (manageStatus.isPermanentlyDenied) {
          return false;
        }
        final result = await Permission.manageExternalStorage.request();
        if (result.isGranted) {
          return true;
        }
        if (result.isPermanentlyDenied) {
          return false;
        }
        return null;
      }

      // Android 10 及以下使用 READ_EXTERNAL_STORAGE 权限
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) {
        return true;
      }
      if (storageStatus.isPermanentlyDenied) {
        return false;
      }
      final result = await Permission.storage.request();
      if (result.isGranted) {
        return true;
      }
      if (result.isPermanentlyDenied) {
        return false;
      }
      return null;
    } else if (Platform.isIOS) {
      // iOS 使用文件选择器，不需要额外权限
      return true;
    }
    return true;
  }

  /// 显示权限被拒绝对话框
  void _showPermissionDeniedDialog() {
    final isDark = isDarkModeFromContext(context, ref);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_shield_fill,
                size: 48,
                color: CupertinoColors.systemOrange,
              ),
              const SizedBox(height: 16),
              Text(
                '需要存储权限',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '扫描本地音乐需要访问存储空间的权限，请在设置中开启。',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoColors.activeBlue,
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () {
                        Navigator.of(context).pop();
                        openAppSettings();
                      },
                      child: const Text(
                        '去设置',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择目录
  Future<void> _pickDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null && !_scanDirectories.contains(result)) {
        setState(() {
          _scanDirectories.add(result);
        });
        await _saveScanDirectories();
      }
    } catch (e) {
      debugPrint('选择目录失败: $e');
    }
  }

  /// 移除目录
  void _removeDirectory(String directory) {
    setState(() {
      _scanDirectories.remove(directory);
    });
    _saveScanDirectories();
  }

  /// 显示最小时长输入对话框
  void _showMinDurationInputDialog(bool isDark) {
    final controller = TextEditingController(
      text: _minDurationSeconds.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置最小时长',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '不扫描低于此时长的音频文件',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: controller,
                      placeholder: '输入秒数',
                      keyboardType: TextInputType.number,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      placeholderStyle: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '秒',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '输入 0 表示不过滤',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoColors.activeBlue,
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () {
                        final text = controller.text.trim();
                        if (text.isEmpty) {
                          Navigator.of(context).pop();
                          return;
                        }

                        final seconds = int.tryParse(text);
                        if (seconds != null && seconds >= 0) {
                          setState(() {
                            _minDurationSeconds = seconds;
                          });
                          _saveMinDuration();
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 开始扫描
  Future<void> _startScan() async {
    // 如果没有设置扫描目录，先让用户设置
    if (_scanDirectories.isEmpty) {
      await _showScanDirectoriesDialog();
      // 设置完目录后，如果有目录则自动开始扫描
      if (_scanDirectories.isEmpty) {
        return;
      }
    }

    setState(() {
      _isScanning = true;
      _scannedCount = 0;
    });

    try {
      final List<LocalSong> foundSongs = [];

      for (final directory in _scanDirectories) {
        final dir = Directory(directory);
        if (await dir.exists()) {
          await _scanDirectory(dir, foundSongs);
        }
      }

      // 替换扫描到的歌曲（清空旧列表，使用新列表）
      // 同时会清理播放列表中不存在的歌曲引用
      await ref
          .read(localMusicStorageProvider.notifier)
          .replaceSongs(foundSongs);

      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        // 保存扫描结果（持久化）
        await _saveScanResult(foundSongs.length);
      }
    } catch (e) {
      debugPrint('扫描失败: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  /// 递归扫描目录
  Future<void> _scanDirectory(
      Directory directory, List<LocalSong> foundSongs) async {
    try {
      final entities = directory.listSync(recursive: true, followLinks: false);

      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          final isAudioFile =
              _supportedExtensions.any((ext) => path.endsWith(ext));

          if (isAudioFile) {
            // 检查文件大小估算时长（用于过滤）
            final stat = await entity.stat();
            final fileSizeKB = stat.size / 1024;
            // 粗略估计：假设 128kbps 的音频，1秒约16KB
            final estimatedDurationSeconds = fileSizeKB / 16;

            if (_minDurationSeconds > 0 &&
                estimatedDurationSeconds < _minDurationSeconds) {
              continue; // 跳过短音频
            }

            // 从文件路径提取默认信息
            final fileName = entity.path.split(Platform.pathSeparator).last;
            final nameWithoutExt =
                fileName.substring(0, fileName.lastIndexOf('.'));

            // 默认值（从文件名解析）
            String title = nameWithoutExt;
            String artist = '未知艺术家';
            String? album;
            String? albumArtPath;
            String? lyrics;
            int durationSeconds = estimatedDurationSeconds.toInt();
            int? bitrate;
            int? bitDepth;
            int? sampleRate;

            if (nameWithoutExt.contains(' - ')) {
              final parts = nameWithoutExt.split(' - ');
              artist = parts[0].trim();
              title = parts.sublist(1).join(' - ').trim();
            }

            // 使用 audiotags 读取音频元数据
            try {
              final tag = await AudioTags.read(entity.path);
              if (tag != null) {
                // 优先使用元数据中的信息
                if (tag.title != null && tag.title!.isNotEmpty) {
                  title = tag.title!;
                }
                if (tag.trackArtist != null && tag.trackArtist!.isNotEmpty) {
                  artist = tag.trackArtist!;
                }
                if (tag.album != null && tag.album!.isNotEmpty) {
                  album = tag.album;
                }
                // 读取时长
                // audiotags 返回的 duration 单位是秒
                if (tag.duration != null && tag.duration! > 0) {
                  durationSeconds = tag.duration!;
                  // 根据文件大小和时长计算比特率 (kbps)
                  // bitrate = (fileSize * 8) / (duration * 1000)
                  bitrate =
                      ((stat.size * 8) / (durationSeconds * 1000)).round();
                }

                // 读取专辑封面
                if (tag.pictures.isNotEmpty) {
                  final picture = tag.pictures.first;
                  if (picture.bytes.isNotEmpty) {
                    albumArtPath = await _saveArtwork(
                        entity.path, Uint8List.fromList(picture.bytes));
                  }
                }

                // ✅ 读取内嵌歌词（FLAC Vorbis Comment: LYRICS / UNSYNCEDLYRICS）
                if (tag.lyrics != null && tag.lyrics!.isNotEmpty) {
                  lyrics = tag.lyrics;
                }
              }
            } catch (e) {
              // 读取元数据失败，使用默认值
              debugPrint('读取元数据失败: $e');
            }

            // 解析文件头获取位深和采样率
            final audioInfo = await _parseAudioFileHeader(entity.path);
            bitDepth = audioInfo['bitDepth'];
            sampleRate = audioInfo['sampleRate'];

            // 如果没有从元数据获取到比特率，根据文件大小估算
            if (bitrate == null && durationSeconds > 0) {
              bitrate = ((stat.size * 8) / (durationSeconds * 1000)).round();
            }

            // ✅ 如果没有内嵌歌词，尝试读取同目录下的 .lrc 歌词文件
            if (lyrics == null || lyrics.isEmpty) {
              lyrics = await _loadLyricsFile(entity.path);
            }

            final song = LocalSong(
              id: entity.path.hashCode.toString(),
              title: title,
              artist: artist,
              album: album,
              albumArt: albumArtPath,
              lyrics: lyrics,
              bitrate: bitrate,
              bitDepth: bitDepth,
              sampleRate: sampleRate,
              path: entity.path,
              duration: Duration(seconds: durationSeconds),
            );

            foundSongs.add(song);

            setState(() {
              _scannedCount = foundSongs.length;
            });
          }
        }
      }
    } catch (e) {
      // 扫描目录失败
    }
  }

  /// 加载歌词文件
  Future<String?> _loadLyricsFile(String audioPath) async {
    try {
      // 获取音频文件的目录和文件名（不含扩展名）
      final lastSeparator = audioPath.lastIndexOf(Platform.pathSeparator);
      final directory = audioPath.substring(0, lastSeparator);
      final fileName = audioPath.substring(lastSeparator + 1);
      final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));

      // 尝试查找同名的 .lrc 文件
      final lrcPath = '$directory${Platform.pathSeparator}$nameWithoutExt.lrc';
      final lrcFile = File(lrcPath);

      if (await lrcFile.exists()) {
        return await lrcFile.readAsString();
      }

      // 尝试查找同名的 .txt 歌词文件
      final txtPath = '$directory${Platform.pathSeparator}$nameWithoutExt.txt';
      final txtFile = File(txtPath);

      if (await txtFile.exists()) {
        final content = await txtFile.readAsString();
        // 简单判断是否像歌词文件（包含时间戳或多行文本）
        if (content.contains('[') || content.split('\n').length > 3) {
          return content;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 保存专辑封面到缓存目录
  Future<String?> _saveArtwork(String audioPath, Uint8List artwork) async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final artworkDir = Directory('${cacheDir.path}/album_artwork');
      if (!await artworkDir.exists()) {
        await artworkDir.create(recursive: true);
      }

      // 使用音频文件路径的哈希作为文件名
      final hash = audioPath.hashCode.abs().toString();
      final artworkPath = '${artworkDir.path}/$hash.jpg';

      final file = File(artworkPath);
      await file.writeAsBytes(artwork);

      return artworkPath;
    } catch (e) {
      debugPrint('保存封面失败: $e');
      return null;
    }
  }

  /// 解析音频文件头获取位深和采样率
  Future<Map<String, int?>> _parseAudioFileHeader(String filePath) async {
    int? bitDepth;
    int? sampleRate;

    try {
      final file = File(filePath);
      final raf = await file.open(mode: FileMode.read);

      try {
        final ext = filePath.toLowerCase();

        if (ext.endsWith('.flac')) {
          // 解析 FLAC 文件头
          // FLAC 文件以 "fLaC" 开头
          final header = await raf.read(4);
          if (header.length == 4 &&
              header[0] == 0x66 && // 'f'
              header[1] == 0x4C && // 'L'
              header[2] == 0x61 && // 'a'
              header[3] == 0x43) {
            // 'C'
            // 读取 METADATA_BLOCK_HEADER
            final metaHeader = await raf.read(4);
            if (metaHeader.length == 4) {
              // 获取 block 类型和长度
              final blockType = metaHeader[0] & 0x7F;
              final blockLength =
                  (metaHeader[1] << 16) | (metaHeader[2] << 8) | metaHeader[3];

              if (blockType == 0 && blockLength >= 18) {
                // STREAMINFO block
                final streamInfo = await raf.read(18);
                if (streamInfo.length >= 18) {
                  // 采样率: bits 80-99 (20 bits)
                  // 位于 byte 10-12
                  sampleRate = (streamInfo[10] << 12) |
                      (streamInfo[11] << 4) |
                      ((streamInfo[12] & 0xF0) >> 4);

                  // 位深: bits 103-107 (5 bits) + 1
                  // 位于 byte 12 的低 1 位和 byte 13 的高 4 位
                  bitDepth = (((streamInfo[12] & 0x01) << 4) |
                          ((streamInfo[13] & 0xF0) >> 4)) +
                      1;
                }
              }
            }
          }
        } else if (ext.endsWith('.wav')) {
          // 解析 WAV 文件头
          // WAV 文件以 "RIFF" 开头
          final riff = await raf.read(12);
          if (riff.length == 12 &&
              riff[0] == 0x52 && // 'R'
              riff[1] == 0x49 && // 'I'
              riff[2] == 0x46 && // 'F'
              riff[3] == 0x46 && // 'F'
              riff[8] == 0x57 && // 'W'
              riff[9] == 0x41 && // 'A'
              riff[10] == 0x56 && // 'V'
              riff[11] == 0x45) {
            // 'E'
            // 查找 "fmt " chunk
            while (await raf.position() < await raf.length() - 8) {
              final chunkHeader = await raf.read(8);
              if (chunkHeader.length < 8) break;

              final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
              final chunkSize = chunkHeader[4] |
                  (chunkHeader[5] << 8) |
                  (chunkHeader[6] << 16) |
                  (chunkHeader[7] << 24);

              if (chunkId == 'fmt ') {
                final fmtData = await raf.read(chunkSize);
                if (fmtData.length >= 16) {
                  // 采样率: bytes 4-7 (little endian)
                  sampleRate = fmtData[4] |
                      (fmtData[5] << 8) |
                      (fmtData[6] << 16) |
                      (fmtData[7] << 24);
                  // 位深: bytes 14-15 (little endian)
                  bitDepth = fmtData[14] | (fmtData[15] << 8);
                }
                break;
              } else {
                // 跳过这个 chunk
                await raf.setPosition(await raf.position() + chunkSize);
              }
            }
          }
        } else if (ext.endsWith('.aiff') || ext.endsWith('.aif')) {
          // 解析 AIFF 文件头
          final form = await raf.read(12);
          if (form.length == 12 &&
              form[0] == 0x46 && // 'F'
              form[1] == 0x4F && // 'O'
              form[2] == 0x52 && // 'R'
              form[3] == 0x4D) {
            // 'M'
            // 查找 "COMM" chunk
            while (await raf.position() < await raf.length() - 8) {
              final chunkHeader = await raf.read(8);
              if (chunkHeader.length < 8) break;

              final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
              final chunkSize = (chunkHeader[4] << 24) |
                  (chunkHeader[5] << 16) |
                  (chunkHeader[6] << 8) |
                  chunkHeader[7];

              if (chunkId == 'COMM') {
                final commData = await raf.read(chunkSize);
                if (commData.length >= 18) {
                  // 位深: bytes 6-7 (big endian)
                  bitDepth = (commData[6] << 8) | commData[7];
                  // 采样率: bytes 8-17 (80-bit extended precision)
                  // 简化处理：只读取整数部分
                  final exp = ((commData[8] & 0x7F) << 8) | commData[9];
                  final mantissa = (commData[10] << 24) |
                      (commData[11] << 16) |
                      (commData[12] << 8) |
                      commData[13];
                  if (exp > 0) {
                    sampleRate = (mantissa >> (16414 - exp)).toInt();
                  }
                }
                break;
              } else {
                // 跳过这个 chunk
                final skipSize = chunkSize + (chunkSize % 2); // AIFF 需要对齐
                await raf.setPosition(await raf.position() + skipSize);
              }
            }
          }
        }
        // MP3, AAC, OGG 等压缩格式通常不存储原始位深
        // 它们使用可变比特率，位深概念不同
      } finally {
        await raf.close();
      }
    } catch (e) {
      // 解析失败，返回空值
    }

    return {'bitDepth': bitDepth, 'sampleRate': sampleRate};
  }
}
