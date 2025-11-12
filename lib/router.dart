import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/connect/modern_connect_page.dart';
import 'features/home/home_page.dart';
import 'features/home/bottom_nav_wrapper.dart';
import 'features/item/item_detail_page.dart';
import 'features/library/library_items_page.dart';
import 'features/library/livetv_page.dart';
import 'features/library/music_page.dart';
import 'features/library/series_detail_page.dart';
import 'features/library/season_episodes_page.dart';
import 'features/player/player_page.dart';
import 'features/splash/splash_page.dart';
import 'utils/app_route_observer.dart';

// 用于全局访问 navigator key
final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

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
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    observers: [appRouteObserver],
    routes: [
      // 启动页
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => buildCupertinoPage(
          child: const SplashPage(),
          state: state,
        ),
      ),
      GoRoute(
        path: '/connect',
        pageBuilder: (context, state) {
          final startAtLogin =
              state.uri.queryParameters['startAtLogin'] == 'true';
          return buildCupertinoPage(
            child: ModernConnectPage(startAtLogin: startAtLogin),
            state: state,
          );
        },
      ),
      // Shell Route - 包含底部导航栏的所有页面（除了播放器等全屏页面）
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        pageBuilder: (context, state, child) {
          return NoTransitionPage(
            child: BottomNavWrapper(child: child),
          );
        },
        routes: [
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
            path: '/series/:seriesId',
            pageBuilder: (context, state) {
              final seriesId = state.pathParameters['seriesId'] ?? '';
              final seriesName = state.uri.queryParameters['name'] ?? '剧集详情';
              return buildCupertinoPage(
                child: SeriesDetailPage(
                  seriesId: seriesId,
                  seriesName: seriesName,
                ),
                state: state,
              );
            },
          ),
          GoRoute(
            path: '/series/:seriesId/season/:seasonId',
            pageBuilder: (context, state) {
              final seriesId = state.pathParameters['seriesId'] ?? '';
              final seasonId = state.pathParameters['seasonId'] ?? '';
              final seriesName =
                  state.uri.queryParameters['seriesName'] ?? '剧集';
              final seasonName =
                  state.uri.queryParameters['seasonName'] ?? '第一季';
              return buildCupertinoPage(
                child: SeasonEpisodesPage(
                  seriesId: seriesId,
                  seasonId: seasonId,
                  seriesName: seriesName,
                  seasonName: seasonName,
                ),
                state: state,
              );
            },
          ),
          GoRoute(
            path: '/item/:itemId',
            pageBuilder: (context, state) => buildCupertinoPage(
              child:
                  ItemDetailPage(itemId: state.pathParameters['itemId'] ?? ''),
              state: state,
            ),
          ),
          GoRoute(
            path: '/livetv/:viewId',
            pageBuilder: (context, state) {
              final viewId = state.pathParameters['viewId'] ?? '';
              final viewName = state.uri.queryParameters['name'] ?? '电视直播';
              return buildCupertinoPage(
                child: LiveTvPage(
                  viewId: viewId,
                  viewName: viewName,
                ),
                state: state,
              );
            },
          ),
          GoRoute(
            path: '/music/:viewId',
            pageBuilder: (context, state) {
              final viewId = state.pathParameters['viewId'] ?? '';
              final viewName = state.uri.queryParameters['name'] ?? '音乐';
              return buildCupertinoPage(
                child: MusicPage(
                  viewId: viewId,
                  viewName: viewName,
                ),
                state: state,
              );
            },
          ),
        ],
      ),
      // 全屏页面（隐藏底部导航）
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/player/:itemId',
        pageBuilder: (context, state) {
          final itemId = state.pathParameters['itemId'] ?? '';
          final params = state.uri.queryParameters;
          final fromStart = params['fromStart'] == 'true';
          final positionTicks = int.tryParse(params['positionTicks'] ?? '');
          final initialTicks = fromStart ? 0 : (positionTicks ?? 0);
          return buildCupertinoPage(
            child: PlayerPage(
              itemId: itemId,
              initialPositionTicks: initialTicks > 0 ? initialTicks : null,
            ),
            state: state,
          );
        },
      ),
    ],
  );
}
