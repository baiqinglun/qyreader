/// 检查 OSS 中的 Android 发布清单。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const updateManifestUrl =
    'https://mtl-updates.oss-cn-beijing.aliyuncs.com/qyreader_latest.json';

class UpdateLink {
  const UpdateLink(this.url, this.password);
  final Uri url;
  final String password;
  bool get isApk => url.path.toLowerCase().endsWith('.apk');
}

class UpdateManifest {
  const UpdateManifest(
    this.versionName,
    this.versionCode,
    this.notes,
    this.links,
  );
  final String versionName;
  final int versionCode;
  final String notes;
  final List<UpdateLink> links;

  factory UpdateManifest.parse(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic> ||
        json['versionName'] is! String ||
        (json['versionName'] as String).trim().isEmpty ||
        json['versionCode'] is! int ||
        (json['versionCode'] as int) <= 0 ||
        (json['notes'] != null && json['notes'] is! String) ||
        (json['updates'] != null && json['updates'] is! List)) {
      throw const FormatException('更新清单格式错误');
    }
    final items = <dynamic>[
      if (json['apkUrl'] != null)
        {'apkUrl': json['apkUrl'], 'password': json['password']},
      ...?json['updates'] as List?,
    ];
    final links = <UpdateLink>[];
    for (final item in items) {
      if (item is! Map || item['apkUrl'] is! String) continue;
      final uri = Uri.tryParse(item['apkUrl'] as String);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      final password = item['password'];
      links.add(UpdateLink(uri, password is String ? password : ''));
    }
    if (links.isEmpty) throw const FormatException('更新清单没有有效的 HTTPS 下载地址');
    return UpdateManifest(
      json['versionName'] as String,
      json['versionCode'] as int,
      (json['notes'] as String?) ?? '',
      links,
    );
  }
}

Future<UpdateManifest> fetchUpdateManifest({Uri? url}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client
        .getUrl(url ?? Uri.parse(updateManifestUrl))
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('更新清单请求失败（${response.statusCode}）');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) throw const FormatException('更新清单过大');
    }
    return UpdateManifest.parse(utf8.decode(bytes));
  } finally {
    client.close(force: true);
  }
}

Future<void> checkForAppUpdate(BuildContext context) async {
  if (!Platform.isAndroid) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检查更新'),
        content: const Text('此更新入口适用于 Android。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return;
  }
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
  );
  var progressOpen = true;
  try {
    final current = await const MethodChannel(
      'qyreader/app_version',
    ).invokeMethod<int>('versionCode');
    if (current == null) throw StateError('无法读取当前版本');
    final update = await fetchUpdateManifest();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    progressOpen = false;
    if (update.versionCode <= current) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('检查更新'),
          content: const Text('当前已是最新版本。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _UpdateDialog(update: update),
    );
  } catch (e) {
    if (!context.mounted) return;
    if (progressOpen) Navigator.of(context, rootNavigator: true).pop();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检查更新失败'),
        content: Text('$e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

Future<void> _downloadApk(Uri uri, int expectedVersion) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  File? target;
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('下载失败（${response.statusCode}）');
    }
    final dir = await getTemporaryDirectory();
    target = File('${dir.path}/qyreader-update.apk');
    final sink = target.openWrite();
    var size = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        size += chunk.length;
        if (size > 512 * 1024 * 1024) throw const FormatException('安装包过大');
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (size == 0 ||
        (response.contentLength >= 0 && size != response.contentLength)) {
      throw const FormatException('安装包下载不完整');
    }
    await const MethodChannel('qyreader/app_version').invokeMethod<void>(
      'installApk',
      {'path': target.path, 'versionCode': expectedVersion},
    );
  } catch (_) {
    if (target != null && await target.exists()) await target.delete();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});
  final UpdateManifest update;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool loading = false;
  Future<void> openLink(int index) async {
    if (loading) return;
    setState(() => loading = true);
    final link = widget.update.links[index];
    try {
      if (link.password.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: link.password));
      }
      if (link.isApk) {
        await _downloadApk(link.url, widget.update.versionCode);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载完成，请在系统安装界面确认安装')));
        return;
      }
      final launched = await launchUrl(
        link.url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('无法打开下载链接');
      if (!mounted) return;
      if (link.password.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('提取码已复制，请在浏览器中粘贴')));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      final fallback = widget.update.links
          .where((item) => !item.isApk)
          .toList();
      if (link.isApk && fallback.isNotEmpty) {
        final target = fallback.first;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('下载失败'),
            content: const Text('请使用备用下载入口。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(openLink(widget.update.links.indexOf(target)));
                },
                child: const Text('打开备用入口'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载失败，请尝试其他下载入口')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('发现新版本 ${widget.update.versionName}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.update.notes.isNotEmpty) Text(widget.update.notes),
          for (var i = 0; i < widget.update.links.length; i++)
            TextButton.icon(
              onPressed: loading ? null : () => unawaited(openLink(i)),
              icon: const Icon(Icons.open_in_browser),
              label: Text(
                '${widget.update.links[i].isApk ? '下载 APK' : '打开下载页面'}${widget.update.links.length > 1 ? ' ${i + 1}' : ''}',
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: loading ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
