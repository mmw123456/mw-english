import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Database, Sqflite;

import '../db/app_database.dart';
import '../models/word_detail.dart';

/// 词条详情的数据装配。
///
/// 一个页面要的东西分散在四张表：`my_words`（820 词原文）、`words`（43,350
/// 词典）、`synonyms`（近义词）、`user_added_words` / `study_record`（用户状态）。
/// 全部在这里拼成一个 [WordDetail]，UI 只负责画。
class DetailDao {
  const DetailDao();

  /// `words.exchange` 的字段含义，顺序即界面顺序。
  static const Map<String, String> _exchangeLabels = {
    'p': '过去式',
    'd': '过去分词',
    'i': '现在分词',
    '3': '第三人称单数',
    's': '复数',
    'r': '比较级',
    't': '最高级',
  };

  /// 读一个词的完整详情。词库里都没有就返回 null。
  Future<WordDetail?> load(String wordKey, {String? displayWord}) async {
    final db = await AppDatabase.open();
    final key = wordKey.trim().toLowerCase();

    final mine = await db.query(
      'my_words',
      where: 'word_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    final dict = await db.query(
      'words',
      where: 'word = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (mine.isEmpty && dict.isEmpty) return null;

    final my = mine.isEmpty ? null : mine.first;
    final dic = dict.isEmpty ? null : dict.first;

    final starRows = await db.query(
      'study_record',
      columns: ['starred'],
      where: 'word_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    final addedRows = await db.query(
      'user_added_words',
      columns: ['word_key'],
      where: 'word_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    final forms = parseExchange((dic?['exchange'] as String?) ?? '');

    return WordDetail(
      wordKey: key,
      word: displayWord ??
          (my?['word'] as String?) ??
          (dic?['word'] as String?) ??
          key,
      phonetic: ((my?['phonetic'] as String?) ??
              (dic?['phonetic'] as String?) ??
              '')
          .trim(),
      meaningPdf: (my?['meaning_pdf'] as String?) ?? '',
      pdfTruncated: ((my?['pdf_truncated'] as int?) ?? 0) == 1,
      meaningEcdict: ((my?['meaning_ecdict'] as String?) ??
              (dic?['translation'] as String?) ??
              '')
          .trim(),
      pos: ((dic?['pos'] as String?) ?? (my?['pos'] as String?) ?? '').trim(),
      tag: ((my?['tag'] as String?) ?? (dic?['tag'] as String?) ?? '').trim(),
      collins: (dic?['collins'] as int?) ?? ((my?['collins'] as int?) ?? 0),
      no: my?['no'] as int?,
      isAdded: addedRows.isNotEmpty,
      starred: ((starRows.isEmpty ? 0 : starRows.first['starred'] as int?) ?? 0) == 1,
      forms: forms,
      synonyms: await _loadSynonyms(db, key),
      nearWords: await _loadNearWords(db, key, (dic?['frq'] as int?) ?? 0),
    );
  }

  /// 解析 `words.exchange`。
  ///
  /// 格式是 `p:abandoned/d:abandoned/i:abandoning/3:abandons`，另有 `0`/`1`
  /// 这类 ECDICT 内部标记，直接忽略。同一个词形重复出现时只留第一条
  /// （如 `p` 与 `d` 都是 `abandoned` 时两行都保留，因为标签不同）。
  static List<WordForm> parseExchange(String exchange) {
    if (exchange.trim().isEmpty) return const [];
    final out = <WordForm>[];
    final seen = <String>{};
    for (final part in exchange.split('/')) {
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      final code = part.substring(0, idx);
      final value = part.substring(idx + 1).trim();
      final label = _exchangeLabels[code];
      if (label == null || value.isEmpty) continue;
      if (!seen.add('$code:$value')) continue;
      out.add(WordForm(label: label, value: value));
    }
    return out;
  }

  Future<List<SynonymEntry>> _loadSynonyms(Database db, String key) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.syn_key, s.distinction, w.translation, w.phonetic
      FROM synonyms s
      LEFT JOIN words w ON w.word = s.syn_key
      WHERE s.word_key = ?
      ORDER BY s.rank ASC
      ''',
      [key],
    );
    return rows.map((r) {
      final gloss = ((r['translation'] as String?) ?? '').split('\n').first.trim();
      return SynonymEntry(
        word: r['syn_key'] as String,
        distinction: r['distinction'] as String,
        gloss: gloss,
        phonetic: ((r['phonetic'] as String?) ?? '').trim(),
      );
    }).toList();
  }

  /// 形近词：先按「首字母 + 长度 ±2」把候选压到几千条，再算编辑距离。
  ///
  /// 43,350 词全量两两算是不可能在手机上做的（O(n·m)），所以必须有前置过滤。
  /// 词组（含空格）跳过——编辑距离对词组没有意义。
  Future<List<NearWord>> _loadNearWords(Database db, String key, int frq) async {
    if (key.isEmpty || key.contains(' ')) return const [];
    final len = key.length;
    if (len < 3) return const [];

    final rows = await db.rawQuery(
      '''
      SELECT word, translation, frq
      FROM words
      WHERE word LIKE ?1 AND LENGTH(word) BETWEEN ?2 AND ?3 AND word <> ?4
      LIMIT 4000
      ''',
      ['${key[0]}%', len - 2, len + 2, key],
    );

    final scored = <({String word, String gloss, int dist, int frq})>[];
    for (final r in rows) {
      final w = r['word'] as String;
      // 派生词不是形近词：eliminate → eliminated / eliminator、sketch → sketchy
      // 这类是同一个词的变形或派生，放在「形近词」里只会误导。
      if (_isDerived(key, w)) continue;
      final d = _distance(key, w, cap: 3);
      if (d <= 0 || d > 3) continue;
      final gloss = ((r['translation'] as String?) ?? '').split('\n').first.trim();
      scored.add((
        word: w,
        gloss: gloss,
        dist: d,
        frq: (r['frq'] as int?) ?? 0,
      ));
    }
    scored.sort((a, b) {
      final byDist = a.dist.compareTo(b.dist);
      if (byDist != 0) return byDist;
      return _frqRank(a.frq).compareTo(_frqRank(b.frq));
    });

    // 越像越好，最多 5 个；本词词频越低，形近词越要挑常用的
    return scored
        .take(5)
        .map((e) => NearWord(word: e.word, gloss: e.gloss, distance: e.dist))
        .toList();
  }

  static int _frqRank(int frq) => frq <= 0 ? 999999 : frq;

  /// 判断 b 是不是 a 的变形/派生（互为前缀且长度接近）。
  static bool _isDerived(String a, String b) {
    if (a == b) return true;
    final short = a.length <= b.length ? a : b;
    final long = a.length <= b.length ? b : a;
    if (!long.startsWith(short)) return false;
    return long.length - short.length <= 4;
  }

  /// Levenshtein 距离，超过 [cap] 立刻返回 cap + 1（省时间）。
  static int _distance(String a, String b, {int cap = 3}) {
    if ((a.length - b.length).abs() > cap) return cap + 1;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > cap) return cap + 1;
      for (var j = 0; j <= b.length; j++) {
        prev[j] = cur[j];
      }
    }
    return prev[b.length];
  }

  /// 星标开关。没有学习记录时补一条空壳（`started = 0`，不算学过）。
  ///
  /// `first_seen_at` 写 0 表示「还没真正开始学」，等第一次答题时再改成当时时间，
  /// 否则单纯加个星标就会被算进当天的「已学新词」。
  Future<bool> toggleStar(String wordKey) async {
    final db = await AppDatabase.open();
    final key = wordKey.trim().toLowerCase();
    final rows = await db.query(
      'study_record',
      columns: ['starred'],
      where: 'word_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (rows.isEmpty) {
      await db.insert(
        'study_record',
        {
          'word_key': key,
          'box': 0,
          'due_at': now,
          'first_seen_at': 0,
          'starred': 1,
          'started': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return true;
    }
    final next = ((rows.first['starred'] as int?) ?? 0) == 1 ? 0 : 1;
    await db.update(
      'study_record',
      {'starred': next},
      where: 'word_key = ?',
      whereArgs: [key],
    );
    return next == 1;
  }

  /// 加入我的词表（自加）。已在 820 里就不动。
  Future<void> addToMyList(String wordKey) async {
    final db = await AppDatabase.open();
    final key = wordKey.trim().toLowerCase();
    final inBook = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM my_words WHERE word_key = ?',
          [key],
        )) ??
        0;
    if (inBook > 0) return;
    await db.insert(
      'user_added_words',
      {'word_key': key, 'added_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 从自加词里移除。820 词本来就不能从这里删。
  Future<void> removeFromMyList(String wordKey) async {
    final db = await AppDatabase.open();
    await db.delete(
      'user_added_words',
      where: 'word_key = ?',
      whereArgs: [wordKey.trim().toLowerCase()],
    );
  }
}
