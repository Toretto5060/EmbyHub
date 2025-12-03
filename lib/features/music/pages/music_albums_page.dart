import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicAlbumsPage extends ConsumerWidget {
  const MusicAlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    // 模拟专辑数据
    final albums = [
      {'name': '专辑一', 'artist': '艺术家 A', 'songs': 12},
      {'name': '专辑二', 'artist': '艺术家 B', 'songs': 8},
      {'name': '专辑三', 'artist': '艺术家 C', 'songs': 15},
      {'name': '专辑四', 'artist': '艺术家 A', 'songs': 10},
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            // TODO: 打开专辑详情
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 专辑封面
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      CupertinoIcons.music_albums,
                      size: 48,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 专辑名称
              Text(
                album['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              // 艺术家
              Text(
                '${album['artist']} · ${album['songs']} 首歌曲',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
