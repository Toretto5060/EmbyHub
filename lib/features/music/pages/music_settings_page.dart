import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicSettingsPage extends ConsumerStatefulWidget {
  const MusicSettingsPage({super.key});

  @override
  ConsumerState<MusicSettingsPage> createState() => _MusicSettingsPageState();
}

class _MusicSettingsPageState extends ConsumerState<MusicSettingsPage> {
  bool _autoPlay = true;
  bool _gaplessPlayback = true;
  bool _crossfade = false;
  double _crossfadeDuration = 3.0;
  bool _showLyrics = true;
  bool _savePlayHistory = true;

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放设置
          _buildSectionTitle('播放', isDark),
          _buildSwitchItem(
            icon: CupertinoIcons.play_circle,
            title: '自动播放',
            subtitle: '播放完成后自动播放下一首',
            value: _autoPlay,
            isDark: isDark,
            onChanged: (value) => setState(() => _autoPlay = value),
          ),
          _buildSwitchItem(
            icon: CupertinoIcons.link,
            title: '无缝播放',
            subtitle: '歌曲之间无间隙切换',
            value: _gaplessPlayback,
            isDark: isDark,
            onChanged: (value) => setState(() => _gaplessPlayback = value),
          ),
          _buildSwitchItem(
            icon: CupertinoIcons.waveform,
            title: '淡入淡出',
            subtitle: '歌曲切换时淡入淡出效果',
            value: _crossfade,
            isDark: isDark,
            onChanged: (value) => setState(() => _crossfade = value),
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
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
            ),
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
                  style: TextStyle(
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
}
