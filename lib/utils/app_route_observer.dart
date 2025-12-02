import 'package:flutter/widgets.dart';
import 'transition_optimizer.dart';

/// ✅ 性能优化的路由观察器
/// 在路由转场时自动标记转场状态，用于性能优化
class PerformanceRouteObserver extends RouteObserver<ModalRoute<void>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // 标记转场开始
    TransitionOptimizer.onPageTransitionStart();

    // 在转场动画结束后标记转场结束（CupertinoPage 默认 300ms）
    Future.delayed(const Duration(milliseconds: 350), () {
      TransitionOptimizer.onPageTransitionEnd();
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // 标记转场开始
    TransitionOptimizer.onPageTransitionStart();

    // 在转场动画结束后标记转场结束（CupertinoPage 默认 300ms）
    Future.delayed(const Duration(milliseconds: 350), () {
      TransitionOptimizer.onPageTransitionEnd();
    });
  }
}

final RouteObserver<ModalRoute<void>> appRouteObserver =
    PerformanceRouteObserver();
