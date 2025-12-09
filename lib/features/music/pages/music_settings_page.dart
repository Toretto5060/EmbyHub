import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../providers/local_music_matcher_provider.dart';
import '../../../utils/theme_utils.dart';
import '../exoplayer_music_controller.dart';

/// 淡入淡出设置的持久化键
const String _crossfadeEnabledKey = 'music_crossfade_enabled';
const String _crossfadeDurationKey = 'music_crossfade_duration';

class MusicSettingsPage extends ConsumerStatefulWidget {
  const MusicSettingsPage({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<MusicSettingsPage> createState() => _MusicSettingsPageState();
}

class _MusicSettingsPageState extends ConsumerState<MusicSettingsPage> {
  bool _crossfade = true; // 默认开启
  double _crossfadeDuration = 3.0; // 默认3秒
  bool _showLyrics = true;
  bool _savePlayHistory = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _crossfade = prefs.getBool(_crossfadeEnabledKey) ?? true; // 默认开启
        _crossfadeDuration =
            prefs.getDouble(_crossfadeDurationKey) ?? 3.0; // 默认3秒
        _isLoading = false;
      });

      // 如果之前没有保存过设置，立即保存默认值并同步到播放器
      if (!prefs.containsKey(_crossfadeEnabledKey)) {
        await _saveCrossfadeSettings();
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// 保存并同步淡入淡出设置到原生播放器
  Future<void> _saveCrossfadeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_crossfadeEnabledKey, _crossfade);
      await prefs.setDouble(_crossfadeDurationKey, _crossfadeDuration);

      // 同步到原生播放器
      final player = ExoPlayerMusicController.instance;
      await player.setCrossfadeEnabled(_crossfade);
      if (_crossfade) {
        // 设置淡入淡出时长（秒），原生端会除以2
        await player.setCrossfadeDuration(_crossfadeDuration);
      }
    } catch (e) {
      print('⚠️ [Settings] Failed to save crossfade settings: $e');
    }
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
        bottom: miniPlayerHeight + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放设置
          _buildSectionTitle('播放', isDark),
          _buildSwitchItem(
            icon: CupertinoIcons.waveform,
            title: '淡入淡出',
            subtitle: '歌曲切换时淡入淡出效果',
            value: _crossfade,
            isDark: isDark,
            onChanged: (value) {
              setState(() => _crossfade = value);
              _saveCrossfadeSettings();
            },
          ),
          if (_crossfade)
            _buildSliderItem(
              icon: CupertinoIcons.timer,
              title: '淡入淡出时长',
              value: _crossfadeDuration,
              min: 1,
              max: 10,
              isDark: isDark,
              onChanged: (value) => setState(() => _crossfadeDuration = value),
              onChangeEnd: (value) {
                setState(() => _crossfadeDuration = value);
                _saveCrossfadeSettings();
              },
            ),
          const SizedBox(height: 24),
          // 媒体库设置
          _buildSectionTitle('媒体库', isDark),
          _buildProgressiveDownloadSwitch(isDark),
          _buildInfoHint(
            '开启后，播放媒体库音乐时会自动下载到本地扫描文件夹中的 Embyhub_Music_Download 目录',
            isDark,
          ),
          const SizedBox(height: 24),
          // 显示设置
          _buildSectionTitle('显示', isDark),
          _buildSwitchItem(
            icon: CupertinoIcons.text_quote,
            title: '显示歌词',
            subtitle: '播放时显示歌词',
            value: _showLyrics,
            isDark: isDark,
            onChanged: (value) => setState(() => _showLyrics = value),
          ),
          const SizedBox(height: 24),
          // 隐私设置
          _buildSectionTitle('隐私', isDark),
          _buildSwitchItem(
            icon: CupertinoIcons.clock,
            title: '保存播放历史',
            subtitle: '记录播放历史用于统计',
            value: _savePlayHistory,
            isDark: isDark,
            onChanged: (value) => setState(() => _savePlayHistory = value),
          ),
          _buildActionItem(
            icon: CupertinoIcons.trash,
            title: '清除播放历史',
            subtitle: '删除所有播放记录',
            isDark: isDark,
            isDestructive: true,
            onTap: () {
              // TODO: 清除播放历史
            },
          ),
          const SizedBox(height: 24),
          // 关于
          _buildSectionTitle('关于', isDark),
          _buildInfoItem(
            icon: CupertinoIcons.info,
            title: '版本',
            value: '1.0.0',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
            CupertinoSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderItem({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required bool isDark,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Text(
                  '${value.toInt()} 秒',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CupertinoSlider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    bool isDestructive = false,
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
                color: isDestructive
                    ? CupertinoColors.destructiveRed
                    : (isDark ? Colors.white54 : Colors.black45),
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
                        color: isDestructive
                            ? CupertinoColors.destructiveRed
                            : (isDark ? Colors.white : Colors.black87),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 边下边播开关
  Widget _buildProgressiveDownloadSwitch(bool isDark) {
    final matcherState = ref.watch(localMusicMatcherProvider);
    final hasScanDirs = matcherState.scanDirectories.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
              CupertinoIcons.cloud_download,
              size: 22,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '边下边播',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    hasScanDirs ? '播放时自动下载到本地' : '请先设置扫描文件夹',
                    style: TextStyle(
                      fontSize: 13,
                      color: hasScanDirs
                          ? (isDark ? Colors.white54 : Colors.black45)
                          : CupertinoColors.systemOrange,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: matcherState.progressiveDownloadEnabled && hasScanDirs,
              onChanged: hasScanDirs
                  ? (value) async {
                      // 开启时，立即创建下载文件夹
                      if (value) {
                        await ref
                            .read(localMusicMatcherProvider.notifier)
                            .getDownloadDirectory();
                      }
                      ref
                          .read(localMusicMatcherProvider.notifier)
                          .setProgressiveDownloadEnabled(value);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 信息提示
  Widget _buildInfoHint(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.info_circle,
            size: 14,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black26,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
