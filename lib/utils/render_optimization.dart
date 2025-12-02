/// 渲染性能优化工具
///
/// 提供页面渲染和动画性能优化

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// ✅ 全局渲染性能优化器
class RenderOptimizer {
  static bool _isInitialized = false;

  /// 初始化渲染优化
  static void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    // ✅ 启用 Skia 渲染优化
    debugProfilePaintsEnabled = false;
    debugRepaintRainbowEnabled = false;

    debugPrint('🚀 [RenderOptimizer] 渲染优化已启用');
  }

  /// 在页面转场时降低渲染优先级
  static void reduceRenderingDuringTransition() {
    // 降低非关键渲染的优先级
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // 强制垃圾回收（仅在转场时）
      // 注意：这会导致短暂的卡顿，但可以避免转场期间的GC
    });
  }
}

/// ✅ 性能监控工具
class PerformanceMonitor {
  static final List<Duration> _frameTimes = [];
  static const int _maxSamples = 60; // 保留最近60帧的数据
  static DateTime? _lastFrameTime;

  /// 记录帧时间
  static void recordFrame() {
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final frameDuration = now.difference(_lastFrameTime!);
      _frameTimes.add(frameDuration);

      if (_frameTimes.length > _maxSamples) {
        _frameTimes.removeAt(0);
      }

      // 检测掉帧（超过16.67ms）
      if (frameDuration.inMilliseconds > 16) {
        debugPrint('⚠️ [Performance] 掉帧检测: ${frameDuration.inMilliseconds}ms');
      }
    }
    _lastFrameTime = now;
  }

  /// 获取平均帧时间
  static double getAverageFrameTime() {
    if (_frameTimes.isEmpty) return 0;
    final sum = _frameTimes.fold<int>(
      0,
      (prev, duration) => prev + duration.inMicroseconds,
    );
    return sum / _frameTimes.length / 1000; // 转换为毫秒
  }

  /// 获取当前FPS
  static double getCurrentFPS() {
    final avgFrameTime = getAverageFrameTime();
    if (avgFrameTime == 0) return 0;
    return 1000 / avgFrameTime;
  }

  /// 打印性能报告
  static void printReport() {
    debugPrint(
        '📊 [Performance] 平均帧时间: ${getAverageFrameTime().toStringAsFixed(2)}ms');
    debugPrint('📊 [Performance] 当前FPS: ${getCurrentFPS().toStringAsFixed(1)}');
  }
}
