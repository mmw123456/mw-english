import 'package:sqflite/sqflite.dart' show Sqflite;

import '../db/app_database.dart';

/// 今日概况。学习页顶部卡片读这个。
class TodayStats {
  const TodayStats({
    required this.newLearned,
    required this.dueReview,
    required this.wrongToday,
    required this.totalLearned,
    required this.mastered,
  });

  /// 今天第一次进入学习的词数。
  final int newLearned;

  /// 到期该复习的词数（不含新词、不含已斩）。
  final int dueReview;

  /// 今天答错的次数。
  final int wrongToday;

  /// 已进入学习流程的总词数。
  final int totalLearned;

  /// 已掌握：箱位 5 且未斩。
  final int mastered;

  static const TodayStats empty = TodayStats(
    newLearned: 0,
    dueReview: 0,
    wrongToday: 0,
    totalLearned: 0,
    mastered: 0,
  );
}

/// 学习记录的读写。
///
/// 表结构见 [AppDatabase]。调度规则（升箱、降箱、熟词保护）在 P0 第 4 步
/// 接进这里，当前只用到「读统计」。
class StudyDao {
  const StudyDao();

  /// 今天的起止时间戳（本地时区 00:00 到次日 00:00）。
  static ({int from, int to}) todayRange([DateTime? now]) {
    final n = now ?? DateTime.now();
    final from = DateTime(n.year, n.month, n.day);
    return (
      from: from.millisecondsSinceEpoch,
      to: from.add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
  }

  Future<TodayStats> todayStats() async {
    final db = await AppDatabase.open();
    final range = todayRange();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final newLearned = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM study_record WHERE first_seen_at >= ? AND first_seen_at < ?',
          [range.from, range.to],
        )) ??
        0;

    final dueReview = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM study_record '
          'WHERE killed = 0 AND box > 0 AND due_at <= ?',
          [nowMs],
        )) ??
        0;

    final wrongToday = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM study_log '
          'WHERE correct = 0 AND at >= ? AND at < ?',
          [range.from, range.to],
        )) ??
        0;

    final totalLearned =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM study_record')) ?? 0;

    final mastered = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM study_record WHERE killed = 0 AND box >= 5',
        )) ??
        0;

    return TodayStats(
      newLearned: newLearned,
      dueReview: dueReview,
      wrongToday: wrongToday,
      totalLearned: totalLearned,
      mastered: mastered,
    );
  }

  /// 已斩（不再出现）的词数。
  Future<int> killedCount() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) FROM study_record WHERE killed = 1');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 当前是学习的第几天。第一条学习记录那天算第 1 天，没有记录返回 0。
  Future<int> studyDayNumber() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT MIN(first_seen_at) AS m FROM study_record');
    final first = rows.first['m'] as int?;
    if (first == null) return 0;
    final start = DateTime.fromMillisecondsSinceEpoch(first);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    return days + 1;
  }

  /// 星标词数。
  Future<int> starredCount() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) FROM study_record WHERE starred = 1');
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
