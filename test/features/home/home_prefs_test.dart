/// 首页偏好：年度目标的默认值 / 落盘 / 越界夹取。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/home/home_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('未设置时默认 24 本', () async {
    expect(await HomePrefs.loadYearlyGoal(), HomePrefs.defaultYearlyGoal);
  });

  test('保存后可以读回', () async {
    await HomePrefs.saveYearlyGoal(36);
    expect(await HomePrefs.loadYearlyGoal(), 36);
  });

  test('越界值夹在 1..999', () async {
    await HomePrefs.saveYearlyGoal(0);
    expect(await HomePrefs.loadYearlyGoal(), 1);
    await HomePrefs.saveYearlyGoal(5000);
    expect(await HomePrefs.loadYearlyGoal(), 999);
  });
}
