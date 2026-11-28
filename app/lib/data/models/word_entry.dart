/// 我的词表条目（来自 820 词单词本）。
///
/// 释义分两段：`meaningPdf` 是单词本 PDF 原文，`meaningEcdict` 是从 ECDICT
/// 词典补全的完整释义。`pdfTruncated` 为 true 表示 PDF 那段的原始释义被
/// 「…」截断过，界面上要标出来，避免用户以为词义就这么多。
class WordEntry {
  const WordEntry({
    required this.no,
    required this.word,
    required this.wordKey,
    required this.phonetic,
    required this.meaningPdf,
    required this.pdfTruncated,
    required this.meaningEcdict,
    required this.pos,
    required this.tag,
    required this.collins,
  });

  /// 单词本里的序号，1–820。
  final int no;

  /// 原始写法（保留大小写与词组形式）。
  final String word;

  /// 小写形式，与词典、学习记录关联用。
  final String wordKey;

  final String phonetic;

  /// 单词本原文释义。
  final String meaningPdf;

  /// PDF 释义是否被截断。
  final bool pdfTruncated;

  /// ECDICT 补全释义。为空表示词典里也没有这个词条。
  final String meaningEcdict;

  final String pos;
  final String tag;
  final int collins;

  factory WordEntry.fromRow(Map<String, Object?> row) {
    return WordEntry(
      no: row['no'] as int,
      word: row['word'] as String,
      wordKey: row['word_key'] as String,
      phonetic: (row['phonetic'] as String?) ?? '',
      meaningPdf: (row['meaning_pdf'] as String?) ?? '',
      pdfTruncated: (row['pdf_truncated'] as int? ?? 0) == 1,
      meaningEcdict: (row['meaning_ecdict'] as String?) ?? '',
      pos: (row['pos'] as String?) ?? '',
      tag: (row['tag'] as String?) ?? '',
      collins: (row['collins'] as int?) ?? 0,
    );
  }
}

/// 离线词典条目（ECDICT 裁剪档，43,350 词）。
class DictEntry {
  const DictEntry({
    required this.word,
    required this.phonetic,
    required this.translation,
    required this.pos,
    required this.tag,
    required this.collins,
    required this.frq,
  });

  final String word;
  final String phonetic;

  /// 释义，多个义项用换行分隔。
  final String translation;

  final String pos;

  /// 考试标签，如 `cet4 cet6 ky`。
  final String tag;

  /// 柯林斯星级 0–5。
  final int collins;

  /// 词频排名，越小越常用；0 表示无词频数据。
  final int frq;

  factory DictEntry.fromRow(Map<String, Object?> row) {
    return DictEntry(
      word: row['word'] as String,
      phonetic: (row['phonetic'] as String?) ?? '',
      translation: (row['translation'] as String?) ?? '',
      pos: (row['pos'] as String?) ?? '',
      tag: (row['tag'] as String?) ?? '',
      collins: (row['collins'] as int?) ?? 0,
      frq: (row['frq'] as int?) ?? 0,
    );
  }

  /// 释义拆成义项列表，界面逐行展示。
  List<String> get senses =>
      translation.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}
