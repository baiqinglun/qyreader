/// 单页最长计时设置：默认值、读写往返、文案。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qy_reader/features/stats/stats_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认 10 分钟（防止开着书离开把时长灌爆）', () async {
    expect(await loadPageCapMinutes(), kDefaultPageCapMinutes);
    expect(kDefaultPageCapMinutes, 10);
  });

  test('写入后读回；0 = 不限制', () async {
    await savePageCapMinutes(3);
    expect(await loadPageCapMinutes(), 3);
    await savePageCapMinutes(0);
    expect(await loadPageCapMinutes(), 0);
    await savePageCapMinutes(30);
    expect(await loadPageCapMinutes(), 30);
  });

  test('pageCapLabel：0 显示「不限制」', () {
    expect(pageCapLabel(0), '不限制');
    expect(pageCapLabel(5), '5 分钟');
  });
}
