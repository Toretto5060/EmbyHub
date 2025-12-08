import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_music_provider.dart';
import '../../providers/local_music_matcher_provider.dart';
import '../../services/music_download_service.dart';
import '../../utils/theme_utils.dart';
import '../../widgets/default_album_cover.dart';
import '../../widgets/local_file_badge.dart';

/// 音质信息
class _QualityInfo {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _QualityInfo(this.label, this.bgColor, [this.textColor = Colors.white]);
}

/// 根据码率获取音质等级信息
_QualityInfo? _getQualityInfo(int? bitrate) {
  if (bitrate == null || bitrate < 128) return null;

  if (bitrate > 2000) {
    // Hi-Res 高解析无损 (> 2Mbps) - 黑底金字
    return const _QualityInfo('Hi-Res', Colors.black, Color(0xFFFFD700));
  } else if (bitrate >= 900) {
    // HD/Lossless 无损音质 (900-2000 kbps) - 橙色
    return const _QualityInfo('HD', Color(0xFFFFA500));
  } else if (bitrate >= 320) {
    // HQ+ 超高品质 (320 kbps) - 蓝紫色
    return const _QualityInfo('HQ+', Color(0xFF7B68EE));
  } else if (bitrate >= 192) {
    // HQ 高品质 (192-256 kbps) - 绿色
    return const _QualityInfo('HQ', CupertinoColors.activeGreen);
  } else {
    // SQ 标准音质 (128 kbps) - 灰色
    return const _QualityInfo('SQ', CupertinoColors.systemGrey);
  }
}

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

  // 封面切换动画（缩放 + 淡入淡出）
  late AnimationController _coverAnimationController;
  late Animation<double> _coverFadeAnimation; // 淡入淡出
  late Animation<double> _oldCoverScaleAnimation; // 旧封面放大
  late Animation<double> _newCoverScaleAnimation; // 新封面缩小
  String? _previousSongId;
  String? _previousAlbumArt; // 当前封面路径（用于下次切换时作为旧封面）
  String? _fadingOutAlbumArt; // 正在淡出的旧封面路径（动画期间使用）
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

  // 海报/歌词水平滑动控制器（0: 海报, 1: 歌词）
  late PageController _coverLyricsPageController;
  int _currentCoverLyricsPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPage);
    _coverLyricsPageController = PageController(initialPage: 0);

    // 监听页面切换，当离开第二屏时滚动到当前歌曲
    _pageController.addListener(_onPageChanged);

    // 监听海报/歌词页面切换
    _coverLyricsPageController.addListener(() {
      final page = _coverLyricsPageController.page?.round() ?? 0;
      if (page != _currentCoverLyricsPage) {
        setState(() {
          _currentCoverLyricsPage = page;
        });
      }
    });

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

    // 初始化封面切换动画控制器（缩放 + 淡入淡出）
    _coverAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // 旧封面：1.0 -> 1.15 放大 + 淡出
    _oldCoverScaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _coverAnimationController,
        curve: Curves.easeOut,
      ),
    );
    // 新封面：1.15 -> 1.0 缩小 + 淡入
    _newCoverScaleAnimation = Tween<double>(begin: 1.15, end: 1.0).animate(
      CurvedAnimation(
        parent: _coverAnimationController,
        curve: Curves.easeOut,
      ),
    );
    // 淡入淡出动画：0->1 表示从旧封面淡出到新封面淡入
    _coverFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _coverAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _coverAnimationController.value = 1.0; // 初始状态为完成（显示新封面）

    // 初始化封面旋转动画控制器（30秒转一圈）
    _rotationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 预加载当前歌曲封面，避免初始化时显示灰色背景
    _precacheCurrentCover();
  }

  // 预加载当前歌曲封面
  void _precacheCurrentCover() {
    final currentSong = ref.read(localMusicPlayerProvider).currentSong;
    if (currentSong?.albumArt != null &&
        currentSong!.albumArt!.isNotEmpty &&
        File(currentSong.albumArt!).existsSync()) {
      precacheImage(FileImage(File(currentSong.albumArt!)), context);
    }
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
    _coverLyricsPageController.dispose();
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

  void _triggerCoverAnimation(int newIndex, {String? oldAlbumArt}) {
    // 如果正在进行封面动画，先停止
    if (_isAnimatingCover) {
      _returnToOriginController?.stop();
      _returnToOriginController?.dispose();
      _returnToOriginController = null;
      _coverAnimationController.stop();
      _isAnimatingCover = false;
    }

    _isAnimatingCover = true;

    // 保存要淡出的旧封面路径
    _fadingOutAlbumArt = oldAlbumArt;

    // 从 provider 获取切换方向
    _isNextSong = ref.read(localMusicPlayerProvider).isNextDirection;

    // 启动歌曲信息滑动动画
    _songInfoSlideController.forward(from: 0);

    // 切换歌曲时，停止旋转
    _rotationAnimationController.stop();

    // 先执行旋转回原点动画，完成后再执行封面替换动画
    _animateRotationAndScale();
  }

  // 切换歌曲时：先旋转回原点，再执行封面替换动画
  void _animateRotationAndScale() {
    const twoPi = 2 * 3.14159265359;
    final normalizedRotation = _currentRotation % twoPi;

    // 如果已经接近原点，直接执行封面替换动画
    if (normalizedRotation < 0.05) {
      _currentRotation = 0;
      _startCoverReplaceAnimation();
      return;
    }

    // 计算旋转回原点的参数
    double targetRotation = 0;
    double rotationDistance = normalizedRotation;

    if (normalizedRotation > twoPi / 2) {
      targetRotation = twoPi;
      rotationDistance = twoPi - normalizedRotation;
    }

    // 计算旋转动画时长
    final rotationDurationMs =
        (rotationDistance / twoPi * 600).toInt().clamp(100, 600);

    final startRotation = normalizedRotation;

    // 创建旋转回原点的动画控制器
    _returnToOriginController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: rotationDurationMs),
    );

    _returnToOriginController!.addListener(() {
      if (!mounted) return;
      setState(() {
        _currentRotation = startRotation +
            (targetRotation - startRotation) *
                Curves.easeOutCubic.transform(_returnToOriginController!.value);
      });
    });

    _returnToOriginController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _currentRotation = 0;
        _returnToOriginController?.dispose();
        _returnToOriginController = null;

        if (mounted) {
          setState(() {});
          // 旋转回原点完成后，执行封面替换动画
          _startCoverReplaceAnimation();
        }
      }
    });

    // 启动旋转回原点动画
    _returnToOriginController!.forward();
  }

  // 执行封面替换动画（淡入淡出+缩放）
  void _startCoverReplaceAnimation() {
    _coverAnimationController.forward(from: 0).then((_) {
      // 封面动画完成后，清除旧封面引用并标记动画结束
      _fadingOutAlbumArt = null;
      _isAnimatingCover = false;
      // 如果正在播放，重新开始旋转
      final isPlaying = ref.read(localMusicPlayerProvider).isPlaying;
      if (isPlaying && mounted) {
        _rotationAnimationController.forward(from: 0);
        _rotationAnimationController.repeat();
      }
    });
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
    // 优先使用大尺寸封面
    final currentCoverUrl = currentSong.albumArtLarge ?? currentSong.albumArt;
    if (_previousSongId != null && _previousSongId != currentSong.id) {
      // 传入上一张封面路径用于淡出效果（注意：此时 _previousAlbumArt 是上一首歌的封面）
      final oldAlbumArt = _previousAlbumArt;
      // 先更新为当前封面，再触发动画
      _previousAlbumArt = currentCoverUrl;
      _triggerCoverAnimation(
        playerState.currentIndex,
        oldAlbumArt: oldAlbumArt,
      );
      // 歌曲切换时，立即跳转到当前歌曲位置（无动画）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToCurrentSong(playerState.currentIndex);
      });

      // 触发边下边播（如果启用）
      _triggerProgressiveDownload(currentSong);
    } else {
      // 没有切换歌曲时，更新当前封面路径
      _previousAlbumArt = currentCoverUrl;
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
              // 专辑封面 + 音轨信息（可左滑显示歌词）
              Expanded(
                child: _buildCoverAndLyricsSection(
                    context, isDark, currentSong, playerState),
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
              // 清除播放列表的持久化缓存
              ref.read(localMusicPlayerProvider.notifier).clearSavedPlaylist();
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
                          // 封面（带本地文件标识）
                          AlbumCoverWithLocalBadge(
                            hasLocalFile: _checkHasLocalFile(song),
                            badgeSize: 14,
                            badgeOffset: 1,
                            child: AlbumCoverImage(
                              albumArt: song.albumArt,
                              size: 48,
                              iconSize: 20,
                              borderRadius: BorderRadius.circular(6),
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
                          // 歌曲标题 + 本地文件标识
                          Row(
                            children: [
                              Flexible(
                                child: _MarqueeText(
                                  text: song.title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              // 本地文件标识（绿色对勾）
                              if (_checkHasLocalFile(song)) ...[
                                const SizedBox(width: 6),
                                LocalFileBadge(size: 14),
                              ],
                            ],
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

  /// 构建封面+音轨信息/歌词区域（可左右滑动）
  Widget _buildCoverAndLyricsSection(
    BuildContext context,
    bool isDark,
    LocalSong currentSong,
    LocalMusicPlayerState playerState,
  ) {
    return PageView(
      controller: _coverLyricsPageController,
      physics: const ClampingScrollPhysics(),
      children: [
        // 第一页：封面 + 音轨信息
        _buildCoverWithTrackInfo(context, isDark, currentSong),
        // 第二页：歌词
        _buildLyricsPage(context, isDark, currentSong, playerState),
      ],
    );
  }

  /// 构建封面 + 音轨信息页面
  Widget _buildCoverWithTrackInfo(
      BuildContext context, bool isDark, LocalSong song) {
    return Column(
      children: [
        // 专辑封面
        Expanded(
          child: _buildAlbumArt(context, isDark, song),
        ),
        // 音轨信息（带切换动画）
        _buildTrackInfo(context, isDark, song),
      ],
    );
  }

  /// 构建音轨信息（格式、位深、采样率等）
  Widget _buildTrackInfo(BuildContext context, bool isDark, LocalSong song) {
    // 优先使用 container 字段，其次从文件路径获取格式
    final format = song.container?.toUpperCase() ?? _getAudioFormat(song.path);
    // 构建音轨信息文本
    final trackInfo = _buildTrackInfoText(
      format,
      song.bitDepth,
      song.sampleRate,
    );

    // 获取音质等级信息
    final qualityInfo = _getQualityInfo(song.bitrate);

    if (trackInfo.isEmpty && qualityInfo == null) {
      return const SizedBox(height: 20);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 音质标签
          if (qualityInfo != null) ...[
            Container(
              padding: const EdgeInsets.only(
                left: 4,
                right: 4,
                top: 2.8,
                bottom: 2.4,
              ),
              decoration: BoxDecoration(
                color: qualityInfo.bgColor,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                qualityInfo.label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: qualityInfo.textColor,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 12), // 三个空格的间距
          ],
          // AudioTrack 信息
          if (trackInfo.isNotEmpty)
            Text(
              'AudioTrack   $trackInfo',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
                letterSpacing: 1.0,
              ),
            ),
        ],
      ),
    );
  }

  /// 从文件路径获取音频格式
  String _getAudioFormat(String? path) {
    if (path == null || path.isEmpty) return '';
    final ext = path.split('.').last.toUpperCase();
    switch (ext) {
      case 'FLAC':
        return 'FLAC';
      case 'MP3':
        return 'MP3';
      case 'WAV':
        return 'WAV';
      case 'AAC':
      case 'M4A':
        return 'AAC';
      case 'OGG':
        return 'OGG';
      case 'WMA':
        return 'WMA';
      case 'APE':
        return 'APE';
      case 'ALAC':
        return 'ALAC';
      default:
        return ext;
    }
  }

  /// 构建音轨信息文本
  String _buildTrackInfoText(String format, int? bitDepth, int? sampleRate) {
    final result = StringBuffer();

    // 格式和位深
    if (format.isNotEmpty) {
      result.write(format);
    }
    if (bitDepth != null && bitDepth > 0) {
      if (result.isNotEmpty) {
        result.write(' ');
      }
      result.write('$bitDepth bits');
    }

    // 采样率与前面用三个空格分隔
    if (sampleRate != null && sampleRate > 0) {
      if (result.isNotEmpty) {
        result.write('   '); // 三个空格
      }
      // 转换为 kHz 格式
      final kHz = sampleRate / 1000.0;
      if (kHz == kHz.roundToDouble()) {
        result.write('${kHz.toInt()}kHz');
      } else {
        result.write('${kHz.toStringAsFixed(1)}kHz');
      }
    }

    return result.toString();
  }

  /// 构建歌词页面
  Widget _buildLyricsPage(
    BuildContext context,
    bool isDark,
    LocalSong song,
    LocalMusicPlayerState playerState,
  ) {
    final lyrics = song.lyrics;

    if (lyrics == null || lyrics.isEmpty) {
      // 如果是服务器音乐且有字幕索引，说明正在加载歌词
      final isLoadingLyrics = song.isServerMusic && song.subtitleIndex != null;

      return Center(
        child: isLoadingLyrics
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '歌词加载中...',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              )
            : Text(
                '暂无歌词',
                style: TextStyle(
                  fontSize: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
      );
    }

    return _LyricsView(
      lyrics: lyrics,
      position: playerState.position,
      isDark: isDark,
    );
  }

  /// 检查歌曲是否有本地文件（仅对服务器音乐显示）
  bool _checkHasLocalFile(LocalSong song) {
    // 只有服务器音乐才显示本地文件标识
    // 本地音乐本身就是本地的，不需要显示标识
    if (!song.isServerMusic) return false;

    // 如果歌曲本身已经标记有本地文件，直接返回
    if (song.hasLocalFile) return true;

    // 检查本地文件匹配
    final matcherState = ref.watch(localMusicMatcherProvider);
    if (!matcherState.isInitialized) return false;

    final match = ref.read(localMusicMatcherProvider.notifier).matchLocalFile(
          song.title,
          song.artist,
        );
    return match.hasLocalFile;
  }

  /// 触发边下边播
  void _triggerProgressiveDownload(LocalSong song) {
    // 异步触发，不阻塞UI
    Future.microtask(() {
      try {
        final downloadService = ref.read(musicDownloadServiceProvider);
        downloadService.startProgressiveDownload(song);
      } catch (e) {
        // 静默处理错误
        print('⚠️ [MusicPlayer] Failed to trigger progressive download: $e');
      }
    });
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
                  // 切换歌曲时封面：放大+淡出 / 缩小+淡入
                  child: Container(
                    // 添加背景色，避免图片加载时透出页面背景
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                    child: AnimatedBuilder(
                      animation: _coverAnimationController,
                      builder: (context, child) {
                        // 是否正在进行淡入淡出动画
                        final isAnimating = _coverFadeAnimation.value < 1.0 &&
                            _fadingOutAlbumArt != null;

                        // 优先使用大尺寸封面，没有则使用普通封面
                        final coverUrl = song.albumArtLarge ?? song.albumArt;

                        if (!isAnimating) {
                          // 没有动画时，直接显示当前封面
                          return _buildCoverImage(coverUrl, isDark);
                        }

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // 旧封面（放大 + 淡出）
                            Opacity(
                              opacity: 1.0 - _coverFadeAnimation.value,
                              child: Transform.scale(
                                scale: _oldCoverScaleAnimation.value,
                                child: _buildCoverImage(
                                    _fadingOutAlbumArt, isDark),
                              ),
                            ),
                            // 新封面（缩小 + 淡入）
                            Opacity(
                              opacity: _coverFadeAnimation.value,
                              child: Transform.scale(
                                scale: _newCoverScaleAnimation.value,
                                child: _buildCoverImage(coverUrl, isDark),
                              ),
                            ),
                          ],
                        );
                      },
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

  // 构建封面图片（支持本地文件和网络URL）
  Widget _buildCoverImage(String? albumArt, bool isDark) {
    if (albumArt == null || albumArt.isEmpty) {
      return DefaultAlbumCover(iconSize: 80);
    }

    // 检查是否为网络URL
    if (albumArt.startsWith('http://') || albumArt.startsWith('https://')) {
      return Image.network(
        albumArt,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return DefaultAlbumCover(iconSize: 80);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
          );
        },
      );
    }

    // 本地文件
    if (File(albumArt).existsSync()) {
      return Image.file(
        File(albumArt),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return DefaultAlbumCover(iconSize: 80);
        },
      );
    }

    return DefaultAlbumCover(iconSize: 80);
  }

  // 进度条拖动状态
  bool _isDraggingProgress = false;
  double _dragProgress = 0.0;

  Widget _buildProgressBar(
      BuildContext context, bool isDark, LocalMusicPlayerState playerState) {
    final position = playerState.position;
    final duration = playerState.duration.inMilliseconds > 0
        ? playerState.duration
        : const Duration(minutes: 3, seconds: 30);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    // 显示的进度：拖动时显示拖动进度，否则显示实际进度
    final displayProgress = _isDraggingProgress ? _dragProgress : progress;
    // 显示的时间：拖动时显示拖动位置的时间
    final displayPosition = _isDraggingProgress
        ? Duration(
            milliseconds: (duration.inMilliseconds * _dragProgress).round())
        : position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // 自定义进度条
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              setState(() {
                _isDraggingProgress = true;
                _dragProgress = progress.clamp(0.0, 1.0);
              });
            },
            onHorizontalDragUpdate: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final width = box.size.width - 80; // 减去左右 padding
              final newProgress =
                  (_dragProgress + details.delta.dx / width).clamp(0.0, 1.0);
              setState(() {
                _dragProgress = newProgress;
              });
            },
            onHorizontalDragEnd: (details) {
              // 拖动结束，seek 到指定位置
              final seekPosition = Duration(
                milliseconds: (duration.inMilliseconds * _dragProgress).round(),
              );
              ref.read(localMusicPlayerProvider.notifier).seekTo(seekPosition);
              setState(() {
                _isDraggingProgress = false;
              });
            },
            onTapDown: (details) {
              // 点击进度条直接跳转
              final RenderBox box = context.findRenderObject() as RenderBox;
              final localPosition = box.globalToLocal(details.globalPosition);
              final width = box.size.width - 80; // 减去左右 padding
              final tapProgress =
                  ((localPosition.dx - 40) / width).clamp(0.0, 1.0);
              setState(() {
                _isDraggingProgress = true;
                _dragProgress = tapProgress;
              });
            },
            onTapUp: (details) {
              // 点击结束，seek 到指定位置
              final seekPosition = Duration(
                milliseconds: (duration.inMilliseconds * _dragProgress).round(),
              );
              ref.read(localMusicPlayerProvider.notifier).seekTo(seekPosition);
              setState(() {
                _isDraggingProgress = false;
              });
            },
            child: Container(
              height: 30, // 增加触摸区域
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                height: _isDraggingProgress ? 6 : 4, // 拖动时变粗
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(_isDraggingProgress ? 3 : 2),
                ),
                child: Stack(
                  children: [
                    // 背景轨道
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        borderRadius:
                            BorderRadius.circular(_isDraggingProgress ? 3 : 2),
                      ),
                    ),
                    // 已播放部分
                    FractionallySizedBox(
                      widthFactor: displayProgress.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: CupertinoColors.activeBlue,
                          borderRadius: BorderRadius.circular(
                              _isDraggingProgress ? 3 : 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 时间显示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(displayPosition),
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
          // 播放/暂停（带加载状态，仅服务器音乐显示 loading）
          _PlayPauseButton(
            isPlaying: playerState.isPlaying,
            isBuffering: playerState.isBuffering &&
                (playerState.currentSong?.isServerMusic ?? false),
            size: 72,
            iconSize: 40,
            isDark: isDark,
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
    final sleepTimerState = ref.watch(sleepTimerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 播放模式
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 36,
                onPressed: () {
                  ref.read(localMusicPlayerProvider.notifier).togglePlayMode();
                },
                child: Icon(
                  _getPlayModeIcon(playMode),
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              // 睡眠定时器
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 36,
                onPressed: () {
                  if (sleepTimerState.isActive) {
                    // 显示倒计时弹窗
                    _showSleepTimerCountdown(context, isDark);
                  } else {
                    // 显示设置弹窗
                    _showSleepTimerSheet(context, isDark);
                  }
                },
                child: Icon(
                  sleepTimerState.isActive
                      ? CupertinoIcons.timer_fill
                      : CupertinoIcons.timer,
                  size: 22,
                  color: sleepTimerState.isActive
                      ? CupertinoColors.activeBlue
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
              ),
              // 喜欢
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 36,
                onPressed: () {
                  // TODO: 添加到喜欢
                },
                child: Icon(
                  CupertinoIcons.heart,
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              // 播放队列
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 36,
                onPressed: () {
                  // 滚动到播放列表页面
                  scrollToPlaylist();
                },
                child: Icon(
                  CupertinoIcons.list_bullet,
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              // 音效
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 36,
                onPressed: () {
                  // TODO: 显示音效设置
                },
                child: Icon(
                  CupertinoIcons.waveform,
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              // 更多
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 36,
                onPressed: () {
                  // TODO: 显示更多选项
                },
                child: Icon(
                  CupertinoIcons.ellipsis,
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
        // 睡眠定时器倒计时显示
        if (sleepTimerState.isActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _formatTimerDuration(sleepTimerState.remainingSeconds),
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.activeBlue,
              ),
            ),
          ),
      ],
    );
  }

  /// 格式化定时器时间
  String _formatTimerDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 显示睡眠定时器设置弹窗
  void _showSleepTimerSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SleepTimerSheet(isDark: isDark),
    );
  }

  /// 显示睡眠定时器倒计时弹窗
  void _showSleepTimerCountdown(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SleepTimerCountdownSheet(isDark: isDark),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 播放/暂停按钮（带加载状态）
class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final bool isBuffering;
  final double size;
  final double iconSize;
  final bool isDark;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isBuffering,
    required this.size,
    required this.iconSize,
    required this.isDark,
    required this.onPressed,
  });

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
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
    // 播放图标需要微调位置
    final iconOffset = widget.isPlaying ? Offset.zero : const Offset(2, 0);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 加载指示器（环形，圆角）
            if (widget.isBuffering)
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  strokeCap: StrokeCap.round,
                  color: widget.isDark
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.4),
                ),
              ),
            // 播放/暂停按钮
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: widget.size - 8,
              height: widget.size - 8,
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
                  offset: iconOffset,
                  child: Icon(
                    widget.isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: widget.iconSize,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 控制按钮（带阴影点击效果）
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final bool isDark;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.isDark,
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
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: widget.isDark ? Colors.white : Colors.black87,
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

/// 睡眠定时器设置弹窗
class _SleepTimerSheet extends ConsumerStatefulWidget {
  final bool isDark;

  const _SleepTimerSheet({required this.isDark});

  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  double _minutes = 30; // 默认 30 分钟
  bool _extendToSongEnd = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Center(
              child: Text(
                '睡眠定时',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 时长显示
            Center(
              child: Text(
                '${_minutes.round()} 分钟',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 进度条
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 20,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                activeTrackColor: CupertinoColors.activeBlue,
                inactiveTrackColor:
                    widget.isDark ? Colors.white12 : Colors.black12,
                thumbColor: CupertinoColors.activeBlue,
                overlayColor: CupertinoColors.activeBlue.withOpacity(0.2),
              ),
              child: Slider(
                value: _minutes,
                min: 1,
                max: 120,
                onChanged: (value) {
                  setState(() {
                    _minutes = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            // 开始按钮
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  ref.read(sleepTimerProvider.notifier).startTimer(
                        _minutes.round(),
                        _extendToSongEnd,
                      );
                  Navigator.of(context).pop();
                },
                child: const Text(
                  '开始',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 分隔线
            Divider(
              color: widget.isDark ? Colors.white12 : Colors.black12,
            ),
            const SizedBox(height: 16),
            // 自动延长选项
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自动延长到整首歌播完',
                        style: TextStyle(
                          fontSize: 15,
                          color: widget.isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '开启将在睡眠定时结束后，将当前歌曲播放完成后停止',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              widget.isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: _extendToSongEnd,
                  activeColor: CupertinoColors.activeBlue,
                  onChanged: (value) {
                    setState(() {
                      _extendToSongEnd = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 睡眠定时器倒计时弹窗
class _SleepTimerCountdownSheet extends ConsumerWidget {
  final bool isDark;

  const _SleepTimerCountdownSheet({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleepTimerState = ref.watch(sleepTimerProvider);
    final minutes = sleepTimerState.remainingSeconds ~/ 60;
    final seconds = sleepTimerState.remainingSeconds % 60;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Text(
              '睡眠定时',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            // 倒计时显示
            Text(
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.activeBlue,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '剩余时间',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            if (sleepTimerState.extendToSongEnd) ...[
              const SizedBox(height: 8),
              Text(
                '将在当前歌曲播放完成后停止',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
            const SizedBox(height: 32),
            // 停止按钮
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: CupertinoColors.destructiveRed,
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  ref.read(sleepTimerProvider.notifier).stopTimer();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  '停止定时',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// LRC 歌词行数据
class _LyricLine {
  final Duration time;
  final String text;

  const _LyricLine(this.time, this.text);
}

/// 判断字符是否为中文
bool _isChinese(int code) {
  // 中文字符 Unicode 范围：\u4e00-\u9fff (CJK统一汉字)
  // 以及 \u3400-\u4dbf (CJK统一汉字扩展A)
  return (code >= 0x4e00 && code <= 0x9fff) ||
      (code >= 0x3400 && code <= 0x4dbf);
}

/// 判断字符是否为日语假名（平假名或片假名）
bool _isJapaneseKana(int code) {
  // 平假名：\u3040-\u309f
  // 片假名：\u30a0-\u30ff
  // 片假名扩展：\u31f0-\u31ff
  return (code >= 0x3040 && code <= 0x309f) ||
      (code >= 0x30a0 && code <= 0x30ff) ||
      (code >= 0x31f0 && code <= 0x31ff);
}

/// 查找字符串中第一个中文字符的索引
int _findFirstChineseIndex(String text) {
  for (int i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (_isChinese(code)) {
      return i;
    }
  }
  return -1;
}

/// 查找日语部分结束、中文部分开始的分界点
/// 返回中文部分开始的索引，如果没找到返回 -1
int _findJapaneseChineseBoundary(String text) {
  bool hasJapaneseKana = false;
  int lastJapaneseOrCommonIndex = -1;

  for (int i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);

    if (_isJapaneseKana(code)) {
      hasJapaneseKana = true;
      lastJapaneseOrCommonIndex = i;
    } else if (_isChinese(code)) {
      // 遇到中文字符
      if (hasJapaneseKana && lastJapaneseOrCommonIndex >= 0) {
        // 之前有日语假名，现在遇到中文，检查是否是纯中文序列的开始
        // 往后看几个字符，如果连续都是中文且没有假名，说明是翻译部分
        int chineseCount = 0;
        int kanaCount = 0;
        for (int j = i; j < text.length && j < i + 10; j++) {
          final c = text.codeUnitAt(j);
          if (_isChinese(c)) {
            chineseCount++;
          } else if (_isJapaneseKana(c)) {
            kanaCount++;
          }
        }
        // 如果后续中文明显多于假名，认为这是分界点
        if (chineseCount >= 3 && kanaCount == 0) {
          return i;
        }
      }
      lastJapaneseOrCommonIndex = i;
    }
  }
  return -1;
}

/// 格式化双语歌词：在不同语言之间自动换行
String _formatBilingualLyrics(String text) {
  // 已经包含换行符的直接返回
  if (text.contains('\n')) return text;

  // 常见的双语分隔符
  // 1. 使用 / 或 | 分隔
  if (text.contains(' / ')) {
    return text.replaceAll(' / ', '\n');
  }
  if (text.contains('/') && !text.contains('://')) {
    // 避免误处理 URL
    final parts = text.split('/');
    if (parts.length == 2 &&
        parts[0].trim().isNotEmpty &&
        parts[1].trim().isNotEmpty) {
      return '${parts[0].trim()}\n${parts[1].trim()}';
    }
  }
  if (text.contains('|')) {
    return text
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('\n');
  }

  // 2. 检测日语后紧跟中文的情况（日语歌词 + 中文翻译）
  final jpCnBoundary = _findJapaneseChineseBoundary(text);
  if (jpCnBoundary > 0) {
    final japanesePart = text.substring(0, jpCnBoundary).trim();
    final chinesePart = text.substring(jpCnBoundary).trim();
    if (japanesePart.isNotEmpty && chinesePart.isNotEmpty) {
      return '$japanesePart\n$chinesePart';
    }
  }

  // 3. 检测英文后紧跟中文的情况（无分隔符）
  // 查找第一个中文字符的位置
  final chineseIndex = _findFirstChineseIndex(text);
  if (chineseIndex > 0) {
    final englishPart = text.substring(0, chineseIndex).trim();
    final chinesePart = text.substring(chineseIndex).trim();
    if (englishPart.isNotEmpty && chinesePart.isNotEmpty) {
      // 确保英文部分确实包含英文字符
      if (RegExp(r'[a-zA-Z]').hasMatch(englishPart)) {
        return '$englishPart\n$chinesePart';
      }
    }
  }

  return text;
}

/// 解析 LRC 歌词
List<_LyricLine> _parseLrc(String lrc) {
  final lines = <_LyricLine>[];
  final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

  for (final line in lrc.split('\n')) {
    final match = regex.firstMatch(line.trim());
    if (match != null) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final msStr = match.group(3)!;
      // 处理两位或三位毫秒
      final milliseconds =
          msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
      var text = match.group(4)?.trim() ?? '';

      // 跳过空歌词行（但保留时间戳用于间奏）
      if (text.isNotEmpty) {
        // 处理双语歌词：自动在分隔符处换行
        text = _formatBilingualLyrics(text);

        lines.add(_LyricLine(
          Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text,
        ));
      }
    }
  }

  // 按时间排序
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

/// 歌词显示组件（带时间轴高亮和自动滚动）
class _LyricsView extends StatefulWidget {
  final String lyrics;
  final Duration position;
  final bool isDark;

  const _LyricsView({
    required this.lyrics,
    required this.position,
    required this.isDark,
  });

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  late List<_LyricLine> _lines;
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = -1;
  // 上次自动滚动的索引（避免重复滚动）
  int _lastScrolledIndex = -1;
  // 每行歌词的 GlobalKey，用于获取位置
  late List<GlobalKey> _itemKeys;
  // 容器高度
  double _containerHeight = 0;
  // 是否已经完成首次滚动定位
  bool _hasInitialScroll = false;
  // 当前行是否已经到达屏幕中间（用于控制顶部虚化）
  bool _hasReachedCenter = false;
  // 是否已经滚动到底部（用于控制底部虚化）
  bool _hasReachedBottom = false;
  // 是否刚刚切换了歌曲（用于强制从顶部开始）
  bool _justSwitchedSong = false;
  // 估算的每行高度
  static const double _estimatedItemHeight = 50.0;

  @override
  void initState() {
    super.initState();
    _lines = _parseLrc(widget.lyrics);
    _itemKeys = List.generate(_lines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(_LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      // 歌曲切换，重置所有状态
      _lines = _parseLrc(widget.lyrics);
      _itemKeys = List.generate(_lines.length, (_) => GlobalKey());
      _currentIndex = -1;
      _lastScrolledIndex = -1;
      _hasInitialScroll = false; // 重置首次滚动标记
      _hasReachedCenter = false; // 重置居中状态
      _hasReachedBottom = false; // 重置底部状态
      _justSwitchedSong = true; // 标记刚刚切换了歌曲

      // 滚动回顶部
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }

      // 触发 UI 更新以应用虚化状态变化
      setState(() {});
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 根据当前播放位置找到对应的歌词索引
  /// 如果位置在第一句歌词之前，返回 0（最近的歌词）
  /// 如果位置在最后一句歌词之后，返回最后一句的索引
  int _findCurrentIndex(Duration position) {
    if (_lines.isEmpty) return -1;

    // 如果位置在第一句歌词之前，返回第一句（最近的）
    if (position < _lines.first.time) {
      return 0;
    }

    // 正常查找：找到最后一个时间小于等于当前位置的歌词
    for (int i = _lines.length - 1; i >= 0; i--) {
      if (position >= _lines[i].time) {
        return i;
      }
    }

    // 不应该到达这里，但作为保险返回最后一句
    return _lines.length - 1;
  }

  /// 计算当前行的自然位置（不滚动时的位置）
  /// 使用实际渲染的高度，如果无法获取则使用估算值
  double _calculateNaturalPosition(int index) {
    double totalHeight = 16.0; // 顶部 padding

    for (int i = 0; i < index && i < _itemKeys.length; i++) {
      final key = _itemKeys[i];
      final context = key.currentContext;
      if (context != null) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          totalHeight += renderBox.size.height;
          continue;
        }
      }
      // 无法获取实际高度，使用估算值
      totalHeight += _estimatedItemHeight;
    }

    return totalHeight;
  }

  /// 获取当前行的实际高度
  double _getItemHeight(int index) {
    if (index < 0 || index >= _itemKeys.length) return _estimatedItemHeight;

    final key = _itemKeys[index];
    final context = key.currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        return renderBox.size.height;
      }
    }
    return _estimatedItemHeight;
  }

  /// 判断当前行是否已经到达或超过屏幕中间
  bool _shouldScrollToCenter(int index) {
    final naturalPosition = _calculateNaturalPosition(index);
    final itemHeight = _getItemHeight(index);
    final centerThreshold = _containerHeight / 2 - itemHeight / 2;
    return naturalPosition >= centerThreshold;
  }

  /// 判断是否已经到达底部（最后几行不需要居中，让歌词自然停在底部）
  bool _isNearBottom(int index) {
    if (_lines.isEmpty) return false;

    // 计算剩余歌词的总高度（使用实际高度）
    double remainingHeight = 0;
    for (int i = index + 1; i < _lines.length && i < _itemKeys.length; i++) {
      remainingHeight += _getItemHeight(i);
    }

    // 如果剩余高度不足半屏，说明到底部了
    return remainingHeight < _containerHeight / 2;
  }

  /// 滚动到当前歌词
  /// 只有当当前行到达屏幕中间后才开始居中滚动
  /// 到达底部后不再强制居中
  void _scrollToCurrentLine(int index, {bool isInitial = false}) {
    if (!_scrollController.hasClients || index < 0 || index >= _itemKeys.length)
      return;
    if (index == _lastScrolledIndex) return; // 避免重复滚动

    _lastScrolledIndex = index;

    // 判断是否需要居中滚动
    final shouldCenter = _shouldScrollToCenter(index);
    // 判断是否到达底部
    final isNearBottom = _isNearBottom(index);

    // 更新居中状态
    if (shouldCenter && !_hasReachedCenter) {
      setState(() {
        _hasReachedCenter = true;
      });
    } else if (!shouldCenter && _hasReachedCenter) {
      // 快退到中间之前的位置，重置状态并滚动回顶部
      setState(() {
        _hasReachedCenter = false;
        _hasReachedBottom = false;
      });
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // 更新底部状态
    if (isNearBottom && !_hasReachedBottom) {
      setState(() {
        _hasReachedBottom = true;
      });
    } else if (!isNearBottom && _hasReachedBottom) {
      setState(() {
        _hasReachedBottom = false;
      });
    }

    // 如果还没到达中间，不需要滚动
    if (!shouldCenter) {
      return;
    }

    // 如果已经到达底部，不再强制居中，让歌词自然停在底部
    if (isNearBottom) {
      // 滚动到最大位置即可
      final maxOffset = _scrollController.position.maxScrollExtent;
      if (_scrollController.offset < maxOffset) {
        if (isInitial) {
          _scrollController.jumpTo(maxOffset);
        } else {
          _scrollController.animateTo(
            maxOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      }
      return;
    }

    // 获取当前歌词项的 RenderBox
    final key = _itemKeys[index];
    final itemContext = key.currentContext;

    // 如果无法获取 context（ListView 懒加载导致目标项未渲染），使用估算方式滚动
    if (itemContext == null) {
      if (isInitial) {
        // 首次滚动时，使用估算的行高直接跳转
        final naturalPosition = _calculateNaturalPosition(index);
        final centerThreshold = _containerHeight / 2 - _estimatedItemHeight / 2;
        final targetOffset = naturalPosition - centerThreshold;
        final maxOffset = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(targetOffset.clamp(0.0, maxOffset));
        // 跳转后重置标记，让下一帧可以精确滚动
        _lastScrolledIndex = -1;
      }
      return;
    }

    final renderBox = itemContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 获取 ListView 的 RenderBox
    final scrollableRenderBox =
        _scrollController.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (scrollableRenderBox == null) return;

    // 计算当前项相对于 ListView 的位置
    final itemPosition =
        renderBox.localToGlobal(Offset.zero, ancestor: scrollableRenderBox);
    final itemHeight = renderBox.size.height;

    // 计算目标滚动位置（让当前歌词在容器中间）
    final currentOffset = _scrollController.offset;
    final targetOffset = currentOffset +
        itemPosition.dy -
        (_containerHeight / 2) +
        (itemHeight / 2);

    if (isInitial) {
      // 首次滚动直接跳转，不需要动画
      _scrollController.jumpTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    } else {
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 更新当前歌词索引
    final newIndex = _findCurrentIndex(widget.position);

    // 首次渲染或歌词切换后，需要立即滚动到当前位置
    if (!_hasInitialScroll && newIndex >= 0) {
      _hasInitialScroll = true;
      _currentIndex = newIndex;
      _lastScrolledIndex = -1; // 强制触发滚动

      // 如果刚刚切换了歌曲，强制从顶部开始，不滚动到当前位置
      if (_justSwitchedSong) {
        _justSwitchedSong = false;
        // 确保滚动到顶部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      } else {
        // 不是切换歌曲（比如恢复播放位置），需要滚动到当前歌词
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // 首次滚动，使用 isInitial=true 支持估算位置跳转
            _scrollToCurrentLine(_currentIndex, isInitial: true);
            // 跳转后再次尝试精确定位
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _lastScrolledIndex == -1) {
                _scrollToCurrentLine(_currentIndex, isInitial: true);
              }
            });
          }
        });
      }
    } else if (newIndex != _currentIndex) {
      final oldIndex = _currentIndex;
      _currentIndex = newIndex;

      // 检查是否是大幅度跳转（快进/快退超过5行，或者 oldIndex 无效）
      final isLargeJump = oldIndex < 0 || (newIndex - oldIndex).abs() > 5;

      if (isLargeJump) {
        // 大幅度跳转时，重置滚动索引，使用 isInitial 模式确保能滚动到位
        _lastScrolledIndex = -1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToCurrentLine(_currentIndex, isInitial: true);
            // 再次尝试精确定位
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _lastScrolledIndex == -1) {
                _scrollToCurrentLine(_currentIndex, isInitial: true);
              }
            });
          }
        });
      } else {
        // 正常播放，在下一帧滚动
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCurrentLine(_currentIndex);
        });
      }
    }

    if (_lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            fontSize: 18,
            color: widget.isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      );
    }

    // 使用 LayoutBuilder 获取实际可用高度
    return LayoutBuilder(
      builder: (context, constraints) {
        // 保存容器高度
        _containerHeight = constraints.maxHeight;
        // 底部 padding：如果还没到底部，需要留出空间让歌词能滚动到中间
        // 如果已经到底部，不需要额外 padding
        final bottomPadding = _hasReachedBottom ? 16.0 : _containerHeight / 2;

        // 根据顶部和底部状态决定虚化效果
        List<Color> gradientColors;
        if (_hasReachedCenter && _hasReachedBottom) {
          // 中间状态：顶部虚化，底部不虚化
          gradientColors = const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.white,
          ];
        } else if (_hasReachedCenter) {
          // 正常居中状态：顶部和底部都虚化
          gradientColors = const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ];
        } else {
          // 开头状态：顶部不虚化，底部虚化
          gradientColors = const [
            Colors.white,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ];
        }

        return Padding(
          padding: const EdgeInsets.only(left: 40, right: 40),
          // 使用 ShaderMask 让文字在边缘渐变透明
          // 顶部虚化只在当前行到达中间后才启用
          // 底部虚化在到达底部后取消
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradientColors,
                // 顶部30%和底部30%渐变，中间40%完全显示
                stops: const [0.0, 0.30, 0.70, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scrollController,
              // 顶部不需要 padding，底部 padding 让最后一行能滚动到中间
              padding: EdgeInsets.only(top: 16, bottom: bottomPadding),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                final isCurrent = index == _currentIndex;
                final isPast = index < _currentIndex;

                return Container(
                  key: _itemKeys[index],
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.centerLeft,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: isCurrent ? 26 : 21,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent
                          ? (widget.isDark ? Colors.white : Colors.black87)
                          : isPast
                              ? (widget.isDark
                                  ? Colors.white30
                                  : Colors.black26)
                              : (widget.isDark
                                  ? Colors.white54
                                  : Colors.black45),
                      height: 1.4,
                    ),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      scale: isCurrent ? 1.0 : 0.95,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        line.text,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
