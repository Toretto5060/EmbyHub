import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 本地文件标识组件
/// 显示一个绿色对勾，表示该歌曲存在本地文件
class LocalFileBadge extends StatelessWidget {
  const LocalFileBadge({
    super.key,
    this.size = 16,
    this.showBackground = true,
  });

  /// 图标大小
  final double size;

  /// 是否显示背景
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    if (showBackground) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: CupertinoColors.activeGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.activeGreen.withOpacity(0.3),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.checkmark,
          size: size * 0.65,
          color: Colors.white,
        ),
      );
    }

    return Icon(
      CupertinoIcons.checkmark_circle_fill,
      size: size,
      color: CupertinoColors.activeGreen,
    );
  }
}

/// 带本地文件标识的封面组件
/// 在封面右下角显示绿色对勾
class AlbumCoverWithLocalBadge extends StatelessWidget {
  const AlbumCoverWithLocalBadge({
    super.key,
    required this.child,
    required this.hasLocalFile,
    this.badgeSize = 16,
    this.badgeOffset = 2,
  });

  /// 封面组件
  final Widget child;

  /// 是否有本地文件
  final bool hasLocalFile;

  /// 标识大小
  final double badgeSize;

  /// 标识偏移量
  final double badgeOffset;

  @override
  Widget build(BuildContext context) {
    if (!hasLocalFile) {
      return child;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -badgeOffset,
          bottom: -badgeOffset,
          child: LocalFileBadge(size: badgeSize),
        ),
      ],
    );
  }
}
