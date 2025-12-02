/// 页面转场优化器
///
/// 在页面转场期间降低构建复杂度

import 'package:flutter/widgets.dart';

/// ✅ 全局转场状态管理
class TransitionOptimizer {
  static bool _isTransitioning = false;
  static final List<VoidCallback> _listeners = [];
  static final List<VoidCallback> _pendingCallbacks = [];

  /// 是否正在转场
  static bool get isTransitioning => _isTransitioning;

  /// 标记转场开始
  static void onPageTransitionStart() {
    if (_isTransitioning) return;
    _isTransitioning = true;
    _notifyListeners();
  }

  /// 标记转场结束
  static void onPageTransitionEnd() {
    if (!_isTransitioning) return;
    _isTransitioning = false;
    _notifyListeners();
    _executePendingCallbacks();
  }

  /// 延迟执行任务直到转场结束
  static void deferUntilTransitionEnd(VoidCallback callback) {
    if (_isTransitioning) {
      _pendingCallbacks.add(callback);
    } else {
      callback();
    }
  }

  /// 执行所有待处理的回调
  static void _executePendingCallbacks() {
    final callbacks = List<VoidCallback>.from(_pendingCallbacks);
    _pendingCallbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// 添加监听器
  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// 通知所有监听器
  static void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
}

/// ✅ 转场感知 Widget - 在转场期间显示简化版本
class TransitionAwareWidget extends StatefulWidget {
  const TransitionAwareWidget({
    required this.builder,
    this.transitionBuilder,
    super.key,
  });

  final WidgetBuilder builder;
  final WidgetBuilder? transitionBuilder;

  @override
  State<TransitionAwareWidget> createState() => _TransitionAwareWidgetState();
}

class _TransitionAwareWidgetState extends State<TransitionAwareWidget> {
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _isTransitioning = TransitionOptimizer.isTransitioning;
    TransitionOptimizer.addListener(_onTransitionChanged);
  }

  @override
  void dispose() {
    TransitionOptimizer.removeListener(_onTransitionChanged);
    super.dispose();
  }

  void _onTransitionChanged() {
    if (mounted) {
      setState(() {
        _isTransitioning = TransitionOptimizer.isTransitioning;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isTransitioning && widget.transitionBuilder != null) {
      return widget.transitionBuilder!(context);
    }
    return widget.builder(context);
  }
}
