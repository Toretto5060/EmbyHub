import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 默认专辑封面组件
/// 当歌曲没有封面时使用此组件显示默认封面
/// 样式：渐变背景 + 金色/黄色双音符图标
class DefaultAlbumCover extends StatelessWidget {
  const DefaultAlbumCover({
    super.key,
    this.size,
    this.iconSize,
    this.borderRadius,
  });

  /// 封面尺寸（宽高相等）
  final double? size;

  /// 图标尺寸
  final double? iconSize;

  /// 圆角半径
  final BorderRadius? borderRadius;

  // 统一的颜色定义
  static const Color _gradientStart = Color(0xFF3A3A3C);
  static const Color _gradientCenter = Color(0xFF2C2C2E);
  static const Color _gradientEnd = Color(0xFF1C1C1E);
  static const Color _iconColor = Color(0xFFFFD700); // 金色/黄色图标

  @override
  Widget build(BuildContext context) {
    final calculatedIconSize = iconSize ?? (size != null ? size! * 0.4 : 40);

    Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gradientStart,
            _gradientCenter,
            _gradientEnd,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.double_music_note, // 双音符图标
          size: calculatedIconSize,
          color: _iconColor,
        ),
      ),
    );

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }
}

/// 带封面图片的组件，如果没有封面则显示默认封面
class AlbumCoverImage extends StatelessWidget {
  const AlbumCoverImage({
    super.key,
    this.albumArt,
    this.size,
    this.iconSize,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  /// 封面图片路径
  final String? albumArt;

  /// 封面尺寸（宽高相等）
  final double? size;

  /// 默认封面的图标尺寸
  final double? iconSize;

  /// 圆角半径
  final BorderRadius? borderRadius;

  /// 图片填充方式
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // 检查是否有有效的封面图片
    final hasValidCover = albumArt != null &&
        albumArt!.isNotEmpty &&
        File(albumArt!).existsSync();

    if (!hasValidCover) {
      return DefaultAlbumCover(
        size: size,
        iconSize: iconSize,
        borderRadius: borderRadius,
      );
    }

    Widget image = Image.file(
      File(albumArt!),
      width: size,
      height: size,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return DefaultAlbumCover(
          size: size,
          iconSize: iconSize,
          borderRadius: borderRadius,
        );
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return image;
  }
}

/// 圆形封面图片组件
class CircularAlbumCover extends StatelessWidget {
  const CircularAlbumCover({
    super.key,
    this.albumArt,
    this.size,
    this.iconSize,
  });

  /// 封面图片路径
  final String? albumArt;

  /// 封面尺寸（直径）
  final double? size;

  /// 默认封面的图标尺寸
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    // 检查是否有有效的封面图片
    final hasValidCover = albumArt != null &&
        albumArt!.isNotEmpty &&
        File(albumArt!).existsSync();

    if (!hasValidCover) {
      return ClipOval(
        child: DefaultAlbumCover(
          size: size,
          iconSize: iconSize,
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        // 使用与默认封面一致的背景色作为加载时的占位
        color: const Color(0xFF2C2C2E),
        child: Image.file(
          File(albumArt!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return DefaultAlbumCover(
              size: size,
              iconSize: iconSize,
            );
          },
        ),
      ),
    );
  }
}
