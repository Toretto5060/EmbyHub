import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 带动态毛玻璃效果的导航栏 - 根据滚动位置显示/隐藏模糊效果
class BlurNavigationBar extends StatefulWidget
    implements ObstructingPreferredSizeWidget {
  const BlurNavigationBar({
    this.leading,
    this.middle,
    this.trailing,
    this.scrollController,
    this.forceBlur,
    this.expandedForegroundColor,
    this.collapsedForegroundColor,
    this.enableTransition = true,
    this.useDynamicOpacity = false,
    this.blurStart = 10.0,
    this.blurEnd = 200.0,
    super.key,
  });

  final Widget? leading;
  final Widget? middle;
  final Widget? trailing;
  final ScrollController? scrollController;
  final bool? forceBlur;
  final Color? expandedForegroundColor;
  final Color? collapsedForegroundColor;
  final bool enableTransition;
  final bool useDynamicOpacity;
  final double blurStart;
  final double blurEnd;

  @override
  Size get preferredSize {
    // 返回一个较大的固定高度，实际高度在 build 中动态计算
    return const Size.fromHeight(100.0);
  }

  @override
  bool shouldFullyObstruct(BuildContext context) => false;

  @override
  State<BlurNavigationBar> createState() => _BlurNavigationBarState();
}

class _BlurNavigationBarState extends State<BlurNavigationBar> {
  static const double _epsilon = 0.001;
  ScrollController? _attachedController;
  double _progress = 0.0;
  late Color _systemColor;

  @override
  void initState() {
    super.initState();
    _systemColor =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? Colors.white
            : Colors.black87;
    _attachController(widget.scrollController);
    _updateProgress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 响应系统主题变化
    final brightness = MediaQuery.of(context).platformBrightness;
    final newSystemColor =
        brightness == Brightness.dark ? Colors.white : Colors.black87;
    if (newSystemColor != _systemColor) {
      setState(() {
        _systemColor = newSystemColor;
      });
    }
  }

  @override
  void didUpdateWidget(covariant BlurNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _attachController(widget.scrollController);
    }
    if (oldWidget.forceBlur != widget.forceBlur ||
        oldWidget.useDynamicOpacity != widget.useDynamicOpacity ||
        oldWidget.blurStart != widget.blurStart ||
        oldWidget.blurEnd != widget.blurEnd) {
      _updateProgress(forceNotify: true);
    }
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  void _attachController(ScrollController? controller) {
    if (_attachedController == controller) return;
    _detachController();
    _attachedController = controller;
    _attachedController?.addListener(_updateProgress);
  }

  void _detachController() {
    _attachedController?.removeListener(_updateProgress);
    _attachedController = null;
  }

  void _updateProgress({bool forceNotify = false}) {
    double newProgress;
    if (widget.forceBlur == true) {
      newProgress = 1.0;
    } else if (widget.scrollController == null) {
      newProgress = 0.0;
    } else if (widget.useDynamicOpacity) {
      final offset = widget.scrollController!.hasClients
          ? widget.scrollController!.offset
          : 0.0;
      if (offset <= widget.blurStart) {
        newProgress = 0.0;
      } else {
        final totalRange = (widget.blurEnd - widget.blurStart)
            .abs()
            .clamp(1.0, double.infinity);
        final effective = (offset - widget.blurStart).clamp(0.0, totalRange);
        newProgress = (effective / totalRange).clamp(0.0, 1.0);
      }
    } else {
      final offset = widget.scrollController!.hasClients
          ? widget.scrollController!.offset
          : 0.0;
      newProgress = offset > widget.blurStart ? 1.0 : 0.0;
    }

    if (forceNotify || (newProgress - _progress).abs() > _epsilon) {
      setState(() {
        _progress = newProgress.clamp(0.0, 1.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final brightness = MediaQuery.of(context).platformBrightness;
    final baseColor = brightness == Brightness.dark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    final Color expandedColor = widget.expandedForegroundColor ?? _systemColor;
    final Color collapsedColor =
        widget.collapsedForegroundColor ?? _systemColor;

    final sigma = 30 * _progress;
    final backgroundOpacity = 0.7 * _progress;
    final Color currentColor = Color.lerp(expandedColor, collapsedColor,
        widget.enableTransition ? _progress : 1.0)!;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: EdgeInsets.only(top: statusBarHeight),
          decoration: BoxDecoration(
            color: baseColor.withOpacity(backgroundOpacity),
          ),
          child: SizedBox(
            height: 44,
            child: NavigationToolbar(
              leading: widget.leading != null
                  ? _wrapWithColor(widget.leading!, currentColor)
                  : null,
              middle: widget.middle != null
                  ? _wrapWithColor(widget.middle!, currentColor)
                  : null,
              trailing: widget.trailing != null
                  ? _wrapWithColor(widget.trailing!, currentColor)
                  : null,
              middleSpacing: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapWithColor(Widget child, Color color) {
    return IconTheme(
      data: IconThemeData(
        color: color,
        size: 28,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
        child: child,
      ),
    );
  }
}

/// 创建带毛玻璃效果的返回按钮
Widget buildBlurBackButton(BuildContext context, {Color? color}) {
  return CupertinoNavigationBarBackButton(
    color: color ?? IconTheme.of(context).color ?? CupertinoColors.activeBlue,
    onPressed: () => context.pop(),
  );
}

/// 创建带样式的标题
Widget buildNavTitle(String title, BuildContext context, {Color? color}) {
  final baseStyle = DefaultTextStyle.of(context).style;
  return Text(
    title,
    style: baseStyle.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: color ?? baseStyle.color,
    ),
  );
}
