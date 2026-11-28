import '../dao/study_dao.dart';
import '../spelling/spelling_round.dart';

/// 趋势图上的一天。
///
/// [total] 为 null = 那天**没有记录**（不是「记录了 0」）。这两种状态在图上
/// 必须分得开：没有记录不画柱，不能补一个 0 高的柱子冒充「学过但 0 个」。
class DaySlot {
  const DaySlot({required this.day, required this.total});

  /// `yyyy-MM-dd`（[StudyDao.dayKey] 同一格式）。
  final String day;

  final DayTotal? total;

  bool get hasData => total != null;
}

/// 学习统计页要的全部数字（一次查询装一包）。
///
/// 每个字段都标明来源表，页面上任何一个数字都能追到一条查询：
///
/// | 数字 | 来源 |
/// | --- | --- |
/// | 今日新学 / 今日复习 | `daily_stat`（v0.7.4 起按天记，去重完成词数） |
/// | 今日拼写题数 / 正确率 | `spelling_round`（v0.13.0 起，一轮一行） |
/// | 累计学习天数 | `daily_stat` 的 DISTINCT day |
/// | 连续打卡天数 | `daily_stat`（[StudyDao.streakFrom]，与首页同一个算法） |
/// | 累计学过词数 | `study_record`（`started = 1`） |
/// | 已掌握词数 | `study_record`（[Mastery.sqlWhere]：box ≥5 或 streak ≥3，且未斩） |
/// | 箱 0–6 分布 | `study_record` + 学习池（[StudyDao.bandCountsFrom]） |
/// | 已斩词数 | `study_record.killed = 1`（只算学习池里的词） |
/// | 趋势 | `daily_stat`（按天分组，只列有记录的天） |
/// | 拼写累计 / 最近 7 天 | `spelling_round` |
///
/// 没有任何一列是算出来的估算值：查不到就是 0 或 null，页面按 null 显示
/// 「暂无数据」，不补数、不画假曲线。
class StatsSnapshot {
  const StatsSnapshot({
    required this.todayKey,
    required this.totals,
    required this.totalDays,
    required this.streak,
    required this.learnedWords,
    required this.mastered,
    required this.boxes,
    required this.killed,
    required this.poolTotal,
    required this.todaySpellTotal,
    required this.todaySpellCorrect,
    required this.spellAllTotal,
    required this.spellAllCorrect,
    required this.spell7Total,
    required this.spell7Correct,
  });

  /// 今天（`yyyy-MM-dd`）。趋势图的右端锚点，测试可注入。
  final String todayKey;

  /// 最近 30 天的按天完成量。7 天档直接用它的尾部。
  final Map<String, DayTotal> totals;

  /// 有学习记录的自然日数（`daily_stat` 的 DISTINCT day）。
  final int totalDays;

  /// 连续打卡天数（今天还没学就从昨天往回数，与首页一致）。
  final int streak;

  /// 已进入学习流程的词数（`study_record.started = 1`，含已斩）。
  final int learnedWords;

  /// 已掌握词数（[Mastery.sqlWhere]）。
  final int mastered;

  /// 箱 0–6 各多少词（**未斩**）。索引即箱位，长度 7。
  final List<int> boxes;

  /// 已斩词数（只算学习池里的词）。
  final int killed;

  /// 学习池词数 = 820 + 自加词（去重）。
  final int poolTotal;

  final int todaySpellTotal;
  final int todaySpellCorrect;
  final int spellAllTotal;
  final int spellAllCorrect;
  final int spell7Total;
  final int spell7Correct;

  /// 七段之和。验收口径：`boxSum + killed == poolTotal`。
  int get boxSum => boxes.fold(0, (a, b) => a + b);

  /// 一条学习记录都没有过。趋势图在这时写「从今天起开始记录」。
  bool get noHistory => totalDays <= 0 && learnedWords <= 0;

  DayTotal totalOn(String day) =>
      totals[day] ?? const DayTotal(newWords: 0, reviews: 0);

  /// 今天的两个数（新学 / 复习）。
  DayTotal get today => totalOn(todayKey);

  int? get todaySpellPercent =>
      SpellingStats.percentOf(todaySpellCorrect, todaySpellTotal);

  int? get spellAllPercent =>
      SpellingStats.percentOf(spellAllCorrect, spellAllTotal);

  int? get spell7Percent =>
      SpellingStats.percentOf(spell7Correct, spell7Total);

  /// 最近 [days] 天，从早到晚，一天一格。没记录的天 `total == null`。
  List<DaySlot> slots(int days) {
    final anchor = DateTime.tryParse(todayKey) ?? DateTime.now();
    final out = <DaySlot>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = DateTime(anchor.year, anchor.month, anchor.day - i);
      final key = StudyDao.dayKey(d);
      out.add(DaySlot(day: key, total: totals[key]));
    }
    return out;
  }

  /// 最近 [days] 天里单日最大完成量。柱子高度按它归一。
  ///
  /// 全是空天时返回 0，调用方不要再除 —— 除 0 会得到 NaN，柱子高度变 null，
  /// 320 宽的真实渲染里会直接报错。
  int maxOf(int days) {
    var max = 0;
    for (final slot in slots(days)) {
      final t = slot.total?.total ?? 0;
      if (t > max) max = t;
    }
    return max;
  }

  /// 最近 [days] 天里有记录的天数。
  int activeDays(int days) =>
      slots(days).where((slot) => slot.hasData).length;
}
