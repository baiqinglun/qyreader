/// 微信读书扫码登录弹窗。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'weread_login.dart';

/// 打开扫码登录弹窗；成功时返回账号昵称（拿不到昵称返回空串），取消返回 null。
Future<String?> showWeReadLoginDialog(
  BuildContext context,
  WeReadLoginApi login,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => WeReadLoginDialog(login: login),
  );
}

/// 扫码登录弹窗。
class WeReadLoginDialog extends StatefulWidget {
  /// 构造。
  const WeReadLoginDialog({required this.login, super.key});

  /// 登录能力。
  final WeReadLoginApi login;

  @override
  State<WeReadLoginDialog> createState() => _WeReadLoginDialogState();
}

class _WeReadLoginDialogState extends State<WeReadLoginDialog> {
  final GlobalKey _qrKey = GlobalKey();
  final TextEditingController _otp = TextEditingController();

  WeReadLoginSession? _session;
  Timer? _timer;
  int _generation = 0;
  bool _starting = true;
  bool _polling = false;
  bool _needOtp = false;
  bool _finished = false;
  String? _qrUrl;
  String? _error;
  String _status = '正在获取二维码…';
  String _otpError = '';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _session?.cancel();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _timer?.cancel();
    _session?.cancel();
    _session = null;
    _finished = false;
    if (mounted) {
      setState(() {
        _starting = true;
        _needOtp = false;
        _error = null;
        _qrUrl = null;
        _status = '正在获取二维码…';
        _otpError = '';
      });
    }
    try {
      final session = await widget.login.start();
      if (!mounted || generation != _generation) {
        session.cancel();
        return;
      }
      setState(() {
        _session = session;
        _qrUrl = session.qrUrl;
        _starting = false;
        _status = '请用微信扫描二维码';
      });
      _timer = Timer.periodic(
        const Duration(milliseconds: 1600),
        (_) => unawaited(_poll()),
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _starting = false;
        _error = _messageOf(error);
        _status = '二维码获取失败';
      });
    }
  }

  Future<void> _poll({String? otp}) async {
    final session = _session;
    if (session == null || _polling || _finished) return;
    final generation = _generation;
    _polling = true;
    try {
      final result = await session.poll(otp: otp ?? _otp.text.trim());
      if (!mounted || _finished || generation != _generation) return;
      switch (result.step) {
        case WeReadLoginStep.waiting:
          setState(() => _status = result.message);
        case WeReadLoginStep.needOtp:
          _timer?.cancel();
          setState(() {
            _needOtp = true;
            _status = result.message;
            _otpError = result.message.contains('不对') ? result.message : '';
          });
        case WeReadLoginStep.success:
          _finished = true;
          _timer?.cancel();
          Navigator.of(context).pop(result.accountName ?? '');
        case WeReadLoginStep.expired:
        case WeReadLoginStep.failed:
          _timer?.cancel();
          setState(() {
            _error = result.message;
            _status = result.message;
          });
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _timer?.cancel();
      setState(() {
        _error = _messageOf(error);
        _status = '登录失败';
      });
    } finally {
      _polling = false;
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      setState(() => _otpError = '请输入手机微信上显示的 4 位数字');
      return;
    }
    setState(() {
      _otpError = '';
      _status = '正在验证…';
    });
    await _poll(otp: code);
    if (mounted && !_finished && _status == '正在验证…') {
      setState(() => _status = '等待验证结果…');
    }
  }

  Future<void> _saveQr() async {
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('二维码生成失败');
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putImageBytes(
        data.buffer.asUint8List(),
        album: 'QYReader',
        name: 'weread-login-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('二维码已保存，可到微信「扫一扫 → 相册」识别')),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() => _otpError = '保存二维码失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final qrUrl = _qrUrl;
    return AlertDialog(
      key: const ValueKey('weread-login-dialog'),
      title: const Text('扫码登录微信读书'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_starting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(),
                )
              else if (qrUrl != null && !_needOtp && _error == null)
                RepaintBoundary(
                  key: _qrKey,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomPaint(
                      key: const ValueKey('weread-qr-image'),
                      size: const Size.square(216),
                      painter: QrPainter(
                        data: qrUrl,
                        version: QrVersions.auto,
                        gapless: true,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_error != null && !_starting) ...<Widget>[
                const SizedBox(height: 16),
                Icon(Icons.error_outline, color: color.error, size: 36),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _status,
                key: const ValueKey('weread-login-status'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (_needOtp) ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('weread-otp-field'),
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '4 位验证码',
                    counterText: '',
                    errorText: _otpError.isEmpty ? null : _otpError,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => unawaited(_verifyOtp()),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('weread-otp-verify'),
                    onPressed: _polling ? null : _verifyOtp,
                    child: const Text('验证'),
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '用微信「扫一扫」扫描二维码并确认登录。\n'
                  '如果在本机登录：先「保存二维码」，再到微信「扫一扫 → 相册」识别。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.onSurface.withValues(alpha: 0.55),
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey('weread-login-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (!_starting && qrUrl != null && !_needOtp && _error == null)
          TextButton(
            key: const ValueKey('weread-qr-save'),
            onPressed: _saveQr,
            child: const Text('保存二维码'),
          ),
        if (!_starting)
          TextButton(
            key: const ValueKey('weread-qr-refresh'),
            onPressed: _start,
            child: const Text('刷新'),
          ),
      ],
    );
  }
}

String _messageOf(Object error) {
  if (error is WeReadLoginException) return error.message;
  return '$error';
}
