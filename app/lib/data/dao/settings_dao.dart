import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Sqflite;

import '../../app/app_defaults.dart';
import '../db/app_database.dart';

/// `settings` 表的读写。整张表就是 key/value，没有别的花样。
///
/// 目前存三类东西：
/// - `dict_revision`：词库资源版本，`AppDatabase` 用
/// - `mask_chinese`：遮盖中文开关（词库页与详情页共用）
/// - `daily_new_target`：每日新词目标（v0.8.0，默认 30，范围 10–50）
/// - `auto_speak`：自动朗读开关（v0.8.0，默认开）
/// - `quota_YYYY-MM-DD`：当天的学习配额缓存（决策 35，改目标时清掉）
class SettingsDao {
  const SettingsDao();

  static const String maskChineseKey = 'mask_chinese';
  static const String dailyTargetKey = 'daily_new_target';
  static const String autoSpeakKey = 'auto_speak';

  /// 把目标夹进 10–50。设置页、读库、门禁都走这一个函数。
  static int clampDailyTarget(int value) => value.clamp(
        AppDefaults.minDailyNewWords,
        AppDefaults.maxDailyNewWords,
      );

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

  /// 每日新词目标。没设过 / 存坏了 / 越界都回到 30 或夹进 10–50。
  Future<int> dailyTarget() async {
    final raw = int.tryParse(await get(dailyTargetKey) ?? '');
    return clampDailyTarget(raw ?? AppDefaults.dailyNewWordTarget);
  }

  /// 改每日目标，并**清掉所有当天配额缓存**（决策 35 / 109）。
  ///
  /// 不清的话，今天已经按旧目标算过的那条 `quota_YYYY-MM-DD` 会被继续读，
  /// 改了目标当天不生效。删掉后下一次 `StudyDao.dailyQuota()` 按新目标重算。
  /// 写目标与删缓存放在同一个事务里，中途被杀进程不会只改一半。
  Future<void> setDailyTarget(int value) async {
    final db = await AppDatabase.open();
    await db.transaction((txn) async {
      await txn.insert(
        'settings',
        {'key': dailyTargetKey, 'value': '${clampDailyTarget(value)}'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('settings', where: "key LIKE 'quota_%'");
    });
  }

  /// 自动朗读开关。默认开：每张新卡出现时读一遍。
  Future<bool> autoSpeak() => getFlag(autoSpeakKey, fallback: true);

  Future<void> setAutoSpeak(bool value) => setFlag(autoSpeakKey, value);

  /// 词库里有多少条自加词，用于「我的词表」计数与「全部词汇」口径。
  Future<int> addedCount() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) FROM user_added_words u WHERE NOT EXISTS '
      '(SELECT 1 FROM my_words m WHERE m.word_key = u.word_key)',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
