import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseExecutor;

import '../db/app_database.dart';

/// 一条待写入的自加词（v0.9.0 导入用）。
class ImportCandidate {
  const ImportCandidate({required this.word, required this.meaning});

  /// 归一化后的词形（小写、空格压成一个）。
  final String word;

  /// 文件里自带的释义；空串表示「导入时没带释义，靠内置词典补」。
  final String meaning;

  ImportCandidate copyWith({String? word, String? meaning}) =>
      ImportCandidate(word: word ?? this.word, meaning: meaning ?? this.meaning);
}

/// 一次导入的结果。
class ImportCommitResult {
  const ImportCommitResult({
    required this.inserted,
    required this.skippedExisting,
    required this.batchId,
  });

  final int inserted;

  /// 库里已经有（820 或已在自加词里）而被跳过的条数。
  final int skippedExisting;

  final int batchId;
}

/// 导入批次（溯源用）。
class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.fileName,
    required this.importedAt,
    required this.wordCount,
    required this.skipped,
  });

  final int id;
  final String fileName;
  final DateTime importedAt;
  final int wordCount;
  final int skipped;
}

/// 导入的写库层（v0.9.0）。
///
/// 导入的词就是普通自加词：同一张 `user_added_words`、同一个 `added_at` 排序、
/// 进同一套六箱调度（决策 107）—— 这里不发明新口径，只多记两个字段：
/// 文件里自带的释义 `meaning` 与批次号 `batch_id`。
class ImportDao {
  const ImportDao();

  /// SQLite 默认变量上限 999，取 400 留余量（每个 key 在 UNION 里出现两次）。
  static const int _chunk = 400;

  /// 库里已存在的词（820 + 自加词）。预览页的「重复跳过」就是它算出来的。
  Future<Set<String>> existingKeys(List<String> keys) async {
    if (keys.isEmpty) return <String>{};
    final db = await AppDatabase.open();
    return _existingKeys(db, keys);
  }

  Future<Set<String>> _existingKeys(DatabaseExecutor db, List<String> keys) async {
    final out = <String>{};
    for (var i = 0; i < keys.length; i += _chunk) {
      final part = keys.sublist(i, i + _chunk > keys.length ? keys.length : i + _chunk);
      final marks = List.filled(part.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT word_key FROM my_words WHERE word_key IN ($marks) '
        'UNION '
        'SELECT word_key FROM user_added_words WHERE word_key IN ($marks)',
        [...part, ...part],
      );
      for (final r in rows) {
        out.add(r['word_key'] as String);
      }
    }
    return out;
  }

  /// 内置词典里这些词的释义（给「文件里没带释义」的词补）。
  ///
  /// 查不到就是查不到 —— 调用方会把释义标成「未查到」，**不许编**（需求原文）。
  Future<Map<String, String>> dictionaryMeanings(List<String> keys) async {
    if (keys.isEmpty) return const {};
    final db = await AppDatabase.open();
    final out = <String, String>{};
    for (var i = 0; i < keys.length; i += _chunk) {
      final part = keys.sublist(i, i + _chunk > keys.length ? keys.length : i + _chunk);
      final marks = List.filled(part.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT word, translation FROM words WHERE word IN ($marks)',
        part,
      );
      for (final r in rows) {
        final t = ((r['translation'] as String?) ?? '').trim();
        if (t.isNotEmpty) out[r['word'] as String] = t;
      }
    }
    return out;
  }

  /// 写库：跳过已存在的，其余按**文件顺序**给 `added_at`（严格递增）。
  ///
  /// 按文件顺序是为了让「先加的先学」成立（决策 107）：新词队列里自加词按
  /// `added_at` 正序排，这里不递增就会乱序。
  Future<ImportCommitResult> commit({
    required String fileName,
    required List<ImportCandidate> candidates,
    int skipped = 0,
    DateTime? now,
  }) async {
    final db = await AppDatabase.open();
    final at = now ?? DateTime.now();
    final keys = candidates.map((c) => c.word).toList();
    final existing = await _existingKeys(db, keys);
    final fresh = candidates.where((c) => !existing.contains(c.word)).toList();
    final skippedExisting = candidates.length - fresh.length;

    return db.transaction((txn) async {
      final batchId = await txn.insert('import_batch', {
        'file_name': fileName,
        'imported_at': at.millisecondsSinceEpoch,
        'word_count': fresh.length,
        'skipped': skipped + skippedExisting,
      });

      final base = at.millisecondsSinceEpoch;
      for (var i = 0; i < fresh.length; i++) {
        await txn.insert(
          'user_added_words',
          {
            'word_key': fresh[i].word,
            'added_at': base + i,
            'meaning': fresh[i].meaning,
            'batch_id': batchId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      return ImportCommitResult(
        inserted: fresh.length,
        skippedExisting: skippedExisting,
        batchId: batchId,
      );
    });
  }

  /// 最近的导入记录（倒序）。本版没有入口展示，留着给日志 / 后续「按批撤销」。
  Future<List<ImportBatch>> recentBatches({int limit = 20}) async {
    final db = await AppDatabase.open();
    final rows = await db.query('import_batch', orderBy: 'imported_at DESC', limit: limit);
    return rows
        .map((r) => ImportBatch(
              id: r['id'] as int,
              fileName: r['file_name'] as String,
              importedAt: DateTime.fromMillisecondsSinceEpoch(r['imported_at'] as int),
              wordCount: r['word_count'] as int,
              skipped: (r['skipped'] as int?) ?? 0,
            ))
        .toList();
  }
}
