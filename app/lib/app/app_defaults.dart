/// 应用级默认值。
///
/// 这些值将来会由「我的 → 学习计划」设置页覆盖，存进 user.db 的 settings 表。
/// 在设置页做出来之前，代码统一引用这里的常量，不要在页面里硬编码数字。
class AppDefaults {
  const AppDefaults._();

  /// 每日新词目标。用户 2026-11-25 定案从 20 改为 30。
  static const int dailyNewWordTarget = 30;

  /// 每日待复习上限。超过上限的积压按天往后顺延，不堆在一天。
  static const int dailyReviewCap = 150;

  /// Leitner 六箱的间隔天数（箱位 0 = 新词，1–5 = 已学）。
  static const List<int> boxIntervals = [0, 1, 2, 4, 7, 15, 30];

  /// 熟词保护：箱位达到该值后答错只降一档，不回到低箱。
  static const int protectedBox = 4;

  /// 熟词保护下答错的最低落点。
  static const int protectedFloorBox = 3;

  /// 新词进入高箱位前需连续答对的次数，防手滑冲高。
  static const int newWordStreakToPromote = 3;

  /// 断档判定：连续未学达到该天数，当天新词减半且只出待复习。
  static const int lapseHalfQuotaDays = 3;

  /// 断档判定：连续未学达到该天数，按断档天数摊薄每日配额。
  static const int lapseSpreadQuotaDays = 7;
}
