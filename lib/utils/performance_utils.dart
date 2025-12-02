/// 性能优化工具类
///
/// 提供页面转场性能优化相关功能

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// ✅ 页面转场性能优化器
/// 在页面转场动画期间，延迟执行重度构建任务
class TransitionPerformanceOptimizer {
  static bool _isTransitioning = false;

  /// 标记转场开始
  static void markTransitionStart() {
    _isTransitioning = true;
  }

  /// 标记转场结束
  static void markTransitionEnd() {
    _isTransitioning = false;
  }

  /// 是否正在转场
  static bool get isTransitioning => _isTransitioning;

  /// ✅ 在转场结束后执行回调
  /// 如果当前不在转场中，立即执行
  static void executeAfterTransition(VoidCallback callback) {
    if (!_isTransitioning) {
      callback();
      return;
    }

    // 等待转场结束后执行
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_isTransitioning) {
        callback();
      } else {
        // 如果还在转场中，继续等待
        executeAfterTransition(callback);
      }
    });
  }
}

/// ✅ 延迟构建 Widget - 在转场动画期间显示占位符
/// 转场结束后才构建实际内容
class DeferredBuildWidget extends StatefulWidget {
  const DeferredBuildWidget({
    required this.builder,
    this.placeholder,
    this.deferDuration = const Duration(milliseconds: 250),
    super.key,
  });

  final WidgetBuilder builder;
  final Widget? placeholder;
  final Duration deferDuration;

  @override
  State<DeferredBuildWidget> createState() => _DeferredBuildWidgetState();
}

class _DeferredBuildWidgetState extends State<DeferredBuildWidget> {
  bool _shouldBuild = false;

  @override
  void initState() {
    super.initState();
    // 延迟构建
    Future.delayed(widget.deferDuration, () {
      if (mounted) {
        setState(() {
          _shouldBuild = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldBuild) {
      return widget.builder(context);
    }
    return widget.placeholder ?? const SizedBox.shrink();
  }
}

/// ✅ 智能 RepaintBoundary - 自动为复杂 Widget 添加重绘边界
class SmartRepaintBoundary extends StatelessWidget {
  const SmartRepaintBoundary({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      return RepaintBoundary(child: child);
    }
    return child;
  }
}

/// ✅ 性能监控 Mixin - 用于监控页面构建性能
mixin PerformanceMonitorMixin<T extends StatefulWidget> on State<T> {
  int _buildCount = 0;
  DateTime? _lastBuildTime;

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    final now = DateTime.now();

    if (_lastBuildTime != null) {
      final duration = now.difference(_lastBuildTime!);
      if (duration.inMilliseconds < 16) {
        // 构建频率过高（超过60fps），可能存在性能问题
        debugPrint(
            '⚠️ [Performance] ${T.toString()} 构建频率过高: ${duration.inMilliseconds}ms');
      }
    }

    _lastBuildTime = now;

    // 子类需要实现 performBuild
    return performBuild(context);
  }

  /// 子类实现实际的构建逻辑
  Widget performBuild(BuildContext context);

  @override
  void dispose() {
    debugPrint('📊 [Performance] ${T.toString()} 总构建次数: $_buildCount');
    super.dispose();
  }
}
