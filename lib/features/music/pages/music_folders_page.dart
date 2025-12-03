import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicFoldersPage extends ConsumerWidget {
  const MusicFoldersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    // 模拟文件夹数据
    final folders = [
      {'name': 'Music', 'path': '/storage/Music', 'songs': 45},
      {'name': 'Downloads', 'path': '/storage/Downloads/Music', 'songs': 12},
      {'name': '我的音乐', 'path': '/storage/我的音乐', 'songs': 28},
    ];

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
}
