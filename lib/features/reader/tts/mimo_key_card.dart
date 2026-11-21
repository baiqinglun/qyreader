/// MiMo 云端 API Key 配置卡：听书弹窗与全屏听书页共用。
///
/// Key 存 flutter_secure_storage（`MimoTtsCredentials`，不进明文 prefs）；
/// 保存后下一次「开始朗读」生效（控制器每次 start 重新读 Key）。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';
import 'mimo_tts_client.dart';

/// MiMo 云端 API Key 配置卡。
class MimoKeyCard extends StatefulWidget {
  /// 构造。
  const MimoKeyCard({required this.theme, super.key});

  /// 阅读主题（配色跟随）。
  final ReadingTheme theme;

  @override
  State<MimoKeyCard> createState() => _MimoKeyCardState();
}

class _MimoKeyCardState extends State<MimoKeyCard> {
  final TextEditingController _controller = TextEditingController();
  final MimoTtsCredentials _credentials = MimoTtsCredentials();
  bool _configured = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _credentials.read();
    if (!mounted) return;
    setState(() => _configured = key != null);
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    await _credentials.save(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _configured = true;
      _controller.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存 MiMo API Key，下次开始朗读生效')));
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _credentials.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _configured = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.theme.chromeForeground;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.vpn_key_rounded,
                size: 16,
                color: _configured
                    ? widget.theme.accent
                    : fg.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _configured
                      ? 'MiMo API Key 已配置'
                      : '还没有配置 API Key（mimo.mi.com 开放平台获取）',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('mimo-key-field'),
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: fg, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: '粘贴 API Key',
              hintStyle: TextStyle(
                color: fg.withValues(alpha: 0.35),
                fontSize: 13,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonal(
                key: const ValueKey('mimo-key-save'),
                onPressed: _busy ? null : _save,
                child: const Text('保存'),
              ),
              const SizedBox(width: 8),
              if (_configured)
                TextButton(
                  key: const ValueKey('mimo-key-clear'),
                  onPressed: _busy ? null : _clear,
                  child: const Text('清除'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
