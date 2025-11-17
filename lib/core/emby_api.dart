import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:shared_preferences/shared_preferences.dart' as sp;

const bool _kEmbyApiLogging = false;
void _apiLog(String message) {
  if (_kEmbyApiLogging) {}
}

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
        connectTimeout: const Duration(seconds: 30), // 增加到30秒
        receiveTimeout: const Duration(seconds: 60), // 增加到60秒
        sendTimeout: const Duration(seconds: 60))); // 增加发送超时

    // 添加请求头拦截器
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
        return list.map((e) => ItemInfo.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _apiLog('getLatestItems error: $e');
      return [];
    }
  }

  Future<List<ItemInfo>> getItemsByParent(
      {required String userId,
      required String parentId,
      int startIndex = 0,
      int limit = 60,
      String? includeItemTypes}) async {
    final queryParams = {
      'ParentId': parentId,
      'StartIndex': startIndex,
      'Limit': limit,
      'Recursive': true,
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds,SeriesId,SeasonId,ParentThumbItemId,ParentThumbImageTag,ParentBackdropItemId,ParentBackdropImageTags,ImageTags,BackdropImageTags,SeriesPrimaryImageTag,SeasonPrimaryImageTag',
    };

    // 如果指定了类型，使用指定的；否则使用默认的
    if (includeItemTypes != null) {
      queryParams['IncludeItemTypes'] = includeItemTypes;
    } else {
      queryParams['IncludeItemTypes'] = 'Movie,Series,BoxSet,Video';
    }

    final res =
        await _dio.get('/Users/$userId/Items', queryParameters: queryParams);
    final list = (res.data['Items'] as List).cast<Map<String, dynamic>>();
    return list.map((e) => ItemInfo.fromJson(e)).toList();
  }

  Future<List<ItemInfo>> getSimilarItems(String userId, String itemId,
      {int limit = 12}) async {
    final baseParams = {
      'Limit': limit,
      'IncludeItemTypes': 'Movie,Series,Video',
      'Fields':
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds,Genres',
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
              'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds,Genres',
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
      final res = await _dio.get('/Shows/$seriesId/Seasons', queryParameters: {
        'UserId': userId,
        'Fields':
            'PrimaryImageAspectRatio,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds',
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
      return list.map((e) => ItemInfo.fromJson(e)).toList();
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
      final res = await _dio.get('/Shows/$seriesId/Episodes', queryParameters: {
        'UserId': userId,
        'SeasonId': seasonId,
        'Fields':
            'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds',
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
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds,Genres,People,ExternalUrls,DateCreated',
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

  // ✅ 获取字幕URL
  Future<String> buildSubtitleUrl({
    required String itemId,
    required int subtitleStreamIndex,
    String format = 'vtt', // vtt, srt, ass, ssa
  }) async {
    final prefs = await sp.SharedPreferences.getInstance();
    final token = prefs.getString('emby_token') ?? '';
    final baseUrl = _dio.options.baseUrl;

    // Emby API 字幕URL格式: /Videos/{itemId}/Subtitles/{subtitleStreamIndex}/Stream.{format}
    final url =
        '$baseUrl/Videos/$itemId/Subtitles/$subtitleStreamIndex/Stream.$format?api_key=$token';
    return url;
  }

  // Prefer HLS master for adaptive bitrate
  Future<MediaSourceUrl> buildHlsUrl(String itemId) async {
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
          'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,Overview,PremiereDate,EndDate,ProductionYear,CommunityRating,ChildCount,ProviderIds',
    });
    final itemJson = res.data as Map<String, dynamic>;
    final item = ItemInfo.fromJson(itemJson);
    _apiLog('🎬 [API] Item: ${item.name}, Type: ${item.type}');

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
        _apiLog('🎬 [API] MediaSourceId: $mediaSourceId');
      }
    }

    // ✅ 尝试使用最简单的直接下载 URL（最兼容的方式）
    final uri =
        _dio.options.baseUrl + '/Items/$itemId/Download' + '?api_key=$token';

    _apiLog('🎬 [API] Trying direct download URL first: $uri');

    // 如果直接下载失败，再尝试 HLS
    // final playSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    // final hlsUri = _dio.options.baseUrl +
    //     '/Videos/$itemId/master.m3u8' +
    //     '?MediaSourceId=$mediaSourceId' +
    //     '&PlaySessionId=$playSessionId' +
    //     '&api_key=$token';

    final headers = <String, String>{
      'X-Emby-Token': token,
    };

    _apiLog('🎬 [API] HLS Master URL: $uri');
    if (token.isNotEmpty) {
      _apiLog(
          '🎬 [API] Token: ${token.substring(0, token.length > 10 ? 10 : token.length)}...');
    } else {
      _apiLog('⚠️ [API] Token is empty!');
    }
    return MediaSourceUrl(
      uri: uri,
      headers: headers,
      bitrate: mediaBitrate,
      width: mediaWidth,
      height: mediaHeight,
      duration: mediaDuration,
    );
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
  });
  final String uri;
  final Map<String, String> headers;
  final int? bitrate;
  final int? width;
  final int? height;
  final Duration? duration;
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
