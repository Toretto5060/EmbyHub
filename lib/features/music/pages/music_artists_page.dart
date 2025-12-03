import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicArtistsPage extends ConsumerWidget {
  const MusicArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    // 模拟艺术家数据
    final artists = [
      {'name': '艺术家 A', 'albums': 3, 'songs': 25},
      {'name': '艺术家 B', 'albums': 2, 'songs': 18},
      {'name': '艺术家 C', 'albums': 1, 'songs': 15},
      {'name': '艺术家 D', 'albums': 4, 'songs': 32},
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            // TODO: 打开艺术家详情
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 艺术家头像
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.person_fill,
                    size: 28,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
                const SizedBox(width: 16),
                // 艺术家信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist['name'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${artist['albums']} 张专辑 · ${artist['songs']} 首歌曲',
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

