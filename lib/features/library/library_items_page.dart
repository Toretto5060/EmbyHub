import 'package:flutter/cupertino.dart';
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
  const LibraryItemsPage({required this.viewId, super.key});
  final String viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider(viewId));
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('资源列表')),
      child: SafeArea(
        child: items.when(
          data: (list) {
            if (list.isEmpty) {
              return const Center(child: Text('此分类暂无内容'));
            }
            return GridView.builder(
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
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
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
      onPressed: () => context.go('/item/${item.id}'),
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
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(color: CupertinoColors.systemGrey4);
        }
        final url = snapshot.data!.buildImageUrl(itemId: itemId);
        return Image.network(url, fit: BoxFit.cover);
      },
    );
  }
}
