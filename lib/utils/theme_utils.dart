import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

/// ✅ 获取当前主题亮度（考虑用户选择的主题模式）
Brightness getCurrentBrightness(WidgetRef ref) {
  final themeMode = ref.read(themeModeProvider);
  final platformBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  switch (themeMode) {
    case AppThemeMode.dark:
      return Brightness.dark;
    case AppThemeMode.light:
      return Brightness.light;
    case AppThemeMode.system:
      return platformBrightness;
  }
}

/// ✅ 获取当前主题亮度（从 BuildContext，用于非 ConsumerWidget）
Brightness getCurrentBrightnessFromContext(BuildContext context, WidgetRef ref) {
  final themeMode = ref.read(themeModeProvider);
  final platformBrightness = MediaQuery.of(context).platformBrightness;

  switch (themeMode) {
    case AppThemeMode.dark:
      return Brightness.dark;
    case AppThemeMode.light:
      return Brightness.light;
    case AppThemeMode.system:
      return platformBrightness;
  }
}

/// ✅ 判断是否为深色模式
bool isDarkMode(WidgetRef ref) {
  return getCurrentBrightness(ref) == Brightness.dark;
}

/// ✅ 判断是否为深色模式（从 BuildContext）
bool isDarkModeFromContext(BuildContext context, WidgetRef ref) {
  return getCurrentBrightnessFromContext(context, ref) == Brightness.dark;
}

