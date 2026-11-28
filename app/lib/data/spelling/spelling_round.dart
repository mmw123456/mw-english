/// 听音拼写（v0.13.0）：题目模型 + 判定规矩 + 一轮怎么组。
///
/// 这一层是**纯函数与纯数据**，不碰数据库、不碰六箱、不碰每日进度。
/// 拼写只读今天的词表，结果只写它自己那张 `spelling_round` 表。
library;

/// 一道听音拼写题。
class SpellingItem {
  const SpellingItem({
    required this.wordKey,
    required this.word,
    this.phonetic = '',
    this.meaning = '',
  });

  /// 库里的 key（小写、空格归一），去重与跳详情页都用它。
  final String wordKey;

  /// 正确拼写。短语是整串（`take advantage of`），词书里的括号注释原样保留
  /// （`once (and) for all`）—— 判定时可省，见 [SpellingJudge]。
  final String word;

  /// 音标。820 里没有音标字段的词留空，不编。
  final String phonetic;

  /// 中文释义（取第一行）。
  final String meaning;

  /// 读给耳朵听的那串：`once (and) for all` → `once and for all`。
  ///
  /// 直接念带括号的原文，Android TTS 会把括号一起念出来（或者干脆停一下），
  /// 听音拼写就没有「听」的意义了。
  String get spoken => SpellingJudge.spokenForm(word);
}

/// 一次作答。
class SpellingAttempt {
  const SpellingAttempt({
    required this.item,
    required this.input,
    required this.correct,
  });

  final SpellingItem item;

  /// 用户输入的原话（只去首尾空白）。判错时要原样回显「你拼的是 xxx」。
  final String input;

  final bool correct;
}

/// 一轮拼写的成绩（小结与累计正确率共用一套口径）。
class SpellingStats {
  const SpellingStats({
    required this.rounds,
    required this.total,
    required this.correct,
  });

  /// 拼过几轮。
  final int rounds;

  /// 一共几题。
  final int total;

  /// 对了几题。
  final int correct;

  static const SpellingStats empty =
      SpellingStats(rounds: 0, total: 0, correct: 0);

  bool get isEmpty => total <= 0;

  /// 正确率百分比（四舍五入到整数）。一题都没拼时返回 null —— 界面上是
  /// 「还没有拼写记录」，不是「0%」（0% 会被读成「全错」）。
  int? get accuracyPercent => percentOf(correct, total);

  static int? percentOf(int correct, int total) {
    if (total <= 0) return null;
    return (correct * 100 / total).round();
  }
}

/// 一轮拼写从哪来、截多长。
class SpellingRound {
  const SpellingRound._();

  /// 组一轮：今天已学的新词 → 今天还没学的新词 → 今天到期的复习词。
  ///
  /// 顺序是有意的 —— 新词是今天最需要巩固的，先拼；复习词只在还有余额时补上。
  /// 三批都来自学习会话同一套词表（820 + 自加词），[cap] 就是今天的每日目标，
  /// 所以一轮最多 30 题（目标调小则跟着变小）。
  ///
  /// 同一个词可能同时出现在两批里（比如今天学的词当天就到期重测），按
  /// `wordKey` 去重，先出现的赢。
  static List<SpellingItem> compose({
    required List<SpellingItem> learnedToday,
    required List<SpellingItem> queued,
    required List<SpellingItem> due,
    required int cap,
  }) {
    if (cap <= 0) return const [];
    final out = <SpellingItem>[];
    final seen = <String>{};
    for (final batch in [learnedToday, queued, due]) {
      for (final item in batch) {
        if (out.length >= cap) return out;
        final key = item.wordKey.trim().toLowerCase();
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(item);
      }
    }
    return out;
  }
}

/// 判定规矩（写死，不改）。
///
/// - 大小写不敏感；
/// - 首尾空白不算，中间连续空白算一个（短语整串拼，不拆词）；
/// - 词书里的括号注释可有可无：`once (and) for all` / `once and for all` /
///   `once for all` 三种写法都算对，其余短语按整串判。
abstract final class SpellingJudge {
  /// 归一化：去首尾空白、内部连续空白压成一个、转小写。
  ///
  /// 只压空白与大小写，**不拆词、不去括号** —— 括号是词条本身的一部分。
  static String normalize(String raw) =>
      raw.trim().replaceAll(_spaces, ' ').toLowerCase();

  /// 念出来的写法：括号去掉、里面的词保留（`once (and) for all` → `once and for all`）。
  static String spokenForm(String answer) =>
      normalize(answer).replaceAll('(', ' ').replaceAll(')', ' ').replaceAll(_spaces, ' ').trim();

  /// 全部算对的写法（都已归一化）。
  ///
  /// 没有括号的词条只有一种；带括号的多两种：保留括号里的内容、整段去掉。
  static List<String> acceptedForms(String answer) {
    final base = normalize(answer);
    if (base.isEmpty) return const [];
    final forms = <String>{base};
    if (base.contains('(')) {
      // `once and for all`：括号当分隔符
      forms.add(_squeeze(base.replaceAll(_openParen, ' ').replaceAll(_closeParen, ' ')));
      // `once for all`：整段括号注释去掉
      forms.add(_squeeze(base.replaceAll(_parenthetical, ' ')));
    }
    return forms.where((f) => f.isNotEmpty).toList();
  }

  /// 拼对没有。空输入一律算错。
  static bool isCorrect(String input, String answer) {
    final given = normalize(input);
    if (given.isEmpty) return false;
    return acceptedForms(answer).contains(given);
  }

  static String _squeeze(String text) =>
      text.replaceAll(_spaces, ' ').trim();

  static final RegExp _spaces = RegExp(r'\s+');
  static const String _openParen = '(';
  static const String _closeParen = ')';
  static final RegExp _parenthetical = RegExp(r'\([^)]*\)');
}
