import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

final itemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  return api.getItemsByParent(userId: auth.userId!, parentId: viewId);
});

class LibraryItemsPage extends ConsumerWidget {
  const LibraryItemsPage({
    required this.viewId,
    this.viewName = '媒体库',
    super.key,
  });
  
  final String viewId;
  final String viewName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider(viewId));
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          context.go('/');
        }
      },
      child: CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          viewName,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Icon(
            CupertinoIcons.back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => context.go('/'),
        ),
        backgroundColor: CupertinoColors.systemBackground,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: items.when(
          data: (list) {
            if (list.isEmpty) {
              return const Center(child: Text('此分类暂无内容'));
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(itemsProvider(viewId));
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.66,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  return _ItemTile(item: item);
                },
              ),
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
      ),
      ),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});
  final ItemInfo item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: item.id != null && item.id!.isNotEmpty 
          ? () => context.go('/item/${item.id}')
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _Poster(itemId: item.id),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Poster extends ConsumerWidget {
  const _Poster({required this.itemId});
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null || itemId!.isEmpty) {
      return Container(
        color: CupertinoColors.systemGrey4,
        child: const Center(
          child: Icon(CupertinoIcons.film, size: 48),
        ),
      );
    }
    
    return FutureBuilder(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(color: CupertinoColors.systemGrey4);
        }
        final url = snapshot.data!.buildImageUrl(itemId: itemId!);
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: CupertinoColors.systemGrey4,
            child: const Center(
              child: Icon(CupertinoIcons.film, size: 48),
            ),
          ),
        );
      },
    );
  }
}
