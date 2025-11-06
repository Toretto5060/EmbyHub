import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../widgets/fade_in_image.dart';

final musicItemsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  // 获取音乐内容：专辑和艺术家
  return api.getItemsByParent(
    userId: auth.userId!,
    parentId: viewId,
    includeItemTypes: 'MusicAlbum,MusicArtist',
  );
});

class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({
    required this.viewId,
    this.viewName = '音乐',
    super.key,
  });

  final String viewId;
  final String viewName;

  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(musicItemsProvider(widget.viewId));
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      navigationBar: BlurNavigationBar(
        leading: buildBlurBackButton(context),
        middle: buildNavTitle(widget.viewName, context),
        scrollController: _scrollController,
      ),
      child: items.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 44,
                ),
                child: const Text('暂无音乐内容'),
              ),
            );
          }
          return RefreshIndicator(
            displacement: 20,
            edgeOffset: MediaQuery.of(context).padding.top + 44,
            onRefresh: () async {
              ref.invalidate(musicItemsProvider(widget.viewId));
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 44 + 12,
                left: 12,
                right: 12,
                bottom: 12,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final item = list[index];
                return _MusicTile(item: item);
              },
            ),
          );
        },
        loading: () => Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
            child: const CupertinoActivityIndicator(),
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 44,
            ),
            child: Text('加载失败: $e'),
          ),
        ),
      ),
    );
  }
}

class _MusicTile extends ConsumerWidget {
  const _MusicTile({required this.item});
  final ItemInfo item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: item.id != null && item.id!.isNotEmpty
          ? () {
              // 音乐专辑/艺术家 - 暂时跳转到详情页
              context.push('/item/${item.id}');
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _MusicCover(itemId: item.id),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicCover extends ConsumerWidget {
  const _MusicCover({required this.itemId});
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null || itemId!.isEmpty) {
      return Container(
        color: CupertinoColors.systemGrey5,
        child: const Center(
          child: Icon(CupertinoIcons.music_note_2, size: 48),
        ),
      );
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: CupertinoColors.systemGrey5,
          );
        }
        final url = snapshot.data!.buildImageUrl(
          itemId: itemId!,
          type: 'Primary',
          maxWidth: 400,
        );
        return EmbyFadeInImage(
          imageUrl: url,
          fit: BoxFit.cover,
        );
      },
    );
  }
}
