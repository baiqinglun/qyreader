/// 同步后端配置序列化：阿里云 OSS 用的「虚拟主机风格」开关要能存回来。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/sync/sync_backend_store.dart';

void main() {
  test('配置往返保留端点 / 区域 / pathStyle', () {
    const config = SyncBackendConfig(
      type: SyncBackendType.s3,
      endPoint: 'oss-cn-hangzhou.aliyuncs.com',
      bucket: 'qyreader',
      prefix: 'qyreader/',
      region: 'oss-cn-hangzhou',
      pathStyle: false,
    );
    final back = SyncBackendConfig.fromMap(config.toMap());
    expect(back.type, SyncBackendType.s3);
    expect(back.endPoint, 'oss-cn-hangzhou.aliyuncs.com');
    expect(back.region, 'oss-cn-hangzhou');
    expect(back.pathStyle, isFalse);
    expect(back.s3Complete, isTrue);
  });

  test('旧配置没有 pathStyle 时按路径风格（MinIO 时代的行为）', () {
    final legacy = SyncBackendConfig.fromMap(<String, dynamic>{
      'type': 's3',
      'endPoint': 'minio.example.com',
      'bucket': 'qyreader',
    });
    expect(legacy.pathStyle, isTrue);
    expect(legacy.useSSL, isTrue);
  });
}
