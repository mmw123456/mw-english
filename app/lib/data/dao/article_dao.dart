import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Sqflite;

import '../db/app_database.dart';
import '../models/article.dart';

/// 文章读写的接口。
///
/// 抽成接口只为了一件事：`flutter test` 里开不了 sqflite（要在设备 / 桌面上跑），
/// 而「取词 → 生成 → 校验 → 存库 → 列表」这条链必须能单测。
/// 生产用 [ArticleDao]，测试塞内存实现；别在业务代码里判类型。
abstract class ArticleStore {
  /// 已经当过目标词的 word_key。取下一篇时全部排除。
  Future<Set<String>> usedWordKeys();

  /// 已生成的文章，新的在前。
  Future<List<Article>> recent({int limit = 50});

  Future<Article?> byId(int id);

  Future<int> count();

  Future<int> save({
    required String title,
    required String body,
    required List<ArticleWord> targetWords,
    required int wordCount,
    required double rareRatio,
    required String model,
    DateTime? now,
  });

  /// 标记已读；已经读过的保持第一次的时间。
  Future<void> markRead(int id, {DateTime? now});
}

/// 落到 SQLite 的实现。
///
/// 两张表一起用：
/// - `article` 存正文、单词表、词数、生词率、时间与已读；
/// - `article_word` 记「哪些词已经被哪篇用过」，取下一篇时直接排除，
///   这是「进度不重复」的硬保证（不靠游标计数，见 app_database 里的说明）。
class ArticleDao implements ArticleStore {
  const ArticleDao();

  @override
  Future<Set<String>> usedWordKeys() async {
    final db = await AppDatabase.open();
    final rows = await db.query('article_word', columns: ['word_key']);
    return {
      for (final r in rows) (r['word_key'] as String?) ?? '',
    }..removeWhere((e) => e.isEmpty);
  }

  @override
  Future<List<Article>> recent({int limit = 50}) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'article',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(articleFromRow).toList();
  }

  @override
  Future<Article?> byId(int id) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'article',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return articleFromRow(rows.first);
  }

  @override
  Future<int> count() async {
    final db = await AppDatabase.open();
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM article')) ?? 0;
  }

  @override
  Future<int> save({
    required String title,
    required String body,
    required List<ArticleWord> targetWords,
    required int wordCount,
    required double rareRatio,
    required String model,
    DateTime? now,
  }) async {
    final db = await AppDatabase.open();
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;

    return db.transaction<int>((txn) async {
      final id = await txn.insert('article', {
        'title': title,
        'body': body,
        'target_words': ArticleWord.encodeList(targetWords),
        'word_count': wordCount,
        'rare_ratio': rareRatio,
        'model': model,
        'created_at': at,
      });
      await linkWords(txn, id, targetWords.map((w) => w.word).toList());
      return id;
    });
  }

  @override
  Future<void> markRead(int id, {DateTime? now}) async {
    final db = await AppDatabase.open();
    await db.rawUpdate(
      'UPDATE article SET read_at = ? WHERE id = ? AND read_at IS NULL',
      [(now ?? DateTime.now()).millisecondsSinceEpoch, id],
    );
  }
}

/// 把一批词登记到某篇文章名下（`article_word`）。
///
/// 抽成公开函数是为了让内存实现与 SQLite 实现共用同一套归一化规则
/// （小写、去空），两边算出来的「已用词」必须一模一样，否则会出现重复出词。
Future<void> linkWords(
  DatabaseExecutor txn,
  int articleId,
  List<String> keys,
) async {
  final batch = txn.batch();
  var any = false;
  for (final k in keys) {
    final key = k.trim().toLowerCase();
    if (key.isEmpty) continue;
    any = true;
    batch.insert('article_word', {
      'article_id': articleId,
      'word_key': key,
    });
  }
  if (any) await batch.commit(noResult: true);
}

/// 行 → [Article]。SQLite 实现用，测试里的内存实现也照这个映射，
/// 免得「数据库里的字段名」与「模型字段名」两处各写一遍。
Article articleFromRow(Map<String, Object?> r) {
  final at = (r['created_at'] as int?) ?? 0;
  final read = r['read_at'] as int?;
  return Article(
    id: (r['id'] as int?) ?? 0,
    title: (r['title'] as String?) ?? '',
    body: (r['body'] as String?) ?? '',
    targetWords: ArticleWord.decodeList((r['target_words'] as String?) ?? '[]'),
    wordCount: (r['word_count'] as int?) ?? 0,
    rareRatio: ((r['rare_ratio'] as num?) ?? 0).toDouble(),
    model: (r['model'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    readAt: read == null ? null : DateTime.fromMillisecondsSinceEpoch(read),
  );
}
