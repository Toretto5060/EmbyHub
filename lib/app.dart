import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'utils/status_bar_manager.dart';
import 'providers/settings_provider.dart';

class EmbyApp extends ConsumerWidget {
  const EmbyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = createRouter();
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
        // ✅ 根据当前主题模式计算亮度（使用 Theme.of(context).brightness 而不是 platformBrightness）
        final brightness = Theme.of(context).brightness;
        final defaultStyle =
            brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
        return ValueListenableBuilder<SystemUiOverlayStyle?>(
          valueListenable: StatusBarManager.listenable,
          builder: (context, style, _) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: style ?? defaultStyle,
              child: child ?? const SizedBox.shrink(),
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
