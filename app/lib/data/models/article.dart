import 'dart:convert';

/// 文章里的一个目标词（详情页单词表的一行）。
///
/// `pos` 是词性（`v.` / `adj.`），`meaning` 是中文释义。两者都来自生成结果，
/// 不从词典反查 —— 词书里同一个词常有多个义项，文章用的是哪一个，只有生成时知道。
class ArticleWord {
  const ArticleWord({
    required this.word,
    required this.pos,
    required this.meaning,
  });

  /// 原形，小写。正文里可能出现变形（`abandoned`），加粗标记记的是原形。
  final String word;
  final String pos;
  final String meaning;

  Map<String, dynamic> toJson() => {'w': word, 'pos': pos, 'zh': meaning};

  static ArticleWord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final w = (raw['w'] ?? '').toString().trim();
    if (w.isEmpty) return null;
    return ArticleWord(
      word: w.toLowerCase(),
      pos: (raw['pos'] ?? '').toString().trim(),
      meaning: (raw['zh'] ?? '').toString().trim(),
    );
  }

  static List<ArticleWord> decodeList(String json) {
    final out = <ArticleWord>[];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        for (final item in decoded) {
          final w = ArticleWord.fromJson(item);
          if (w != null) out.add(w);
        }
      }
    } catch (_) {
      // 坏 JSON 就当没有单词表：正文还能读，只是下面少一块。
    }
    return out;
  }

  static String encodeList(List<ArticleWord> words) =>
      jsonEncode(words.map((w) => w.toJson()).toList());
}

/// 一篇已生成的文章。
class Article {
  const Article({
    required this.id,
    required this.title,
    required this.body,
    required this.targetWords,
    required this.wordCount,
    required this.rareRatio,
    required this.model,
    required this.createdAt,
    this.readAt,
  });

  final int id;
  final String title;

  /// 正文原文，目标词仍是 `**word**` 标记。
  final String body;

  final List<ArticleWord> targetWords;

  /// 正文词数（生成时算好存下）。
  final int wordCount;

  /// 生词率，0.031 表示 3.1%。分母是全文词次，分子是「除目标词外 frq > 5000 的词次」。
  final double rareRatio;

  final String model;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  /// 列表上显示的百分数，四舍五入到整数位。
  int get rarePercent => (rareRatio * 100).round();

  Article copyWith({DateTime? readAt}) => Article(
    id: id,
    title: title,
    body: body,
    targetWords: targetWords,
    wordCount: wordCount,
    rareRatio: rareRatio,
    model: model,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
  );
}
