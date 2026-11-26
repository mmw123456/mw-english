import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Sqflite;

import '../db/app_database.dart';

/// `settings` 表的读写。整张表就是 key/value，没有别的花样。
///
/// 目前存两类东西：
/// - `dict_revision`：词库资源版本，`AppDatabase` 用
/// - `mask_chinese`：遮盖中文开关（词库页与详情页共用）
class SettingsDao {
  const SettingsDao();

  static const String maskChineseKey = 'mask_chinese';

  Future<String?> get(String key) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await AppDatabase.open();
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getFlag(String key, {bool fallback = false}) async {
    final v = await get(key);
    if (v == null) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<void> setFlag(String key, bool value) async {
    await set(key, value ? '1' : '0');
  }

  /// 遮盖中文开关。默认关。
  Future<bool> maskChinese() => getFlag(maskChineseKey);

  Future<void> setMaskChinese(bool value) => setFlag(maskChineseKey, value);

  /// 词库里有多少条自加词，用于「我的词表」计数。
  Future<int> addedCount() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) FROM user_added_words');
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
