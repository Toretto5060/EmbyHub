import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicLibraryPage extends ConsumerWidget {
  const MusicLibraryPage({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);
    
    // 顶部安全区域 + 标题栏高度
    final topPadding = MediaQuery.of(context).padding.top + 56;
    // 迷你播放器高度
    const miniPlayerHeight = 72.0;

    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.only(top: topPadding + 20, left: 20, right: 20, bottom: miniPlayerHeight + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 音乐库概览
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CupertinoColors.activeBlue.withOpacity(0.2),
                  CupertinoColors.systemPurple.withOpacity(0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.music_albums,
                  size: 56,
                  color: CupertinoColors.activeBlue,
                ),
                const SizedBox(height: 16),
                Text(
                  '本地音乐库',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '管理您的本地音乐文件',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 统计信息
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: CupertinoIcons.double_music_note,
                  label: '歌曲',
                  value: '85',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: CupertinoIcons.square_stack,
                  label: '专辑',
                  value: '12',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: CupertinoIcons.person_2,
                  label: '艺术家',
                  value: '8',
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 操作选项
          Text(
            '管理',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildActionItem(
            icon: CupertinoIcons.refresh,
            title: '刷新音乐库',
            subtitle: '重新扫描所有音乐文件',
            isDark: isDark,
            onTap: () {},
          ),
          _buildActionItem(
            icon: CupertinoIcons.trash,
            title: '清空缓存',
            subtitle: '清除封面图片缓存',
            isDark: isDark,
            onTap: () {},
          ),
          _buildActionItem(
            icon: CupertinoIcons.arrow_down_doc,
            title: '导入音乐',
            subtitle: '从其他位置导入音乐',
            isDark: isDark,
            onTap: () {},
          ),
          _buildActionItem(
            icon: CupertinoIcons.arrow_up_doc,
            title: '导出播放列表',
            subtitle: '导出歌单到文件',
            isDark: isDark,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 24,
            color: CupertinoColors.activeBlue,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
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
}
