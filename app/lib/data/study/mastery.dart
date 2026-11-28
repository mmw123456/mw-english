/// 「已掌握」的唯一口径（v0.14.0 统一）。
///
/// 口径本身是决策 117 定的：**箱位 ≥5 或连对 ≥3**。v0.14.0 之前只有文章取词
/// （`word_picker.dart`）照这个口径算，`StudyDao.todayStats()` 还按 `box >= 5`
/// 单独算一遍 —— 于是同一个词在文章里算「已掌握」、在我的页不算，两处数字不同。
///
/// 从 v0.14.0 起三处（学习页 / 我的页 / 学习统计页）加文章取词全走这里：
///
/// - Dart 侧：`Mastery.of(box, streak)`
/// - SQL 侧：把 [sqlWhere] 拼进 WHERE，**不要在别处再写一遍 `box >= 5`**
///
/// [sqlWhere] 里带 `killed = 0`：已斩的词不算已掌握 —— 斩是「不再学这个词」，
/// 不是「学会了」。也带 `started = 1`：星标但没开学的空壳记录不算。
///
/// 门禁用「`box >= 5` 只许出现在本文件」来保证不会有人再写第三份。
class Mastery {
  const Mastery._();

  /// 箱位门槛：到 5 箱（15 天间隔）就算掌握，不必等到箱 6（30 天）。
  static const int boxCut = 5;

  /// 连对门槛：连对 3 次也算，照顾「升箱慢但确实记住了」的词。
  static const int streakCut = 3;

  /// 单个词的判定（Dart 侧，词条还没进库时也能算）。
  static bool of(int box, int streak) => box >= boxCut || streak >= streakCut;

  /// 可直接拼进 `study_record` 查询的 WHERE 片段。
  ///
  /// 阈值从上面两个常量插值而来，改门槛只改一处。
  static const String sqlWhere =
      'started = 1 AND killed = 0 AND (box >= $boxCut OR streak >= $streakCut)';
}
