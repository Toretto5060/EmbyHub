import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'utils/platform_utils.dart';
import 'utils/render_optimization.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 性能优化：在 Debug 模式下禁用日志输出，避免控制台日志导致卡顿
  if (kDebugMode) {
    debugPrint = (String? message, {int? wrapWidth}) {
      // 不输出任何日志，或者只输出关键日志
      // 如果需要查看日志，可以注释掉这一行
    };
  }

  // ✅ 性能优化：启用高刷新率
  await PlatformUtils.requestHighRefreshRate();

  // ✅ 性能优化：设置时间膨胀系数为1.0（确保动画以正常速度运行）
  timeDilation = 1.0;

  // ✅ 性能优化：初始化渲染优化器
  RenderOptimizer.initialize();

  // ✅ 性能优化：设置系统UI模式为沉浸式（减少系统UI重绘）
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );

  runApp(const ProviderScope(child: EmbyApp()));
}
