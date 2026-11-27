import 'package:sqflite/sqflite.dart' show Database;

import '../db/app_database.dart';
import '../models/article.dart';

/// 候选池里的一个词：词形 + 来源顺序 + 学习状态 + 释义。
class PoolWord {
  const PoolWord({
    required this.wordKey,
    required this.order,
    required this.fromBook,
    required this.killed,
    required this.box,
    required this.streak,
    required this.meaning,
  });

  final String wordKey;

  /// 排序依据：820 用 `my_words.no`，自加词用 `added_at`。
  final int order;

  /// true = 820 单词本，false = 自加 / 导入词。
  final bool fromBook;

  final bool killed;
  final int box;
  final int streak;

  /// 词书本义（`meaning_pdf` 优先，退而 `meaning_ecdict`）。
  final String meaning;

  /// 已掌握：箱位 ≥5 或连对 ≥3（决策 117）。
  bool get mastered => box >= 5 || streak >= 3;

  /// 词性从释义开头提（820 的 `pos` 列是空的，词性都写在释义里）。
  String get pos {
    final m = RegExp(r'^\s*([a-z]{1,4}\.)').firstMatch(meaning);
    return m?.group(1) ?? '';
  }

  ArticleWord toArticleWord() =>
      ArticleWord(word: wordKey, pos: pos, meaning: meaning);
}

/// 候选池的来源。抽成接口是为了测试能塞内存池。
abstract class WordPool {
  Future<List<PoolWord>> load();
}

/// 从 SQLite 读全部候选（820 + 自加词），各带学习状态。
///
/// 一次读全而不是在 SQL 里筛，是为了让「怎么挑」这件事落在纯函数
/// [pickTargets] 里 —— 那段规则最容易写错，必须能单测。
class SqlWordPool implements WordPool {
  const SqlWordPool();

  @override
  Future<List<PoolWord>> load() async {
    final db = await AppDatabase.open();
    return [...await _bookWords(db), ...await _addedWords(db)];
  }

  Future<List<PoolWord>> _bookWords(Database db) async {
    final rows = await db.rawQuery('''
      SELECT m.word_key                        AS word_key,
             m.no                              AS ord,
             COALESCE(NULLIF(m.meaning_pdf, ''), m.meaning_ecdict, '') AS meaning,
             COALESCE(r.killed, 0)             AS killed,
             COALESCE(r.box, 0)                AS box,
             COALESCE(r.streak, 0)             AS streak
      FROM my_words m
      LEFT JOIN study_record r ON r.word_key = m.word_key
      ORDER BY m.no
    ''');
    return rows.map((r) => _row(r, fromBook: true)).toList();
  }

  Future<List<PoolWord>> _addedWords(Database db) async {
    final rows = await db.rawQuery('''
      SELECT u.word_key                                     AS word_key,
             u.added_at                                     AS ord,
             COALESCE(NULLIF(u.meaning, ''), w.translation, '') AS meaning,
             COALESCE(r.killed, 0)                          AS killed,
             COALESCE(r.box, 0)                             AS box,
             COALESCE(r.streak, 0)                          AS streak
      FROM user_added_words u
      LEFT JOIN words w ON w.word = u.word_key
      LEFT JOIN study_record r ON r.word_key = u.word_key
      ORDER BY u.added_at
    ''');
    return rows.map((r) => _row(r, fromBook: false)).toList();
  }

  PoolWord _row(Map<String, Object?> r, {required bool fromBook}) {
    return PoolWord(
      wordKey: ((r['word_key'] as String?) ?? '').trim().toLowerCase(),
      order: (r['ord'] as num?)?.toInt() ?? 0,
      fromBook: fromBook,
      killed: ((r['killed'] as num?)?.toInt() ?? 0) != 0,
      box: (r['box'] as num?)?.toInt() ?? 0,
      streak: (r['streak'] as num?)?.toInt() ?? 0,
      meaning: ((r['meaning'] as String?) ?? '').trim(),
    );
  }
}

/// 挑下一篇的 25 个目标词。
///
/// 顺序与优先级（决策 117，用户 2026-11-27 定）：
/// 1. 820 里没斩、没掌握、没当过目标词的，按 `no` 顺序；
/// 2. 不够就从 820 里「已掌握但没斩、没当过目标词」的回填（学过的词拿来复现也不亏）；
/// 3. 还不够就接自加 / 导入词，同样先未掌握、按 `added_at`；
/// 4. 还不够再从自加词里已掌握的回填。
///
/// 已斩的**任何一轮都不进** —— 用户主动说「这词我不要」，不该再塞回阅读里。
/// 已用过（在 `article_word` 里）的也不进，保证「进度不重复」。
///
/// 凑不满 [count] 就返回短的，由调用方决定报错还是降级 ——
/// 这里不抛异常，纯函数只管排序取词。
List<PoolWord> pickTargets({
  required List<PoolWord> pool,
  required Set<String> used,
  int count = 25,
}) {
  final available = pool
      .where((w) => w.wordKey.isNotEmpty && !w.killed && !used.contains(w.wordKey))
      .toList();

  final picked = <PoolWord>[];
  final taken = <String>{};

  void takeWhere(bool Function(PoolWord) test) {
    if (picked.length >= count) return;
    final batch = available
        .where((w) => !taken.contains(w.wordKey) && test(w))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final w in batch) {
      if (picked.length >= count) break;
      taken.add(w.wordKey);
      picked.add(w);
    }
  }

  takeWhere((w) => w.fromBook && !w.mastered);
  takeWhere((w) => w.fromBook && w.mastered);
  takeWhere((w) => !w.fromBook && !w.mastered);
  takeWhere((w) => !w.fromBook && w.mastered);

  return picked;
}
