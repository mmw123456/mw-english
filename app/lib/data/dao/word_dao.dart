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

  /// 查询里有没有汉字。
  ///
  /// 中文查词没有「前缀」这回事：释义一律以词性或编号开头（`vt. 传送…`），
  /// 按开头匹配等于永远搜不到。所以**英文仍只匹配单词开头**（v0.6.2 的规则
  /// 不变，避免搜 no 带出 indigenous），**中文改走释义包含**（v0.6.7）。
  static final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

  static bool _isChinese(String q) => _cjk.hasMatch(q);

  /// 在我的词表里查：英文按单词前缀，中文按释义包含（v0.6.7）。
  Future<List<WordEntry>> searchMyWords(String query, {int limit = 60}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final db = await AppDatabase.open();

    if (_isChinese(q)) {
      // 两段释义都查：PDF 原文与 ECDICT 补全，任一段命中就算。
      final rows = await db.rawQuery(
        '''
        SELECT * FROM my_words
        WHERE meaning_pdf LIKE ?1 OR meaning_ecdict LIKE ?1
        ORDER BY no ASC
        LIMIT ?2
        ''',
        ['%$q%', limit],
      );
      return rows.map(WordEntry.fromRow).toList();
    }

    final rows = await db.rawQuery(
      '''
      SELECT * FROM my_words
      WHERE word_key LIKE ?1
      ORDER BY CASE WHEN word_key = ?2 THEN 0
                    WHEN word_key LIKE ?3 THEN 1
                    ELSE 2 END, no ASC
      LIMIT ?4
      ''',
      ['$q%', q, '$q%', limit],
    );
    return rows.map(WordEntry.fromRow).toList();
  }

  /// 在离线词典里查词：英文精确 → 前缀（v0.6.2），中文按释义包含（v0.6.7）。
  Future<List<DictEntry>> searchDictionary(String query, {int limit = 40}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final db = await AppDatabase.open();

    if (_isChinese(q)) {
      final rows = await db.rawQuery(
        '''
        SELECT * FROM words
        WHERE translation LIKE ?1
        ORDER BY CASE WHEN frq = 0 THEN 999999 ELSE frq END ASC,
                 word ASC
        LIMIT ?2
        ''',
        ['%$q%', limit],
      );
      return rows.map(DictEntry.fromRow).toList();
    }

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
      ['$q%', q, '$q%', limit],
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

  /// 自加词（用户在词典详情页点「加入我的词表」）。按加入时间倒序。
  Future<List<DictEntry>> loadAddedWords({int limit = 300}) async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      '''
      SELECT w.* FROM user_added_words u
      JOIN words w ON w.word = u.word_key
      ORDER BY u.added_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(DictEntry.fromRow).toList();
  }

  /// 自加词里查：英文按单词前缀，中文按释义包含（v0.6.7）。
  Future<List<DictEntry>> searchAddedWords(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final db = await AppDatabase.open();

    if (_isChinese(q)) {
      final rows = await db.rawQuery(
        '''
        SELECT w.* FROM user_added_words u
        JOIN words w ON w.word = u.word_key
        WHERE w.translation LIKE ?1
        ORDER BY u.added_at DESC
        LIMIT ?2
        ''',
        ['%$q%', limit],
      );
      return rows.map(DictEntry.fromRow).toList();
    }

    final rows = await db.rawQuery(
      '''
      SELECT w.* FROM user_added_words u
      JOIN words w ON w.word = u.word_key
      WHERE u.word_key LIKE ?1
      ORDER BY CASE WHEN u.word_key = ?2 THEN 0
                    WHEN u.word_key LIKE ?3 THEN 1
                    ELSE 2 END, u.added_at DESC
      LIMIT ?4
      ''',
      ['$q%', q, '$q%', limit],
    );
    return rows.map(DictEntry.fromRow).toList();
  }

  /// 这个词是否在 820 词单词本里。详情页据此决定按钮文案。
  Future<bool> inWorkbook(String wordKey) async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) FROM my_words WHERE word_key = ?',
      [wordKey.trim().toLowerCase()],
    );
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }
}
