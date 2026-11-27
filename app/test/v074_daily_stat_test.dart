import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:mw_english/data/dao/study_dao.dart';

/// v0.7.4 按天日志的契约。
///
/// 真正的 SQL 去重行为由门禁脚本 `_source/check_v074.py` 用 Python 的
/// sqlite3 真跑一遍（本机没装 sqlite3 的 Dart FFI 绑定，flutter test 里
/// 开不了内存库）。这里钉住两件**代码层面**的事：
/// 1. 写入策略是 insert + ignore，不是 replace / update
/// 2. 表主键是 (day, word_key)
///
/// 再加上连续天数算法的纯函数测试。
void main() {
  group('连续天数（纯函数）', () {
    int streak(List<DateTime> days, DateTime now) => StudyDao.streakFrom(
          days.map(StudyDao.dayKey).toSet(),
          now,
        );

    test('没有记录 = 0', () {
      expect(StudyDao.streakFrom(<String>{}, DateTime(2026, 11, 26)), 0);
    });

    test('今天、昨天、前天都有 = 3', () {
      expect(
        streak(
          <DateTime>[
            DateTime(2026, 11, 26),
            DateTime(2026, 11, 25),
            DateTime(2026, 11, 24),
          ],
          DateTime(2026, 11, 26),
        ),
        3,
      );
    });

    test('今天还没学：从昨天往回数', () {
      expect(
        streak(
          <DateTime>[DateTime(2026, 11, 25), DateTime(2026, 11, 24)],
          DateTime(2026, 11, 26),
        ),
        2,
      );
    });

    test('今天和昨天都没学 = 0（前天有也不算连续）', () {
      expect(
        streak(<DateTime>[DateTime(2026, 11, 24)], DateTime(2026, 11, 26)),
        0,
      );
    });

    test('中间断一天就停', () {
      expect(
        streak(
          <DateTime>[
            DateTime(2026, 11, 26),
            DateTime(2026, 11, 25),
            // 11-24 缺失
            DateTime(2026, 11, 23),
            DateTime(2026, 11, 22),
          ],
          DateTime(2026, 11, 26),
        ),
        2,
      );
    });

    test('跨月连续算得对', () {
      expect(
        streak(
          <DateTime>[DateTime(2026, 11, 1), DateTime(2026, 10, 31)],
          DateTime(2026, 11, 1),
        ),
        2,
      );
    });

    test('跨年连续算得对', () {
      expect(
        streak(
          <DateTime>[DateTime(2026, 1, 1), DateTime(2025, 12, 31)],
          DateTime(2026, 1, 1),
        ),
        2,
      );
    });
  });

  test('按天日志写入口径是 insert + ignore，旧数据不会被改写', () {
    expect(StudyDao.dayStatConflict, ConflictAlgorithm.ignore,
        reason: '换成 replace/update 就等于「后来的作答改写了当天的记录」');
  });

  test('按天日志的主键是 (day, word_key)：一天一个词只算一次', () {
    final source = File('lib/data/db/app_database.dart').readAsStringSync();
    expect(source.contains('daily_stat'), isTrue);
    expect(source.contains('PRIMARY KEY(day, word_key)'), isTrue,
        reason: '没有这个主键，当日重测和先错后对会把完成量抬高');
  });

  test('只答对才计入完成量', () {
    final source = File('lib/data/dao/study_dao.dart').readAsStringSync();
    // 写入被 `if (correct)` 包着：答错只动 Leitner，不进热力图。
    expect(source.contains('if (correct) {'), isTrue);
  });
}
