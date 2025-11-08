import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emby_api.dart';

/// 全局 EmbyApi 实例，避免滚动列表频繁创建对象导致卡顿
final embyApiProvider = FutureProvider<EmbyApi>((ref) async {
  return EmbyApi.create();
});

