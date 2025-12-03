import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicScanPage extends ConsumerStatefulWidget {
  const MusicScanPage({super.key});

  @override
  ConsumerState<MusicScanPage> createState() => _MusicScanPageState();
}

class _MusicScanPageState extends ConsumerState<MusicScanPage> {
  bool _isScanning = false;
  int _scannedCount = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
                      : CupertinoIcons.music_note_2,
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
                Text(
                  _isScanning ? '已发现 $_scannedCount 首歌曲' : '扫描设备上的音乐文件',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
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
            subtitle: '选择要扫描的文件夹',
            isDark: isDark,
            onTap: () {
              // TODO: 选择扫描目录
            },
          ),
          _buildSettingItem(
            icon: CupertinoIcons.doc,
            title: '文件类型',
            subtitle: 'MP3, FLAC, WAV, AAC, OGG',
            isDark: isDark,
            onTap: () {
              // TODO: 选择文件类型
            },
          ),
          _buildSettingItem(
            icon: CupertinoIcons.clock,
            title: '最小时长',
            subtitle: '30 秒',
            isDark: isDark,
            onTap: () {
              // TODO: 设置最小时长
            },
          ),
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

  void _startScan() {
    setState(() {
      _isScanning = true;
      _scannedCount = 0;
    });

    // 模拟扫描过程
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scannedCount = 85;
        });
      }
    });
  }
}
