import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/local_music_provider.dart';
import '../../../utils/theme_utils.dart';

class MusicFoldersPage extends ConsumerWidget {
  const MusicFoldersPage({super.key});

  void _goToScanPage(WidgetRef ref) {
    ref.read(currentMusicNavProvider.notifier).state = MusicNavItem.scan;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);
    final musicSourceMode = ref.watch(musicSourceModeProvider);

    // TODO: 从存储中获取文件夹数据
    final folders = <Map<String, dynamic>>[];

    if (folders.isEmpty) {
      return _buildEmptyState(context, isDark, musicSourceMode, ref);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            // TODO: 打开文件夹
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 文件夹图标
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark
                        ? CupertinoColors.systemYellow.withOpacity(0.15)
                        : CupertinoColors.systemYellow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    CupertinoIcons.folder_fill,
                    size: 26,
                    color: CupertinoColors.systemYellow,
                  ),
                ),
                const SizedBox(width: 12),
                // 文件夹信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder['name'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${folder['songs']} 首歌曲',
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
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark,
      MusicSourceMode sourceMode, WidgetRef ref) {
    final isServerMode = sourceMode == MusicSourceMode.server;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.folder,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 24),
            Text(
              '暂无文件夹',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            if (isServerMode)
              Text(
                '快去服务器添加音乐文件吧',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black38,
                ),
                textAlign: TextAlign.center,
              )
            else
              Column(
                children: [
                  Text(
                    '当前为本地播放，快去扫描吧',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black38,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    color: CupertinoColors.activeBlue,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: () => _goToScanPage(ref),
                    child: const Text(
                      '扫描音乐',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
