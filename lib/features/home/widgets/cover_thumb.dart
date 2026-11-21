/// 首页用的封面缩略图：文件不存在或解码失败时显示占位图标。
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 固定尺寸的封面缩略图。
class CoverThumb extends StatelessWidget {
  /// 构造。
  const CoverThumb({
    required this.path,
    required this.width,
    required this.height,
    required this.radius,
    this.shadow = false,
    super.key,
  });

  /// 封面文件路径（可为空）。
  final String? path;

  /// 宽。
  final double width;

  /// 高。
  final double height;

  /// 圆角。
  final double radius;

  /// 是否加一层轻投影（年度封面流用）。
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.menu_book_outlined,
        size: math.min(width, height) * 0.4,
        color: scheme.outline,
      ),
    );
    final Widget image;
    if (path == null || path!.isEmpty) {
      image = placeholder;
    } else {
      image = Image.file(
        File(path!),
        fit: BoxFit.cover,
        cacheWidth: (width * 3).round(),
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: scheme.surfaceContainerHighest,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: image),
    );
  }
}
