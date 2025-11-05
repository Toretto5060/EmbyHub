import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;

import 'features/connect/modern_connect_page.dart';
import 'features/home/home_page.dart';
import 'features/item/item_detail_page.dart';
import 'features/library/library_items_page.dart';
import 'features/player/player_page.dart';

// Cupertino style page transition
CupertinoPage<T> buildCupertinoPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CupertinoPage<T>(
    key: state.pageKey,
    child: child,
  );
}

GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final prefs = await sp.SharedPreferences.getInstance();
      final token = prefs.getString('emby_token');
      final hasToken = token != null && token.isNotEmpty;
      
      // Allow access to home page always
      // If logged in and on connect page, go to home
      if (hasToken && state.matchedLocation == '/connect') {
        return '/';
      }
      
      // Redirect to connect page only for protected routes when not logged in
      if (!hasToken && state.matchedLocation.startsWith('/library/')) {
        return '/';
      }
      if (!hasToken && state.matchedLocation.startsWith('/item/')) {
        return '/';
      }
      if (!hasToken && state.matchedLocation.startsWith('/player/')) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/connect',
        pageBuilder: (context, state) {
          final startAtLogin = state.uri.queryParameters['startAtLogin'] == 'true';
          return buildCupertinoPage(
            child: ModernConnectPage(startAtLogin: startAtLogin),
            state: state,
          );
        },
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => buildCupertinoPage(
          child: const HomePage(),
          state: state,
        ),
      ),
      GoRoute(
        path: '/library/:viewId',
        pageBuilder: (context, state) {
          final viewId = state.pathParameters['viewId'] ?? '';
          final viewName = state.uri.queryParameters['name'] ?? '媒体库';
          return buildCupertinoPage(
            child: LibraryItemsPage(
              viewId: viewId,
              viewName: viewName,
            ),
            state: state,
          );
        },
      ),
      GoRoute(
        path: '/item/:itemId',
        pageBuilder: (context, state) => buildCupertinoPage(
          child: ItemDetailPage(itemId: state.pathParameters['itemId'] ?? ''),
          state: state,
        ),
      ),
      GoRoute(
        path: '/player/:itemId',
        pageBuilder: (context, state) => buildCupertinoPage(
          child: PlayerPage(itemId: state.pathParameters['itemId'] ?? ''),
          state: state,
        ),
      ),
    ],
  );
}
