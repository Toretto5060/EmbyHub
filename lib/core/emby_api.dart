import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:shared_preferences/shared_preferences.dart' as sp;

class EmbyApi {
  EmbyApi(this._dio);

  final dio.Dio _dio;

  static const String _clientName = 'FlutterEmbyClient';
  static const String _clientVersion = '1.0.0';

  static Future<EmbyApi> create() async {
    final prefs = await sp.SharedPreferences.getInstance();
    final protocol = prefs.getString('server_protocol') ?? 'http';
    final host = prefs.getString('server_host') ?? '';
    final port = prefs.getString('server_port') ?? '';
    final baseUrl = _buildBaseUrl(protocol, host, port);
    final dioClient = dio.Dio(dio.BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30)));
    dioClient.interceptors
        .add(dio.InterceptorsWrapper(onRequest: (options, handler) async {
      final token = prefs.getString('emby_token');
      final deviceId = await _ensureDeviceId(prefs);
      final auth =
          'MediaBrowser Client="$_clientName", Device="${Platform.operatingSystem}", DeviceId="$deviceId", Version="$_clientVersion"';
      options.headers['X-Emby-Authorization'] = auth;
      if (token != null && token.isNotEmpty) {
        options.headers['X-Emby-Token'] = token;
      }
      handler.next(options);
    }));
    return EmbyApi(dioClient);
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
    
    // Save account to history
    final protocol = prefs.getString('server_protocol') ?? 'http';
    final host = prefs.getString('server_host') ?? '';
    final port = prefs.getString('server_port') ?? '';
    final serverUrl = _buildBaseUrl(protocol, host, port);
    // Note: This would need to be called from the provider layer
    // For now, we'll handle this in the connect page
    
    return LoginResult(
        token: token,
        userId: user['Id'] as String,
        userName: user['Name'] as String? ?? username);
  }

  Future<List<ViewInfo>> getUserViews(String userId) async {
    try {
      print('getUserViews: userId=$userId');
      final res = await _dio.get('/Users/$userId/Views');
      print('getUserViews response type: ${res.data.runtimeType}');
      print('getUserViews response: ${res.data}');
      
      if (res.data is! Map<String, dynamic>) {
        print('getUserViews: Response is not a Map');
        return [];
      }
      
      final items = res.data['Items'];
      if (items == null) {
        print('getUserViews: No Items field in response');
        return [];
      }
      
      if (items is! List) {
        print('getUserViews: Items is not a List');
        return [];
      }
      
      final list = items.cast<Map<String, dynamic>>();
      print('getUserViews: Found ${list.length} views');
      return list.map((e) => ViewInfo.fromJson(e)).toList();
    } catch (e, stack) {
      print('getUserViews error: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  // Get resume items (continue watching)
  Future<List<ItemInfo>> getResumeItems(String userId, {int limit = 12}) async {
    final res = await _dio.get('/Users/$userId/Items/Resume', queryParameters: {
      'Limit': limit,
      'Recursive': true,
      'Fields': 'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,UserData',
      'ImageTypeLimit': 1,
      'EnableImageTypes': 'Primary,Backdrop,Thumb',
    });
    final list = (res.data['Items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return list.map((e) => ItemInfo.fromJson(e)).toList();
  }

  // Get latest items from a library
  Future<List<ItemInfo>> getLatestItems(String userId, {required String parentId, int limit = 16}) async {
    try {
      print('Fetching latest items for parentId: $parentId, userId: $userId');
      final res = await _dio.get('/Users/$userId/Items/Latest', queryParameters: {
        'ParentId': parentId,
        'Limit': limit,
        'Fields': 'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,UserData',
        'ImageTypeLimit': 1,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
      });
      
      print('Latest API response type: ${res.data.runtimeType}');
      print('Latest API response data: ${res.data}');
      
      // Latest API returns an array directly, not wrapped in Items
      if (res.data is List) {
        final list = (res.data as List).cast<Map<String, dynamic>>();
        print('Found ${list.length} items');
        return list.map((e) => ItemInfo.fromJson(e)).toList();
      }
      print('Response data is not a List');
      return [];
    } catch (e, stack) {
      print('Error fetching latest items for $parentId: $e');
      print('Stack trace: $stack');
      return [];
    }
  }

  Future<List<ItemInfo>> getItemsByParent(
      {required String userId,
      required String parentId,
      int startIndex = 0,
      int limit = 60}) async {
    final res = await _dio.get('/Users/$userId/Items', queryParameters: {
      'ParentId': parentId,
      'StartIndex': startIndex,
      'Limit': limit,
      'Recursive': true,
      'IncludeItemTypes': 'Movie,Series,Episode,BoxSet,Video',
      'Fields': 'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview',
    });
    final list = (res.data['Items'] as List).cast<Map<String, dynamic>>();
    return list.map((e) => ItemInfo.fromJson(e)).toList();
  }

  Future<ItemInfo> getItem(String userId, String itemId) async {
    final res =
        await _dio.get('/Users/$userId/Items/$itemId', queryParameters: {
      'Fields': 'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview',
    });
    return ItemInfo.fromJson(res.data as Map<String, dynamic>);
  }

  String buildImageUrl(
      {required String itemId, String type = 'Primary', int maxWidth = 400}) {
    return _dio.options.baseUrl +
        '/Items/$itemId/Images/$type?maxWidth=$maxWidth';
  }

  // Prefer HLS master for adaptive bitrate
  MediaSourceUrl buildHlsUrl(String itemId) {
    final uri = _dio.options.baseUrl + '/Videos/$itemId/master.m3u8';
    final headers = Map<String, String>.from(
        _dio.options.headers.map((k, v) => MapEntry(k, '$v')));
    return MediaSourceUrl(uri: uri, headers: headers);
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
    
    print('ViewInfo.fromJson: id=$id, name=$name, type=$collectionType');
    
    return ViewInfo(
      id: id,
      name: name,
      collectionType: collectionType,
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
    );
  }
}

class MediaSourceUrl {
  MediaSourceUrl({required this.uri, required this.headers});
  final String uri;
  final Map<String, String> headers;
}
