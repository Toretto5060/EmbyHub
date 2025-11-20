import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'status_bar_util.dart';
import 'theme_utils.dart';

/// 全局状态栏样式管理器，支持嵌套覆盖。
class StatusBarManager {
  StatusBarManager._();

  static final ValueNotifier<SystemUiOverlayStyle?> _notifier =
      ValueNotifier<SystemUiOverlayStyle?>(null);
  static final List<_StatusBarEntry> _stack = <_StatusBarEntry>[];
  static int _nextToken = 0;
  static bool _observerRegistered = false;
  static final _BrightnessObserver _brightnessObserver = _BrightnessObserver();
  // ✅ 当前主题亮度（用户选择的主题模式对应的亮度，而不是系统平台亮度）
  static Brightness? _currentThemeBrightness;

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

  /// ✅ 设置当前主题亮度（用户选择的主题模式对应的亮度）
  static void setCurrentThemeBrightness(Brightness? brightness) {
    _currentThemeBrightness = brightness;
    _notify();
  }

  static void refresh() {
    _notify();
  }

  static void _notify() {
    final nextStyle = _stack.isEmpty ? null : _stack.last.style;
    // ✅ 如果有自定义主题亮度，使用它；否则使用系统平台亮度
    final brightnessToUse = _currentThemeBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final styleToApply =
        nextStyle ?? StatusBarUtil.styleForBrightness(brightnessToUse);
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
    // ✅ 只有当用户没有设置自定义主题亮度时，才响应系统平台亮度变化
    // 如果用户设置了自定义主题亮度（固定深色或浅色），则忽略系统平台亮度变化
    // 注意：这里不能直接访问 _currentThemeBrightness，因为它可能已经更新
    // 所以总是调用 _notify()，让它在内部判断是否使用系统平台亮度
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

  void release() {
    _state._releaseToken();
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

  /// ✅ 根据用户选择的主题模式自适应状态栏样式（而不是系统平台亮度）
  static Widget adaptiveToTheme({required Widget child, Key? key}) {
    return _ThemeAdaptiveStatusBarStyleScope(key: key, child: child);
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
  bool _tokenReleased = false;

  @override
  void initState() {
    super.initState();
    _currentStyle = widget.style;
    _controller = StatusBarStyleController(this);
    _ensureToken();
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
    _releaseToken();
    super.dispose();
  }

  void _setStyle(SystemUiOverlayStyle style, {bool fromWidgetUpdate = false}) {
    _ensureToken();
    if (_token == null) return;
    if (!fromWidgetUpdate && style == _currentStyle) {
      return;
    }
    _currentStyle = style;
    StatusBarManager.replace(_token!, style);
    setState(() {});
  }

  void _ensureToken() {
    if (_token != null) {
      return;
    }
    _token = StatusBarManager.push(_currentStyle);
    _tokenReleased = false;
  }

  void _releaseToken() {
    if (_token == null) {
      return;
    }
    StatusBarManager.remove(_token!);
    _token = null;
    _tokenReleased = true;
  }

  @override
  Widget build(BuildContext context) {
    if (_token == null && !_tokenReleased) {
      _ensureToken();
    }
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
    // ⚠️ 这个实现使用系统平台亮度，用于向后兼容
    // 新的代码应该使用 adaptiveToTheme() 来根据用户选择的主题模式自适应
    final brightness =
        MediaQuery.maybeOf(context)?.platformBrightness ?? _platformBrightness;
    final style = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return StatusBarStyleScope(style: style, child: widget.child);
  }
}

/// ✅ 根据用户选择的主题模式自适应状态栏样式（而不是系统平台亮度）
class _ThemeAdaptiveStatusBarStyleScope extends ConsumerWidget {
  const _ThemeAdaptiveStatusBarStyleScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ 使用用户选择的主题模式计算亮度，而不是系统平台亮度
    final brightness = getCurrentBrightnessFromContext(context, ref);
    final style = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return StatusBarStyleScope(style: style, child: child);
  }
}
