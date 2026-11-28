/// 文章度量：词数、加粗词、生词率。
///
/// 全是纯函数 —— 不查库、不联网，好让「生成 → 校验」这条链在 `flutter test`
/// 里跑到底。词难不难由调用方注入（[isRareWord]），生产里查内置词典的 `frq`，
/// 测试里塞一个固定集合。
library;

/// 一次度量的结果。
class ArticleMetrics {
  const ArticleMetrics({
    required this.wordCount,
    required this.rareCount,
    required this.boldWords,
  });

  /// 正文词次（含目标词）。按空格/标点切，纯标点不算词。
  final int wordCount;

  /// 除目标词外、被判为生词的词次。
  final int rareCount;

  /// 正文里 `**xxx**` 标出来的词，按出现顺序，已小写。
  final List<String> boldWords;

  /// 生词率 = 生词词次 / 全文词次。0.031 表示 3.1%。
  double get rareRatio => wordCount == 0 ? 0 : rareCount / wordCount;

  /// 列表上显示的百分数。
  int get rarePercent => (rareRatio * 100).round();
}

/// 判断一个词（小写、原形）算不算「生词」。
///
/// 生产实现查 `words.frq`：排名 > 5000 或查不到 / 排名为 0 的算生词。
/// 依据是实测的词典数据 —— `the` 排 1、`abandon` 2182、`significant` 719，
/// 都 ≤5000；`algorithm` 8230、`photosynthesis` 17755，都 >5000。
typedef IsRareWord = bool Function(String lowerWord);

/// 把正文切成词。汉字与标点都当分隔符，只留含拉丁字母的 token。
final RegExp _tokenSplit = RegExp(r"[^A-Za-z'’\-]+");

/// 加粗标记。只认 `**`：提示词里写死了，别的形式模型不该用。
final RegExp _boldPattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);

/// 度量一篇正文。
///
/// [targetWords] 是这篇的 25 个目标词（小写）。它们**不计入生词率**：
/// 分子里剔掉，按「目标词拆成的单词集合」剔 —— `take advantage of` 这种短语
/// 会拆成 take / advantage / of 三个词，正文里它们出现几次都不算生词。
ArticleMetrics measureArticle({
  required String body,
  required Set<String> targetWords,
  required IsRareWord isRareWord,
}) {
  final bold = <String>[];
  for (final m in _boldPattern.allMatches(body)) {
    final w = _normalize(m.group(1) ?? '');
    if (w.isNotEmpty) bold.add(w);
  }

  // 统计词数时去掉 `**` 标记，否则 `**abandon**` 会被切出一个空 token
  // （`*` 是分隔符），数字不受影响，但读起来容易误会。
  final plain = body.replaceAll('**', ' ');

  // 目标词拆成单词集合：短语里的每个词都不算生词。
  final targetTokens = <String>{};
  for (final t in targetWords) {
    for (final piece in t.split(_tokenSplit)) {
      final p = _normalize(piece);
      if (p.isNotEmpty) targetTokens.add(p);
    }
  }

  var words = 0;
  var rare = 0;
  for (final piece in plain.split(_tokenSplit)) {
    final w = _normalize(piece);
    if (w.isEmpty) continue;
    words++;
    if (targetTokens.contains(w)) continue;
    if (isRareWord(w)) rare++;
  }

  return ArticleMetrics(wordCount: words, rareCount: rare, boldWords: bold);
}

/// 小写 + 去掉首尾的撇号/连字符（`'em` / `well-` 这种切出来会带边）。
final RegExp _hasLatin = RegExp('[a-z]');

String _normalize(String raw) {
  var s = raw.trim().toLowerCase();
  while (s.isNotEmpty && (s[0] == "'" || s[0] == '’' || s[0] == '-')) {
    s = s.substring(1);
  }
  while (s.isNotEmpty && (s.endsWith("'") || s.endsWith('’') || s.endsWith('-'))) {
    s = s.substring(0, s.length - 1);
  }
  if (!_hasLatin.hasMatch(s)) return '';
  return s;
}

/// 正文切成词（小写、去标点）。给「查词典判难度」与统计共用。
///
/// `**` 标记会先换成分隔符，所以 [tokenizeBody] 得到的词是干净的。
List<String> tokenizeBody(String body) {
  final plain = body.replaceAll('**', ' ');
  final out = <String>[];
  for (final piece in plain.split(_tokenSplit)) {
    final w = _normalize(piece);
    if (w.isNotEmpty) out.add(w);
  }
  return out;
}

/// 数一个词（或短语）在正文里出现了几次，大小写不敏感、按词边界。
///
/// 用「词边界」是为了让 `art` 不会命中 `article`。短语整体匹配，
/// 内部多个空格压成一个再比。
int countOccurrences(String body, String word) {
  final plain = body.replaceAll('**', ' ').replaceAll(RegExp(r'\s+'), ' ');
  final target = word.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (target.isEmpty) return 0;

  final escaped = RegExp.escape(target);
  final pattern = RegExp(
    '(?<![A-Za-z])$escaped(?![A-Za-z])',
    caseSensitive: false,
  );
  return pattern.allMatches(plain).length;
}
