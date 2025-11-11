import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'status_bar_util.dart';

/// 全局状态栏样式管理器，支持嵌套覆盖。
class StatusBarManager {
  StatusBarManager._();

  static final ValueNotifier<SystemUiOverlayStyle?> _notifier =
      ValueNotifier<SystemUiOverlayStyle?>(null);
  static final List<_StatusBarEntry> _stack = <_StatusBarEntry>[];
  static int _nextToken = 0;
  static bool _observerRegistered = false;
  static final _BrightnessObserver _brightnessObserver = _BrightnessObserver();

  static ValueListenable<SystemUiOverlayStyle?> get listenable => _notifier;

  static int push(SystemUiOverlayStyle style) {
    _ensureObserver();
    final entry = _StatusBarEntry(_nextToken++, style);
    _stack.add(entry);
    _notify();
    return entry.token;
  }

  static void replace(int token, SystemUiOverlayStyle style) {
    final index = _stack.indexWhere((entry) => entry.token == token);
    if (index == -1) {
      return;
    }
    _stack[index] = _StatusBarEntry(token, style);
    if (index == _stack.length - 1) {
      _notify();
    }
  }

  static void remove(int token) {
    final index = _stack.indexWhere((entry) => entry.token == token);
    if (index == -1) {
      return;
    }
    _stack.removeAt(index);
    _notify();
  }

  static SystemUiOverlayStyle? get currentStyle => _notifier.value;

  static void _ensureObserver() {
    if (_observerRegistered) return;
    WidgetsBinding.instance.addObserver(_brightnessObserver);
    _observerRegistered = true;
  }

  static void refresh() {
    _notify();
  }

  static void _notify() {
    final nextStyle = _stack.isEmpty ? null : _stack.last.style;
    final styleToApply = nextStyle ??
        StatusBarUtil.styleForBrightness(
            WidgetsBinding.instance.platformDispatcher.platformBrightness);
    StatusBarUtil.applyStyle(styleToApply);
    if (_notifier.value == nextStyle) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notifier.value != nextStyle) {
        _notifier.value = nextStyle;
      }
    });
  }
}

class _BrightnessObserver extends WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    StatusBarManager._notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      StatusBarManager._notify();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    StatusBarManager._notify();
  }
}

class _StatusBarEntry {
  const _StatusBarEntry(this.token, this.style);
  final int token;
  final SystemUiOverlayStyle style;
}

class StatusBarStyleController {
  StatusBarStyleController(this._state);
  final _StatusBarStyleScopeState _state;

  void update(SystemUiOverlayStyle style) {
    _state._setStyle(style);
  }
}

/// 包裹页面并设置状态栏样式，支持嵌套覆盖。
class StatusBarStyleScope extends StatefulWidget {
  const StatusBarStyleScope({
    required this.child,
    required this.style,
    super.key,
  });

  factory StatusBarStyleScope.light({required Widget child, Key? key}) {
    return StatusBarStyleScope(
      key: key,
      style: SystemUiOverlayStyle.light,
      child: child,
    );
  }

  factory StatusBarStyleScope.dark({required Widget child, Key? key}) {
    return StatusBarStyleScope(
      key: key,
      style: SystemUiOverlayStyle.dark,
      child: child,
    );
  }

  factory StatusBarStyleScope.transparentLight(
      {required Widget child, Key? key}) {
    return StatusBarStyleScope(
      key: key,
      style: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: child,
    );
  }

  static Widget adaptive({required Widget child, Key? key}) {
    return _AdaptiveStatusBarStyleScope(key: key, child: child);
  }

  final Widget child;
  final SystemUiOverlayStyle style;

  static StatusBarStyleController? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_StatusBarScopeInherited>()
        ?.controller;
  }

  @override
  State<StatusBarStyleScope> createState() => _StatusBarStyleScopeState();
}

class _StatusBarStyleScopeState extends State<StatusBarStyleScope> {
  late SystemUiOverlayStyle _currentStyle;
  late final StatusBarStyleController _controller;
  int? _token;

  @override
  void initState() {
    super.initState();
    _currentStyle = widget.style;
    _controller = StatusBarStyleController(this);
    _token = StatusBarManager.push(_currentStyle);
  }

  @override
  void didUpdateWidget(covariant StatusBarStyleScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style != oldWidget.style) {
      _setStyle(widget.style, fromWidgetUpdate: true);
    }
  }

  @override
  void dispose() {
    if (_token != null) {
      StatusBarManager.remove(_token!);
    }
    super.dispose();
  }

  void _setStyle(SystemUiOverlayStyle style, {bool fromWidgetUpdate = false}) {
    if (_token == null) {
      return;
    }
    if (!fromWidgetUpdate && style == _currentStyle) {
      return;
    }
    _currentStyle = style;
    StatusBarManager.replace(_token!, style);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _StatusBarScopeInherited(
      controller: _controller,
      child: widget.child,
    );
  }
}

class _StatusBarScopeInherited extends InheritedWidget {
  const _StatusBarScopeInherited({
    required this.controller,
    required super.child,
  });

  final StatusBarStyleController controller;

  @override
  bool updateShouldNotify(_StatusBarScopeInherited oldWidget) => false;
}

class _AdaptiveStatusBarStyleScope extends StatefulWidget {
  const _AdaptiveStatusBarStyleScope({required this.child, super.key});

  final Widget child;

  @override
  State<_AdaptiveStatusBarStyleScope> createState() =>
      _AdaptiveStatusBarStyleScopeState();
}

class _AdaptiveStatusBarStyleScopeState
    extends State<_AdaptiveStatusBarStyleScope> with WidgetsBindingObserver {
  Brightness? _platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final newBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (newBrightness != _platformBrightness) {
      setState(() {
        _platformBrightness = newBrightness;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness =
        MediaQuery.maybeOf(context)?.platformBrightness ?? _platformBrightness;
    final style = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return StatusBarStyleScope(style: style, child: widget.child);
  }
}
