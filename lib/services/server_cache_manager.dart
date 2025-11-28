import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// ✅ 服务器缓存管理器
///
/// 功能：
/// 1. 根据服务器标识（域名+IP，不包含端口）管理缓存
/// 2. 当服务器切换时，清除旧服务器的所有缓存（图片和数据）
/// 3. 支持多服务器缓存隔离
class ServerCacheManager {
  static const String _kCurrentServerIdKey = 'current_server_id';
  static const String _kServerListKey = 'server_list';

  /// ✅ 获取当前服务器的唯一标识（基于域名/IP，不包含端口）
  static Future<String> getCurrentServerId() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('server_host') ?? '';

    if (host.isEmpty) {
      return '';
    }

    // ✅ 移除端口号（如果有）
    final hostWithoutPort = _removePort(host);

    // ✅ 使用 MD5 生成唯一标识（避免特殊字符问题）
    final bytes = utf8.encode(hostWithoutPort.toLowerCase());
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// ✅ 移除 host 中的端口号
  static String _removePort(String host) {
    // 处理 IPv6 地址：[::1]:8096 -> [::1]
    if (host.startsWith('[')) {
      final closeBracket = host.indexOf(']');
      if (closeBracket != -1) {
        return host.substring(0, closeBracket + 1);
      }
    }

    // 处理普通域名或 IPv4：example.com:8096 -> example.com
    final colonIndex = host.lastIndexOf(':');
    if (colonIndex != -1) {
      // 检查是否是 IPv6 地址（包含多个冒号）
      final colonCount = ':'.allMatches(host).length;
      if (colonCount == 1) {
        // 只有一个冒号，说明是端口号
        return host.substring(0, colonIndex);
      }
    }

    return host;
  }

  /// ✅ 记录当前服务器（用于后续删除时清理缓存）
  static Future<void> recordCurrentServer() async {
    final currentServerId = await getCurrentServerId();

    if (currentServerId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // ✅ 更新当前服务器ID
    await prefs.setString(_kCurrentServerIdKey, currentServerId);

    // ✅ 记录服务器列表（用于后续清理）
    await _addToServerList(currentServerId);
  }

  /// ✅ 删除指定服务器的缓存（在删除服务器配置时调用）
  static Future<void> deleteServerCache(String host) async {
    // 根据 host 计算服务器ID
    final hostWithoutPort = _removePort(host);
    final bytes = utf8.encode(hostWithoutPort.toLowerCase());
    final digest = md5.convert(bytes);
    final serverId = digest.toString();

    print('🗑️ [ServerCache] Deleting server cache: $host (ID: $serverId)');
    await _clearServerCache(serverId);

    // 从服务器列表中移除
    await _removeFromServerList(serverId);
  }

  /// ✅ 清除指定服务器的所有缓存
  static Future<void> _clearServerCache(String serverId) async {
    print('🗑️ [ServerCache] Cleaning cache for server: $serverId');

    // 1. 清除图片缓存
    await _clearImageCache(serverId);

    // 2. 清除数据缓存（SharedPreferences）
    await _clearDataCache(serverId);

    print('✅ [ServerCache] Cache cleaned for server: $serverId');
  }

  /// ✅ 清除图片缓存
  static Future<void> _clearImageCache(String serverId) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final imageCacheDir = Directory('${appDir.path}/image_cache');

      if (!imageCacheDir.existsSync()) {
        return;
      }

      // ✅ 删除整个图片缓存目录
      // 因为图片缓存是基于 URL 的 MD5，无法区分服务器
      // 所以切换服务器时清除所有图片缓存
      await imageCacheDir.delete(recursive: true);
      print('✅ [ServerCache] Image cache cleared');
    } catch (e) {
      print('❌ [ServerCache] Failed to clear image cache: $e');
    }
  }

  /// ✅ 清除数据缓存（SharedPreferences）
  static Future<void> _clearDataCache(String serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // ✅ 清除所有缓存相关的键
      final cacheKeyPrefixes = [
        'cache_views',
        'cache_latest_items_',
        'cache_library_items_',
        'cache_item_detail_',
        'cache_similar_items_',
        'cache_series_detail_',
        'cache_seasons_',
        'cache_season_detail_',
        'cache_episodes_',
        'cache_next_up_episode_',
        'cache_similar_items_',
        'cache_season_resume_episode_',
      ];

      int removedCount = 0;
      for (final key in keys) {
        for (final prefix in cacheKeyPrefixes) {
          if (key.startsWith(prefix)) {
            await prefs.remove(key);
            removedCount++;
            break;
          }
        }
      }

      print('✅ [ServerCache] Data cache cleared: $removedCount keys removed');
    } catch (e) {
      print('❌ [ServerCache] Failed to clear data cache: $e');
    }
  }

  /// ✅ 添加到服务器列表
  static Future<void> _addToServerList(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final serverListJson = prefs.getString(_kServerListKey);

    List<String> serverList = [];
    if (serverListJson != null) {
      try {
        serverList = (jsonDecode(serverListJson) as List).cast<String>();
      } catch (e) {
        // 解析失败，使用空列表
      }
    }

    if (!serverList.contains(serverId)) {
      serverList.add(serverId);
      await prefs.setString(_kServerListKey, jsonEncode(serverList));
    }
  }

  /// ✅ 从服务器列表中移除
  static Future<void> _removeFromServerList(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final serverListJson = prefs.getString(_kServerListKey);

    if (serverListJson == null) return;

    try {
      List<String> serverList =
          (jsonDecode(serverListJson) as List).cast<String>();
      serverList.remove(serverId);
      await prefs.setString(_kServerListKey, jsonEncode(serverList));
    } catch (e) {
      // 解析失败，忽略
    }
  }

  /// ✅ 清除所有服务器的缓存（用于设置页面的"清除缓存"功能）
  static Future<void> clearAllCache() async {
    print('🗑️ [ServerCache] Cleaning all cache');

    // 1. 清除所有图片缓存
    try {
      final appDir = await getApplicationSupportDirectory();
      final imageCacheDir = Directory('${appDir.path}/image_cache');

      if (imageCacheDir.existsSync()) {
        await imageCacheDir.delete(recursive: true);
        print('✅ [ServerCache] All image cache cleared');
      }
    } catch (e) {
      print('❌ [ServerCache] Failed to clear all image cache: $e');
    }

    // 2. 清除所有数据缓存
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      final cacheKeyPrefixes = [
        'cache_views',
        'cache_latest_items_',
        'cache_library_items_',
        'cache_item_detail_',
        'cache_similar_items_',
        'cache_series_detail_',
        'cache_seasons_',
        'cache_season_detail_',
        'cache_episodes_',
        'cache_next_up_episode_',
        'cache_similar_items_',
        'cache_season_resume_episode_',
      ];

      int removedCount = 0;
      for (final key in keys) {
        for (final prefix in cacheKeyPrefixes) {
          if (key.startsWith(prefix)) {
            await prefs.remove(key);
            removedCount++;
            break;
          }
        }
      }

      print(
          '✅ [ServerCache] All data cache cleared: $removedCount keys removed');
    } catch (e) {
      print('❌ [ServerCache] Failed to clear all data cache: $e');
    }

    print('✅ [ServerCache] All cache cleaned');
  }

  /// ✅ 获取缓存大小（用于显示）
  static Future<int> getCacheSize() async {
    int totalSize = 0;

    try {
      // 1. 图片缓存大小
      final appDir = await getApplicationSupportDirectory();
      final imageCacheDir = Directory('${appDir.path}/image_cache');

      if (imageCacheDir.existsSync()) {
        await for (final entity in imageCacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      print('❌ [ServerCache] Failed to get cache size: $e');
    }

    return totalSize;
  }

  /// ✅ 格式化缓存大小（用于显示）
  static String formatCacheSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
