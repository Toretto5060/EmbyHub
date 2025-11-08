import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'utils/status_bar_manager.dart';

class EmbyApp extends StatelessWidget {
  const EmbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = createRouter();
    return MaterialApp.router(
      title: 'EmbyHub',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        final brightness = MediaQuery.of(context).platformBrightness;
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
