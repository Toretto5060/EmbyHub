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
    // ✅ 新增参数：tab 相关
    this.libraryType,
    this.tabs,
    this.selectedTab = 0,
    this.onTabChanged,
    this.itemCount,
    this.sortLabel,
    this.onSortTap,
    this.sortAscending,
    this.isSortMenuOpen,
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
  // ✅ 新增参数
  final String? libraryType; // 'Movie' 或 'Series'
  final List<String>? tabs;
  final int selectedTab;
  final ValueChanged<int>? onTabChanged;
  final int? itemCount;
  final String? sortLabel;
  final VoidCallback? onSortTap;
  final bool? sortAscending; // ✅ 排序方向：true=正序，false=倒序
  final bool? isSortMenuOpen; // ✅ 排序菜单是否打开

  @override
  Size get preferredSize {
    // ✅ 如果有 tab，增加高度
    final hasTabs = tabs != null && tabs!.isNotEmpty;
    final tabHeight = hasTabs ? 36.0 : 0.0; // ✅ tab 高度：从44改为36
    final infoHeight = hasTabs ? 36.0 : 0.0; // tab 下方信息高度
    return Size.fromHeight(100.0 + tabHeight + infoHeight);
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

    final hasTabs = widget.tabs != null && widget.tabs!.isNotEmpty;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: EdgeInsets.only(top: statusBarHeight),
          decoration: BoxDecoration(
            color: baseColor.withOpacity(backgroundOpacity),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ 基础导航栏
              SizedBox(
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
              // ✅ Tab 切换
              if (hasTabs) ...[
                SizedBox(
                  height: 36, // ✅ 调小tab高度：从44改为36
                  width: double.infinity, // ✅ 让SizedBox占满宽度
                  child: Align(
                    alignment: Alignment.centerLeft, // ✅ 让tab整体居左对齐
                    child: _buildTabBar(context, currentColor),
                  ),
                ),
                // ✅ Tab 下方信息：左侧 x项，右侧排序方式
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左侧：x项
                      Text(
                        widget.itemCount != null
                            ? '${widget.itemCount}项'
                            : '',
                        style: TextStyle(
                          fontSize: 13,
                          color: currentColor.withOpacity(0.7),
                        ),
                      ),
                      // 右侧：排序方式
                      if (widget.sortLabel != null && widget.onSortTap != null)
                        GestureDetector(
                          onTap: widget.onSortTap,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ✅ 左侧显示排序icon
                              Icon(
                                CupertinoIcons.sort_down,
                                size: 14,
                                color: currentColor.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.sortLabel!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: currentColor.withOpacity(0.7),
                                ),
                              ),
                              // ✅ 第一个icon：上下箭头，代表当前是正序还是倒序（无间距）
                              Icon(
                                widget.sortAscending == true
                                    ? CupertinoIcons.arrow_up
                                    : CupertinoIcons.arrow_down,
                                size: 12,
                                color: currentColor.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              // ✅ 第二个icon：倒三角/正三角，代表下拉是否打开
                              Icon(
                                widget.isSortMenuOpen == true
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 12,
                                color: currentColor.withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 构建 Tab 栏
  Widget _buildTabBar(BuildContext context, Color textColor) {
    if (widget.tabs == null || widget.tabs!.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // ✅ 保留适当的left padding，让tab有左边距，但整体居左显示
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start, // ✅ tab居左显示
        mainAxisSize: MainAxisSize.min, // ✅ 让Row只占用必要的宽度，确保居左显示
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(widget.tabs!.length, (index) {
          final isSelected = index == widget.selectedTab;
          return GestureDetector(
            onTap: () => widget.onTabChanged?.call(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // ✅ 调小垂直padding
              // ✅ 所有tab都从最左边开始，只有right margin作为tab之间的间距
              margin: const EdgeInsets.only(right: 8), // ✅ tab之间的间距
              decoration: BoxDecoration(
                color: isSelected
                    ? textColor.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.tabs![index],
                style: TextStyle(
                  fontSize: 13, // ✅ 缩小字体
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: textColor.withOpacity(isSelected ? 1.0 : 0.7),
                ),
              ),
            ),
          );
        }),
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
