/// 同步后端设置：本地桶 / S3（端点、桶、前缀、区域、密钥、连接测试）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../data/sync/s3_object_store.dart';
import '../../../data/sync/sync_backend_store.dart';

/// 打开同步后端设置页。
Future<void> showSyncBackendSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const SyncBackendSettingsPage(),
    ),
  );
}

/// 同步后端设置页。
class SyncBackendSettingsPage extends ConsumerStatefulWidget {
  const SyncBackendSettingsPage({super.key});

  @override
  ConsumerState<SyncBackendSettingsPage> createState() =>
      _SyncBackendSettingsPageState();
}

class _SyncBackendSettingsPageState
    extends ConsumerState<SyncBackendSettingsPage> {
  final _endPoint = TextEditingController();
  final _bucket = TextEditingController();
  final _prefix = TextEditingController();
  final _region = TextEditingController();
  final _port = TextEditingController();
  final _accessKey = TextEditingController();
  final _secretKey = TextEditingController();

  SyncBackendType _type = SyncBackendType.local;
  bool _useSSL = true;
  bool _loading = true;
  bool _testing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(syncBackendStoreProvider);
    final config = await store.loadConfig();
    final creds = await store.loadCredentials();
    if (!mounted) return;
    setState(() {
      _type = config.type;
      _endPoint.text = config.endPoint;
      _bucket.text = config.bucket;
      _prefix.text = config.prefix;
      _region.text = config.region ?? '';
      _port.text = config.port?.toString() ?? '';
      _accessKey.text = creds.accessKey;
      _secretKey.text = creds.secretKey;
      _useSSL = config.useSSL;
      _loading = false;
    });
  }

  SyncBackendConfig _configOf() => SyncBackendConfig(
        type: _type,
        endPoint: _endPoint.text.trim(),
        bucket: _bucket.text.trim(),
        prefix: _prefix.text.trim(),
        region: _region.text.trim().isEmpty ? null : _region.text.trim(),
        useSSL: _useSSL,
        port: int.tryParse(_port.text.trim()),
      );

  SyncCredentials _credsOf() => SyncCredentials(
        accessKey: _accessKey.text.trim(),
        secretKey: _secretKey.text.trim(),
      );

  Future<void> _save() async {
    final store = ref.read(syncBackendStoreProvider);
    await store.saveConfig(_configOf());
    await store.saveCredentials(_credsOf());
    if (!mounted) return;
    setState(() => _message = '已保存；下次同步生效');
  }

  Future<void> _testConnection() async {
    final config = _configOf();
    final creds = _credsOf();
    if (!config.s3Complete || !creds.configured) {
      setState(() => _message = '请先填齐端点、桶、AccessKey、SecretKey');
      return;
    }
    setState(() {
      _testing = true;
      _message = null;
    });
    final store = S3ObjectStore(
      endPoint: config.endPoint,
      bucket: config.bucket,
      prefix: config.prefix,
      accessKey: creds.accessKey,
      secretKey: creds.secretKey,
      region: config.region,
      useSSL: config.useSSL,
      port: config.port,
    );
    final error = await store.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _message = error ?? '连接成功';
    });
  }

  @override
  void dispose() {
    for (final c in [
      _endPoint,
      _bucket,
      _prefix,
      _region,
      _port,
      _accessKey,
      _secretKey,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reading = dark ? ReadingTheme.night : ReadingTheme.paper;
    final fg = reading.chromeForeground;
    return Scaffold(
      backgroundColor: reading.background,
      appBar: AppBar(
        backgroundColor: reading.chromeSurface,
        foregroundColor: fg,
        title: const Text('同步存储'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: Text(
              '保存',
              style: TextStyle(color: reading.accent),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: reading.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<SyncBackendType>(
                  segments: const [
                    ButtonSegment(
                      value: SyncBackendType.local,
                      label: Text('本地桶'),
                      icon: Icon(Icons.folder_outlined),
                    ),
                    ButtonSegment(
                      value: SyncBackendType.s3,
                      label: Text('S3'),
                      icon: Icon(Icons.cloud_outlined),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) =>
                      setState(() => _type = v.first),
                ),
                const SizedBox(height: 12),
                Text(
                  _type == SyncBackendType.local
                      ? '书籍与标注存本机目录（离线可用，多设备需共享同一目录）'
                      : '对象存 S3 兼容存储（AWS S3 / R2 / B2 / MinIO）',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                if (_type == SyncBackendType.s3) ...[
                  const SizedBox(height: 16),
                  _Field(
                    controller: _endPoint,
                    label: '端点（域名或 IP，不含协议）',
                    hint: 's3.amazonaws.com / minio.example.com',
                    reading: reading,
                  ),
                  _Field(
                    controller: _bucket,
                    label: '桶名',
                    hint: 'qyreader-sync',
                    reading: reading,
                  ),
                  _Field(
                    controller: _prefix,
                    label: '对象前缀',
                    hint: 'qyreader/（限定授权范围）',
                    reading: reading,
                  ),
                  _Field(
                    controller: _region,
                    label: '区域（AWS 必填）',
                    hint: 'ap-east-1',
                    reading: reading,
                  ),
                  _Field(
                    controller: _port,
                    label: '端口（可空）',
                    hint: '9000',
                    keyboardType: TextInputType.number,
                    reading: reading,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: reading.accent,
                    title: Text('使用 HTTPS', style: TextStyle(color: fg)),
                    value: _useSSL,
                    onChanged: (v) => setState(() => _useSSL = v),
                  ),
                  _Field(
                    controller: _accessKey,
                    label: 'AccessKey',
                    reading: reading,
                    secret: false,
                  ),
                  _Field(
                    controller: _secretKey,
                    label: 'SecretKey（存系统安全存储）',
                    reading: reading,
                    secret: true,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _message!.contains('失败') ||
                              _message!.contains('请先')
                          ? Colors.redAccent
                          : reading.accent,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  '说明：更换后端后，「立即同步」会把本机未上传的操作推到新后端；'
                  '同一空间的多台设备需配置相同的桶与前缀。',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.5),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.reading,
    this.hint,
    this.keyboardType,
    this.secret = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ReadingTheme reading;
  final TextInputType? keyboardType;
  final bool secret;

  @override
  Widget build(BuildContext context) {
    final fg = reading.chromeForeground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: secret,
        style: TextStyle(color: fg, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: fg.withValues(alpha: 0.7)),
          hintStyle: TextStyle(color: fg.withValues(alpha: 0.35)),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: fg.withValues(alpha: 0.2)),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: reading.accent),
          ),
        ),
      ),
    );
  }
}
