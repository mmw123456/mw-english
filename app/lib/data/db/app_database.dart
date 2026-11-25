import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 数据库入口。
///
/// 只有一个库文件 `mw_english.db`，里面同时装：
/// - 词库表 `words`（43,350 词离线词典）、`my_words`（820 词单词本）、`roots`（词根）
/// - 用户表 `study_record`（学习记录）、`study_log`（答题流水）、`settings`（设置）
///
/// 首次启动从 assets 拷 `dict.sqlite` 到 databases 目录，再补建用户表。
/// 词库是只读的，用户数据单独建表，所以以后换词库只要重导三张词表，
/// 不碰 study_record —— 但这条策略 P0 不实现，见下方 [_dictRevision] 说明。
class AppDatabase {
  AppDatabase._();

  static const String assetPath = 'assets/db/dict.sqlite';
  static const String fileName = 'mw_english.db';

  /// 词库资源版本。
  ///
  /// 每次重新生成 `dict.sqlite` 并且要让老用户也拿到新词库时，把这个值 +1。
  /// 启动时比对 settings.dict_revision，不一致就整库重拷（用户学习记录会清空）。
  /// P0 阶段词库固定，保持 1；真要上线换词库前得先做「导出用户表 → 重拷 → 导回」。
  static const int _dictRevision = 1;

  /// 用户表结构版本，与 `PRAGMA user_version` 对应。
  static const int _schemaVersion = 1;

  static Database? _db;
  static Future<Database>? _opening;

  /// 拿到数据库连接。首次调用会触发资源拷贝与建表。
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
    if (db != null && db.isOpen) await db.close();
  }

  static Future<Database> _openInternal() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, fileName);
    await _ensureAssetCopied(dir, path);

    return openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) => _createUserTables(db),
      onUpgrade: (db, oldVersion, newVersion) => _createUserTables(db),
    );
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
  /// 首次 openDatabase 走的是 onUpgrade(0, 1) 而不是 onCreate。
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
        killed        INTEGER NOT NULL DEFAULT 0
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

    await db.insert(
      'settings',
      {'key': 'dict_revision', 'value': _dictRevision.toString()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

/// 数据库不可用。UI 层据此显示错误态，不白屏。
class DatabaseUnavailable implements Exception {
  DatabaseUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => '本地数据库打不开：$cause';
}
