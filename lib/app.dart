import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'utils/status_bar_manager.dart';
import 'providers/settings_provider.dart';

// ✅ 使用 Provider 缓存 router，避免每次 build 时重新创建
final routerProvider = Provider<GoRouter>((ref) {
  return createRouter();
});

class EmbyApp extends ConsumerWidget {
  const EmbyApp({super.key});

  /// ✅ 根据主题模式获取亮度
  static Brightness _getBrightnessFromThemeMode(
      AppThemeMode themeMode, BuildContext context) {
    switch (themeMode) {
      case AppThemeMode.dark:
        return Brightness.dark;
      case AppThemeMode.light:
        return Brightness.light;
      case AppThemeMode.system:
        // ✅ 使用 MediaQuery 获取系统平台亮度，如果不存在则使用平台亮度
        return MediaQuery.maybeOf(context)?.platformBrightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ 从 Provider 获取 router，不会在每次 build 时重新创建
    final GoRouter router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // ✅ 根据用户选择的主题模式确定 ThemeMode（MaterialApp 会自动处理主题切换，不会重建整个应用）
    ThemeMode materialThemeMode;
    switch (themeMode) {
      case AppThemeMode.dark:
        materialThemeMode = ThemeMode.dark;
        break;
      case AppThemeMode.light:
        materialThemeMode = ThemeMode.light;
        break;
      case AppThemeMode.system:
        materialThemeMode = ThemeMode.system;
        break;
    }

    return MaterialApp.router(
      title: 'EmbyHub',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: materialThemeMode, // ✅ 使用 themeMode，MaterialApp 会自动切换主题而不重建应用
      builder: (context, child) {
        // ✅ 监听主题模式变化，使用用户选择的主题模式计算亮度（而不是系统平台亮度）
        return Consumer(
          builder: (context, ref, _) {
            // ✅ 明确 watch themeModeProvider，确保主题变化时重建
            final themeMode = ref.watch(themeModeProvider);
            // ✅ 直接根据 themeMode 计算亮度，而不是依赖 MediaQuery
            final brightness = _getBrightnessFromThemeMode(themeMode, context);
            final defaultStyle = brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark;

            // ✅ 设置当前主题亮度到 StatusBarManager
            // 这样 StatusBarManager 在计算默认样式时会使用用户选择的主题亮度，而不是系统平台亮度
            StatusBarManager.setCurrentThemeBrightness(brightness);

            return ValueListenableBuilder<SystemUiOverlayStyle?>(
              valueListenable: StatusBarManager.listenable,
              builder: (context, style, _) {
                // ✅ 始终使用基于用户选择的主题亮度计算的 defaultStyle
                // 如果 StatusBarManager 返回的 style 为 null（没有页面设置自定义样式），使用 defaultStyle
                // 这样确保状态栏字体颜色始终跟随用户选择的主题变化
                final finalStyle = style ?? defaultStyle;
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: finalStyle,
                  child: child ?? const SizedBox.shrink(),
                );
              },
            );
          },
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF667eea),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF667eea),
          brightness: Brightness.dark,
        ),
      ),
    );
  }
}
