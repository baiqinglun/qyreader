/// 笔记 / 划线 / 高亮的卡片式分享：三种卡片模板 + 保存到相册 + 系统分享。
///
/// 模板：
/// - 「墨句」深色渐变底，大字引文，适合金句；
/// - 「便签」纸面底 + 标注色侧条，引文 + 想法并重；
/// - 「简约」白底居中排版，极简出处。
///
/// 捕获/保存/分享沿用 `reading_share_sheet` 的模式（RepaintBoundary → PNG →
/// `gal` 存相册，失败退应用目录；`share_plus` 系统分享）。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 卡片内容（笔记 / 划线 / 高亮 / 书签通用）。
class AnnotationCardData {
  /// 构造。
  const AnnotationCardData({
    required this.quote,
    this.note,
    required this.bookTitle,
    this.author,
    required this.createdAt,
    this.colorToken,
    this.kindLabel = '摘录',
  });

  /// 原文（划线 / 高亮的引文；书签为章节标签）。
  final String quote;

  /// 想法（可空）。
  final String? note;

  /// 书名。
  final String bookTitle;

  /// 作者（可空）。
  final String? author;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 标注色 token（yellow / green / blue / rose；书签为 null）。
  final String? colorToken;

  /// 类型标签（划线 / 高亮 / 笔记 / 书签）。
  final String kindLabel;
}

/// 弹出卡片分享面板。
Future<void> showAnnotationShareSheet(
  BuildContext context,
  AnnotationCardData data,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AnnotationShareSheet(data: data),
  );
}

/// 卡片分享面板。
class AnnotationShareSheet extends StatefulWidget {
  /// 构造。
  const AnnotationShareSheet({required this.data, super.key});

  /// 卡片内容。
  final AnnotationCardData data;

  @override
  State<AnnotationShareSheet> createState() => _AnnotationShareSheetState();
}

class _AnnotationShareSheetState extends State<AnnotationShareSheet> {
  static const List<String> _templateNames = <String>['墨句', '便签', '简约'];

  final GlobalKey _posterKey = GlobalKey();
  int _template = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.9;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: RepaintBoundary(
                      key: _posterKey,
                      child: _buildPoster(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 模板切换
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _templateNames.length; i++)
                  Padding(
                    key: ValueKey('annotation-template-$i'),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ChoiceChip(
                      label: Text(_templateNames[i]),
                      selected: _template == i,
                      selectedColor: theme.colorScheme.primary.withValues(
                        alpha: 0.2,
                      ),
                      labelStyle: TextStyle(
                        color: _template == i
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                      onSelected: (_) => setState(() => _template = i),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 动作行
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  _Action(
                    icon: Icons.download_outlined,
                    label: '保存',
                    onTap: _busy ? null : _save,
                  ),
                  _Action(
                    icon: Icons.ios_share_outlined,
                    label: '分享',
                    onTap: _busy ? null : _share,
                  ),
                  _Action(
                    icon: Icons.close,
                    label: '取消',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoster() {
    final data = widget.data;
    return switch (_template) {
      0 => _QuotePoster(data: data),
      1 => _NotePaperPoster(data: data),
      _ => _MinimalPoster(data: data),
    };
  }

  Future<Uint8List?> _capture() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  String _fileName() {
    final d = DateTime.fromMillisecondsSinceEpoch(widget.data.createdAt);
    final stamp =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        '-${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';
    return '笔记-${widget.data.bookTitle}-$stamp';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) {
        _toast('生成图片失败，请重试');
        return;
      }
      final name = _fileName();
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          if (!await Gal.hasAccess(toAlbum: true)) {
            await Gal.requestAccess(toAlbum: true);
          }
          await Gal.putImageBytes(bytes, album: 'QYReader', name: name);
          _toast('已保存到相册');
          return;
        } catch (_) {
          // 相册权限被拒 / 平台不支持：退回到应用目录保存。
        }
      }
      final path = await _writeTemp(bytes, name);
      _toast('已保存到 $path');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) {
        _toast('生成图片失败，请重试');
        return;
      }
      final path = await _writeTemp(bytes, _fileName());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'image/png')],
          text: '${widget.data.kindLabel} · ${widget.data.bookTitle}',
        ),
      );
    } catch (e) {
      _toast('分享失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _writeTemp(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory(p.join(dir.path, 'QYReader', 'shares'));
    await out.create(recursive: true);
    final file = File(p.join(out.path, '$name.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 底部动作位（与阅读分享面板同款）。
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标注色 → 卡片强调色（未标注色 / 书签用暖金）。
Color _accentOf(String? colorToken) => switch (colorToken) {
  'green' => const Color(0xFF8FBF7F),
  'blue' => const Color(0xFF7FA8E8),
  'rose' => const Color(0xFFE88FA8),
  'yellow' => const Color(0xFFE5B84B),
  _ => const Color(0xFFD6A400),
};

String _dateLabel(int createdAt) {
  final d = DateTime.fromMillisecondsSinceEpoch(createdAt);
  return '${d.year}年${d.month}月${d.day}日';
}

String _authorLabel(String? author) =>
    (author ?? '').trim().isEmpty ? '未知作者' : author!.trim();

/// 模板一「墨句」：深色渐变底，大字引文。
class _QuotePoster extends StatelessWidget {
  const _QuotePoster({required this.data});

  final AnnotationCardData data;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD6A400);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF23262C), Color(0xFF15171B)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '「',
                style: TextStyle(
                  color: accent,
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'QYReader',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              data.quote,
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF2F2F0),
                fontSize: 21,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (data.note != null && data.note!.trim().isNotEmpty) ...[
            Container(
              width: 28,
              height: 1,
              color: accent,
              margin: const EdgeInsets.only(bottom: 10),
            ),
            Text(
              data.note!,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(color: Color(0xFF3A3E45), height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '《${data.bookTitle}》 ${_authorLabel(data.author)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                  ),
                ),
              ),
              Text(
                _dateLabel(data.createdAt),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 模板二「便签」：纸面底 + 标注色侧条，引文与想法并重。
class _NotePaperPoster extends StatelessWidget {
  const _NotePaperPoster({required this.data});

  final AnnotationCardData data;

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFFFFDF6);
    const ink = Color(0xFF33312C);
    final accent = _accentOf(data.colorToken);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: const BoxDecoration(color: paper),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                data.kindLabel,
                style: const TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                _dateLabel(data.createdAt),
                style: TextStyle(
                  color: ink.withValues(alpha: 0.4),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Text(
              data.quote,
              maxLines: 11,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ink,
                fontSize: 19,
                height: 1.65,
              ),
            ),
          ),
          if (data.note != null && data.note!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                data.note!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFE4DFD2), height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '《${data.bookTitle}》 ${_authorLabel(data.author)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.6),
                    fontSize: 11.5,
                  ),
                ),
              ),
              Text(
                'QYReader',
                style: TextStyle(
                  color: ink.withValues(alpha: 0.4),
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 模板三「简约」：白底居中排版，极简出处。
class _MinimalPoster extends StatelessWidget {
  const _MinimalPoster({required this.data});

  final AnnotationCardData data;

  @override
  Widget build(BuildContext context) {
    const bg = Colors.white;
    const ink = Color(0xFF262626);
    final accent = _accentOf(data.colorToken);
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      decoration: const BoxDecoration(color: bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            data.kindLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ink.withValues(alpha: 0.4),
              fontSize: 11,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(width: 26, height: 2, color: accent),
          ),
          Expanded(
            child: Center(
              child: Text(
                data.quote,
                maxLines: 12,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ink,
                  fontSize: 19,
                  height: 1.7,
                ),
              ),
            ),
          ),
          if (data.note != null && data.note!.trim().isNotEmpty) ...[
            Text(
              data.note!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.withValues(alpha: 0.55),
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Divider(color: Color(0xFFEAEAEA), height: 20),
          Text(
            '《${data.bookTitle}》',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_authorLabel(data.author)} · ${_dateLabel(data.createdAt)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ink.withValues(alpha: 0.4),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
