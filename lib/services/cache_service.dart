import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/emby_api.dart';

/// 缓存服务：用于持久化存储首页和列表页数据
/// 策略：先显示缓存，后台更新，静默刷新
class CacheService {
  static const String _kResumeItemsKey = 'cache_resume_items';
  static const String _kViewsKey = 'cache_views';
  static const String _kLatestItemsPrefix = 'cache_latest_items_';
  static const String _kLibraryItemsPrefix = 'cache_library_items_';
  static const String _kItemDetailPrefix = 'cache_item_detail_';
  static const String _kSimilarItemsPrefix = 'cache_similar_items_';
  static const String _kCollectionItemsPrefix = 'cache_collection_items_';

  // 缓存有效期（永久有效，设置为极大值）
  static const Duration _cacheExpiry = Duration(days: 365 * 100); // 100年，相当于永久

  /// 保存继续观看数据
  static Future<void> saveResumeItems(
      String userId, List<ItemInfo> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_kResumeItemsKey}_$userId';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((item) => item.toJson()).toList(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      // 缓存失败不影响主流程
      print('❌ Failed to save resume items cache: $e');
    }
  }

  /// 读取继续观看数据
  static Future<List<ItemInfo>?> loadResumeItems(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_kResumeItemsKey}_$userId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final itemsJson = data['items'] as List;
      return itemsJson
          .map((json) => ItemInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Failed to load resume items cache: $e');
      return null;
    }
  }

  /// 保存媒体库列表
  static Future<void> saveViews(String userId, List<ViewInfo> views) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_kViewsKey}_$userId';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'views': views.map((view) => view.toJson()).toList(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      print('❌ Failed to save views cache: $e');
    }
  }

  /// 读取媒体库列表
  static Future<List<ViewInfo>?> loadViews(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_kViewsKey}_$userId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final viewsJson = data['views'] as List;
      return viewsJson
          .map((json) => ViewInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Failed to load views cache: $e');
      return null;
    }
  }

  /// 保存媒体库最新内容
  static Future<void> saveLatestItems(
      String userId, String viewId, List<ItemInfo> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kLatestItemsPrefix${userId}_$viewId';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((item) => item.toJson()).toList(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      print('❌ Failed to save latest items cache: $e');
    }
  }

  /// 读取媒体库最新内容
  static Future<List<ItemInfo>?> loadLatestItems(
      String userId, String viewId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kLatestItemsPrefix${userId}_$viewId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final itemsJson = data['items'] as List;
      return itemsJson
          .map((json) => ItemInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Failed to load latest items cache: $e');
      return null;
    }
  }

  /// 保存列表页数据
  static Future<void> saveLibraryItems({
    required String userId,
    required String parentId,
    required String sortBy,
    required bool ascending,
    required List<ItemInfo> items,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          '$_kLibraryItemsPrefix${userId}_${parentId}_${sortBy}_$ascending';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((item) => item.toJson()).toList(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      print('❌ Failed to save library items cache: $e');
    }
  }

  /// 读取列表页数据
  static Future<List<ItemInfo>?> loadLibraryItems({
    required String userId,
    required String parentId,
    required String sortBy,
    required bool ascending,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          '$_kLibraryItemsPrefix${userId}_${parentId}_${sortBy}_$ascending';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final itemsJson = data['items'] as List;
      return itemsJson
          .map((json) => ItemInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Failed to load library items cache: $e');
      return null;
    }
  }

  /// 保存详情页数据
  static Future<void> saveItemDetail(
      String userId, String itemId, ItemInfo item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_kItemDetailPrefix}${userId}_$itemId';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'item': item.toJson(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      // 缓存失败不影响主流程，静默处理
    }
  }

  /// 读取详情页数据
  static Future<ItemInfo?> loadItemDetail(String userId, String itemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_kItemDetailPrefix}${userId}_$itemId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final itemJson = data['item'] as Map<String, dynamic>;
      return ItemInfo.fromJson(itemJson);
    } catch (e) {
      // 缓存读取失败，静默处理
      return null;
    }
  }

  /// 清除所有缓存
  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('cache_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      print('❌ Failed to clear cache: $e');
    }
  }

  /// 保存相似影片数据
  static Future<void> saveSimilarItems(
      String userId, String itemId, List<ItemInfo> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kSimilarItemsPrefix${userId}_$itemId';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((item) => item.toJson()).toList(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      // 缓存失败不影响主流程
    }
  }

  /// 读取相似影片数据
  static Future<List<ItemInfo>?> loadSimilarItems(
      String userId, String itemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kSimilarItemsPrefix${userId}_$itemId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final itemsJson = data['items'] as List;
      return itemsJson.map((json) => ItemInfo.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  /// 保存合集影片数据
  static Future<void> saveCollectionItems(
      String userId, String collectionId, List<ItemInfo> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kCollectionItemsPrefix${userId}_$collectionId';
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((item) => item.toJson()).toList(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      // 缓存失败不影响主流程
    }
  }

  /// 读取合集影片数据
  static Future<List<ItemInfo>?> loadCollectionItems(
      String userId, String collectionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kCollectionItemsPrefix${userId}_$collectionId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      // 检查缓存是否过期
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final itemsJson = data['items'] as List;
      return itemsJson.map((json) => ItemInfo.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  /// 清除指定用户的缓存
  static Future<void> clearUserCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.contains(userId)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      print('❌ Failed to clear user cache: $e');
    }
  }
}
