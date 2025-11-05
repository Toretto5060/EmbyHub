import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'router.dart';

class EmbyApp extends StatelessWidget {
  const EmbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = createRouter();
    return MaterialApp.router(
      title: 'EmbyHub',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
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
