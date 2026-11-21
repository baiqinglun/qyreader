import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读器键盘和鼠标翻页；快捷键在本机保存。
class ReaderInput extends StatefulWidget {
  const ReaderInput({
    required this.child,
    required this.previous,
    required this.next,
    this.wheelEnabled = true,
    super.key,
  });
  final Widget child;
  final VoidCallback previous;
  final VoidCallback next;
  final bool wheelEnabled;
  @override
  State<ReaderInput> createState() => ReaderInputState();
}

class ReaderInputState extends State<ReaderInput> {
  int _previous = LogicalKeyboardKey.arrowLeft.keyId;
  int _next = LogicalKeyboardKey.arrowRight.keyId;
  bool _wheel = true;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _previous =
          prefs.getInt('reader.key.previous') ??
          LogicalKeyboardKey.arrowLeft.keyId;
      _next =
          prefs.getInt('reader.key.next') ??
          LogicalKeyboardKey.arrowRight.keyId;
      _wheel = prefs.getBool('reader.mouse.wheel') ?? true;
    });
  }

  Future<void> configure() async {
    var previous = _previous;
    var next = _next;
    var wheel = _wheel;
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> record(bool isPrevious) async {
            final key = await showDialog<LogicalKeyboardKey>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(isPrevious ? '设置上一页按键' : '设置下一页按键'),
                content: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      Navigator.pop(ctx, event.logicalKey);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: const Text('请按下一个按键'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                ],
              ),
            );
            if (key == null || !context.mounted) return;
            if (key.keyId == (isPrevious ? next : previous)) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('上一页和下一页不能使用同一个按键')));
              return;
            }
            setDialogState(() {
              if (isPrevious) {
                previous = key.keyId;
              } else {
                next = key.keyId;
              }
            });
          }

          String label(int id) =>
              LogicalKeyboardKey.findKeyByKeyId(id)?.keyLabel ?? '按键 $id';
          return AlertDialog(
            title: const Text('键盘与鼠标翻页'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('上一页'),
                  subtitle: Text(label(previous)),
                  trailing: const Icon(Icons.edit),
                  onTap: () => record(true),
                ),
                ListTile(
                  title: const Text('下一页'),
                  subtitle: Text(label(next)),
                  trailing: const Icon(Icons.edit),
                  onTap: () => record(false),
                ),
                SwitchListTile(
                  title: const Text('鼠标滚轮翻页'),
                  value: wheel,
                  onChanged: (v) => setDialogState(() => wheel = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader.key.previous', previous);
    await prefs.setInt('reader.key.next', next);
    await prefs.setBool('reader.mouse.wheel', wheel);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent || ModalRoute.of(context)?.isCurrent != true) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey.keyId == _previous) {
        widget.previous();
        return KeyEventResult.handled;
      }
      if (event.logicalKey.keyId == _next) {
        widget.next();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Listener(
      onPointerSignal: (event) {
        if (!widget.wheelEnabled ||
            !_wheel ||
            event is! PointerScrollEvent ||
            ModalRoute.of(context)?.isCurrent != true ||
            event.scrollDelta.dy == 0) {
          return;
        }
        final now = DateTime.now();
        if (now.difference(_lastWheel).inMilliseconds < 350) return;
        _lastWheel = now;
        if (event.scrollDelta.dy > 0) {
          widget.next();
        } else {
          widget.previous();
        }
      },
      child: widget.child,
    ),
  );
}
