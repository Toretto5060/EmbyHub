import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

final itemProvider =
    FutureProvider.family<ItemInfo, String>((ref, itemId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, itemId);
});

class ItemDetailPage extends ConsumerWidget {
  const ItemDetailPage({required this.itemId, super.key});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(itemId));
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          color: isDark ? Colors.white : Colors.black87,
          onPressed: () => context.pop(),
        ),
        middle: Text(
          '详情',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        backgroundColor: CupertinoColors.systemBackground,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity( 0.1) : Colors.black.withOpacity( 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: item.when(
          data: (data) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _Poster(itemId: data.id),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          if (data.runTimeTicks != null)
                            Text(_formatDuration(Duration(
                                microseconds:
                                    (data.runTimeTicks! / 10).round()))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if ((data.overview ?? '').isNotEmpty) Text(data.overview!),
                const SizedBox(height: 16),
                if (data.id != null && data.id!.isNotEmpty)
                  Row(children: [
                    Expanded(
                        child: CupertinoButton.filled(
                            onPressed: () => context.go('/player/${data.id}'),
                            child: const Text('播放'))),
                  ]),
              ],
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

class _Poster extends ConsumerWidget {
  const _Poster({required this.itemId});
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null || itemId!.isEmpty) {
      return Container(
        width: 120,
        height: 180,
        color: CupertinoColors.systemGrey4,
        child: const Icon(CupertinoIcons.film, size: 48),
      );
    }
    
    return FutureBuilder(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(width: 120, height: 180);
        }
        final url = snapshot.data!.buildImageUrl(itemId: itemId!, maxWidth: 360);
        return Image.network(
          url,
          width: 120,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 120,
            height: 180,
            color: CupertinoColors.systemGrey4,
            child: const Icon(CupertinoIcons.film, size: 48),
          ),
        );
      },
    );
  }
}
