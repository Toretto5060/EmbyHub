import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../utils/theme_utils.dart';

/// 滚动文字组件 - 当文字超出宽度时自动滚动
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  ScrollController? _scrollController;
  bool _needsScroll = false;
  bool _isScrolling = false;
  bool _measured = false;
  double _scrollDistance = 0;

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _reset();
    }
  }

  void _reset() {
    _isScrolling = false;
    _needsScroll = false;
    _measured = false;
    _scrollController?.dispose();
    _scrollController = null;
    if (mounted) setState(() {});
  }

  void _onTextLayout(double textWidth, double maxWidth) {
    if (_measured) return;
    _measured = true;

    // 文字宽度超过可用宽度 5 像素以上才滚动
    if (textWidth > maxWidth + 5) {
      _scrollDistance = textWidth - maxWidth + 20;
      _needsScroll = true;
      _scrollController = ScrollController();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScrolling();
      });
    }
  }

  void _startScrolling() async {
    if (!mounted || !_needsScroll || _isScrolling) return;
    _isScrolling = true;

    await Future.delayed(const Duration(seconds: 1));

    while (mounted && _needsScroll && _isScrolling) {
      if (_scrollController == null || !_scrollController!.hasClients) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      await _scrollController!.animateTo(
        _scrollDistance,
        duration: Duration(milliseconds: (_scrollDistance * 30).toInt()),
        curve: Curves.linear,
      );

      if (!mounted || !_needsScroll) break;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_needsScroll) break;

      if (_scrollController != null && _scrollController!.hasClients) {
        await _scrollController!.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }

      if (!mounted || !_needsScroll) break;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 已确定需要滚动
    if (_needsScroll) {
      return SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
        ),
      );
    }

    // 使用自定义的测量组件
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // 计算文字实际宽度
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final textWidth = textPainter.width;

        // 在布局后回调
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onTextLayout(textWidth, maxWidth);
        });

        return Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

class MusicPlayerPage extends ConsumerStatefulWidget {
  const MusicPlayerPage({
    required this.onCollapseWithOffset,
    this.initialPage = 0,
    super.key,
  });

  /// 折叠回调，参数为当前拖拽偏移量
  final void Function(double dragOffset) onCollapseWithOffset;

  /// 初始页面：0=播放页面，1=播放列表
  final int initialPage;

  @override
  ConsumerState<MusicPlayerPage> createState() => MusicPlayerPageState();
}

class MusicPlayerPageState extends ConsumerState<MusicPlayerPage>
    with TickerProviderStateMixin {
  double _dragOffset = 0;
  late AnimationController _resetAnimationController;
  late Animation<double> _resetAnimation;

  // 封面切换动画
  late AnimationController _coverAnimationController;
  late Animation<double> _coverScaleAnimation;
  String? _previousSongId;
  bool _isAnimatingCover = false;

  // 封面旋转动画
  late AnimationController _rotationAnimationController;
  double _currentRotation = 0; // 当前旋转角度
  bool _wasPlaying = false; // 上一次的播放状态

  // 歌曲信息滑动动画
  late AnimationController _songInfoSlideController;
  late Animation<double> _songInfoSlideAnimation;
  bool _isNextSong = true; // true: 下一首（从右滑入），false: 上一首（从左滑入）

  // 圆容器缩放动画（播放时正常大小，暂停时缩小）
  late AnimationController _containerScaleController;
  late Animation<double> _containerScaleAnimation;

  // 页面控制器（用于播放页面和播放列表之间切换）
  late PageController _pageController;

  // 播放列表滚动控制器
  final ScrollController _playlistScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPage);

    // 监听页面切换，当离开第二屏时滚动到当前歌曲
    _pageController.addListener(_onPageChanged);

    _resetAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _resetAnimation = CurvedAnimation(
      parent: _resetAnimationController,
      curve: Curves.easeOut,
    );
    _resetAnimationController.addListener(() {
      setState(() {
        _dragOffset = _resetAnimation.value;
      });
    });

    // 初始化封面切换动画控制器（从大缩小到正常）
    _coverAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _coverScaleAnimation = Tween<double>(begin: 1.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _coverAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _coverAnimationController.value = 1.0; // 初始状态为完成

    // 初始化封面旋转动画控制器（30秒转一圈）
    _rotationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    _rotationAnimationController.addListener(() {
      setState(() {
        _currentRotation =
            _rotationAnimationController.value * 2 * 3.14159265359;
      });
    });

    // 初始化歌曲信息滑动动画控制器
    _songInfoSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _songInfoSlideAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _songInfoSlideController,
        curve: Curves.easeOutCubic,
      ),
    );
    _songInfoSlideController.value = 1.0; // 初始状态为完成

    // 初始化圆容器缩放动画控制器（播放时放大，暂停时缩小）
    _containerScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _containerScaleAnimation = Tween<double>(begin: 0.88, end: 0.92).animate(
      CurvedAnimation(
        parent: _containerScaleController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _containerScaleController.value = 0.0; // 初始状态为暂停（缩小）
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _resetAnimationController.dispose();
    _coverAnimationController.dispose();
    _rotationAnimationController.dispose();
    _returnToOriginController?.dispose();
    _songInfoSlideController.dispose();
    _containerScaleController.dispose();
    _pageController.dispose();
    _playlistScrollController.dispose();
    super.dispose();
  }

  /// 页面切换监听（保留用于将来扩展）
  void _onPageChanged() {
    // 当前不需要额外处理，歌曲切换时已经跳转到正确位置
  }

  /// 滚动到播放列表页面
  void scrollToPlaylist() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  /// 滚动到播放页面
  void scrollToPlayer() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  void _animateToTop() {
    // 从当前偏移量动画到 0
    _resetAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _resetAnimationController,
      curve: Curves.easeOut,
    ));
    _resetAnimationController.forward(from: 0);
  }

  void _triggerCoverAnimation(int newIndex) {
    // 如果正在进行封面动画，先停止
    if (_isAnimatingCover) {
      _returnToOriginController?.stop();
      _returnToOriginController?.dispose();
      _returnToOriginController = null;
      _isAnimatingCover = false;
    }

    _isAnimatingCover = true;

    // 从 provider 获取切换方向
    _isNextSong = ref.read(localMusicPlayerProvider).isNextDirection;

    // 启动歌曲信息滑动动画
    _songInfoSlideController.forward(from: 0);

    // 切换歌曲时，停止旋转
    _rotationAnimationController.stop();

    // 同时播放：旋转回原点 + 封面图片缩放动画
    _animateRotationAndScale();
  }

  // 切换歌曲时：旋转回原点和缩放动画同时进行
  void _animateRotationAndScale() {
    const twoPi = 2 * 3.14159265359;
    final normalizedRotation = _currentRotation % twoPi;
    final isPlaying = ref.read(localMusicPlayerProvider).isPlaying;

    // 计算旋转回原点的参数
    double targetRotation = 0;
    double rotationDistance = normalizedRotation;

    if (normalizedRotation > 0.05) {
      if (normalizedRotation > twoPi / 2) {
        targetRotation = twoPi;
        rotationDistance = twoPi - normalizedRotation;
      }
    }

    // 计算动画时长
    final rotationDurationMs = normalizedRotation < 0.05
        ? 0
        : (rotationDistance / twoPi * 600).toInt().clamp(100, 600);
    // 播放状态下不需要缩放动画，直接用旋转动画时长
    final scaleDurationMs = isPlaying ? 0 : 300;
    final totalDurationMs = rotationDurationMs > scaleDurationMs
        ? rotationDurationMs
        : scaleDurationMs;

    final startRotation = normalizedRotation;

    // 创建统一的动画控制器
    _returnToOriginController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalDurationMs),
    );

    _returnToOriginController!.addListener(() {
      if (!mounted) return;
      setState(() {
        // 旋转动画（如果需要）
        if (normalizedRotation >= 0.05) {
          final rotationProgress = rotationDurationMs > 0
              ? (_returnToOriginController!.value *
                      totalDurationMs /
                      rotationDurationMs)
                  .clamp(0.0, 1.0)
              : 1.0;
          _currentRotation = startRotation +
              (targetRotation - startRotation) *
                  Curves.easeOutCubic.transform(rotationProgress);
        }
      });
    });

    _returnToOriginController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _currentRotation = 0;
        _returnToOriginController?.dispose();
        _returnToOriginController = null;
        _isAnimatingCover = false;
        if (mounted) {
          setState(() {});
          // 如果正在播放，重新开始旋转
          final isPlaying = ref.read(localMusicPlayerProvider).isPlaying;
          if (isPlaying) {
            _rotationAnimationController.forward(from: 0);
            _rotationAnimationController.repeat();
          }
        }
      }
    });

    // 播放状态下不执行封面缩放动画，保持容器大小不变
    if (!isPlaying) {
      // 只有暂停状态下才启动封面图片缩放动画
      _coverAnimationController.forward(from: 0);
    }

    // 启动旋转回原点动画
    _returnToOriginController!.forward();
  }

  // 回到原点动画控制器
  AnimationController? _returnToOriginController;

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkModeFromContext(context, ref);
    final playerState = ref.watch(localMusicPlayerProvider);
    final currentSong = playerState.currentSong;
    final isPlaying = playerState.isPlaying;

    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    // 检测歌曲切换，触发封面动画
    if (_previousSongId != null && _previousSongId != currentSong.id) {
      _triggerCoverAnimation(playerState.currentIndex);
      // 歌曲切换时，立即跳转到当前歌曲位置（无动画）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToCurrentSong(playerState.currentIndex);
      });
    }
    _previousSongId = currentSong.id;

    // 检测播放状态变化，控制旋转动画和圆容器缩放
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      if (isPlaying) {
        // 开始播放：取消回到原点动画，从当前角度继续旋转，圆容器放大
        _returnToOriginController?.stop();
        _returnToOriginController?.dispose();
        _returnToOriginController = null;
        _isAnimatingCover = false; // 重置封面动画状态
        // 从当前角度继续旋转
        final currentValue = (_currentRotation / (2 * 3.14159265359)) % 1.0;
        _rotationAnimationController.forward(from: currentValue);
        _rotationAnimationController.repeat();
        _containerScaleController.forward(); // 圆容器放大到正常
      } else {
        // 暂停播放：停止旋转，保持当前角度，圆容器缩小
        _rotationAnimationController.stop();
        _containerScaleController.reverse(); // 圆容器缩小
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF1A1A2E),
                  const Color(0xFF0A0A0A),
                ]
              : [
                  const Color(0xFFE8E8F0),
                  const Color(0xFFF8F8F8),
                ],
        ),
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // 监听 PageView 的过度滚动（在第一页向下拉）
          if (notification is OverscrollNotification) {
            if (notification.overscroll < 0 &&
                (_pageController.page ?? 0) < 0.1) {
              // 在第一页向下过度滚动，开始下拉折叠
              setState(() {
                _dragOffset -= notification.overscroll;
                _isDraggingDown = true;
              });
              return true;
            }
          } else if (notification is ScrollUpdateNotification) {
            // 如果正在下拉且有偏移，继续处理
            if (_isDraggingDown && _dragOffset > 0) {
              if (notification.scrollDelta != null &&
                  notification.scrollDelta! < 0) {
                setState(() {
                  _dragOffset -= notification.scrollDelta!;
                });
                return true;
              }
            }
          } else if (notification is ScrollEndNotification) {
            // 滚动结束时处理折叠逻辑
            if (_isDraggingDown && _dragOffset > 0) {
              _isDraggingDown = false;
              if (_dragOffset > 100) {
                widget.onCollapseWithOffset(_dragOffset);
              } else {
                _animateToTop();
              }
              return true;
            }
            _isDraggingDown = false;
          }
          return false;
        },
        child: PageView(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          physics: const _FastPageScrollPhysics(),
          allowImplicitScrolling: true, // 预渲染相邻页面，让 ScrollController 有 clients
          children: [
            // 第一屏：播放页面
            _buildPlayerPage(context, isDark, playerState, currentSong),
            // 第二屏：播放列表
            _buildPlaylistPage(context, isDark, playerState),
          ],
        ),
      ),
    );
  }

  // 是否正在处理下拉手势
  bool _isDraggingDown = false;

  /// 构建播放页面（第一屏）
  Widget _buildPlayerPage(
    BuildContext context,
    bool isDark,
    LocalMusicPlayerState playerState,
    LocalSong currentSong,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        // 侧滑返回
        if (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 500) {
          widget.onCollapseWithOffset(_dragOffset);
        }
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部区域
              _buildTopSection(context, isDark, currentSong),
              // 专辑封面
              Expanded(
                child: _buildAlbumArt(context, isDark, currentSong),
              ),
              // 进度条
              _buildProgressBar(context, isDark, playerState),
              // 控制按钮
              _buildControls(context, isDark, playerState),
              // 底部额外操作
              _buildBottomActions(context, isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 是否允许列表滚动（当在顶部下拉时禁用，让 PageView 接管）
  bool _allowListScroll = true;

  /// 显示清除队列确认对话框
  void _showClearQueueDialog(BuildContext context, bool isDark) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清除播放队列'),
        content: const Text('确认清除将停止播放当前曲目并清空当前队列。是否清除？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('清除'),
            onPressed: () {
              Navigator.of(context).pop();
              // 停止播放并清空队列
              ref.read(localMusicPlayerProvider.notifier).stop();
              // 返回到第一屏
              scrollToPlayer();
              // 折叠播放器
              widget.onCollapseWithOffset(0);
            },
          ),
        ],
      ),
    );
  }

  /// 直接跳转到当前播放的歌曲（无动画）
  void _jumpToCurrentSong(int currentIndex) {
    if (!_playlistScrollController.hasClients) return;

    // 每个列表项的高度约为 72 (48 封面高度 + 24 padding)
    const itemHeight = 72.0;
    final targetOffset = currentIndex * itemHeight;

    // 确保不超出滚动范围
    final maxOffset = _playlistScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxOffset);

    // 直接跳转，无动画
    _playlistScrollController.jumpTo(clampedOffset);
  }

  /// 构建播放列表页面（第二屏）
  Widget _buildPlaylistPage(
    BuildContext context,
    bool isDark,
    LocalMusicPlayerState playerState,
  ) {
    return GestureDetector(
      onVerticalDragStart: (details) {
        // 检查是否在列表顶部
        if (_playlistScrollController.hasClients &&
            _playlistScrollController.offset <= 0) {
          // 在顶部，准备让 PageView 接管
          _allowListScroll = false;
        } else {
          _allowListScroll = true;
        }
      },
      onVerticalDragUpdate: (details) {
        if (!_allowListScroll && details.delta.dy > 0) {
          // 在顶部下拉，手动滚动 PageView
          _pageController.position.moveTo(
            _pageController.position.pixels - details.delta.dy,
          );
        }
      },
      onVerticalDragEnd: (details) {
        if (!_allowListScroll) {
          // 根据速度和位置决定是否切换页面
          final velocity = details.primaryVelocity ?? 0;
          final page = _pageController.page ?? 1;

          if (velocity > 300 || page < 0.5) {
            // 快速下拉或已经过半，切换到第一屏
            scrollToPlayer();
          } else {
            // 恢复到第二屏
            scrollToPlaylist();
          }
          _allowListScroll = true;
        }
      },
      child: SafeArea(
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 左侧：当前歌曲位置
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${playerState.currentIndex + 1}/${playerState.playlist.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                  // 中间：标题
                  Expanded(
                    child: Text(
                      '播放队列',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  // 右侧：清除按钮
                  SizedBox(
                    width: 70,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 32,
                        onPressed: () => _showClearQueueDialog(context, isDark),
                        child: Text(
                          '清除',
                          style: TextStyle(
                            fontSize: 14,
                            color: CupertinoColors.destructiveRed,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 播放列表
            Expanded(
              child: ListView.builder(
                controller: _playlistScrollController,
                physics: _allowListScroll
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: playerState.playlist.length,
                itemBuilder: (context, index) {
                  final song = playerState.playlist[index];
                  final isCurrentSong = playerState.currentIndex == index;

                  return CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      ref.read(localMusicPlayerProvider.notifier).setPlaylist(
                            playerState.playlist,
                            startIndex: index,
                          );
                      // 切换歌曲后滚动回播放页面
                      scrollToPlayer();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      color: isCurrentSong
                          ? CupertinoColors.activeBlue.withOpacity(0.1)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          // 封面
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: song.albumArt != null &&
                                    File(song.albumArt!).existsSync()
                                ? Image.file(
                                    File(song.albumArt!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        CupertinoIcons.double_music_note,
                                        size: 20,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black26,
                                      );
                                    },
                                  )
                                : Icon(
                                    CupertinoIcons.double_music_note,
                                    size: 20,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black26,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          // 歌曲信息
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isCurrentSong
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isCurrentSong
                                        ? CupertinoColors.activeBlue
                                        : (isDark
                                            ? Colors.white
                                            : Colors.black87),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 播放指示器
                          if (isCurrentSong)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                playerState.isPlaying
                                    ? CupertinoIcons.waveform
                                    : CupertinoIcons.pause_fill,
                                size: 18,
                                color: CupertinoColors.activeBlue,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection(BuildContext context, bool isDark, LocalSong song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 16, 12),
      child: Row(
        children: [
          // 歌曲信息（左侧）- 带滑动动画
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 使用容器的最大宽度作为滑动距离
                final maxWidth = constraints.maxWidth;
                return ClipRect(
                  child: AnimatedBuilder(
                    animation: _songInfoSlideAnimation,
                    builder: (context, child) {
                      // 计算滑动偏移量（使用容器最大宽度）
                      // 下一首：从右边滑入（正值到0）
                      // 上一首：从左边滑入（负值到0）
                      final slideOffset = _isNextSong
                          ? (1 - _songInfoSlideAnimation.value) * maxWidth
                          : -(1 - _songInfoSlideAnimation.value) * maxWidth;

                      return Transform.translate(
                        offset: Offset(slideOffset, 0),
                        child: Opacity(
                          opacity: _songInfoSlideAnimation.value,
                          child: child,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MarqueeText(
                            text: song.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _MarqueeText(
                            text: song.artist,
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 更多选项（右侧）
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 40,
            onPressed: () {
              // TODO: 显示更多选项
            },
            child: Icon(
              CupertinoIcons.ellipsis,
              size: 24,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, bool isDark, LocalSong song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(35, 60, 35, 0),
      child: Align(
        alignment: Alignment.topCenter,
        // 圆容器缩放动画（播放时正常大小，暂停时缩小）
        child: AnimatedBuilder(
          animation: _containerScaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _containerScaleAnimation.value,
              child: child,
            );
          },
          child: AspectRatio(
            aspectRatio: 1,
            child: Transform.rotate(
              angle: _currentRotation,
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                  shape: BoxShape.circle,
                  boxShadow: [
                    // 轻微阴影
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.2),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  // 切换歌曲时图片有缩放动画
                  child: AnimatedBuilder(
                    animation: _coverScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _coverScaleAnimation.value,
                        child: child,
                      );
                    },
                    child: song.albumArt != null &&
                            File(song.albumArt!).existsSync()
                        ? Image.file(
                            File(song.albumArt!),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  CupertinoIcons.double_music_note,
                                  size: 80,
                                  color:
                                      isDark ? Colors.white24 : Colors.black12,
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              CupertinoIcons.double_music_note,
                              size: 80,
                              color: isDark ? Colors.white24 : Colors.black12,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(
      BuildContext context, bool isDark, LocalMusicPlayerState playerState) {
    final position = playerState.position;
    final duration = playerState.duration.inMilliseconds > 0
        ? playerState.duration
        : const Duration(minutes: 3, seconds: 30);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // 进度条
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: CupertinoColors.activeBlue,
              inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
              thumbColor: CupertinoColors.activeBlue,
              overlayColor: CupertinoColors.activeBlue.withOpacity(0.2),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (value) {
                // TODO: 跳转到指定位置
              },
            ),
          ),
          // 时间显示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
      BuildContext context, bool isDark, LocalMusicPlayerState playerState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一首
          _ControlButton(
            icon: CupertinoIcons.backward_fill,
            size: 56,
            iconSize: 28,
            isDark: isDark,
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).playPrevious();
            },
          ),
          const SizedBox(width: 16),
          // 播放/暂停
          _ControlButton(
            icon: playerState.isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            size: 72,
            iconSize: 40,
            isDark: isDark,
            // 播放图标需要微调位置
            iconOffset:
                playerState.isPlaying ? Offset.zero : const Offset(2, 0),
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).togglePlayPause();
            },
          ),
          const SizedBox(width: 16),
          // 下一首
          _ControlButton(
            icon: CupertinoIcons.forward_fill,
            size: 56,
            iconSize: 28,
            isDark: isDark,
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).playNext();
            },
          ),
        ],
      ),
    );
  }

  /// 获取播放模式对应的图标
  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.listLoop:
        return CupertinoIcons.repeat;
      case PlayMode.singleLoop:
        return CupertinoIcons.repeat_1;
      case PlayMode.shuffle:
        return CupertinoIcons.shuffle;
    }
  }

  Widget _buildBottomActions(BuildContext context, bool isDark) {
    final playMode = ref.watch(localMusicPlayerProvider).playMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 播放模式
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              ref.read(localMusicPlayerProvider.notifier).togglePlayMode();
            },
            child: Icon(
              _getPlayModeIcon(playMode),
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 喜欢
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 添加到喜欢
            },
            child: Icon(
              CupertinoIcons.heart,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 播放队列
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // 滚动到播放列表页面
              scrollToPlaylist();
            },
            child: Icon(
              CupertinoIcons.list_bullet,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          // 音效
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              // TODO: 显示音效设置
            },
            child: Icon(
              CupertinoIcons.waveform,
              size: 26,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 控制按钮（带阴影点击效果）
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final bool isDark;
  final Offset iconOffset;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.isDark,
    this.iconOffset = Offset.zero,
    required this.onPressed,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isPressed = false;

  void _onTapDown(TapDownDetails details) {
    setState(() {
      _isPressed = true;
    });
  }

  void _onTapUp(TapUpDetails details) {
    setState(() {
      _isPressed = false;
    });
    widget.onPressed();
  }

  void _onTapCancel() {
    setState(() {
      _isPressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: (widget.isDark ? Colors.white : Colors.black)
                        .withOpacity(0.15),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Transform.translate(
            offset: widget.iconOffset,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

/// 自定义快速 PageView 滚动物理效果
class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics({super.parent});

  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring {
    // 使用临界阻尼公式：damping = 2 * sqrt(mass * stiffness)
    const mass = 1.0;
    const stiffness = 500.0;
    final criticalDamping = 2 * sqrt(mass * stiffness);
    return SpringDescription(
      mass: mass,
      stiffness: stiffness,
      damping: criticalDamping,
    );
  }
}
