import '../study/leitner.dart';

/// 三种题型。新词第一次见不进题型轮换，先用「认词卡」过一遍。
enum QuestionType {
  /// 给英文，选中文释义。
  enToCn('英 → 中'),

  /// 给中文释义，选英文单词。
  cnToEn('中 → 英'),

  /// 只给单词，先自己回忆，再自评想没想起来。
  recall('回忆');

  const QuestionType(this.label);

  final String label;

  String get code => name;
}

/// 会话里的一张卡。
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
    required this.type,
    required this.options,
    required this.answerIndex,
  });

  final String wordKey;
  final String word;
  final String phonetic;

  /// 中文释义（单词本原文，取首句）。
  final String meaning;

  /// 词典补全释义，答完才展示。
  final String meaningEcdict;

  final int box;

  /// 第一次学这个词 → 认词卡，不设选项。
  final bool isNew;

  /// 今日重测（答错后当天再考，或新词当天收尾复习）。
  final bool isRetest;

  final QuestionType type;

  /// 四选一的选项。认词卡与回忆卡为空。
  final List<String> options;

  /// 正确选项下标。没有选项时为 -1。
  final int answerIndex;

  bool get hasOptions => options.isNotEmpty;

  /// 卡面主文本：给英文的题型显示单词，给中文的题型显示释义。
  String get prompt => type == QuestionType.cnToEn ? meaning : word;

  /// 卡面副文本：音标只在给英文时显示。
  String get promptSub => type == QuestionType.cnToEn ? '' : phonetic;
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
