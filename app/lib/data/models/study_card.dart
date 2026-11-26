import '../study/leitner.dart';

/// 会话里的一张卡。
///
/// v0.6.0 起只有一种形态：上面单词 + 音标 + 发音，下面四个中文意思。
/// 新词、复习、当日重测都用同一套，不再分题型。
class StudyCard {
  const StudyCard({
    required this.wordKey,
    required this.word,
    required this.phonetic,
    required this.meaning,
    required this.meaningEcdict,
    required this.box,
    required this.isNew,
    required this.isRetest,
    required this.options,
    required this.answerIndex,
  });

  final String wordKey;
  final String word;
  final String phonetic;

  /// 正确选项文本（中文释义，取首句）。
  final String meaning;

  /// 词典补全释义。卡片上不显示，只给详情页兜底。
  final String meaningEcdict;

  final int box;

  /// 第一次学这个词。
  final bool isNew;

  /// 今日重测（答错后当天再考，或新词当天收尾复习）。
  final bool isRetest;

  /// 四个选项，顺序已打乱。
  final List<String> options;

  /// 正确选项下标。
  final int answerIndex;
}

/// 一次学习会话。
class StudySession {
  const StudySession({
    required this.cards,
    required this.quota,
    required this.newCount,
    required this.reviewCount,
    required this.retestCount,
    required this.learnedToday,
  });

  final List<StudyCard> cards;
  final DailyQuota quota;

  /// 本次会话里的新词数。
  final int newCount;

  /// 本次会话里的到期复习数。
  final int reviewCount;

  /// 其中属于今日重测的数。
  final int retestCount;

  /// 今天已经学过多少新词（含本次之外）。
  final int learnedToday;

  bool get isEmpty => cards.isEmpty;
}

/// 一次作答的结果。
class AnswerResult {
  const AnswerResult({
    required this.box,
    required this.dueInDays,
    required this.retest,
    required this.promoted,
    required this.demoted,
  });

  final int box;
  final int dueInDays;
  final bool retest;
  final bool promoted;
  final bool demoted;
}
