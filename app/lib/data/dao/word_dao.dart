import 'package:sqflite/sqflite.dart' show Sqflite;

import '../db/app_database.dart';
import '../models/word_entry.dart';

/// 词库查询。只读，不改任何表。
class WordDao {
  const WordDao();

  /// 我的词表条数（820）。
  Future<int> countMyWords() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM my_words');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 离线词典条数（43,350）。
  Future<int> countDictionary() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM words');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 按序号读我的词表。分页，避免一次把 820 条全塞进内存。
  Future<List<WordEntry>> loadMyWords({int offset = 0, int limit = 200}) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'my_words',
      orderBy: 'no ASC',
      offset: offset,
      limit: limit,
    );
    return rows.map(WordEntry.fromRow).toList();
  }

  /// 在我的词表里按单词模糊查。
  Future<List<WordEntry>> searchMyWords(String query, {int limit = 60}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      '''
      SELECT * FROM my_words
      WHERE word_key LIKE ?1
      ORDER BY CASE WHEN word_key = ?2 THEN 0
                    WHEN word_key LIKE ?3 THEN 1
                    ELSE 2 END, no ASC
      LIMIT ?4
      ''',
      ['%$q%', q, '$q%', limit],
    );
    return rows.map(WordEntry.fromRow).toList();
  }

  /// 在离线词典里查词。精确命中的排最前，其次前缀，再其次包含。
  Future<List<DictEntry>> searchDictionary(String query, {int limit = 40}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      '''
      SELECT * FROM words
      WHERE word LIKE ?1
      ORDER BY CASE WHEN word = ?2 THEN 0
                    WHEN word LIKE ?3 THEN 1
                    ELSE 2 END,
               CASE WHEN frq = 0 THEN 999999 ELSE frq END ASC
      LIMIT ?4
      ''',
      ['%$q%', q, '$q%', limit],
    );
    return rows.map(DictEntry.fromRow).toList();
  }

  /// 精确查一个词，用于学习卡片顶部查词。
  Future<DictEntry?> lookup(String word) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'words',
      where: 'word = ?',
      whereArgs: [word.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DictEntry.fromRow(rows.first);
  }
}
