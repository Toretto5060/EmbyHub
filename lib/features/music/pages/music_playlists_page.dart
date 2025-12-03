import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicPlaylistsPage extends ConsumerWidget {
  const MusicPlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    // 模拟歌单数据
    final playlists = [
      {
        'name': '我喜欢的音乐',
        'songs': 35,
        'icon': CupertinoIcons.heart_fill,
        'color': CupertinoColors.systemPink
      },
      {
        'name': '最近播放',
        'songs': 20,
        'icon': CupertinoIcons.time,
        'color': CupertinoColors.activeBlue
      },
      {
        'name': '运动歌单',
        'songs': 15,
        'icon': CupertinoIcons.flame_fill,
        'color': CupertinoColors.systemOrange
      },
      {
        'name': '睡前音乐',
        'songs': 10,
        'icon': CupertinoIcons.moon_fill,
        'color': CupertinoColors.systemPurple
      },
    ];

    return Column(
      children: [
        // 创建歌单按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              // TODO: 创建新歌单
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.plus,
                    size: 20,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '创建新歌单',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 歌单列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    // TODO: 打开歌单详情
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // 歌单图标
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color:
                                (playlist['color'] as Color).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            playlist['icon'] as IconData,
                            size: 26,
                            color: playlist['color'] as Color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 歌单信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playlist['name'] as String,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${playlist['songs']} 首歌曲',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white54 : Colors.black45,
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
            },
          ),
        ),
      ],
    );
  }
}
