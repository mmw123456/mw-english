import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 数据库入口。
///
/// 只有一个库文件 `mw_english.db`，里面同时装：
/// - 词库表 `words`（43,350 词离线词典）、`my_words`（820 词单词本）、`roots`（词根）
/// - 用户表 `study_record`（学习记录）、`study_log`（答题流水）、`settings`（设置）、
///   `synonyms`（近义词，首次启动从 assets 灌入）、`user_added_words`（自加词）
///
/// 首次启动从 assets 拷 `dict.sqlite` 到 databases 目录，再补建用户表。
/// 词库是只读的，用户数据单独建表，所以以后换词库只要重导三张词表，
/// 不碰 study_record —— 但这条策略 P0 不实现，见下方 [_dictRevision] 说明。
class AppDatabase {
  AppDatabase._();

  static const String assetPath = 'assets/db/dict.sqlite';
  static const String synonymsAsset = 'assets/data/synonyms.json';
  static const String fileName = 'mw_english.db';

  /// 词库资源版本。
  ///
  /// 每次重新生成 `dict.sqlite` 并且要让老用户也拿到新词库时，把这个值 +1。
  /// 启动时比对 settings.dict_revision，不一致就整库重拷（用户学习记录会清空）。
  /// P0 阶段词库固定，保持 1；真要上线换词库前得先做「导出用户表 → 重拷 → 导回」。
  static const int _dictRevision = 1;

  /// 用户表结构版本，与 `PRAGMA user_version` 对应。
  ///
  /// 2 = 增加 `synonyms`、`user_added_words`（v0.4.0）。
  /// 3 = `study_record` 增加 `started` / `retest` / `peak_box`（v0.5.0）。
  /// 4 = 增加 `daily_stat` 按天完成日志（v0.7.4，热力图用）。
  /// 5 = `user_added_words` 增加 `meaning` / `batch_id`，新增 `import_batch`（v0.9.0）。
  /// 6 = 新增 `article` / `article_word`（v0.10.0，按词库生成文章）。
  static const int _schemaVersion = 6;

  static Database? _db;
  static Future<Database>? _opening;
  static bool _synonymsSeeded = false;

  /// 拿到数据库连接。首次调用会触发资源拷贝、建表与近义词灌入。
  static Future<Database> open() {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    return _opening ??= _openInternal().then((db) {
      _db = db;
      _opening = null;
      return db;
    }).catchError((Object e) {
      _opening = null;
      throw DatabaseUnavailable(e);
    });
  }

  /// 关闭连接。测试与热重载用。
  static Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    _synonymsSeeded = false;
    if (db != null && db.isOpen) await db.close();
  }

  static Future<Database> _openInternal() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, fileName);
    await _ensureAssetCopied(dir, path);

    final db = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) => _createUserTables(db),
      onUpgrade: (db, oldVersion, newVersion) => _migrate(db, oldVersion),
    );
    await _seedSynonyms(db);
    return db;
  }

  /// 升级：先补齐可能缺的表，再补 3 版新增的列。
  ///
  /// `CREATE TABLE IF NOT EXISTS` 不会给已存在的表加列，所以老库必须走 ALTER。
  /// 从 assets 拷来的库 user_version 是 0，study_record 还不存在，
  /// 走的是「建表」分支，ALTER 会因为列已存在而自动跳过。
  static Future<void> _migrate(Database db, int oldVersion) async {
    await _createUserTables(db);
    if (oldVersion >= _schemaVersion) return;

    final cols = (await db.rawQuery('PRAGMA table_info(study_record)'))
        .map((r) => r['name'] as String)
        .toSet();
    if (!cols.contains('started')) {
      await db.execute(
        'ALTER TABLE study_record ADD COLUMN started INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!cols.contains('retest')) {
      await db.execute(
        'ALTER TABLE study_record ADD COLUMN retest INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!cols.contains('peak_box')) {
      await db.execute(
        'ALTER TABLE study_record ADD COLUMN peak_box INTEGER NOT NULL DEFAULT 0',
      );
    }

    // v0.9.0：自加词补释义与批次号。老库里这两列不存在，靠列名判断再 ALTER。
    final addedCols = (await db.rawQuery('PRAGMA table_info(user_added_words)'))
        .map((r) => r['name'] as String)
        .toSet();
    if (!addedCols.contains('meaning')) {
      await db.execute(
        "ALTER TABLE user_added_words ADD COLUMN meaning TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!addedCols.contains('batch_id')) {
      await db.execute('ALTER TABLE user_added_words ADD COLUMN batch_id INTEGER');
    }
  }

  static Future<void> _ensureAssetCopied(String dir, String path) async {
    final file = File(path);
    if (await file.exists()) return;

    await Directory(dir).create(recursive: true);
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  /// 用户表。全部 IF NOT EXISTS——从 assets 拷来的库 user_version 是 0，
  /// 首次 openDatabase 走的是 onUpgrade(0, 2) 而不是 onCreate。
  static Future<void> _createUserTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_record(
        word_key      TEXT PRIMARY KEY,
        box           INTEGER NOT NULL DEFAULT 0,
        due_at        INTEGER NOT NULL,
        streak        INTEGER NOT NULL DEFAULT 0,
        correct_count INTEGER NOT NULL DEFAULT 0,
        wrong_count   INTEGER NOT NULL DEFAULT 0,
        first_seen_at INTEGER NOT NULL,
        last_seen_at  INTEGER,
        starred       INTEGER NOT NULL DEFAULT 0,
        killed        INTEGER NOT NULL DEFAULT 0,
        started       INTEGER NOT NULL DEFAULT 0,
        retest        INTEGER NOT NULL DEFAULT 0,
        peak_box      INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_record_due ON study_record(killed, due_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_log(
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        word_key      TEXT NOT NULL,
        at            INTEGER NOT NULL,
        correct       INTEGER NOT NULL,
        question_type TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_log_at ON study_log(at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings(
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 按天完成日志（v0.7.4）：首页热力图与「连续 N 天」读它。
    //
    // 主键 (day, word_key) 保证「一天一个词只算一次完成」—— 当日重测、
    // 先错后对都不会把数字抬高。kind：0 = 新词，1 = 复习。
    //
    // 只从 v0.7.4 起攒，不回填历史：`study_log` 虽有作答流水，但推不出
    // 当时那条是「新词」还是「复习」，回填出来的是另一个口径。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_stat(
        day      TEXT NOT NULL,
        word_key TEXT NOT NULL,
        kind     INTEGER NOT NULL DEFAULT 1,
        at       INTEGER NOT NULL,
        PRIMARY KEY(day, word_key)
      )
    ''');

    // 近义词：只做 820 词，词典里的其他词一行都没有。
    // 单独建表而不是塞进 dict.sqlite，好处是换词库/补数据时不用重拷整库。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS synonyms(
        word_key    TEXT NOT NULL,
        syn_key     TEXT NOT NULL,
        distinction TEXT NOT NULL,
        rank        INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(word_key, syn_key)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_syn_word ON synonyms(word_key)',
    );

    // 用户从词典里自己加进来的词。不动 my_words 的 1–820 原序。
    //
    // v0.9.0（schema 5）：加 `meaning` 与 `batch_id`。
    // - `meaning`：导入时文件里自带的释义。以前自加词的释义只能靠 `words.translation`，
    //   导入的词条一旦不在 43,350 词词典里就什么都显示不出来；有了这列才能
    //   「自带释义保留 → 没有的查词典 → 都查不到标未查到」。
    // - `batch_id`：来自哪一批导入（`import_batch`），方便溯源与按批撤销。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_added_words(
        word_key TEXT PRIMARY KEY,
        added_at INTEGER NOT NULL,
        meaning  TEXT NOT NULL DEFAULT '',
        batch_id INTEGER
      )
    ''');

    // 导入批次（v0.9.0）：一次导入一条，记文件名与日期。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_batch(
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name   TEXT NOT NULL,
        imported_at INTEGER NOT NULL,
        word_count  INTEGER NOT NULL,
        skipped     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 生成的文章（v0.10.0）。
    //
    // - `body` 存**原文**，目标词仍是 `**word**` 标记：渲染时再解析成加粗，
    //   而不是存一段 HTML / 一堆 span。好处是同一个字段既能显示、又能重新统计词数。
    // - `target_words` 是 JSON 数组 `[{"w":"abandon","pos":"v.","zh":"放弃"}]`，
    //   只给详情页的单词表用；判定「哪些词该加粗」仍然看 body 里的标记。
    // - `rare_ratio` 是生成时算好的生词率（0.031 = 3.1%），存下来是为了列表直接显示，
    //   不用每次重算（重算要再查一遍 43,350 词词典）。
    // - `read_at` 为 null 即未读。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS article(
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        title        TEXT NOT NULL,
        body         TEXT NOT NULL,
        target_words TEXT NOT NULL,
        word_count   INTEGER NOT NULL,
        rare_ratio   REAL NOT NULL DEFAULT 0,
        model        TEXT NOT NULL DEFAULT '',
        created_at   INTEGER NOT NULL,
        read_at      INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_at ON article(created_at)',
    );

    // 哪些词已经被哪篇文章用过（v0.10.0）。
    //
    // 这是「进度自动管理、不重复」的**硬保证**：取下一篇的目标词时，
    // 直接排除在这张表里出现过的 word_key。不靠游标计数——游标一旦算错
    // （比如用户中途斩了词、或补了自加词）就会漏词或重词，而这张表不会。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS article_word(
        article_id INTEGER NOT NULL,
        word_key   TEXT NOT NULL,
        PRIMARY KEY(article_id, word_key)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_word ON article_word(word_key)',
    );

    await db.insert(
      'settings',
      {'key': 'dict_revision', 'value': _dictRevision.toString()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 把 assets 里的近义词灌进 `synonyms` 表。
  ///
  /// 只灌一次：表为空才动手。词库资源换了、`synonyms.json` 变多时，
  /// 用 `synonyms` 的条数判断不够准，所以这里以「表空」为唯一条件，
  /// 补数据靠 `_source/gen_synonyms.py` 重出 json + 手动清表。
  static Future<void> _seedSynonyms(Database db) async {
    if (_synonymsSeeded) return;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM synonyms'),
        ) ??
        0;
    if (count > 0) {
      _synonymsSeeded = true;
      return;
    }

    try {
      final raw = await rootBundle.loadString(synonymsAsset);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final batch = db.batch();
      var rank = 0;
      decoded.forEach((key, value) {
        if (value is! List) return;
        final wordKey = key.toString();
        rank = 0;
        for (final item in value) {
          if (item is! Map) continue;
          final syn = (item['w'] ?? '').toString().trim().toLowerCase();
          final dist = (item['dist'] ?? '').toString().trim();
          if (syn.isEmpty || dist.isEmpty) continue;
          batch.insert(
            'synonyms',
            {
              'word_key': wordKey,
              'syn_key': syn,
              'distinction': dist,
              'rank': rank++,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });
      await batch.commit(noResult: true);
      _synonymsSeeded = true;
    } catch (_) {
      // assets 缺失（例如测试环境）不算致命：详情页近义词区块整块不显示。
      _synonymsSeeded = true;
    }
  }
}

/// 数据库不可用。UI 层据此显示错误态，不白屏。
class DatabaseUnavailable implements Exception {
  DatabaseUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => '本地数据库打不开：$cause';
}
