/// 微信读书单本进度合并：补上累计阅读时长与读完时间。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/weread/weread_models.dart';

void main() {
  test('单本进度补上累计时长 / 读完时间 / 最近阅读时间', () {
    const book = WeReadBook(
      bookId: 'r1',
      title: '书',
      progressPercent: 10,
      readingSeconds: 100,
      readUpdateTime: 1000,
    );
    final merged = mergeWeReadProgress(
      book,
      const WeReadProgress(
        bookId: 'r1',
        progressPercent: 60,
        updateTime: 2000,
        readingSeconds: 3660,
        finishTime: 2500,
      ),
    );

    expect(merged.progressPercent, 60);
    expect(merged.readingSeconds, 3660);
    expect(merged.finishTime, 2500);
    expect(merged.readUpdateTime, 2000);
    expect(merged.finished, isFalse);
  });

  test('进度接口缺失的字段不覆盖已有值，较旧的时间不回头', () {
    const book = WeReadBook(
      bookId: 'r2',
      title: '书',
      progressPercent: 30,
      readingSeconds: 7200,
      readUpdateTime: 5000,
    );
    final merged = mergeWeReadProgress(
      book,
      const WeReadProgress(
        bookId: 'r2',
        progressPercent: 40,
        updateTime: 4000,
      ),
    );

    expect(merged.readingSeconds, 7200);
    expect(merged.readUpdateTime, 5000);
    expect(merged.progressPercent, 40);
  });

  test('单本进度返回 0 时不冲掉快照里已有的进度', () {
    const book = WeReadBook(
      bookId: 'r4',
      title: '书',
      progressPercent: 55,
      readingSeconds: 1800,
    );
    final merged = mergeWeReadProgress(
      book,
      const WeReadProgress(
        bookId: 'r4',
        progressPercent: 0,
        readingSeconds: 2400,
      ),
    );

    expect(merged.progressPercent, 55);
    expect(merged.readingSeconds, 2400);
  });

  test('进度到 100 时标记读完', () {
    const book = WeReadBook(bookId: 'r3', title: '书', progressPercent: 99);
    final merged = mergeWeReadProgress(
      book,
      const WeReadProgress(bookId: 'r3', progressPercent: 100),
    );

    expect(merged.finished, isTrue);
  });
}
