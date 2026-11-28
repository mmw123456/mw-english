import 'package:sqflite/sqflite.dart' show Database;

import '../db/app_database.dart';
import '../spelling/spelling_round.dart';
import 'study_dao.dart';

/// 拼写练习的数据源。
///
/// 只做两件事：**读**今天能拼的词（与学习会话同一套词表）、**写**拼写自己的
/// 记录。六箱、streak、每日进度（`study_record` / `study_log` / `daily_stat`）
/// 一个字节都不写 —— 拼错不降箱、拼对不升箱，这是本版的硬规矩。
abstract class SpellingStore {
  /// 今天的题（最多 = 每日目标）。没词可拼时返回空表。
  Future<List<SpellingItem>> loadItems({DateTime? now});

  /// 累计正确率（`spelling_round` 的历史之和）。
  Future<SpellingStats> stats();

  /// 一轮拼完记一笔。`total <= 0` 不写（空轮不算成绩）。
  Future<void> saveRound({
    required int total,
    required int correct,
    DateTime? now,
  });
}

/// SQLite 实现。
///
/// 题源与 [StudyDao.buildSession] 是同一套：820 + 自加词、`killed = 0`、
/// 到期复习取 `due_at <= now AND (box > 0 OR retest = 1)`、新词队列 820 在前
/// 自加按 `added_at`。区别只有两处，都是为了「一轮拼今天的词」这句需求：
/// 1. 今天已经学过的新词也算今天的词（否则学完就拼不了，功能等于废掉）；
/// 2. 截到当日目标（默认 30），不像会话那样可能带 100 多张复习卡。
class SqlSpellingStore implements SpellingStore {
  const SqlSpellingStore();

  static const StudyDao _study = StudyDao();

  /// 学习池（820 + 自加词）的公共子查询。
  ///
  /// 释义口径与别处一致：`COALESCE(NULLIF(meaning,''), translation, '')`，
  /// 自加词对 `words` 一律 `LEFT JOIN`（写 INNER 会让不在 43,350 词里的短语
  /// 凭空消失，v0.9.0 的坑）。
  static const String _pool = '''
    SELECT m.word_key AS word_key,
           m.word AS word,
           COALESCE(m.phonetic, '') AS phonetic,
           TRIM(COALESCE(NULLIF(m.meaning_pdf, ''), m.meaning_ecdict, '')) AS meaning,
           COALESCE(r.started, 0) AS started,
           COALESCE(r.killed, 0) AS killed,
           COALESCE(r.due_at, 0) AS due_at,
           COALESCE(r.first_seen_at, 0) AS first_seen_at,
           COALESCE(r.box, 0) AS box,
           COALESCE(r.retest, 0) AS retest,
           0 AS grp, m.no AS ord
    FROM my_words m
    LEFT JOIN study_record r ON r.word_key = m.word_key
    UNION ALL
    SELECT u.word_key,
           COALESCE(NULLIF(w.word, ''), u.word_key),
           COALESCE(w.phonetic, ''),
           TRIM(COALESCE(NULLIF(u.meaning, ''), w.translation, '')),
           COALESCE(r.started, 0),
           COALESCE(r.killed, 0),
           COALESCE(r.due_at, 0),
           COALESCE(r.first_seen_at, 0),
           COALESCE(r.box, 0),
           COALESCE(r.retest, 0),
           1, u.added_at
    FROM user_added_words u
    LEFT JOIN words w ON w.word = u.word_key
    LEFT JOIN study_record r ON r.word_key = u.word_key
    WHERE NOT EXISTS (SELECT 1 FROM my_words m2 WHERE m2.word_key = u.word_key)
  ''';

  @override
  Future<List<SpellingItem>> loadItems({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final db = await AppDatabase.open();

    // 配额读的是学习页同一份（当天第一次由首页算好并落库）。只读，不改。
    final quota = await _study.dailyQuota(now: n);
    final range = StudyDao.todayRange(n);

    final learned = await _items(
      db,
      'SELECT * FROM ($_pool) '
      'WHERE killed = 0 AND started = 1 AND first_seen_at >= ? AND first_seen_at < ? '
      'ORDER BY first_seen_at ASC, grp ASC, ord ASC',
      [range.from, range.to],
    );

    final remaining = quota.newWords - learned.length;
    final queued = remaining <= 0
        ? const <SpellingItem>[]
        : await _items(
            db,
            'SELECT * FROM ($_pool) WHERE killed = 0 AND started = 0 '
            'ORDER BY grp ASC, ord ASC LIMIT ?',
            [remaining],
          );

    final due = await _items(
      db,
      'SELECT * FROM ($_pool) WHERE killed = 0 AND started = 1 AND due_at <= ? '
      'AND (box > 0 OR retest = 1) '
      'ORDER BY due_at ASC, grp ASC, ord ASC',
      [n.millisecondsSinceEpoch],
    );

    return SpellingRound.compose(
      learnedToday: learned,
      queued: queued,
      due: due,
      cap: quota.newWords,
    );
  }

  /// 今天有没有词可拼（首页入口用）。与 [loadItems] 同一套口径，不另写一份 SQL。
  Future<int> countToday({DateTime? now}) async =>
      (await loadItems(now: now)).length;

  @override
  Future<SpellingStats> stats() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS rounds, COALESCE(SUM(total), 0) AS total, '
      'COALESCE(SUM(correct), 0) AS correct FROM spelling_round',
    );
    final row = rows.first;
    return SpellingStats(
      rounds: (row['rounds'] as int?) ?? 0,
      total: (row['total'] as int?) ?? 0,
      correct: (row['correct'] as int?) ?? 0,
    );
  }

  @override
  Future<void> saveRound({
    required int total,
    required int correct,
    DateTime? now,
  }) async {
    if (total <= 0) return;
    final n = now ?? DateTime.now();
    final db = await AppDatabase.open();
    await db.insert('spelling_round', {
      'day': StudyDao.dayKey(n),
      'total': total,
      'correct': correct.clamp(0, total),
      'at': n.millisecondsSinceEpoch,
    });
  }

  static Future<List<SpellingItem>> _items(
    Database db,
    String sql,
    List<Object?> args,
  ) async {
    final rows = await db.rawQuery(sql, args);
    return rows.map(_item).toList();
  }

  static SpellingItem _item(Map<String, Object?> row) {
    final key = ((row['word_key'] as String?) ?? '').trim().toLowerCase();
    final word = ((row['word'] as String?) ?? '').trim();
    final meaning = ((row['meaning'] as String?) ?? '').trim();
    return SpellingItem(
      wordKey: key,
      word: word.isEmpty ? key : word,
      phonetic: ((row['phonetic'] as String?) ?? '').trim(),
      meaning: meaning.isEmpty ? '' : meaning.split('\n').first.trim(),
    );
  }
}
