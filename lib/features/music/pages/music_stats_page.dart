import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/theme_utils.dart';

class MusicStatsPage extends ConsumerWidget {
  const MusicStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放统计
          Text(
            '播放统计',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: CupertinoIcons.play_fill,
                  label: '总播放次数',
                  value: '1,234',
                  color: CupertinoColors.activeBlue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: CupertinoIcons.time,
                  label: '总播放时长',
                  value: '48小时',
                  color: CupertinoColors.systemGreen,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 最常播放
          Text(
            '最常播放',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildTopSongsList(isDark),
          const SizedBox(height: 24),
          // 最喜欢的艺术家
          Text(
            '最喜欢的艺术家',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildTopArtistsList(isDark),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 28,
            color: color,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSongsList(bool isDark) {
    final topSongs = [
      {'rank': 1, 'title': '示例歌曲 1', 'artist': '艺术家 A', 'plays': 156},
      {'rank': 2, 'title': '示例歌曲 2', 'artist': '艺术家 B', 'plays': 123},
      {'rank': 3, 'title': '示例歌曲 3', 'artist': '艺术家 A', 'plays': 98},
      {'rank': 4, 'title': '示例歌曲 4', 'artist': '艺术家 C', 'plays': 87},
      {'rank': 5, 'title': '示例歌曲 5', 'artist': '艺术家 B', 'plays': 76},
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: topSongs.map((song) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: song['rank'] != 5
                  ? Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.05),
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                // 排名
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _getRankColor(song['rank'] as int).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${song['rank']}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getRankColor(song['rank'] as int),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 歌曲信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['title'] as String,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        song['artist'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                // 播放次数
                Text(
                  '${song['plays']} 次',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopArtistsList(bool isDark) {
    final topArtists = [
      {'rank': 1, 'name': '艺术家 A', 'plays': 456},
      {'rank': 2, 'name': '艺术家 B', 'plays': 321},
      {'rank': 3, 'name': '艺术家 C', 'plays': 198},
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: topArtists.map((artist) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: artist['rank'] != 3
                  ? Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.05),
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                // 排名
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color:
                        _getRankColor(artist['rank'] as int).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${artist['rank']}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getRankColor(artist['rank'] as int),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 艺术家头像
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.person_fill,
                    size: 20,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
                const SizedBox(width: 12),
                // 艺术家名称
                Expanded(
                  child: Text(
                    artist['name'] as String,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                // 播放次数
                Text(
                  '${artist['plays']} 次',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // 金色
      case 2:
        return const Color(0xFFC0C0C0); // 银色
      case 3:
        return const Color(0xFFCD7F32); // 铜色
      default:
        return CupertinoColors.activeBlue;
    }
  }
}
