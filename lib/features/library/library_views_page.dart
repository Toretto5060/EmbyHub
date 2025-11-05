import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

final _viewsProvider = FutureProvider<List<ViewInfo>>((ref) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ViewInfo>[];
  final api = await EmbyApi.create();
  return api.getUserViews(auth.userId!);
});

class LibraryViewsPage extends ConsumerWidget {
  const LibraryViewsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    
    final auth = ref.watch(authStateProvider);
    final views = ref.watch(_viewsProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('媒体库'),
        backgroundColor: Color(0x00000000),
        border: null,
      ),
      child: SafeArea(
        top: false,
        child: auth.when(
          data: (authData) {
            if (!authData.isLoggedIn) {
              return _buildEmptyState(context, isLoggedIn: false);
            }
            return views.when(
              data: (list) {
                if (list.isEmpty) {
                  return _buildEmptyState(context, isLoggedIn: true);
                }
                return _buildGridView(context, list);
              },
              loading: () => const Center(child: CupertinoActivityIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_triangle,
                        size: 64, color: CupertinoColors.systemRed),
                    const SizedBox(height: 16),
                    Text('加载失败: $e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: CupertinoColors.systemGrey)),
                    const SizedBox(height: 16),
                    CupertinoButton.filled(
                      onPressed: () => ref.refresh(_viewsProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => _buildEmptyState(context, isLoggedIn: false),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isLoggedIn}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLoggedIn
                  ? CupertinoIcons.folder
                  : CupertinoIcons.person_crop_circle_badge_xmark,
              size: 80,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 24),
            Text(
              isLoggedIn ? '暂无媒体库' : '未登录',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isLoggedIn
                  ? '服务器上还没有可用的媒体库\n请在 Emby 服务器中添加媒体内容'
                  : '连接 Emby 服务器后即可浏览媒体库\n您也可以使用本地下载功能',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 32),
            if (!isLoggedIn)
              CupertinoButton.filled(
                onPressed: () => context.go('/connect'),
                child: const Text('去连接服务器'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(BuildContext context, List<ViewInfo> list) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 3.2),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final v = list[index];
        return CupertinoButton(
          padding: const EdgeInsets.all(12),
          onPressed: () => context.go('/library/${v.id}'),
          child: Container(
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
                '${v.name}${v.collectionType != null ? ' (${v.collectionType})' : ''}'),
          ),
        );
      },
    );
  }
}
