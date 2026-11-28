import 'package:sqflite/sqflite.dart' show Database, Sqflite;

import '../db/app_database.dart';
import '../study/mastery.dart';
import 'study_dao.dart';
import '../stats/stats_snapshot.dart';

/// 统计数据的来源（抽成接口是为了测试塞假数据，不碰 SQLite）。
abstract class StatsStore {
  Future<StatsSnapshot> load({DateTime? now});
}

/// 从 SQLite 读统计页要的数（只读，一行都不写）。
///
/// 五个数字块的来源全在这一处，页面不自己查库：
///
/// - 学习量 / 趋势 / 学习天数 / 连续天数 → `daily_stat`（v0.7.4 起按天记）
/// - 学过 / 已掌握 / 箱位分布 / 已斩 → `study_record`（+ 学习池 my_words / user_added_words）
/// - 拼写 → `spelling_round`（v0.13.0 起一轮一行）
///
/// 复用已有算法而不是另写一遍：[StudyDao.dailyTotals] 的按天聚合、
/// [StudyDao.studyStreak] 的连续天数（与首页热力图同一个，两处不能算出两个数）。
class SqlStatsStore implements StatsStore {
  const SqlStatsStore();

  /// 趋势图最多往回看 30 天（7 天档取尾部）。
  static const int windowDays = 30;

  static const StudyDao _study = StudyDao();

  @override
  Future<StatsSnapshot> load({DateTime? now}) async {
    final db = await AppDatabase.open();
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final todayKey = StudyDao.dayKey(today);
    final from = DateTime(today.year, today.month, today.day - (windowDays - 1));

    final totals = await _study.dailyTotals(from: from, to: today);
    final totalDays = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(DISTINCT day) FROM daily_stat',
        )) ??
        0;
    final streak = await _study.studyStreak(now: n);
    final learned = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM study_record WHERE started = 1',
        )) ??
        0;

    // 已掌握：口径只写在 Mastery 一处（v0.14.0 统一，决策 117）。
    final mastered = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM study_record WHERE ${Mastery.sqlWhere}',
        )) ??
        0;

    final pool = await _poolCount(db);
    final boxes = await _boxCounts(db);
    final killed = await _killedCount(db);

    final spellToday = await _spellSum(db, todayKey, todayKey);
    final spellAll = await _spellSum(db, null, null);
    final weekAgo = StudyDao.dayKey(
      DateTime(today.year, today.month, today.day - 6),
    );
    final spell7 = await _spellSum(db, weekAgo, todayKey);

    return StatsSnapshot(
      todayKey: todayKey,
      totals: totals,
      totalDays: totalDays,
      streak: streak,
      learnedWords: learned,
      mastered: mastered,
      boxes: boxes,
      killed: killed,
      poolTotal: pool,
      todaySpellTotal: spellToday.total,
      todaySpellCorrect: spellToday.correct,
      spellAllTotal: spellAll.total,
      spellAllCorrect: spellAll.correct,
      spell7Total: spell7.total,
      spell7Correct: spell7.correct,
    );
  }

  /// 学习池 = 820 单词本 ∪ 自加词。`UNION` 会自动去重（自加词可能与 820 同词）。
  static const String _poolSql =
      'SELECT word_key FROM my_words UNION SELECT word_key FROM user_added_words';

  Future<int> _poolCount(Database db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) FROM ($_poolSql)');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 箱 0–6 各多少词（**未斩**）。
  ///
  /// 一段 SQL 出七个数：以学习池为底 `LEFT JOIN study_record`，没记录 / 没开学
  /// 的词落在箱 0，已斩的不进任何一段。所以七段之和天然等于「池里未斩的词数」，
  /// 不用再拿总数减一遍 —— 减出来的是另一个口径，对不上时看不出是谁错。
  Future<List<int>> _boxCounts(Database db) async {
    final rows = await db.rawQuery('''
      SELECT CASE
               WHEN r.word_key IS NULL OR r.started = 0 THEN 0
               WHEN r.box IS NULL OR r.box < 0 THEN 0
               WHEN r.box > ? THEN ?
               ELSE r.box
             END AS bx,
             COUNT(*) AS c
      FROM ($_poolSql) p
      LEFT JOIN study_record r ON r.word_key = p.word_key
      WHERE COALESCE(r.killed, 0) = 0
      GROUP BY bx
    ''', [topBox, topBox]);
    final out = List<int>.filled(topBox + 1, 0);
    for (final r in rows) {
      final bx = (r['bx'] as int?) ?? 0;
      if (bx < 0 || bx >= out.length) continue;
      out[bx] = (r['c'] as int?) ?? 0;
    }
    return out;
  }

  /// 已斩词数（只算学习池里的词，与 [StudyDao.killedCount] 同口径）。
  Future<int> _killedCount(Database db) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) FROM ($_poolSql) p
      JOIN study_record r ON r.word_key = p.word_key
      WHERE r.killed = 1
    ''');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 最高箱位（6）。与 `AppDefaults.boxIntervals` 对齐，但不引调度代码。
  static const int topBox = 6;

  /// 拼写成绩合计。[from] / [to] 都传 null = 全时段。
  Future<({int total, int correct})> _spellSum(
    Database db,
    String? from,
    String? to,
  ) async {
    final rows = from == null || to == null
        ? await db.rawQuery(
            'SELECT COALESCE(SUM(total), 0) AS t, COALESCE(SUM(correct), 0) AS c '
            'FROM spelling_round',
          )
        : await db.rawQuery(
            'SELECT COALESCE(SUM(total), 0) AS t, COALESCE(SUM(correct), 0) AS c '
            'FROM spelling_round WHERE day >= ? AND day <= ?',
            [from, to],
          );
    final row = rows.first;
    return (
      total: (row['t'] as int?) ?? 0,
      correct: (row['c'] as int?) ?? 0,
    );
  }
}
