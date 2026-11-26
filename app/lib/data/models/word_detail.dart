/// 词条详情页用的模型。
///
/// 一个词条可能来自三处，详情页要能同时说清「它在哪」：
/// - `my_words`：单词本 820 词
/// - `user_added_words`：用户自己从词典加进来的
/// - `words`：43,350 词的离线词典
class WordDetail {
  const WordDetail({
    required this.wordKey,
    required this.word,
    required this.phonetic,
    required this.meaningPdf,
    required this.pdfTruncated,
    required this.meaningEcdict,
    required this.pos,
    required this.tag,
    required this.collins,
    required this.no,
    required this.box,
    required this.isAdded,
    required this.starred,
    required this.forms,
    required this.synonyms,
    required this.nearWords,
  });

  /// 小写形式，所有表关联都靠它。
  final String wordKey;

  /// 原始写法（保留大小写与词组）。
  final String word;

  final String phonetic;

  /// 单词本原文释义。词典里的词没有这一段，为空。
  final String meaningPdf;

  /// PDF 释义被「…」截断过。
  final bool pdfTruncated;

  /// ECDICT 释义。为空表示词典也没收录。
  final String meaningEcdict;

  final String pos;
  final String tag;
  final int collins;

  /// 在单词本里的序号（1–820）。不在单词本里为 null。
  final int? no;

  /// 当前 Leitner 箱位（v0.7.7）：0 = 新词，1–6 = 已学。
  ///
  /// **只有 820 词表里的词才有箱位**；自加词和纯词典词不进调度，这里为 null，
  /// 详情页据此不显示箱位徽章 —— 给它们标「新词」会让人以为明天要考。
  final int? box;

  /// 在 user_added_words 里（自加）。
  final bool isAdded;

  final bool starred;

  /// 单词变形，解析自 `words.exchange`，解析不出内容就是空列表。
  final List<WordForm> forms;

  /// 近义词，只有 820 词有。词典里的其他词一律为空。
  final List<SynonymEntry> synonyms;

  /// 形近词，按编辑距离排序。
  final List<NearWord> nearWords;

  bool get inWorkbook => no != null;
  bool get inMyList => inWorkbook || isAdded;
}

/// 一条单词变形，如「过去式 · abandoned」。
class WordForm {
  const WordForm({required this.label, required this.value});

  final String label;
  final String value;
}

/// 一条近义词。
///
/// `distinction` 是 DeepSeek 生成的辨析，`gloss` 是词典释义首行，用来对照。
class SynonymEntry {
  const SynonymEntry({
    required this.word,
    required this.distinction,
    required this.gloss,
    required this.phonetic,
  });

  final String word;
  final String distinction;
  final String gloss;
  final String phonetic;
}

/// 一个形近词。
class NearWord {
  const NearWord({
    required this.word,
    required this.gloss,
    required this.distance,
  });

  final String word;
  final String gloss;

  /// 与当前词的编辑距离，1–3。
  final int distance;
}

/// 词根/词缀拆解结果。只由精确白名单产生，规则不参与。
class RootAnalysis {
  const RootAnalysis({required this.parts, required this.note});

  final List<Morpheme> parts;

  /// 一句话说明这个词为什么这么拆（词源）。
  final String note;
}

enum MorphemeKind { prefix, root, suffix }

/// 一个构词成分。
class Morpheme {
  const Morpheme(
    this.text,
    this.kind,
    this.meaning, {
    this.trailingDash = false,
    this.leadingDash = false,
  });

  /// 显示文本，如 `trans`。
  final String text;
  final MorphemeKind kind;

  /// 中文含义，如 `横过、转移`。
  final String meaning;

  /// 前缀末尾补连字符：`trans-`。
  final bool trailingDash;

  /// 后缀开头补连字符：`-ate`。
  final bool leadingDash;

  String get label =>
      '${leadingDash ? '-' : ''}$text${trailingDash ? '-' : ''}';

  String get kindLabel => switch (kind) {
        MorphemeKind.prefix => '前缀',
        MorphemeKind.root => '词根',
        MorphemeKind.suffix => '后缀',
      };

  /// 方便手写白名单的简写。
  static Morpheme p(String text, String meaning) =>
      Morpheme(text, MorphemeKind.prefix, meaning, trailingDash: true);

  static Morpheme r(String text, String meaning) =>
      Morpheme(text, MorphemeKind.root, meaning);

  static Morpheme s(String text, String meaning) =>
      Morpheme(text, MorphemeKind.suffix, meaning, leadingDash: true);
}
