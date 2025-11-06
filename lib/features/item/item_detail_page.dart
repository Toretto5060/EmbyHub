import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/fade_in_image.dart';

final itemProvider =
    FutureProvider.family<ItemInfo, String>((ref, itemId) async {
  final auth = ref.read(authStateProvider).value;
  if (auth == null || !auth.isLoggedIn) {
    throw Exception('未登录');
  }
  final api = await EmbyApi.create();
  return api.getItem(auth.userId!, itemId);
});

class ItemDetailPage extends ConsumerStatefulWidget {
  const ItemDetailPage({required this.itemId, super.key});
  final String itemId;

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(itemProvider(widget.itemId));

    // 设置状态栏为亮色图标（因为背景图片通常较暗）
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: item.when(
        data: (data) {
          final isPlayed = (data.userData?['Played'] as bool?) ?? false;

          return Stack(
            children: [
              // 背景和可滚动内容
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // 顶部背景图片区域（从状态栏开始）
                  SliverToBoxAdapter(
                    child: _buildBackdropHeader(context, data, isPlayed),
                  ),
                  // 占位空间（预留给悬浮的内容卡片）
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 100),
                  ),
                  // 后续内容（剧情简介等）
                  SliverToBoxAdapter(
                    child: Container(
                      color: CupertinoColors.systemBackground.resolveFrom(context),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 剧情简介
                          if ((data.overview ?? '').isNotEmpty) ...[
                            Text(
                              data.overview!,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // 悬浮的内容（无背景，左对齐）
              Positioned(
                top: 350 - 120, // 海报高度 - 向上偏移量
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      data.name,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 评分、年份、时长等信息
                    DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _buildMetaInfo(data),
                    ),
                    const SizedBox(height: 8),
                    // 类型、视频、音频信息
                    _buildMediaInfo(data),
                    const SizedBox(height: 16),
                    // 播放按钮
                    _buildPlayButton(context, data),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  Widget _buildBackdropHeader(
      BuildContext context, ItemInfo item, bool isPlayed) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return SizedBox(
      height: 350,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图片（从顶部开始，包含状态栏区域）
          if (item.id != null)
            FutureBuilder<EmbyApi>(
              future: EmbyApi.create(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(color: CupertinoColors.systemGrey5);
                }
                final url = snapshot.data!.buildImageUrl(
                  itemId: item.id!,
                  type: 'Backdrop',
                  maxWidth: 800,
                );
                return EmbyFadeInImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                );
              },
            ),
          // 底部虚化渐变（轻微虚化，自然过渡）
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    bgColor.withOpacity(0.5),
                    bgColor,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // 顶部浮动栏（返回按钮 + 右上角图标）
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 返回按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.pop(),
                    child: const Icon(
                      CupertinoIcons.back,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  // 右上角图标组
                  Row(
                    children: [
                      // 投屏图标（预留）
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: null,
                        child: Icon(
                          CupertinoIcons.tv,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
                        ),
                      ),
                      // 已观看标记
                      if (isPlayed)
                        CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          minSize: 0,
                          onPressed: null,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: CupertinoColors.activeGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.check_mark,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      // 收藏图标（预留）
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: null,
                        child: Icon(
                          CupertinoIcons.heart,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
                        ),
                      ),
                      // 更多选项图标（预留）
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: null,
                        child: Icon(
                          CupertinoIcons.ellipsis,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaInfo(ItemInfo item) {
    final List<String> metaItems = [];

    // 评分
    final rating = item.getRating();
    if (rating != null) {
      if (item.getRatingSource() == 'douban') {
        metaItems.add('豆 ${rating.toStringAsFixed(1)}');
      } else {
        metaItems.add('⭐ ${rating.toStringAsFixed(1)}');
      }
    }

    // 年份
    if (item.productionYear != null) {
      metaItems.add('${item.productionYear}');
    }

    // 时长
    if (item.runTimeTicks != null) {
      final duration =
          Duration(microseconds: (item.runTimeTicks! / 10).round());
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      metaItems.add('${hours}时${minutes}分');
    }

    return Text(
      metaItems.join(' · '),
      style: const TextStyle(
        fontSize: 14,
        color: CupertinoColors.systemGrey,
      ),
    );
  }

  Widget _buildMediaInfo(ItemInfo item) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 这里可以添加类型、视频规格、音频等信息
        // 暂时预留
      ],
    );
  }

  Widget _buildPlayButton(BuildContext context, ItemInfo item) {
    return Row(
      children: [
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: CupertinoColors.activeBlue,
            borderRadius: BorderRadius.circular(8),
            onPressed: item.id != null && item.id!.isNotEmpty
                ? () => context.push('/player/${item.id}')
                : null,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.play_fill, color: Colors.white),
                SizedBox(width: 8),
                Text('播放', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
