/// 小米 MiMo 云端 TTS 客户端：请求体结构、响应解包、错误透出。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/tts/mimo_tts_client.dart';

void main() {
  group('MimoTtsClient.synthesize', () {
    test('请求体：文本放 assistant、audio.format=wav、Bearer 认证', () async {
      Uri? capturedUrl;
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;
      final wav = Uint8List.fromList(
        [0x52, 0x49, 0x46, 0x46, ...List<int>.filled(16, 1)],
      );
      final client = MimoTtsClient(
        apiKey: 'test-key',
        post: (url, headers, body) async {
          capturedUrl = url;
          capturedHeaders = headers;
          capturedBody = body;
          return <String, dynamic>{
            'choices': [
              <String, dynamic>{
                'message': <String, dynamic>{
                  'audio': <String, dynamic>{'data': base64Encode(wav)},
                },
              },
            ],
          };
        },
      );

      final out = await client.synthesize('你好世界。', voice: '冰糖');

      expect(capturedUrl.toString(), '$kMimoTtsBaseUrl/chat/completions');
      expect(capturedHeaders?['Authorization'], 'Bearer test-key');
      expect(capturedBody?['model'], kMimoTtsModel);
      final messages = capturedBody?['messages'] as List;
      // 默认语速：只有一条 assistant 消息，内容是待合成文本
      expect(messages, hasLength(1));
      expect(messages.single['role'], 'assistant');
      expect(messages.single['content'], '你好世界。');
      final audio = capturedBody?['audio'] as Map;
      expect(audio['format'], 'wav');
      expect(audio['voice'], '冰糖');
      // 响应 base64 → 原始 WAV 字节
      expect(out, wav);
      expect(looksLikeWav(out), isTrue);
    });

    test('HTTP 错误透出 error.message', () async {
      final client = MimoTtsClient(
        apiKey: 'k',
        post: (url, headers, body) async {
          throw const MimoTtsException('HTTP 401：无效的 API Key');
        },
      );
      await expectLater(
        client.synthesize('x', voice: '冰糖'),
        throwsA(
          isA<MimoTtsException>().having(
            (e) => '$e',
            'message',
            contains('401'),
          ),
        ),
      );
    });

    test('响应缺音频数据时报可读错误', () async {
      final client = MimoTtsClient(
        apiKey: 'k',
        post: (url, headers, body) async {
          return <String, dynamic>{
            'choices': [
              <String, dynamic>{
                'message': <String, dynamic>{'content': '没有音频'},
              },
            ],
          };
        },
      );
      await expectLater(
        client.synthesize('x', voice: '冰糖'),
        throwsA(isA<MimoTtsException>()),
      );
    });
  });

  test('describeErrorBody：OpenAI 风格 error.message 优先', () {
    expect(
      MimoTtsClient.describeErrorBody(
        '{"error":{"message":"model not found","type":"invalid"}}',
      ),
      'model not found',
    );
    expect(
      MimoTtsClient.describeErrorBody('{"message":"quota exceeded"}'),
      'quota exceeded',
    );
    expect(MimoTtsClient.describeErrorBody('not json'), 'not json');
    expect(MimoTtsClient.describeErrorBody(''), '（无响应体）');
  });

  test('extractMimoAudio：坏 base64 报错而不是崩溃', () {
    expect(
      () => MimoTtsClient.extractMimoAudio(<String, dynamic>{
        'choices': [
          <String, dynamic>{
            'message': <String, dynamic>{
              'audio': <String, dynamic>{'data': '!!!not-base64!!!'},
            },
          },
        ],
      }),
      throwsA(isA<MimoTtsException>()),
    );
  });
}
