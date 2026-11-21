/// 「我的阅读」分享海报：深色 / 浅色模板、保存到相册、系统分享。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'my_reading_data.dart';

/// 弹出阅读分享面板。
Future<void> showReadingShareSheet(
  BuildContext context,
  List<MyReadingBook> books, {
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReadingShareSheet(books: books, title: title),
  );
}

/// 分享面板。
class ReadingShareSheet extends StatefulWidget {
  const ReadingShareSheet({required this.books, this.title, super.key});

  /// 要分享的书。
  final List<MyReadingBook> books;

  /// 可选标题（年 / 月分享），null = 全部。
  final String? title;

  @override
  State<ReadingShareSheet> createState() => _ReadingShareSheetState();
}

class _ReadingShareSheetState extends State<ReadingShareSheet> {
  final GlobalKey _posterKey = GlobalKey();
  bool _dark = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.92;
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: RepaintBoundary(
                      key: _posterKey,
                      child: _ReadingPoster(
                        books: widget.books,
                        dark: _dark,
                        title: widget.title,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  _Action(
                    icon: Icons.auto_awesome_mosaic_outlined,
                    label: '模板',
                    onTap: _busy ? null : () => setState(() => _dark = !_dark),
                  ),
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
          text: widget.title == null ? '我的阅读' : '我的阅读 · ${widget.title}',
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

  String _fileName() {
    final now = DateTime.now();
    final stamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'qyreader-reading-$stamp';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
                child: Icon(icon, size: 24),
              ),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// 海报本体（固定 9:16，照片墙式时间线）。
class _ReadingPoster extends StatelessWidget {
  const _ReadingPoster({required this.books, required this.dark, this.title});

  final List<MyReadingBook> books;
  final bool dark;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF141517) : const Color(0xFFF7F3EC);
    final fg = dark ? Colors.white : const Color(0xFF1C1B19);
    final muted = fg.withValues(alpha: 0.62);
    final gold = dark ? const Color(0xFFCDA96A) : const Color(0xFF9A7434);
    final card = dark ? const Color(0xFF222326) : Colors.white;
    final visible = books.take(6).toList();
    final remaining = math.max(0, books.length - visible.length);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${books.length}',
                            style: TextStyle(
                              color: gold,
                              fontSize: 58,
                              fontWeight: FontWeight.w300,
                              height: 0.95,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '本',
                            style: TextStyle(
                              color: muted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'BOOK',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          letterSpacing: 4,
                        ),
                      ),
                      if (title != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: gold, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: gold.withValues(alpha: 0.18),
                      child: Icon(Icons.person_outline, color: gold, size: 28),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'QYReader 读者',
                      style: TextStyle(color: fg, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _PosterBookRow(
                  book: visible[index],
                  dark: dark,
                  fg: fg,
                  muted: muted,
                  card: card,
                  gold: gold,
                ),
              ),
            ),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ $remaining 本',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterBookRow extends StatelessWidget {
  const _PosterBookRow({
    required this.book,
    required this.dark,
    required this.fg,
    required this.muted,
    required this.card,
    required this.gold,
  });

  final MyReadingBook book;
  final bool dark;
  final Color fg;
  final Color muted;
  final Color card;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final line = fg.withValues(alpha: 0.16);
    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  myReadingMonthDay(book.date),
                  style: TextStyle(
                    color: gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${book.date.year}',
                  style: TextStyle(color: muted, fontSize: 9),
                ),
              ],
            ),
          ),
          Container(width: 1, color: line, height: double.infinity),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          book.book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          book.book.author?.trim().isNotEmpty == true
                              ? book.book.author!.trim()
                              : '未知作者',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 9),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatReadingDuration(book.durationMs)} · '
                          '${formatReadingChars(book.charsRead)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _PosterCover(book: book, width: 40, height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterCover extends StatelessWidget {
  const _PosterCover({
    required this.book,
    required this.width,
    required this.height,
  });

  final MyReadingBook book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final path = book.book.coverPath ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: path.isEmpty
            ? _placeholder()
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: const Color(0xFF8A8F98).withValues(alpha: 0.22),
    child: const Icon(
      Icons.menu_book_outlined,
      size: 18,
      color: Color(0xFF8A8F98),
    ),
  );
}
