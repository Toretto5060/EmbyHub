import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/blur_navigation_bar.dart';
import '../../utils/theme_utils.dart';

final liveTvChannelsProvider =
    FutureProvider.family<List<ItemInfo>, String>((ref, viewId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) return <ItemInfo>[];
  final api = await EmbyApi.create();
  // 获取电视直播频道
  return api.getItemsByParent(
    userId: auth.userId!,
    parentId: viewId,
    includeItemTypes: 'LiveTvChannel',
  );
});

class LiveTvPage extends ConsumerStatefulWidget {
  const LiveTvPage({
    required this.viewId,
    this.viewName = '电视直播',
    super.key,
  });

  final String viewId;
  final String viewName;

  @override
  ConsumerState<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends ConsumerState<LiveTvPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(liveTvChannelsProvider(widget.viewId));
    final isDark = isDarkModeFromContext(context, ref);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      navigationBar: BlurNavigationBar(
        leading: buildBlurBackButton(context),
        middle: buildNavTitle(widget.viewName, context),
        scrollController: _scrollController,
      ),
      child: channels.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 44,
                ),
                child: const Text('暂无直播频道'),
              ),
            );
          }
          return RefreshIndicator(
            displacement: 20,
            edgeOffset: MediaQuery.of(context).padding.top + 44,
            onRefresh: () async {
              ref.invalidate(liveTvChannelsProvider(widget.viewId));
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 44 + 12,
                left: 12,
                right: 12,
                bottom: 12,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final channel = list[index];
                return _ChannelTile(channel: channel);
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

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel});
  final ItemInfo channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isDarkModeFromContext(context, ref);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: channel.id != null && channel.id!.isNotEmpty
          ? () => context.push('/player/${channel.id}')
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark
              ? CupertinoColors.systemGrey6.darkColor
              : CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 频道图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey5,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: const Icon(
                CupertinoIcons.tv,
                size: 32,
                color: CupertinoColors.systemGrey,
              ),
            ),
            // 频道信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      child: Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 播放图标
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                CupertinoIcons.play_circle,
                size: 28,
                color: CupertinoColors.activeBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
