import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:shared_preferences/shared_preferences.dart' as sp;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/device_name.dart';

const bool _kEmbyApiLogging = false;
void _apiLog(String message) {
  if (_kEmbyApiLogging) {}
}

class EmbyApi {
  EmbyApi(this._dio);

  final dio.Dio _dio;

  static Future<EmbyApi> create() async {
    final prefs = await sp.SharedPreferences.getInstance();
    final protocol = prefs.getString('server_protocol') ?? 'http';
    final host = prefs.getString('server_host') ?? '';
    final port = prefs.getString('server_port') ?? '';
    final baseUrl = _buildBaseUrl(protocol, host, port);
    final dioClient = dio.Dio(dio.BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30), // 增加到30秒
        receiveTimeout: const Duration(seconds: 60), // 增加到60秒
        sendTimeout: const Duration(seconds: 60))); // 增加发送超时

    // 添加请求头拦截器
    dioClient.interceptors
        .add(dio.InterceptorsWrapper(onRequest: (options, handler) async {
      final token = prefs.getString('emby_token');
      final deviceId = await _ensureDeviceId(prefs);
      final deviceModel = await _getDeviceModelForHeader();
      final packageInfo = await PackageInfo.fromPlatform();
      final clientName = packageInfo.appName;
      final clientVersion = packageInfo.version;
      final auth =
          'MediaBrowser Client="$clientName", Device="$deviceModel", DeviceId="$deviceId", Version="$clientVersion"';
      options.headers['X-Emby-Authorization'] = auth;
      if (token != null && token.isNotEmpty) {
        options.headers['X-Emby-Token'] = token;
      }
      handler.next(options);
    }));

    // 添加重试拦截器（仅对非登录接口，最多重试2次）
    dioClient.interceptors.add(
      dio.InterceptorsWrapper(
        onError: (error, handler) async {
          final retryCount =
              error.requestOptions.extra['retryCount'] as int? ?? 0;

          // 对于网络错误进行重试（除了登录接口，最多重试2次）
          if (_shouldRetry(error) && retryCount < 2) {
            _apiLog(
                '🔄 Retry ${retryCount + 1}/2 for: ${error.requestOptions.uri}');

            // 等待一段时间后重试
            await Future.delayed(
                Duration(milliseconds: 500 * (retryCount + 1)));

            try {
              // 更新重试计数
              error.requestOptions.extra['retryCount'] = retryCount + 1;
              final response = await dioClient.fetch(error.requestOptions);
              _apiLog('✅ Retry successful for: ${error.requestOptions.uri}');
              handler.resolve(response);
            } catch (e) {
              _apiLog('❌ Retry ${retryCount + 1} failed: $e');
              handler.next(error);
            }
          } else {
            if (retryCount >= 2) {
              _apiLog(
                  '❌ Max retries (2) reached for: ${error.requestOptions.uri}');
            }
            handler.next(error);
          }
        },
      ),
    );

    return EmbyApi(dioClient);
  }

  // 判断是否应该重试
  static bool _shouldRetry(dio.DioException error) {
    // 登录接口不重试
    if (error.requestOptions.path.contains('AuthenticateByName')) {
      return false;
    }

    // 只对网络错误和超时错误重试
    return error.type == dio.DioExceptionType.connectionTimeout ||
        error.type == dio.DioExceptionType.receiveTimeout ||
        error.type == dio.DioExceptionType.sendTimeout ||
        error.type == dio.DioExceptionType.connectionError;
  }

  static String _buildBaseUrl(String protocol, String host, String port) {
    final p = port.isEmpty ? '' : ':$port';
    return '$protocol://$host$p';
  }

  static Future<String> _ensureDeviceId(sp.SharedPreferences prefs) async {
    var id = prefs.getString('device_id');
    if (id == null || id.isEmpty) {
      id = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('device_id', id);
    }
    return id;
  }

  // ✅ 品牌名称中文映射
  static String _getChineseBrandName(String brand) {
    final brandLower = brand.toLowerCase();
    final brandMap = {
      'xiaomi': '小米',
      'redmi': '红米',
      'samsung': '三星',
      'huawei': '华为',
      'honor': '荣耀',
      'oppo': 'OPPO',
      'vivo': 'vivo',
      'oneplus': '一加',
      'realme': 'realme',
      'meizu': '魅族',
      'motorola': '摩托罗拉',
      'lenovo': '联想',
      'google': 'Google',
      'sony': '索尼',
      'lg': 'LG',
      'asus': '华硕',
    };
    return brandMap[brandLower] ?? brand;
  }

  // ✅ 尝试从 Android 设备信息中提取友好的设备名称
  static String _extractFriendlyDeviceName(
    String brand,
    String model,
    String? product,
    String? device,
  ) {
    // 如果 model 是纯数字+字母的代号（如 "2509FPN0BC"），尝试使用 product 或 device
    // 纯代号通常匹配模式：全是大写字母和数字，长度较长
    final isCodePattern = RegExp(r'^[A-Z0-9]{8,}$').hasMatch(model);

    String friendlyModel = model;

    // 如果 model 看起来像代号，尝试使用 product 或 device
    if (isCodePattern) {
      // 优先使用 product（如 "xmsirius"），去除前缀后格式化
      if (product != null && product.isNotEmpty) {
        // 移除常见的前缀（如 "xm" 代表小米）
        final cleanedProduct = product.replaceAll(
            RegExp(r'^(xm|redmi|huawei|honor)', caseSensitive: false), '');
        if (cleanedProduct.isNotEmpty && cleanedProduct != product) {
          // 将下划线或连字符转换为空格，并格式化首字母大写
          friendlyModel = cleanedProduct
              .replaceAll(RegExp(r'[_-]'), ' ')
              .split(' ')
              .map((word) => word.isNotEmpty
                  ? word[0].toUpperCase() + word.substring(1).toLowerCase()
                  : '')
              .join(' ');
        } else {
          // 如果 product 本身就是友好的名称，直接使用（首字母大写）
          friendlyModel =
              product[0].toUpperCase() + product.substring(1).toLowerCase();
        }
      }
      // 如果 product 不可用，尝试使用 device
      else if (device != null && device.isNotEmpty && device != model) {
        friendlyModel = device
            .replaceAll(RegExp(r'[_-]'), ' ')
            .split(' ')
            .map((word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1).toLowerCase()
                : '')
            .join(' ');
      }
    } else {
      // 如果 model 本身看起来像友好名称，直接格式化（首字母大写）
      friendlyModel = model;
    }

    // 获取中文品牌名称
    final chineseBrand = _getChineseBrandName(brand);

    // 组合：品牌 + 型号（用空格分隔）
    return '$chineseBrand $friendlyModel'.trim();
  }

  // ✅ 获取设备型号（如 "小米 7 Pro Max"）- 用于显示
  // ignore: unused_element
  static Future<String> _getDeviceModel() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // 提取友好的设备名称
        final brand = androidInfo.brand;
        final model = androidInfo.model;
        final product = androidInfo.product;
        final device = androidInfo.device;

        return _extractFriendlyDeviceName(
          brand,
          model,
          product,
          device,
        );
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.model;
      } else {
        return Platform.operatingSystem;
      }
    } catch (e) {
      // 如果获取失败，回退到操作系统名称
      return Platform.operatingSystem;
    }
  }

  // ✅ 获取设备型号用于 HTTP header（使用平台通道获取真实商用名称）
  static Future<String> _getDeviceModelForHeader() async {
    try {
      if (Platform.isAndroid) {
        // ✅ 优先使用平台通道获取真实设备商用名称（从系统属性 ro.product.marketname）
        try {
          final deviceName = await DeviceName.getMarketName();
          if (deviceName.isNotEmpty && deviceName != "Unknown") {
            return deviceName;
          }
        } catch (e) {
          // 如果平台通道失败，回退到原有逻辑
        }

        // ✅ 回退方案：使用 Build.MANUFACTURER + Build.MODEL
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        final brand = androidInfo.brand;
        final model = androidInfo.model;

        // 使用英文品牌名称（首字母大写）
        final englishBrand = brand.isNotEmpty
            ? brand[0].toUpperCase() + brand.substring(1).toLowerCase()
            : brand;

        // 组合：品牌 + 型号
        return '$englishBrand $model'.trim();
      } else if (Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.model;
      } else {
        return Platform.operatingSystem;
      }
    } catch (e) {
      // 如果获取失败，回退到操作系统名称
      return Platform.operatingSystem;
    }
  }

  Future<Map<String, dynamic>> systemInfo() async {
    final res = await _dio.get('/System/Info/Public');
    return res.data as Map<String, dynamic>;
  }

  Future<LoginResult> authenticate(
      {required String username, required String password}) async {
    final res = await _dio.post(
      '/Users/AuthenticateByName',
      data: {
        'Username': username,
        'Pw': password,
      },
      options: dio.Options(
        contentType: 'application/json',
        headers: {
          'Accept': 'application/json',
        },
      ),
    );
    final data = res.data as Map<String, dynamic>;
    final token = data['AccessToken'] as String?;
    final user = data['User'] as Map<String, dynamic>?;
    if (token == null || user == null) {
      throw Exception('登录失败');
    }
    final prefs = await sp.SharedPreferences.getInstance();
    await prefs.setString('emby_token', token);
    await prefs.setString('emby_user_id', user['Id'] as String);
    await prefs.setString(
        'emby_user_name', user['Name'] as String? ?? username);

    // Note: Account history is handled in the connect page

    return LoginResult(
        token: token,
        userId: user['Id'] as String,
        userName: user['Name'] as String? ?? username);
  }

  Future<List<ViewInfo>> getUserViews(String userId) async {
    try {
      _apiLog('getUserViews: userId=$userId');
      final res = await _dio.get('/Users/$userId/Views');
      _apiLog('getUserViews response type: ${res.data.runtimeType}');
      _apiLog('getUserViews response: ${res.data}');

      if (res.data is! Map<String, dynamic>) {
        _apiLog('getUserViews: Response is not a Map');
        return [];
      }

      final items = res.data['Items'];
      if (items == null) {
        _apiLog('getUserViews: No Items field in response');
        return [];
      }

      if (items is! List) {
        _apiLog('getUserViews: Items is not a List');
        return [];
      }

      final list = items.cast<Map<String, dynamic>>();
      _apiLog('getUserViews: Found ${list.length} views');
      return list.map((e) => ViewInfo.fromJson(e)).toList();
    } catch (e) {
      _apiLog('getUserViews error: $e');
      rethrow;
    }
  }

  // Get resume items (continue watching)
  Future<List<ItemInfo>> getResumeItems(String userId, {int limit = 12}) async {
    try {
      final res = await _dio.get('/Users/$userId/Items', queryParameters: {
        'Limit': limit,
        'Recursive': true,
        'Filters': 'IsResumable',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Fields':
            'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,UserData,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds,SeriesId,SeasonId,ParentThumbItemId,ParentThumbImageTag,ParentBackdropItemId,ParentBackdropImageTags,ImageTags,BackdropImageTags,SeriesPrimaryImageTag,SeasonPrimaryImageTag',
        'ImageTypeLimit': 1,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
      });
      final list =
          (res.data['Items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return list.map((e) => ItemInfo.fromJson(e)).toList();
    } catch (e) {
      _apiLog('getResumeItems error: $e');
      return [];
    }
  }

  // Get latest items from a library
  Future<List<ItemInfo>> getLatestItems(String userId,
      {required String parentId, int limit = 16}) async {
    try {
      final res =
          await _dio.get('/Users/$userId/Items/Latest', queryParameters: {
        'ParentId': parentId,
        'Limit': limit,
        'Fields':
            'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,UserData,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds,SeriesId,SeasonId,ParentThumbItemId,ParentThumbImageTag,ParentBackdropItemId,ParentBackdropImageTags,ImageTags,BackdropImageTags,SeriesPrimaryImageTag,SeasonPrimaryImageTag',
        'ImageTypeLimit': 1,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
      });

      // Latest API returns an array directly, not wrapped in Items
      if (res.data is List) {
        final list = (res.data as List).cast<Map<String, dynamic>>();
        // ✅ 处理Series合并逻辑
        _processMergedSeries(list);
        return list.map((e) => ItemInfo.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _apiLog('getLatestItems error: $e');
      return [];
    }
  }

  // ✅ 提取基础Series名称（去除数字后缀，如"地球脉动 3" -> "地球脉动"）
  static String _extractBaseSeriesName(String name) {
    // 匹配模式：名称 + 空格 + 数字（如"地球脉动 3"、"Planet Earth 2"）
    final regex = RegExp(r'^(.+?)\s+(\d+)$');
    final match = regex.firstMatch(name.trim());
    if (match != null) {
      return match.group(1)!.trim();
    }
    return name.trim();
  }

  // ✅ 处理Series合并逻辑（过滤重复Series并累加未观看集数）
  static void _processMergedSeries(List<Map<String, dynamic>> list) {
    // ✅ 检测可能的重复Series（如"地球脉动"和"地球脉动 3"）
    final seriesJsonList =
        list.where((item) => item['Type'] == 'Series').toList();
    final seriesNames = <String, List<Map<String, dynamic>>>{};
    for (final json in seriesJsonList) {
      final name = json['Name'] as String? ?? '';
      if (name.isEmpty) continue;

      // ✅ 提取基础名称（去除数字后缀，如"地球脉动 3" -> "地球脉动"）
      final baseName = _extractBaseSeriesName(name);
      if (!seriesNames.containsKey(baseName)) {
        seriesNames[baseName] = [];
      }
      seriesNames[baseName]!.add(json);
    }

    // ✅ 识别应该被过滤的Series（那些应该是季但被识别为独立Series的项目）
    final itemsToFilter = <String>{};
    // ✅ 记录需要更新UnplayedItemCount的基础Series
    final baseSeriesToUpdate = <String, int>{}; // baseSeriesId -> 需要累加的未观看集数

    for (final entry in seriesNames.entries) {
      if (entry.value.length > 1) {
        // ✅ 找出基础名称的Series（没有数字后缀）
        Map<String, dynamic>? baseSeries;
        final numberedSeries = <Map<String, dynamic>>[];

        for (final json in entry.value) {
          final name = json['Name'] as String? ?? '';
          final baseName = _extractBaseSeriesName(name);
          if (name == baseName) {
            // ✅ 这是基础名称的Series
            baseSeries = json;
          } else {
            // ✅ 这是带数字后缀的Series
            numberedSeries.add(json);
          }
        }

        // ✅ 如果找到了基础Series且有ChildCount，则过滤掉带数字后缀的Series
        if (baseSeries != null && numberedSeries.isNotEmpty) {
          final baseChildCount = baseSeries['ChildCount'] as int? ?? 0;
          if (baseChildCount > 0) {
            final baseSeriesId = baseSeries['Id'] as String? ?? '';
            int totalUnplayedFromMerged = 0;

            // ✅ 计算合并进来的Series的未观看集数总和
            for (final json in numberedSeries) {
              final id = json['Id'] as String? ?? '';
              itemsToFilter.add(id);

              // ✅ 获取该Series的未观看集数
              final userData = json['UserData'] as Map<String, dynamic>?;
              if (userData != null) {
                final unplayedCount =
                    (userData['UnplayedItemCount'] as num?)?.toInt() ?? 0;
                if (unplayedCount > 0) {
                  totalUnplayedFromMerged += unplayedCount;
                }
              }
            }

            // ✅ 如果有未观看集数需要累加，记录到baseSeriesToUpdate
            if (totalUnplayedFromMerged > 0 && baseSeriesId.isNotEmpty) {
              baseSeriesToUpdate[baseSeriesId] = totalUnplayedFromMerged;
            }
          }
        }
      }
    }

    // ✅ 更新基础Series的UnplayedItemCount
    if (baseSeriesToUpdate.isNotEmpty) {
      for (final item in list) {
        final id = item['Id'] as String? ?? '';
        if (baseSeriesToUpdate.containsKey(id)) {
          final additionalUnplayed = baseSeriesToUpdate[id]!;
          // ✅ 确保UserData存在
          if (item['UserData'] == null) {
            item['UserData'] = <String, dynamic>{};
          }
          final userData = item['UserData'] as Map<String, dynamic>;
          final currentUnplayed =
              (userData['UnplayedItemCount'] as num?)?.toInt() ?? 0;
          final newUnplayed = currentUnplayed + additionalUnplayed;
          userData['UnplayedItemCount'] = newUnplayed;
        }
      }
    }

    // ✅ 过滤掉应该被移除的Series
    if (itemsToFilter.isNotEmpty) {
      list.removeWhere((item) {
        final id = item['Id'] as String? ?? '';
        return itemsToFilter.contains(id);
      });
    }
  }

  Future<List<ItemInfo>> getItemsByParent(
      {required String userId,
      required String parentId,
      int startIndex = 0,
      int limit = 60,
      String? includeItemTypes,
      String? sortBy,
      String? sortOrder,
      bool? groupItemsIntoCollections,
      String? genres}) async {
    final queryParams = {
      'ParentId': parentId,
      'StartIndex': startIndex,
      'Limit': limit,
      'Recursive': true,
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,SeriesId,SeasonId,ParentThumbItemId,ParentThumbImageTag,ParentBackdropItemId,ParentBackdropImageTags,ImageTags,BackdropImageTags,SeriesPrimaryImageTag,SeasonPrimaryImageTag,DateLastSaved,DateLastSavedForUser,DateModified,DateAdded,UserData',
    };

    // 如果指定了类型，使用指定的；否则使用默认的
    if (includeItemTypes != null) {
      queryParams['IncludeItemTypes'] = includeItemTypes;
    } else {
      queryParams['IncludeItemTypes'] = 'Movie,Series,BoxSet,Video';
    }

    // 添加排序参数
    if (sortBy != null && sortBy.isNotEmpty) {
      queryParams['SortBy'] = sortBy;
    }
    if (sortOrder != null && sortOrder.isNotEmpty) {
      queryParams['SortOrder'] = sortOrder;
    }
    // 添加合集合并参数
    if (groupItemsIntoCollections != null) {
      queryParams['GroupItemsIntoCollections'] = groupItemsIntoCollections;
    }
    // 添加类型筛选参数
    if (genres != null && genres.isNotEmpty) {
      queryParams['Genres'] = genres;
    }

    final res =
        await _dio.get('/Users/$userId/Items', queryParameters: queryParams);
    final list = (res.data['Items'] as List).cast<Map<String, dynamic>>();

    // ✅ 处理Series合并逻辑
    _processMergedSeries(list);

    return list.map((e) => ItemInfo.fromJson(e)).toList();
  }

  // ✅ 返回分页结果（包含列表和总数）
  Future<({List<ItemInfo> items, int? totalCount})> getItemsByParentWithTotal(
      {required String userId,
      required String parentId,
      int startIndex = 0,
      int limit = 60,
      String? includeItemTypes,
      String? sortBy,
      String? sortOrder,
      bool? groupItemsIntoCollections,
      String? genres}) async {
    final queryParams = {
      'ParentId': parentId,
      'StartIndex': startIndex,
      'Limit': limit,
      'Recursive': true,
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,SeriesId,SeasonId,ParentThumbItemId,ParentThumbImageTag,ParentBackdropItemId,ParentBackdropImageTags,ImageTags,BackdropImageTags,SeriesPrimaryImageTag,SeasonPrimaryImageTag,DateLastSaved,DateLastSavedForUser,DateModified,DateAdded,UserData',
    };

    // 如果指定了类型，使用指定的；否则使用默认的
    if (includeItemTypes != null) {
      queryParams['IncludeItemTypes'] = includeItemTypes;
    } else {
      queryParams['IncludeItemTypes'] = 'Movie,Series,BoxSet,Video';
    }

    // 添加排序参数
    if (sortBy != null && sortBy.isNotEmpty) {
      queryParams['SortBy'] = sortBy;
    }
    if (sortOrder != null && sortOrder.isNotEmpty) {
      queryParams['SortOrder'] = sortOrder;
    }
    // 添加合集合并参数
    if (groupItemsIntoCollections != null) {
      queryParams['GroupItemsIntoCollections'] = groupItemsIntoCollections;
    }
    // 添加类型筛选参数
    if (genres != null && genres.isNotEmpty) {
      queryParams['Genres'] = genres;
    }

    final res =
        await _dio.get('/Users/$userId/Items', queryParameters: queryParams);
    final list = (res.data['Items'] as List).cast<Map<String, dynamic>>();
    // ✅ 获取总数
    final totalCount = (res.data['TotalRecordCount'] as num?)?.toInt();

    // ✅ 处理Series合并逻辑
    _processMergedSeries(list);

    return (
      items: list.map((e) => ItemInfo.fromJson(e)).toList(),
      totalCount: totalCount,
    );
  }

  Future<List<ItemInfo>> getSimilarItems(String userId, String itemId,
      {int limit = 12}) async {
    final baseParams = {
      'Limit': limit,
      'IncludeItemTypes': 'Movie,Series,Video',
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,Genres',
      'ImageTypeLimit': 1,
      'EnableImageTypes': 'Primary,Backdrop,Thumb',
    };

    Future<List<ItemInfo>> fetch(
      String path,
      Map<String, dynamic> queryParams,
      String tag,
    ) async {
      try {
        _apiLog('[API][Similar] try $tag path=$path params=$queryParams');
        final res = await _dio.get(path, queryParameters: queryParams);
        final data = res.data;
        final items = _extractItemsList(data);
        final result = items?.map(ItemInfo.fromJson).toList() ?? [];
        _apiLog('[API][Similar] ok $tag path=$path -> ${result.length} items');
        return result;
      } catch (e) {
        _apiLog('[API][Similar] error $tag path=$path: $e');
        return const [];
      }
    }

    final requestVariants = [
      (
        path: '/Users/$userId/Items/$itemId/Similar',
        params: {...baseParams},
        tag: 'user+include',
      ),
      (
        path: '/Users/$userId/Items/$itemId/Similar',
        params: {...baseParams}..remove('IncludeItemTypes'),
        tag: 'user+noType',
      ),
      (
        path: '/Items/$itemId/Similar',
        params: {...baseParams, 'UserId': userId},
        tag: 'items+include',
      ),
      (
        path: '/Items/$itemId/Similar',
        params: {...baseParams, 'UserId': userId}..remove('IncludeItemTypes'),
        tag: 'items+noType',
      ),
      (
        path: '/Users/$userId/Items/$itemId/Similar',
        params: {
          'Limit': limit,
          'Fields':
              'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,Genres',
        },
        tag: 'user+minimal',
      ),
    ];

    for (final variant in requestVariants) {
      final result = await fetch(variant.path, variant.params, variant.tag);
      if (result.isNotEmpty) {
        return result;
      }
    }

    final fallback = await _fallbackSimilarItems(
      userId: userId,
      itemId: itemId,
      limit: limit,
      baseParams: baseParams,
    );

    if (fallback.isNotEmpty) {
      return fallback;
    }

    _apiLog('[API][Similar] no results for item=$itemId');
    return const [];
  }

  List<Map<String, dynamic>>? _extractItemsList(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final items = data['Items'];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList();
      }
    }
    return null;
  }

  Future<List<ItemInfo>> _fallbackSimilarItems({
    required String userId,
    required String itemId,
    required int limit,
    required Map<String, dynamic> baseParams,
  }) async {
    try {
      _apiLog('[API][Similar] fallback start for item=$itemId');
      final itemRes = await _dio.get(
        '/Users/$userId/Items/$itemId',
        queryParameters: {
          'Fields':
              'PrimaryImageAspectRatio,Genres,ParentId,CollectionType,RunTimeTicks,ProviderIds',
        },
      );

      if (itemRes.data is! Map<String, dynamic>) {
        _apiLog('[API][Similar] fallback: item response not a map');
        return const [];
      }

      final itemJson = itemRes.data as Map<String, dynamic>;
      final itemType = itemJson['Type']?.toString();
      final parentId = itemJson['ParentId']?.toString();
      final genres = (itemJson['Genres'] as List?)
              ?.whereType<String>()
              .where((g) => g.isNotEmpty)
              .toList() ??
          const [];

      final fallbackParams = <String, dynamic>{
        ...baseParams,
        'Recursive': true,
        'SortBy': 'Random',
        'Filters': 'IsNotFolder',
        'ExcludeItemIds': itemId,
        'Limit': limit + 6,
      };

      if (itemType != null && itemType.isNotEmpty) {
        fallbackParams['IncludeItemTypes'] = itemType;
      }

      if (parentId != null && parentId.isNotEmpty) {
        fallbackParams['ParentId'] = parentId;
      }

      if (genres.isNotEmpty) {
        fallbackParams['Genres'] = genres.take(3).join(',');
      }

      _apiLog(
          '[API][Similar] fallback params: type=$itemType parent=$parentId genres=${genres.take(3).join('/')}');

      final res = await _dio.get(
        '/Users/$userId/Items',
        queryParameters: fallbackParams,
      );

      final items = _extractItemsList(res.data) ?? const [];
      if (items.isEmpty) {
        _apiLog('[API][Similar] fallback: no items returned');
        return const [];
      }

      final filtered = items
          .where((e) => e['Id'] != itemId)
          .take(limit)
          .map(ItemInfo.fromJson)
          .toList();

      _apiLog('[API][Similar] fallback produced ${filtered.length} items');
      return filtered;
    } catch (e, stack) {
      _apiLog('[API][Similar] fallback error: $e');
      _apiLog(stack.toString());
      return const [];
    }
  }

  // 获取某个剧集的季列表
  Future<List<ItemInfo>> getSeasons({
    required String userId,
    required String seriesId,
  }) async {
    try {
      _apiLog('getSeasons: userId=$userId, seriesId=$seriesId');

      // ✅ 先获取Series的详细信息（包括名称）
      final seriesInfo = await getItem(userId, seriesId);
      final seriesName = seriesInfo.name;

      // ✅ 获取正常季列表
      final res = await _dio.get('/Shows/$seriesId/Seasons', queryParameters: {
        'UserId': userId,
        'Fields':
            'PrimaryImageAspectRatio,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,UserData',
      });
      _apiLog('getSeasons response: ${res.data}');

      if (res.data is! Map<String, dynamic>) {
        _apiLog('getSeasons: Response is not a Map');
        return [];
      }

      final items = res.data['Items'];
      if (items == null) {
        _apiLog('getSeasons: No Items field in response');
        return [];
      }

      if (items is! List) {
        _apiLog('getSeasons: Items is not a List');
        return [];
      }

      final list = items.cast<Map<String, dynamic>>();
      _apiLog('getSeasons: Found ${list.length} seasons');

      // ✅ 统一格式化所有季的名称为"第x季"格式（无空格）
      final seasons = list.map((e) {
        final seasonItem = ItemInfo.fromJson(e);
        final originalName = seasonItem.name.trim();
        int? seasonNumber;

        // ✅ 优先从名称中提取数字（更准确）
        // 支持格式：第x季、第 x 季、季 x、季x、Season x、Sx等
        // ⚠️ 只提取阿拉伯数字，不提取中文数字（一二三）
        final seasonNamePatterns = [
          RegExp(r'第\s*(\d+)\s*季'), // 第1季、第 1 季（只匹配阿拉伯数字）
          RegExp(r'季\s*(\d+)', caseSensitive: false), // 季 1、季1（只匹配阿拉伯数字）
          RegExp(r'Season\s*(\d+)', caseSensitive: false), // Season 1（只匹配阿拉伯数字）
          RegExp(r'\bS(\d+)\b', caseSensitive: false), // S1、S01（只匹配阿拉伯数字）
        ];

        for (final pattern in seasonNamePatterns) {
          final match = pattern.firstMatch(originalName);
          if (match != null) {
            // ✅ 确保提取的是阿拉伯数字（\d+只匹配0-9）
            final numStr = match.group(1)!;
            final num = int.tryParse(numStr);
            // ✅ 允许提取 0（S0 特辑）和正数
            if (num != null && num >= 0) {
              seasonNumber = num;
              break;
            }
          }
        }

        // ✅ 如果从名称中无法提取，且parentIndexNumber有效，使用parentIndexNumber
        // ⚠️ 但只有当名称看起来像季名称时才使用（避免"三叉戟"这样的名称被误格式化）
        // ✅ 允许 parentIndexNumber 为 0（特辑）
        if (seasonNumber == null &&
            seasonItem.parentIndexNumber != null &&
            seasonItem.parentIndexNumber! >= 0) {
          // ✅ 检查名称是否包含季相关的关键词（必须包含）
          final hasSeasonKeyword =
              RegExp(r'(季|Season|S\d+)', caseSensitive: false)
                  .hasMatch(originalName);
          // ✅ 或者名称本身就是纯数字（如"0"、"1"、"2"等）
          final isPureNumber = RegExp(r'^\d+$').hasMatch(originalName);
          if (hasSeasonKeyword || isPureNumber) {
            seasonNumber = seasonItem.parentIndexNumber;
          }
        }

        // ✅ 格式化名称为"第x季"或"特辑"（无空格）
        // ⚠️ 只有当成功提取到数字时才格式化，否则保持原名
        final formattedSeasonName = seasonNumber != null
            ? (seasonNumber == 0 ? '特辑' : '第$seasonNumber季')
            : originalName; // 如果无法提取数字，保持原名

        // ✅ 如果名称有变化，创建新的ItemInfo
        if (formattedSeasonName != originalName ||
            seasonNumber != seasonItem.parentIndexNumber) {
          return ItemInfo(
            id: seasonItem.id,
            name: formattedSeasonName,
            type: seasonItem.type,
            overview: seasonItem.overview,
            runTimeTicks: seasonItem.runTimeTicks,
            userData: seasonItem.userData,
            seriesName: seasonItem.seriesName,
            parentIndexNumber: seasonNumber ?? seasonItem.parentIndexNumber,
            indexNumber: seasonItem.indexNumber,
            seriesId: seasonItem.seriesId,
            seasonId: seasonItem.seasonId,
            seriesPrimaryImageTag: seasonItem.seriesPrimaryImageTag,
            seasonPrimaryImageTag: seasonItem.seasonPrimaryImageTag,
            imageTags: seasonItem.imageTags,
            backdropImageTags: seasonItem.backdropImageTags,
            parentThumbItemId: seasonItem.parentThumbItemId,
            parentThumbImageTag: seasonItem.parentThumbImageTag,
            parentBackdropItemId: seasonItem.parentBackdropItemId,
            parentBackdropImageTags: seasonItem.parentBackdropImageTags,
            genres: seasonItem.genres,
            mediaSources: seasonItem.mediaSources,
            performers: seasonItem.performers,
            externalUrls: seasonItem.externalUrls,
            premiereDate: seasonItem.premiereDate,
            endDate: seasonItem.endDate,
            productionYear: seasonItem.productionYear,
            communityRating: seasonItem.communityRating,
            childCount: seasonItem.childCount,
            providerIds: seasonItem.providerIds,
            dateCreated: seasonItem.dateCreated,
            status: seasonItem.status,
          );
        }

        return seasonItem;
      }).toList();

      // ✅ 尝试补充被识别为独立Series但应该是季的项目
      try {
        // ✅ 获取Series的ParentId（从Series信息中获取）
        final seriesDetailRes =
            await _dio.get('/Users/$userId/Items/$seriesId', queryParameters: {
          'Fields': 'ParentId',
        });
        final seriesParentId = seriesDetailRes.data['ParentId'] as String?;

        if (seriesParentId != null) {
          // ✅ 获取同一个ParentId下的所有Series
          final allSeriesRes =
              await _dio.get('/Users/$userId/Items', queryParameters: {
            'ParentId': seriesParentId,
            'IncludeItemTypes': 'Series',
            'Recursive': true,
            'Fields':
                'PrimaryImageAspectRatio,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,UserData',
          });

          final allSeriesList = (allSeriesRes.data['Items'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];

          // ✅ 查找应该是这个Series的季的项目
          for (final seriesJson in allSeriesList) {
            final name = seriesJson['Name'] as String? ?? '';
            final id = seriesJson['Id'] as String? ?? '';

            // ✅ 跳过当前Series本身
            if (id == seriesId) continue;

            // ✅ 检查名称是否匹配"Series名称 + 数字"的模式
            final baseName = _extractBaseSeriesName(name);
            if (baseName == seriesName && name != seriesName) {
              // ✅ 这是一个应该作为季的Series

              // ✅ 检查是否已经在季列表中
              final alreadyInSeasons = seasons.any((season) => season.id == id);
              if (!alreadyInSeasons) {
                // ✅ 提取季数字（从名称中提取，如"地球脉动 3" -> "3"）
                // 只匹配"名称 + 空格 + 数字"的模式，避免误匹配
                final regex = RegExp(r'^(.+?)\s+(\d+)$');
                final match = regex.firstMatch(name.trim());
                final seasonNumberStr = match?.group(2);
                int? seasonNumber;

                if (seasonNumberStr != null) {
                  seasonNumber = int.tryParse(seasonNumberStr);
                  // ✅ 验证数字合理性（0-100之间，0表示特辑）
                  if (seasonNumber != null &&
                      (seasonNumber < 0 || seasonNumber > 100)) {
                    seasonNumber = null;
                  }
                }

                // ✅ 创建ItemInfo并修改名称为"第X季"或"特辑"格式
                final seasonItem = ItemInfo.fromJson(seriesJson);
                final formattedSeasonName = seasonNumber != null
                    ? (seasonNumber == 0 ? '特辑' : '第$seasonNumber季')
                    : name;

                // ✅ 确保UserData存在，如果不存在则创建
                Map<String, dynamic>? userData = seasonItem.userData;
                if (userData == null) {
                  userData = {};
                }

                // ✅ 如果UserData中没有UnplayedItemCount或为0，尝试从该Series的所有集中计算
                final unplayedCount =
                    (userData['UnplayedItemCount'] as num?)?.toInt() ?? 0;
                if (unplayedCount == 0) {
                  try {
                    // ✅ 获取该Series的所有集来计算未观看集数
                    final episodesRes =
                        await _dio.get('/Shows/$id/Episodes', queryParameters: {
                      'UserId': userId,
                      'Fields': 'UserData',
                    });
                    if (episodesRes.data is Map<String, dynamic>) {
                      final episodes = episodesRes.data['Items'] as List?;
                      if (episodes != null) {
                        int calculatedUnplayed = 0;
                        for (final episode in episodes) {
                          final episodeUserData =
                              episode['UserData'] as Map<String, dynamic>?;
                          if (episodeUserData != null) {
                            final played =
                                episodeUserData['Played'] as bool? ?? false;
                            if (!played) {
                              calculatedUnplayed++;
                            }
                          }
                        }
                        if (calculatedUnplayed > 0) {
                          userData = Map<String, dynamic>.from(userData);
                          userData['UnplayedItemCount'] = calculatedUnplayed;
                        }
                      }
                    }
                  } catch (e) {
                    // ✅ 如果计算失败，使用原有的UserData
                    _apiLog(
                        'getSeasons: Failed to calculate UnplayedItemCount for $id: $e');
                  }
                }

                // ✅ 创建一个新的ItemInfo，使用格式化后的名称和更新后的UserData
                final modifiedSeasonItem = ItemInfo(
                  id: seasonItem.id,
                  name: formattedSeasonName,
                  type: seasonItem.type,
                  overview: seasonItem.overview,
                  runTimeTicks: seasonItem.runTimeTicks,
                  userData: userData,
                  seriesName: seasonItem.seriesName,
                  parentIndexNumber: seasonNumber,
                  indexNumber: seasonItem.indexNumber,
                  seriesId: seasonItem.seriesId,
                  seasonId: seasonItem.seasonId,
                  seriesPrimaryImageTag: seasonItem.seriesPrimaryImageTag,
                  seasonPrimaryImageTag: seasonItem.seasonPrimaryImageTag,
                  imageTags: seasonItem.imageTags,
                  backdropImageTags: seasonItem.backdropImageTags,
                  parentThumbItemId: seasonItem.parentThumbItemId,
                  parentThumbImageTag: seasonItem.parentThumbImageTag,
                  parentBackdropItemId: seasonItem.parentBackdropItemId,
                  parentBackdropImageTags: seasonItem.parentBackdropImageTags,
                  genres: seasonItem.genres,
                  mediaSources: seasonItem.mediaSources,
                  performers: seasonItem.performers,
                  externalUrls: seasonItem.externalUrls,
                  premiereDate: seasonItem.premiereDate,
                  endDate: seasonItem.endDate,
                  productionYear: seasonItem.productionYear,
                  communityRating: seasonItem.communityRating,
                  childCount: seasonItem.childCount,
                  providerIds: seasonItem.providerIds,
                  dateCreated: seasonItem.dateCreated,
                  status: seasonItem.status,
                );

                seasons.add(modifiedSeasonItem);
              }
            }
          }
        }
      } catch (e) {
        // ✅ 如果补充失败，不影响正常返回
        _apiLog('getSeasons: Failed to supplement seasons: $e');
      }

      return seasons;
    } catch (e, stack) {
      _apiLog('getSeasons error: $e');
      _apiLog('Stack trace: $stack');
      rethrow;
    }
  }

  // 获取某一季的所有集
  Future<List<ItemInfo>> getEpisodes({
    required String userId,
    required String seriesId,
    required String seasonId,
  }) async {
    try {
      _apiLog(
          'getEpisodes: userId=$userId, seriesId=$seriesId, seasonId=$seasonId');

      // ✅ 先检查seasonId是否实际上是一个Series（被误识别为独立Series的季）
      try {
        final seasonItemRes =
            await _dio.get('/Users/$userId/Items/$seasonId', queryParameters: {
          'Fields': 'Type',
        });
        final seasonType = seasonItemRes.data['Type'] as String?;

        // ✅ 如果seasonId是一个Series类型，使用不同的API获取集信息
        if (seasonType == 'Series') {
          // ✅ 使用seasonId作为seriesId来获取集（因为这个"季"实际上是一个独立的Series）
          final res =
              await _dio.get('/Shows/$seasonId/Episodes', queryParameters: {
            'UserId': userId,
            'Fields':
                'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds',
          });
          _apiLog('getEpisodes (Series mode) response: ${res.data}');

          if (res.data is! Map<String, dynamic>) {
            _apiLog('getEpisodes: Response is not a Map');
            return [];
          }

          final items = res.data['Items'];
          if (items == null) {
            _apiLog('getEpisodes: No Items field in response');
            return [];
          }

          if (items is! List) {
            _apiLog('getEpisodes: Items is not a List');
            return [];
          }

          final list = items.cast<Map<String, dynamic>>();
          _apiLog('getEpisodes: Found ${list.length} episodes');
          return list.map((e) => ItemInfo.fromJson(e)).toList();
        }
      } catch (e) {
        // ✅ 如果检查失败，继续使用原来的逻辑
        _apiLog(
            'getEpisodes: Failed to check season type, using default logic: $e');
      }

      // ✅ 正常的季获取逻辑
      final res = await _dio.get('/Shows/$seriesId/Episodes', queryParameters: {
        'UserId': userId,
        'SeasonId': seasonId,
        'Fields':
            'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,Status,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds',
      });
      _apiLog('getEpisodes response: ${res.data}');

      if (res.data is! Map<String, dynamic>) {
        _apiLog('getEpisodes: Response is not a Map');
        return [];
      }

      final items = res.data['Items'];
      if (items == null) {
        _apiLog('getEpisodes: No Items field in response');
        return [];
      }

      if (items is! List) {
        _apiLog('getEpisodes: Items is not a List');
        return [];
      }

      final list = items.cast<Map<String, dynamic>>();
      _apiLog('getEpisodes: Found ${list.length} episodes');
      return list.map((e) => ItemInfo.fromJson(e)).toList();
    } catch (e, stack) {
      _apiLog('getEpisodes error: $e');
      _apiLog('Stack trace: $stack');
      rethrow;
    }
  }

  Future<ItemInfo> getItem(String userId, String itemId) async {
    final res =
        await _dio.get('/Users/$userId/Items/$itemId', queryParameters: {
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds,Genres,People,ExternalUrls,DateCreated',
    });
    return ItemInfo.fromJson(res.data as Map<String, dynamic>);
  }

  String buildImageUrl({
    required String itemId,
    String type = 'Primary',
    int maxWidth = 400,
    int? imageIndex,
    String? tag,
  }) {
    final buffer =
        StringBuffer('${_dio.options.baseUrl}/Items/$itemId/Images/$type');
    if (imageIndex != null) {
      buffer.write('/$imageIndex');
    }

    final params = <String, String>{};
    if (maxWidth > 0) {
      params['maxWidth'] = maxWidth.toString();
    }
    if (tag != null && tag.isNotEmpty) {
      params['tag'] = tag;
    }

    if (params.isEmpty) {
      return buffer.toString();
    }

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '${buffer.toString()}?$query';
  }

  // ✅ 获取用户头像URL
  String buildUserImageUrl(String userId) {
    return _dio.options.baseUrl + '/Users/$userId/Images/Primary';
  }

  // ✅ 获取类型列表（返回完整信息，包括图片）
  Future<List<GenreInfo>> getGenres({
    required String userId,
    String? parentId,
    String? includeItemTypes,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'Fields':
            'BasicSyncInfo,CanDelete,CanDownload,PrimaryImageAspectRatio,ImageTags',
        'StartIndex': 0,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
        'ImageTypeLimit': 1,
        'Recursive': true
      };

      if (parentId != null && parentId.isNotEmpty) {
        queryParams['ParentId'] = parentId;
      }
      if (includeItemTypes != null && includeItemTypes.isNotEmpty) {
        queryParams['IncludeItemTypes'] = includeItemTypes;
      }

      // ✅ 使用 /Genres 路径
      final res = await _dio.get('/Genres', queryParameters: queryParams);

      _apiLog('✅ [API] Get Genres response: ${res.data}');

      // Genres API 返回的可能是一个数组，每个元素包含 Name 字段
      // 或者可能是一个包含 Items 字段的对象
      List<Map<String, dynamic>> items = [];
      if (res.data is List) {
        items = (res.data as List).cast<Map<String, dynamic>>();
      } else if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        if (data['Items'] != null) {
          items = (data['Items'] as List).cast<Map<String, dynamic>>();
        }
      }

      final genres = items.map((e) => GenreInfo.fromJson(e)).where((genre) {
        // ✅ 基本过滤：必须有名称和ID
        if (genre.name.isEmpty || genre.id.isEmpty) {
          return false;
        }
        // ✅ 通过ImageTags判断是否有详情：如果ImageTags为空或null，则排除
        if (genre.imageTags == null || genre.imageTags!.isEmpty) {
          return false;
        }
        return true;
      }).toList();

      _apiLog('✅ [API] Get Genres parsed: ${genres.length} genres');
      return genres;
    } catch (e, stack) {
      _apiLog('❌ [API] Get Genres failed: $e');
      _apiLog('❌ [API] Stack trace: $stack');
      return [];
    }
  }

  // ✅ 获取播放信息（PlaybackInfo），包含正确的字幕流信息
  Future<Map<String, dynamic>> getPlaybackInfo({
    required String itemId,
    required String userId,
  }) async {
    try {
      final res =
          await _dio.get('/Items/$itemId/PlaybackInfo', queryParameters: {
        'UserId': userId,
        'StartTimeTicks': '0', // ✅ 添加开始时间参数
        'IsPlayback': 'true', // ✅ 标记为播放请求
        'AutoOpenLiveStream': 'true', // ✅ 自动打开直播流
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      _apiLog('❌ [API] Get PlaybackInfo failed: $e');
      rethrow;
    }
  }

  // ✅ 获取字幕URL（尝试多种格式以兼容不同的 Emby 版本）
  Future<List<String>> buildSubtitleUrls({
    required String itemId,
    required int subtitleStreamIndex,
    String? mediaSourceId,
    String format = 'vtt', // vtt, srt, ass, ssa
  }) async {
    final prefs = await sp.SharedPreferences.getInstance();
    final token = prefs.getString('emby_token') ?? '';
    final baseUrl = _dio.options.baseUrl;

    final urls = <String>[];

    // ✅ 格式1: /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{format}
    // 这是最标准的格式，mediaSourceId 作为路径的一部分
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      urls.add(
          '$baseUrl/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleStreamIndex/Stream.$format?api_key=$token');
    }

    // ✅ 格式2: /Videos/{itemId}/Subtitles/{index}/Stream.{format} (不带 MediaSourceId)
    // 适用于 mediaSourceId 等于 itemId 的情况
    urls.add(
        '$baseUrl/Videos/$itemId/Subtitles/$subtitleStreamIndex/Stream.$format?api_key=$token');

    // ✅ 格式3: /Videos/{itemId}/Subtitles/{index}/Stream.{format}?MediaSourceId={mediaSourceId}
    // MediaSourceId 作为查询参数
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      urls.add(
          '$baseUrl/Videos/$itemId/Subtitles/$subtitleStreamIndex/Stream.$format?MediaSourceId=$mediaSourceId&api_key=$token');
    }

    // ✅ 格式4: /Items/{itemId}/Subtitles/{index}/Stream.{format}
    // Items 端点（备用方案）
    urls.add(
        '$baseUrl/Items/$itemId/Subtitles/$subtitleStreamIndex/Stream.$format?api_key=$token');

    // ✅ 格式5: /Items/{itemId}/Subtitles/{index}/Stream.{format}?MediaSourceId={mediaSourceId}
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      urls.add(
          '$baseUrl/Items/$itemId/Subtitles/$subtitleStreamIndex/Stream.$format?MediaSourceId=$mediaSourceId&api_key=$token');
    }

    return urls;
  }

  // Prefer HLS master for adaptive bitrate
  Future<MediaSourceUrl> buildHlsUrl(
    String itemId, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    // ✅ 从 SharedPreferences 获取 token（因为 dio headers 是在拦截器中动态设置的）
    final prefs = await sp.SharedPreferences.getInstance();
    final token = prefs.getString('emby_token') ?? '';
    final userId = prefs.getString('emby_user_id') ?? '';

    if (userId.isEmpty) {
      throw Exception('User ID is empty');
    }

    // ✅ 先获取 item 信息（包含 MediaSources）
    final res =
        await _dio.get('/Users/$userId/Items/$itemId', queryParameters: {
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,Status,ProductionYear,CommunityRating,ChildCount,ProviderIds',
    });
    final itemJson = res.data as Map<String, dynamic>;

    // ✅ 从 MediaSources 获取第一个可用的 MediaSourceId
    String mediaSourceId = itemId; // 默认使用 itemId
    int? mediaWidth;
    int? mediaHeight;
    int? mediaBitrate;
    Duration? mediaDuration;
    if (itemJson['MediaSources'] != null && itemJson['MediaSources'] is List) {
      final mediaSources = itemJson['MediaSources'] as List;
      if (mediaSources.isNotEmpty) {
        final firstSource = mediaSources[0] as Map<String, dynamic>;
        mediaSourceId = firstSource['Id'] as String? ?? itemId;
        mediaWidth = (firstSource['Width'] as num?)?.toInt();
        mediaHeight = (firstSource['Height'] as num?)?.toInt();
        mediaBitrate = (firstSource['Bitrate'] as num?)?.toInt();
        final runTimeTicks = (firstSource['RunTimeTicks'] as num?)?.toInt();
        if (runTimeTicks != null && runTimeTicks > 0) {
          mediaDuration = Duration(microseconds: (runTimeTicks / 10).round());
        }
      }
    }

    // ✅ 只使用 HLS master 流（支持自适应码率）
    String? uri;
    String? playSessionId;
    try {
      // ✅ 获取 PlaybackInfo 以获取 PlaySessionId
      final playbackInfo = await getPlaybackInfo(
        itemId: itemId,
        userId: userId,
      );
      // ✅ 从 PlaybackInfo 获取 PlaySessionId
      playSessionId = playbackInfo['PlaySessionId'] as String?;
      if (playSessionId == null || playSessionId.isEmpty) {
        playSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (e) {
      _apiLog('⚠️ [API] Failed to get PlaybackInfo: $e');
      playSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // ✅ 使用 HLS master 流（支持自适应码率）
    // 添加音频和字幕流选择参数
    final queryParams = <String, String>{
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'api_key': token,
      // ✅ 强制音频转码参数，确保 AC3/DTS/TrueHD 等格式能正常播放
      'AudioCodec': 'aac',  // 转码为 AAC（所有设备都支持）
      'TranscodingMaxAudioChannels': '2',  // 转为立体声（避免多声道问题）
      'EnableAutoStreamCopy': 'false',  // 禁用直接复制，强制转码
    };

    // ✅ 添加音频流索引（如果指定）
    if (audioStreamIndex != null && audioStreamIndex >= 0) {
      queryParams['AudioStreamIndex'] = audioStreamIndex.toString();
    }

    // ✅ 添加字幕流索引（如果指定且不是-1）
    if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
      queryParams['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
    }

    // ✅ 构建完整的 URL
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    uri = '${_dio.options.baseUrl}/Videos/$itemId/master.m3u8?$queryString';

    // ✅ 根据 Emby 要求：
    // - 使用 DirectStreamUrl 或 HLS 时，token 必须作为 api_key 参数在 URL 里
    // - 播放本地文件时，token 必须在 Header 里用 X-Emby-Token
    // 对于 HLS 流，即使 token 在 URL 中，也可能需要在 Header 中添加（某些 Emby 版本要求）
    final headers = <String, String>{
      // ✅ 对于 HLS 流，同时添加 Header 中的 token（某些 Emby 版本可能需要）
      if (uri.contains('.m3u8')) 'X-Emby-Token': token,
      // ✅ 如果 URL 中没有 token，则在 Header 中添加（本地文件场景）
      if (!uri.contains('api_key=')) 'X-Emby-Token': token,
    };
    return MediaSourceUrl(
      uri: uri,
      headers: headers,
      bitrate: mediaBitrate,
      width: mediaWidth,
      height: mediaHeight,
      duration: mediaDuration,
      playSessionId: playSessionId, // ✅ 返回 PlaySessionId，用于调用 /Sessions/Playing
    );
  }

  // ✅ 通知 Emby 服务器开始播放（必须调用此 API 才能记录播放历史）
  Future<void> reportPlaybackStart({
    required String itemId,
    required String userId,
    required String playSessionId,
    String? mediaSourceId,
    int? positionTicks,
  }) async {
    try {
      final payload = <String, dynamic>{
        'ItemId': itemId,
        'PlaySessionId': playSessionId,
        'Command': 'Play',
        'PositionTicks': positionTicks ?? 0,
      };
      if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
        payload['MediaSourceId'] = mediaSourceId;
      }

      await _dio.post('/Sessions/Playing', data: payload);
    } catch (e) {
      _apiLog('⚠️ [API] Failed to report playback start: $e');
      // ✅ 不抛出异常，避免影响播放
    }
  }

  // ✅ 通知 Emby 服务器播放进度更新
  Future<void> reportPlaybackProgress({
    required String itemId,
    required String userId,
    required String playSessionId,
    String? mediaSourceId,
    required int positionTicks,
    bool isPaused = false,
  }) async {
    try {
      final payload = <String, dynamic>{
        'ItemId': itemId,
        'PlaySessionId': playSessionId,
        'PositionTicks': positionTicks,
        'IsPaused': isPaused,
      };
      if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
        payload['MediaSourceId'] = mediaSourceId;
      }

      await _dio.post('/Sessions/Playing/Progress', data: payload);
    } catch (e) {
      _apiLog('⚠️ [API] Failed to report playback progress: $e');
      // ✅ 不抛出异常，避免影响播放
    }
  }

  // ✅ 通知 Emby 服务器停止播放
  Future<void> reportPlaybackStopped({
    required String itemId,
    required String userId,
    required String playSessionId,
    String? mediaSourceId,
    int? positionTicks,
  }) async {
    try {
      final payload = <String, dynamic>{
        'ItemId': itemId,
        'PlaySessionId': playSessionId,
        'Command': 'Stop',
      };
      if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
        payload['MediaSourceId'] = mediaSourceId;
      }
      if (positionTicks != null && positionTicks > 0) {
        payload['PositionTicks'] = positionTicks;
      }

      // ✅ 使用 POST 方法调用 /Sessions/Playing/Stopped（停止播放的专用端点）
      await _dio.post('/Sessions/Playing/Stopped', data: payload);
    } catch (e) {
      // ✅ 如果 /Sessions/Playing/Stopped 失败，尝试使用 /Sessions/Playing
      try {
        final payload = <String, dynamic>{
          'ItemId': itemId,
          'PlaySessionId': playSessionId,
          'Command': 'Stop',
        };
        if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
          payload['MediaSourceId'] = mediaSourceId;
        }
        if (positionTicks != null && positionTicks > 0) {
          payload['PositionTicks'] = positionTicks;
        }
        await _dio.post('/Sessions/Playing', data: payload);
      } catch (e2) {
        _apiLog('⚠️ [API] Failed to report playback stopped: $e2');
      }
    }
  }

  Future<void> updateUserItemData(
    String userId,
    String itemId, {
    Duration? position,
    bool? played,
  }) async {
    final payload = <String, dynamic>{};
    if (position != null) {
      final ticks = position.inMicroseconds * 10;
      final clamped = ticks < 0 ? 0 : ticks.clamp(0, 0x7FFFFFFFFFFFFFFF);
      payload['PlaybackPositionTicks'] = clamped.toInt();
    }
    if (played != null) {
      payload['Played'] = played;
    }
    if (payload.isEmpty) {
      return;
    }
    try {
      await _dio.post('/Users/$userId/Items/$itemId/UserData', data: payload);
    } catch (e) {
      _apiLog('updateUserItemData error: $e');
    }
  }

  /// 添加收藏
  Future<void> addFavoriteItem(String userId, String itemId) async {
    final path = '/Users/$userId/FavoriteItems/$itemId';
    try {
      await _dio.post(path);
    } catch (e) {
      _apiLog('addFavoriteItem error: $e');
      rethrow;
    }
  }

  /// 取消收藏
  Future<void> removeFavoriteItem(String userId, String itemId) async {
    final path = '/Users/$userId/FavoriteItems/$itemId/Delete';
    try {
      await _dio.post(path);
    } catch (e) {
      _apiLog('removeFavoriteItem error: $e');
      rethrow;
    }
  }

  /// 标记为已观看
  Future<void> markAsPlayed(String userId, String itemId) async {
    final path = '/Users/$userId/PlayedItems/$itemId';
    try {
      await _dio.post(path);
    } catch (e) {
      _apiLog('markAsPlayed error: $e');
      rethrow;
    }
  }

  /// 取消已观看标记
  Future<void> unmarkAsPlayed(String userId, String itemId) async {
    final path = '/Users/$userId/PlayedItems/$itemId/Delete';
    try {
      await _dio.post(path);
    } catch (e) {
      _apiLog('unmarkAsPlayed error: $e');
      rethrow;
    }
  }
}

class LoginResult {
  LoginResult(
      {required this.token, required this.userId, required this.userName});
  final String token;
  final String userId;
  final String userName;
}

class ViewInfo {
  ViewInfo(
      {required this.id, required this.name, required this.collectionType});
  final String? id;
  final String name;
  final String? collectionType;

  factory ViewInfo.fromJson(Map<String, dynamic> json) {
    final id = json['Id'] as String?;
    final name = json['Name'] as String? ?? 'Unknown';
    final collectionType = json['CollectionType'] as String?;

    _apiLog('ViewInfo.fromJson: id=$id, name=$name, type=$collectionType');

    return ViewInfo(
      id: id,
      name: name,
      collectionType: collectionType,
    );
  }
}

// ✅ 类型信息类
class GenreInfo {
  final String id;
  final String name;
  final Map<String, String>? imageTags;

  GenreInfo({
    required this.id,
    required this.name,
    this.imageTags,
  });

  factory GenreInfo.fromJson(Map<String, dynamic> json) {
    return GenreInfo(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      imageTags: (json['ImageTags'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
    );
  }
}

class ItemInfo {
  ItemInfo({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.runTimeTicks,
    this.userData,
    this.seriesName,
    this.parentIndexNumber,
    this.indexNumber,
    this.seriesId,
    this.seasonId,
    this.seriesPrimaryImageTag,
    this.seasonPrimaryImageTag,
    this.imageTags,
    this.backdropImageTags,
    this.parentThumbItemId,
    this.parentThumbImageTag,
    this.parentBackdropItemId,
    this.parentBackdropImageTags,
    this.genres,
    this.mediaSources,
    this.performers,
    this.externalUrls,
    this.premiereDate,
    this.endDate,
    this.productionYear,
    this.communityRating,
    this.childCount,
    this.providerIds,
    this.dateCreated,
    this.status,
  });

  final String? id;
  final String name;
  final String type;
  final String? overview;
  final int? runTimeTicks;
  final Map<String, dynamic>? userData;
  final String? seriesName;
  final int? parentIndexNumber;
  final int? indexNumber;
  final String? seriesId;
  final String? seasonId;
  final String? seriesPrimaryImageTag;
  final String? seasonPrimaryImageTag;
  final Map<String, String>? imageTags;
  final List<String>? backdropImageTags;
  final String? parentThumbItemId;
  final String? parentThumbImageTag;
  final String? parentBackdropItemId;
  final List<String>? parentBackdropImageTags;
  final List<String>? genres;
  final List<Map<String, dynamic>>? mediaSources;
  final List<PerformerInfo>? performers;
  final String? premiereDate;
  final String? endDate;
  final int? productionYear;
  final double? communityRating; // 评分（IMDb等）
  final int? childCount; // 子项目数量（剧集的总集数）
  final Map<String, dynamic>? providerIds; // 第三方ID（包含豆瓣）
  final String? dateCreated;
  final String? status; // Series状态：Ended, Canceled, In Production, Continuing
  final List<ExternalUrlInfo>? externalUrls;

  // 获取评分和来源
  double? getRating() {
    // 优先使用豆瓣评分
    if (providerIds != null && providerIds!['Douban'] != null) {
      final doubanRating = double.tryParse(providerIds!['Douban'].toString());
      if (doubanRating != null) return doubanRating;
    }
    // 没有豆瓣评分则使用社区评分
    return communityRating;
  }

  String getRatingSource() {
    if (providerIds != null && providerIds!['Douban'] != null) {
      return 'douban';
    }
    return 'community';
  }

  factory ItemInfo.fromJson(Map<String, dynamic> json) {
    return ItemInfo(
      id: json['Id'] as String?,
      name: json['Name'] as String? ?? 'Unknown',
      type: json['Type'] as String? ?? 'Unknown',
      overview: json['Overview'] as String?,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      userData: json['UserData'] as Map<String, dynamic>?,
      seriesName: json['SeriesName'] as String?,
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      seriesId: json['SeriesId'] as String?,
      seasonId: json['SeasonId'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
      seasonPrimaryImageTag: json['SeasonPrimaryImageTag'] as String?,
      imageTags: (json['ImageTags'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
      backdropImageTags: (json['BackdropImageTags'] as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((element) => element.isNotEmpty)
          .toList(),
      parentThumbItemId: json['ParentThumbItemId'] as String?,
      parentThumbImageTag: json['ParentThumbImageTag'] as String?,
      parentBackdropItemId: json['ParentBackdropItemId'] as String?,
      parentBackdropImageTags: (json['ParentBackdropImageTags'] as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((element) => element.isNotEmpty)
          .toList(),
      genres: (json['Genres'] as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((element) => element.isNotEmpty)
          .toList(),
      mediaSources: (json['MediaSources'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      performers: (json['People'] as List?)
          ?.where((element) => element is Map)
          .map((element) =>
              PerformerInfo.fromJson(Map<String, dynamic>.from(element as Map)))
          .toList(),
      externalUrls: (json['ExternalUrls'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(ExternalUrlInfo.fromJson)
          .where((e) => e.isValid)
          .toList(),
      premiereDate: json['PremiereDate'] as String?,
      endDate: json['EndDate'] as String?,
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      childCount: (json['ChildCount'] as num?)?.toInt(),
      providerIds: json['ProviderIds'] as Map<String, dynamic>?,
      dateCreated: json['DateCreated'] as String?,
      status: json['Status'] as String?,
    );
  }
}

class MediaSourceUrl {
  MediaSourceUrl({
    required this.uri,
    required this.headers,
    this.bitrate,
    this.width,
    this.height,
    this.duration,
    this.playSessionId,
  });
  final String uri;
  final Map<String, String> headers;
  final int? bitrate;
  final int? width;
  final int? height;
  final Duration? duration;
  final String? playSessionId; // ✅ PlaySessionId，用于调用 /Sessions/Playing
}

class ExternalUrlInfo {
  ExternalUrlInfo({required this.name, required this.url});

  final String name;
  final String url;

  factory ExternalUrlInfo.fromJson(Map<String, dynamic> map) {
    return ExternalUrlInfo(
      name: map['Name']?.toString() ?? '',
      url: map['Url']?.toString() ?? '',
    );
  }

  bool get isValid => name.isNotEmpty && url.isNotEmpty;
}

class PerformerInfo {
  PerformerInfo({
    required this.id,
    required this.name,
    this.role,
    this.primaryImageTag,
    this.raw,
  });

  final String id;
  final String name;
  final String? role;
  final String? primaryImageTag;
  final Map<String, dynamic>? raw;

  factory PerformerInfo.fromJson(Map<String, dynamic> map) {
    return PerformerInfo(
      id: map['Id']?.toString() ?? '',
      name: map['Name']?.toString() ?? '',
      role: map['Role']?.toString(),
      primaryImageTag: map['PrimaryImageTag']?.toString(),
      raw: map,
    );
  }
}
