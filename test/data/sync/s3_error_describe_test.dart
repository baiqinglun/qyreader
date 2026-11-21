// describeStoreError 回归：同步失败只显示「MinioError: Forbidden」这种
// HTTP reason phrase 时看不出真实原因（HEAD 响应没有 body，SDK 拿不到
// S3 错误码）。这里断言错误信息带 HTTP 状态、S3 错误码与请求 ID，
// 非 S3 异常原样透传。
// MinioResponse 在 SDK 的 src/ 里（它是 MinioS3Error.response 的真实类型，
// 事实上属于公开 API 面），只在测试里导入来构造响应对象。
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minio/minio.dart';
import 'package:minio/models.dart';
import 'package:minio/src/minio_client.dart';

import 'package:qy_reader/data/sync/s3_object_store.dart';

MinioS3Error s3Error(
  String code,
  String? message,
  int? status,
  Map<String, String>? headers,
) {
  final response = status == null
      ? null
      : MinioResponse.bytes(
          Uint8List.fromList(utf8.encode(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Error><Code>$code</Code></Error>',
          )),
          status,
          headers: headers ?? const {},
        );
  return MinioS3Error(message ?? code, Error(code, null, message, null), response);
}

void main() {
  group('describeStoreError', () {
    test('阿里云账号停机（UserDisable）：带 HTTP 403、错误码与 OSS 请求 ID', () {
      final error = s3Error('UserDisable', 'UserDisable', 403,
          {'x-oss-request-id': 'REQ-1'});
      expect(
        describeStoreError(error),
        '存储服务返回错误：HTTP 403，错误码 UserDisable，请求 ID REQ-1',
      );
    });

    test('HEAD 空响应体：SDK 用 reason phrase 兜底，不再重复 message', () {
      final error = s3Error('Forbidden', 'Forbidden', 403, const {});
      expect(
        describeStoreError(error),
        '存储服务返回错误：HTTP 403，错误码 Forbidden',
      );
    });

    test('message 与 code 不同（NoSuchBucket）时两者都保留', () {
      final error = s3Error(
          'NoSuchBucket', 'The specified bucket does not exist', 404, null);
      expect(
        describeStoreError(error),
        '存储服务返回错误：HTTP 404，错误码 NoSuchBucket，'
        'The specified bucket does not exist',
      );
    });

    test('没有响应对象时只报错误码', () {
      final error = s3Error('UserDisable', 'UserDisable', null, null);
      expect(describeStoreError(error), '存储服务返回错误：错误码 UserDisable');
    });

    test('AWS 系请求 ID 头（x-amz-request-id）也识别', () {
      final error = s3Error('AccessDenied', 'AccessDenied', 403,
          {'X-Amz-Request-Id': 'AWS-REQ'});
      expect(
        describeStoreError(error),
        '存储服务返回错误：HTTP 403，错误码 AccessDenied，请求 ID AWS-REQ',
      );
    });

    test('非 S3 异常原样透传', () {
      expect(describeStoreError(Exception('boom')), 'Exception: boom');
    });
  });
}
