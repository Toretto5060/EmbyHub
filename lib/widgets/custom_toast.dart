import 'package:flutter/material.dart';

/// 自定义 Toast 工具类
class CustomToast {
  /// 显示成功提示
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, ToastType.success);
  }

  /// 显示错误提示
  static void showError(BuildContext context, String message) {
    _show(context, message, ToastType.error);
  }

  /// 显示信息提示
  static void showInfo(BuildContext context, String message) {
    _show(context, message, ToastType.info);
  }

  /// 显示警告提示
  static void showWarning(BuildContext context, String message) {
    _show(context, message, ToastType.warning);
  }

  static void _show(BuildContext context, String message, ToastType type) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(message: message, type: type),
    );

    overlay.insert(overlayEntry);

    // 2秒后自动移除
    Future.delayed(const Duration(milliseconds: 2000), () {
      overlayEntry.remove();
    });
  }
}

enum ToastType {
  success,
  error,
  info,
  warning,
}

/// Toast 组件（居中显示，底部靠上）
class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.type,
  });

  final String message;
  final ToastType type;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    // 1.7秒后开始淡出动画
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBackgroundColor() {
    switch (widget.type) {
      case ToastType.success:
        return Colors.green;
      case ToastType.error:
        return Colors.red;
      case ToastType.info:
        return Colors.blue;
      case ToastType.warning:
        return Colors.orange;
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle;
      case ToastType.error:
        return Icons.error;
      case ToastType.info:
        return Icons.info;
      case ToastType.warning:
        return Icons.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20, // ✅ 调整为60，距离底部更近一些
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _getBackgroundColor().withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIcon(),
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
