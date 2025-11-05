import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;

import 'features/connect/modern_connect_page.dart';
import 'features/home/home_page.dart';
import 'features/item/item_detail_page.dart';
import 'features/library/library_items_page.dart';
import 'features/player/player_page.dart';

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
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ModernConnectPage()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: HomePage()),
      ),
      GoRoute(
        path: '/library/:viewId',
        pageBuilder: (context, state) => NoTransitionPage(
          child: LibraryItemsPage(viewId: state.pathParameters['viewId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/item/:itemId',
        pageBuilder: (context, state) => NoTransitionPage(
          child: ItemDetailPage(itemId: state.pathParameters['itemId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/player/:itemId',
        pageBuilder: (context, state) => NoTransitionPage(
          child: PlayerPage(itemId: state.pathParameters['itemId'] ?? ''),
        ),
      ),
    ],
  );
}
