/// 阅读页「边距直调」覆盖层：正文 / 页眉 / 页脚三页。
///
/// 参考稿的交互：把正文、页眉、页脚的实际区域用细框标出来，四周的数字
/// 就是对应边距；点数字可选中，拖动数字或点 −/+ 实时改变，页面按新边距
/// 即时重排预览。中间悬浮条切换三组、复位、显示/隐藏参考框、勾选退出。
///
/// 只负责「草稿 + 手势 + 视觉」；预览与落库由 ReaderPage 注入的回调处理。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../reader_settings.dart';

/// 边距直调覆盖层。
class MarginEditorOverlay extends StatefulWidget {
  const MarginEditorOverlay({
    required this.settings,
    required this.textScale,
    required this.initialGroup,
    required this.onPreview,
    required this.onCommit,
    required this.onClose,
    super.key,
  });

  /// 进入时的持久化设置。
  final ReadingSettings settings;

  /// 系统字体缩放（页眉/页脚文字高度要按它算）。
  final double textScale;

  /// 初始分组。
  final MarginGroup initialGroup;

  /// 拖动/步进中的实时预览（不落库）。
  final ValueChanged<ReadingSettings> onPreview;

  /// 一次调整结束（松手 / 点 −+）后提交。
  final ValueChanged<ReadingSettings> onCommit;

  /// 勾选完成（由上层提交并关闭）。
  final VoidCallback onClose;

  @override
  State<MarginEditorOverlay> createState() => _MarginEditorOverlayState();
}

class _MarginEditorOverlayState extends State<MarginEditorOverlay> {
  late ReadingSettings _draft;
  late MarginGroup _group;
  late String _edge;
  bool _guidesVisible = true;

  static const double _chipW = 46;
  static const double _chipH = 36;
  static const double _selectedW = 116;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _group = widget.initialGroup;
    _edge = _defaultEdge(_group);
  }

  static String _defaultEdge(MarginGroup group) =>
      group == MarginGroup.footer ? 'bottom' : 'top';

  bool get _headerVisible =>
      _draft.headerLeft != RunningContent.none ||
      _draft.headerCenter != RunningContent.none ||
      _draft.headerRight != RunningContent.none;

  bool get _footerVisible =>
      _draft.footerLeft != RunningContent.none ||
      _draft.footerCenter != RunningContent.none ||
      _draft.footerRight != RunningContent.none;

  double get _headerTextH =>
      _headerVisible ? _draft.headerFontSize * widget.textScale * 1.5 : 0;

  double get _footerTextH =>
      _footerVisible ? _draft.headerFontSize * widget.textScale * 1.5 : 0;

  _MarginGeo _geometry(Size size) {
    final headerTop = _draft.headerMarginTop;
    final headerBottom = headerTop + _headerTextH;
    final footerBottom = size.height - _draft.footerMarginBottom;
    final footerTop = footerBottom - _footerTextH;
    final body = Rect.fromLTRB(
      _draft.marginLeft,
      headerBottom + _draft.marginTop,
      size.width - _draft.marginRight,
      footerTop - _draft.marginBottom,
    );
    return _MarginGeo(
      body: body,
      header: Rect.fromLTRB(
        _draft.headerMarginLeft,
        headerTop,
        size.width - _draft.headerMarginRight,
        headerBottom,
      ),
      footer: Rect.fromLTRB(
        _draft.footerMarginLeft,
        footerTop,
        size.width - _draft.footerMarginRight,
        footerBottom,
      ),
      headerTextBottom: headerBottom,
      footerTextTop: footerTop,
    );
  }

  double _valueOf(String edge) => switch (_group) {
        MarginGroup.body => switch (edge) {
            'top' => _draft.marginTop,
            'bottom' => _draft.marginBottom,
            'left' => _draft.marginLeft,
            _ => _draft.marginRight,
          },
        MarginGroup.header => switch (edge) {
            'top' => _draft.headerMarginTop,
            'bottom' => _draft.marginTop,
            'left' => _draft.headerMarginLeft,
            _ => _draft.headerMarginRight,
          },
        MarginGroup.footer => switch (edge) {
            'top' => _draft.marginBottom,
            'bottom' => _draft.footerMarginBottom,
            'left' => _draft.footerMarginLeft,
            _ => _draft.footerMarginRight,
          },
      };

  ReadingSettings _withValue(String edge, double raw) {
    final value = raw.clamp(0.0, 64.0).toDouble();
    return switch (_group) {
      MarginGroup.body => switch (edge) {
          'top' => _draft.copyWith(marginTop: value),
          'bottom' => _draft.copyWith(marginBottom: value),
          'left' => _draft.copyWith(marginLeft: value),
          _ => _draft.copyWith(marginRight: value),
        },
      MarginGroup.header => switch (edge) {
          'top' => _draft.copyWith(headerMarginTop: value),
          'bottom' => _draft.copyWith(marginTop: value),
          'left' => _draft.copyWith(headerMarginLeft: value),
          _ => _draft.copyWith(headerMarginRight: value),
        },
      MarginGroup.footer => switch (edge) {
          'top' => _draft.copyWith(marginBottom: value),
          'bottom' => _draft.copyWith(footerMarginBottom: value),
          'left' => _draft.copyWith(footerMarginLeft: value),
          _ => _draft.copyWith(footerMarginRight: value),
        },
    };
  }

  /// 拖动方向 → 边距增量的符号（正文上边距往下的拖动是「变大」）。
  double _dragSign(String edge) => switch (_group) {
        MarginGroup.body => edge == 'top' || edge == 'left' ? 1 : -1,
        MarginGroup.header =>
          edge == 'right' ? -1 : 1, // 顶部/底部/左边都是越往右/下越大
        MarginGroup.footer =>
          edge == 'top' || edge == 'bottom' ? -1 : (edge == 'left' ? 1 : -1),
      };

  void _apply(ReadingSettings next, {bool commit = false}) {
    setState(() => _draft = next);
    widget.onPreview(next);
    if (commit) widget.onCommit(next);
  }

  void _updateEdge(String edge, double delta) {
    _apply(_withValue(edge, _valueOf(edge) + delta));
  }

  void _step(String edge, int direction) {
    _apply(_withValue(edge, _valueOf(edge) + direction), commit: true);
  }

  void _select(String edge) {
    if (_edge == edge) return;
    setState(() => _edge = edge);
  }

  void _switchGroup(MarginGroup? group) {
    if (group == null || group == _group) return;
    setState(() {
      _group = group;
      _edge = _defaultEdge(group);
    });
  }

  void _resetGroup() {
    final next = switch (_group) {
      MarginGroup.body => _draft.copyWith(
          marginLeft: 16,
          marginRight: 16,
          marginTop: 12,
          marginBottom: 12,
        ),
      MarginGroup.header => _draft.copyWith(
          headerMarginTop: 6,
          headerMarginLeft: 16,
          headerMarginRight: 16,
        ),
      MarginGroup.footer => _draft.copyWith(
          footerMarginLeft: 16,
          footerMarginRight: 16,
          footerMarginBottom: 6,
        ),
    };
    _apply(next, commit: true);
  }

  @override
  Widget build(BuildContext context) {
    final readingTheme = _draft.theme;
    final fg = readingTheme.chromeForeground;
    final surface = readingTheme.chromeSurface;
    final accent = readingTheme.accent;

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final geo = _geometry(size);
          final chips = _chips(geo, size);
          return Stack(
            children: [
              // 吃掉所有手势，避免边距拖动时翻页。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
              if (_guidesVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MarginGuidePainter(
                        geo: geo,
                        group: _group,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              if (_guidesVisible)
                for (final chip in chips)
                  _chip(context, chip, fg, accent, size),
              Center(
                child: _toolbar(context, fg, surface, accent),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_ChipData> _chips(_MarginGeo geo, Size size) {
    final cx = size.width / 2;
    return switch (_group) {
      MarginGroup.body => [
          _ChipData('top', Offset(cx, geo.body.top), false),
          _ChipData('bottom', Offset(cx, geo.body.bottom), false),
          _ChipData(
            'left',
            // 侧边数字放 38% 高度：正中间会和悬浮工具栏撞在一起。
            Offset(geo.body.left, geo.body.top + geo.body.height * 0.38),
            true,
          ),
          _ChipData(
            'right',
            Offset(geo.body.right, geo.body.top + geo.body.height * 0.38),
            true,
          ),
        ],
      MarginGroup.header => [
          _ChipData('top', Offset(cx, geo.header.top), false),
          _ChipData(
            'bottom',
            Offset(cx, (geo.headerTextBottom + geo.body.top) / 2),
            false,
          ),
          _ChipData(
            'left',
            Offset(geo.header.left, geo.header.center.dy),
            true,
          ),
          _ChipData(
            'right',
            Offset(geo.header.right, geo.header.center.dy),
            true,
          ),
        ],
      MarginGroup.footer => [
          _ChipData(
            'top',
            Offset(cx, (geo.body.bottom + geo.footerTextTop) / 2),
            false,
          ),
          _ChipData('bottom', Offset(cx, geo.footer.bottom), false),
          _ChipData(
            'left',
            Offset(geo.footer.left, geo.footer.center.dy),
            true,
          ),
          _ChipData(
            'right',
            Offset(geo.footer.right, geo.footer.center.dy),
            true,
          ),
        ],
    };
  }

  Widget _chip(
    BuildContext context,
    _ChipData chip,
    Color fg,
    Color accent,
    Size screen,
  ) {
    final selected = _edge == chip.edge;
    final width = selected ? _selectedW : _chipW;
    final height = selected ? 42.0 : _chipH;
    final value = _valueOf(chip.edge).round();
    // 数字贴在参考框**外侧**（参考稿就是这样）：不压住正文第一行。
    final double left;
    final double top;
    switch (chip.edge) {
      case 'top':
        left = chip.center.dx - width / 2;
        top = chip.center.dy - height - 4;
      case 'bottom':
        left = chip.center.dx - width / 2;
        top = chip.center.dy + 4;
      case 'left':
        left = chip.center.dx - width - 4;
        top = chip.center.dy - height / 2;
      default: // right
        left = chip.center.dx + 4;
        top = chip.center.dy - height / 2;
    }
    // 数字贴边时也保证整块可点（左边距 0 的芯片不会一半在屏幕外）。
    final clampedLeft = left
        .clamp(2.0, math.max(2.0, screen.width - width - 2))
        .toDouble();
    final clampedTop = top
        .clamp(2.0, math.max(2.0, screen.height - height - 2))
        .toDouble();

    return Positioned(
      left: clampedLeft,
      top: clampedTop,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(chip.edge),
        onPanStart: (_) => _select(chip.edge),
        onPanUpdate: (d) {
          final delta = chip.horizontal ? d.delta.dx : d.delta.dy;
          _updateEdge(chip.edge, delta * _dragSign(chip.edge));
        },
        onPanEnd: (_) => widget.onCommit(_draft),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.30)
                : accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 0.85 : 0.45),
            ),
          ),
          child: selected
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StepButton(
                      key: ValueKey('margin-minus-${chip.edge}'),
                      icon: Icons.remove,
                      color: fg,
                      onTap: () => _step(chip.edge, -1),
                    ),
                    Text(
                      '$value',
                      key: ValueKey('margin-value-${chip.edge}'),
                      style: TextStyle(
                        color: fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _StepButton(
                      key: ValueKey('margin-plus-${chip.edge}'),
                      icon: Icons.add,
                      color: fg,
                      onTap: () => _step(chip.edge, 1),
                    ),
                  ],
                )
              : Center(
                  child: Text(
                    '$value',
                    key: ValueKey('margin-value-${chip.edge}'),
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _toolbar(
    BuildContext context,
    Color fg,
    Color surface,
    Color accent,
  ) {
    return Container(
      key: const ValueKey('margin-toolbar'),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<MarginGroup>(
              key: const ValueKey('margin-group'),
              value: _group,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: surface,
              icon: Icon(Icons.expand_more, size: 18, color: fg),
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: [
                for (final g in MarginGroup.values)
                  DropdownMenuItem(
                    value: g,
                    child: Text(g.title),
                  ),
              ],
              onChanged: _switchGroup,
            ),
          ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: fg.withValues(alpha: 0.12),
          ),
          _ToolButton(
            key: const ValueKey('margin-reset'),
            icon: Icons.restart_alt,
            color: fg,
            onTap: _resetGroup,
          ),
          _ToolButton(
            key: const ValueKey('margin-guides'),
            icon: _guidesVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: fg,
            onTap: () => setState(() => _guidesVisible = !_guidesVisible),
          ),
          const SizedBox(width: 2),
          _ToolButton(
            key: const ValueKey('margin-check'),
            icon: Icons.check,
            color: const Color(0xFFFFFFFF),
            background: accent,
            onTap: () => widget.onClose(),
          ),
        ],
      ),
    );
  }
}

/// 一个边距数字（位置 + 方向）。
class _ChipData {
  const _ChipData(this.edge, this.center, this.horizontal);

  final String edge;
  final Offset center;
  final bool horizontal;
}

/// 当前分组的几何（屏幕坐标）。
class _MarginGeo {
  const _MarginGeo({
    required this.body,
    required this.header,
    required this.footer,
    required this.headerTextBottom,
    required this.footerTextTop,
  });

  final Rect body;
  final Rect header;
  final Rect footer;
  final double headerTextBottom;
  final double footerTextTop;
}

/// 细框参考线：正文四边 / 页眉带 / 页脚带。
class _MarginGuidePainter extends CustomPainter {
  const _MarginGuidePainter({
    required this.geo,
    required this.group,
    required this.color,
  });

  final _MarginGeo geo;
  final MarginGroup group;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.75);

    switch (group) {
      case MarginGroup.body:
        canvas.drawRect(geo.body, paint);
      case MarginGroup.header:
        // 页眉文字带（没有页眉内容时给一个可见的最小高度）。
        final band = geo.header.height < 18
            ? Rect.fromLTWH(
                geo.header.left,
                geo.header.top,
                geo.header.width,
                18,
              )
            : geo.header;
        canvas.drawRect(band, paint);
        _dashedLine(
          canvas,
          Offset(geo.header.left, geo.headerTextBottom),
          Offset(geo.header.right, geo.headerTextBottom),
          paint,
        );
      case MarginGroup.footer:
        final band = geo.footer.height < 18
            ? Rect.fromLTWH(
                geo.footer.left,
                geo.footer.bottom - 18,
                geo.footer.width,
                18,
              )
            : geo.footer;
        canvas.drawRect(band, paint);
        _dashedLine(
          canvas,
          Offset(geo.footer.left, geo.footerTextTop),
          Offset(geo.footer.right, geo.footerTextTop),
          paint,
        );
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint..strokeWidth = 1);
      t = end + gap;
    }
  }

  @override
  bool shouldRepaint(_MarginGuidePainter old) =>
      old.geo.body != geo.body ||
      old.geo.header != geo.header ||
      old.geo.footer != geo.footer ||
      old.group != group ||
      old.color != color;
}

/// 选中数字左右的 −/+。
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 32,
        height: 40,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

/// 工具栏圆形按钮。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.background,
    super.key,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
