/// 封面压缩：入库前把从 EPUB 解析出的封面缩到最长边 512、JPEG 质量 82。
///
/// 书架/列表只显示 ~360px 宽的图，原图动辄几百 KB；压缩后一般 20–60 KB。
/// 任何一步失败都返回原图——绝不因为封面把导入搞挂。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 压缩封面图（[maxEdge] 最长边像素，[quality] JPEG 质量）。
Uint8List compressCover(
  Uint8List bytes, {
  int maxEdge = 512,
  int quality = 82,
}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final longest = math.max(decoded.width, decoded.height);
    final resized = longest > maxEdge
        ? img.copyResize(
            decoded,
            width: (decoded.width * maxEdge / longest).round(),
            height: (decoded.height * maxEdge / longest).round(),
            interpolation: img.Interpolation.average,
          )
        : decoded;
    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    // 原图本来就是压过的小 jpg 时不要反而变大
    return encoded.length < bytes.length ? encoded : bytes;
  } catch (_) {
    return bytes;
  }
}
