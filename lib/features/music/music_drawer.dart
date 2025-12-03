import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/theme_utils.dart';

class MusicDrawer extends ConsumerWidget {
  const MusicDrawer({
    required this.onExit,
    super.key,
  });

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);
    final currentNav = ref.watch(currentMusicNavProvider);

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // 顶部操作栏
            _buildHeader(context, isDark, ref),
            const SizedBox(height: 8),
            // 导航列表
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // 主要导航项
                  _buildSectionTitle('浏览', isDark),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.music_note,
                    label: '歌曲',
                    item: MusicNavItem.songs,
                    isSelected: currentNav == MusicNavItem.songs,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.square_stack,
                    label: '专辑',
                    item: MusicNavItem.albums,
                    isSelected: currentNav == MusicNavItem.albums,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.person_2,
                    label: '艺术家',
                    item: MusicNavItem.artists,
                    isSelected: currentNav == MusicNavItem.artists,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.folder,
                    label: '文件夹',
                    item: MusicNavItem.folders,
                    isSelected: currentNav == MusicNavItem.folders,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.music_note_list,
                    label: '歌单',
                    item: MusicNavItem.playlists,
                    isSelected: currentNav == MusicNavItem.playlists,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 16),
                  _buildSectionTitle('管理', isDark),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.search,
                    label: '扫描音乐',
                    item: MusicNavItem.scan,
                    isSelected: currentNav == MusicNavItem.scan,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.music_albums,
                    label: '音乐库',
                    item: MusicNavItem.library,
                    isSelected: currentNav == MusicNavItem.library,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.chart_bar,
                    label: '统计',
                    item: MusicNavItem.stats,
                    isSelected: currentNav == MusicNavItem.stats,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    context: context,
                    ref: ref,
                    icon: CupertinoIcons.gear,
                    label: '设置',
                    item: MusicNavItem.settings,
                    isSelected: currentNav == MusicNavItem.settings,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 退出按钮
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 40,
            onPressed: onExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.arrow_left,
                    size: 18,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '退出',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 切换媒体库按钮（待实现）
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 40,
            onPressed: () {
              // TODO: 切换媒体库音乐数据
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.arrow_2_circlepath,
                    size: 18,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '媒体库',
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white38 : Colors.black38,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required WidgetRef ref,
    required IconData icon,
    required String label,
    required MusicNavItem item,
    required bool isSelected,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          ref.read(currentMusicNavProvider.notifier).state = item;
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? CupertinoColors.activeBlue.withOpacity(0.2)
                    : CupertinoColors.activeBlue.withOpacity(0.1))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? CupertinoColors.activeBlue
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? CupertinoColors.activeBlue
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
