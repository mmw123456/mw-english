import '../../app/app_defaults.dart';

/// 一条学习记录的调度状态。纯数据，不碰数据库。
class LeitnerState {
  const LeitnerState({
    this.box = 0,
    this.streak = 0,
    this.peakBox = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.retest = false,
  });

  /// 箱位 0 = 还没学会，1–6 = 六个复习箱。
  final int box;

  /// 连续答对次数。答错清零。
  final int streak;

  /// 历史最高箱位。用来判断「这个箱位 3 以上的词」不能再用新手门槛压着。
  final int peakBox;

  final int correctCount;
  final int wrongCount;

  /// 今日重测标记：这个词今天要再考一次，考过才回到正常间隔。
  final bool retest;

  int get attempts => correctCount + wrongCount;
}

/// 一次作答之后的新状态。
class LeitnerOutcome {
  const LeitnerOutcome({
    required this.box,
    required this.streak,
    required this.peakBox,
    required this.correctCount,
    required this.wrongCount,
    required this.retest,
    required this.dueInDays,
    required this.demoted,
    required this.promoted,
  });

  final int box;
  final int streak;
  final int peakBox;
  final int correctCount;
  final int wrongCount;
  final bool retest;

  /// 下次到期还有几天。0 表示今天内还要再考一次。
  final int dueInDays;

  final bool demoted;
  final bool promoted;
}

/// Leitner 六箱的全部规则，集中在这里，方便单测。
///
/// 规则（2026-11-25 锁定）：
/// - 箱位 0 = 新词，1–6 间隔 1 / 2 / 4 / 7 / 15 / 30 天
/// - 答对升一箱，答错降一箱，不归零
/// - 熟词保护：历史最高到过 4 箱的词，答错最低落到 3 箱
/// - 新词（历史最高箱位 < 3）连续答对 3 次才进 3 箱以上
/// - 当天答错的词当天重测，过关才算回到箱里（过关只回箱，不额外升箱）
/// - 当天新学的词当天再出一次（收尾复习），同样只回箱不升箱
class Leitner {
  const Leitner._();

  static int get topBox => AppDefaults.boxIntervals.length - 1;

  /// 作答后的新状态。[isFirstAnswer] 表示这个词还没学过（库里没有可用记录）。
  static LeitnerOutcome apply(
    LeitnerState s, {
    required bool correct,
    bool isFirstAnswer = false,
  }) {
    var box = s.box;
    var streak = s.streak;
    var peak = s.peakBox;
    var cc = s.correctCount;
    var wc = s.wrongCount;
    var retest = s.retest;
    var promoted = false;
    var demoted = false;

    // 首次作答时，旧状态其实是「只有星标、没学过」的空壳，box 归零重算。
    if (isFirstAnswer) {
      box = 0;
      streak = 0;
      peak = 0;
      retest = false;
    }

    if (correct) {
      cc++;
      streak++;
      if (retest) {
        // 当日重测过关：只把它放回箱里，不额外升箱。
        if (box == 0) {
          box = 1;
          promoted = true;
        }
        retest = false;
      } else {
        final wasNew = box == 0;
        var next = box + 1;
        if (next > topBox) next = topBox;
        // 新手门槛：还没到过 3 箱、且连续答对不满 3 次，最多停在 2 箱。
        if (peak < AppDefaults.protectedFloorBox &&
            streak < AppDefaults.newWordStreakToPromote &&
            next > AppDefaults.protectedFloorBox - 1) {
          next = AppDefaults.protectedFloorBox - 1;
        }
        if (next < 1) next = 1;
        promoted = next > box;
        box = next;
        if (box > peak) peak = box;
        // 当天新学的词（从 0 箱升到 1 箱）当天收尾复习一次。
        retest = wasNew;
      }
    } else {
      wc++;
      streak = 0;
      final next = demote(box, peak: peak);
      demoted = next < box;
      box = next;
      retest = true;
    }

    final dueInDays = retest ? 0 : AppDefaults.boxIntervals[box];

    return LeitnerOutcome(
      box: box,
      streak: streak,
      peakBox: peak,
      correctCount: cc,
      wrongCount: wc,
      retest: retest,
      dueInDays: dueInDays,
      demoted: demoted,
      promoted: promoted,
    );
  }

  /// 答错降一箱。
  ///
  /// 熟词保护按「历史最高箱位」算：到过 4 箱以上的词，答错最多落到 3 箱，
  /// 之后继续答错也停在 3 箱，不会被一次手滑打回低箱重学。
  static int demote(int box, {int peak = 0}) {
    final floor = peak >= AppDefaults.protectedBox
        ? AppDefaults.protectedFloorBox
        : 0;
    final next = box - 1;
    return next < floor ? floor : next;
  }

  /// 今天该学多少新词、最多复习多少。
  ///
  /// - 断档 ≥ 7 天：按断档天数摊薄新词配额，最少 3 个
  /// - 断档 ≥ 3 天：新词减半
  /// - 断档不足 3 天：按默认值
  static DailyQuota quota({
    DateTime? lastStudyAt,
    DateTime? now,
    int base = AppDefaults.dailyNewWordTarget,
    int reviewCap = AppDefaults.dailyReviewCap,
  }) {
    final n = now ?? DateTime.now();
    if (lastStudyAt == null) {
      return DailyQuota(newWords: base, reviewCap: reviewCap, gapDays: 0);
    }
    final gap = _dayDiff(lastStudyAt, n);
    if (gap >= AppDefaults.lapseSpreadQuotaDays) {
      final spread = (base / gap).floor();
      return DailyQuota(
        newWords: spread.clamp(3, base),
        reviewCap: reviewCap,
        gapDays: gap,
        reduced: true,
      );
    }
    if (gap >= AppDefaults.lapseHalfQuotaDays) {
      return DailyQuota(
        newWords: (base / 2).ceil(),
        reviewCap: reviewCap,
        gapDays: gap,
        reduced: true,
      );
    }
    return DailyQuota(newWords: base, reviewCap: reviewCap, gapDays: gap);
  }

  /// 两个时间相差几个自然日（按日历天算，不按 24 小时）。
  static int _dayDiff(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}

/// 今天的学习配额。
class DailyQuota {
  const DailyQuota({
    required this.newWords,
    required this.reviewCap,
    required this.gapDays,
    this.reduced = false,
  });

  final int newWords;
  final int reviewCap;

  /// 距上次学习隔了几个自然日。0 = 今天已经学过或第一次用。
  final int gapDays;

  /// 是否因为断档被削减过。
  final bool reduced;

  /// 断档时复习优先：会话把复习排在新词前面。
  bool get reviewsFirst => gapDays >= AppDefaults.lapseHalfQuotaDays;
}
