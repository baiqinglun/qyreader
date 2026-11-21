/// 同步设置：自动同步间隔 + 阿里云 OSS 存储（端点、桶、前缀、地域、密钥、
/// 连接测试）。
///
/// 只支持阿里云 OSS：走 S3 兼容接口，必须用虚拟主机风格（桶名拼在域名前），
/// 所以界面上没有服务商选择、也没有「路径风格」开关。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../data/sync/s3_object_store.dart';
import '../../../data/sync/sync_backend_store.dart';
import '../auto_sync.dart';


/// 打开同步设置页。
Future<void> showSyncBackendSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const SyncBackendSettingsPage(),
    ),
  );
}

/// 同步设置页。
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

  SyncBackendType _type = SyncBackendType.s3;
  bool _useSSL = true;
  bool _loading = true;
  bool _testing = false;
  String? _message;

  /// 自动同步间隔（分钟；0 = 关闭）。
  int _autoMinutes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(syncBackendStoreProvider);
    final config = await store.loadConfig();
    final creds = await store.loadCredentials();
    final prefs = await SharedPreferences.getInstance();
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
      _autoMinutes = prefs.getInt(kAutoSyncPrefsKey) ?? 0;
      _loading = false;
    });
  }

  /// 切换自动同步间隔：立即落盘并重排定时器。
  Future<void> _setAutoMinutes(int minutes) async {
    await ref.read(autoSyncProvider).setMinutes(minutes);
    if (!mounted) return;
    setState(() {
      _autoMinutes = minutes;
      _message = '已保存：${kAutoSyncOptions[minutes]}';
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
        // 只有阿里云 OSS：必须虚拟主机风格（桶名.端点）
        pathStyle: false,
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
      pathStyle: config.pathStyle,
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
        title: const Text('同步设置'),
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
                const SizedBox(height: 12),
                // 自动同步：按间隔在后台静默跑 syncNow（前台才执行）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '自动同步',
                        style: TextStyle(color: fg, fontSize: 15),
                      ),
                      const Spacer(),
                      DropdownButton<int>(
                        value: _autoMinutes,
                        underline: const SizedBox.shrink(),
                        dropdownColor: reading.chromeSurface,
                        style: TextStyle(color: fg, fontSize: 15),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: fg.withValues(alpha: 0.6),
                        ),
                        items: [
                          for (final entry in kAutoSyncOptions.entries)
                            DropdownMenuItem<int>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) _setAutoMinutes(v);
                        },
                      ),
                    ],
                  ),
                ),
                Text(
                  '到点后在前台静默同步一次；手动同步不受影响',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                const Divider(height: 32),
                Text(
                  '存储：阿里云 OSS（S3 兼容接口，走「桶名.端点」）',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                ...[
                  const SizedBox(height: 16),
                  _Field(
                    controller: _endPoint,
                    label: 'OSS 端点（地域域名，不含协议）',
                    hint: 'oss-cn-hangzhou.aliyuncs.com',
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
                    label: '地域（签名用，如 oss-cn-hangzhou）',
                    hint: 'oss-cn-hangzhou',
                    reading: reading,
                  ),
                  _Field(
                    controller: _accessKey,
                    label: 'AccessKey ID（RAM 子账号）',
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
                  '说明：阿里云 OSS 的桶建议设为私有，用 RAM 子账号只授权该桶的'
                  ' List / Get / Put / Delete；端点与 bucket 必须同地域。'
                  '同一空间的多台设备填相同的桶与前缀。',
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
    this.secret = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ReadingTheme reading;
  final bool secret;

  @override
  Widget build(BuildContext context) {
    final fg = reading.chromeForeground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
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
