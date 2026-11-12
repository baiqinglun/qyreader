/// 主题色偏好：默认蓝、切换落盘、启动恢复。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/appearance_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('默认亮蓝；切换后落盘', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appAccentControllerProvider), AppAccent.blue);
    await container
        .read(appAccentControllerProvider.notifier)
        .set(AppAccent.purple);
    expect(container.read(appAccentControllerProvider), AppAccent.purple);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.accent'), 'purple');
  });

  test('启动时从 prefs 恢复；非法值回退默认', () async {
    SharedPreferences.setMockInitialValues({'app.accent': 'orange'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appAccentControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(appAccentControllerProvider), AppAccent.orange);

    SharedPreferences.setMockInitialValues({'app.accent': 'no-such'});
    final fallback = ProviderContainer();
    addTearDown(fallback.dispose);
    fallback.read(appAccentControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fallback.read(appAccentControllerProvider), AppAccent.blue);
  });
}
