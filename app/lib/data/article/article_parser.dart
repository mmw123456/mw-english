import '../models/article.dart';

/// 模型返回的原文解析不了。
///
/// 这一层只做「格式」判定，不管内容对不对（25 词、篇幅那些在 article_check 里）。
/// 抛出来的话术是给人看的，会直接显示在阅读页的错误条上。
class ArticleFormatException implements Exception {
  const ArticleFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析结果：标题 + 正文（保留 `**` 标记）+ 单词表。
class RawArticle {
  const RawArticle({
    required this.title,
    required this.body,
    required this.words,
  });

  final String title;
  final String body;
  final List<ArticleWord> words;

  bool get isEmpty => body.trim().isEmpty;
}

/// 期望模型返回的三段格式：
///
/// ```
/// TITLE: A Lesson in Patience
/// ---
/// On Monday she decided to **abandon** the plan.
/// ---
/// abandon|v.|放弃
/// deliberate|adj.|故意的
/// ```
///
/// 解析故意写得宽松：分隔线认 `---` / `===` / `***`，单词表分隔符认 `|` / `｜` /
/// Tab / ` - `，还认带表头（`word|pos|meaning`）与代码围栏。理由是本地实测过的
/// 经验 —— 模型对大结构的遵从度很高，对「用哪个符号」的遵从度一般，卡死在符号上
/// 只会白白浪费一次调用（按量付费）。
///
/// 真正不放宽的是：正文里必须有 `**` 加粗，单词表必须能读出至少一行。
/// 这两条不满足就抛 [ArticleFormatException]，让上层重试。
RawArticle parseArticleResponse(String raw) {
  final text = _stripFence(raw);
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  // 1) 标题：第一处 `TITLE:` / `Title:` / `标题:`。
  var title = '';
  var titleLine = -1;
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^\s*(?:TITLE|Title|title|标题)\s*[:：]\s*(.+?)\s*$')
        .firstMatch(lines[i]);
    if (m != null) {
      title = m.group(1)!.trim();
      titleLine = i;
      break;
    }
  }

  // 2) 单词表：从尾部往上扫连续能解析成 `词|词性|释义` 的行。
  final wordStart = _wordsStart(lines);
  final words = <ArticleWord>[];
  if (wordStart >= 0) {
    for (var i = wordStart; i < lines.length; i++) {
      if (_isWordHeader(lines[i])) continue;
      final w = _parseWordLine(lines[i]);
      if (w != null) words.add(w);
    }
  }

  // 3) 正文：标题行之后、单词表之前的行，去掉纯分隔线。
  final from = titleLine + 1;
  final to = wordStart < 0 ? lines.length : wordStart;
  final bodyLines = <String>[];
  for (var i = from; i < to; i++) {
    final line = lines[i];
    if (_isSeparator(line)) continue;
    bodyLines.add(line);
  }
  var body = bodyLines.join('\n').trim();

  // 正文里可能残留尾部空格，逐行 rtrim 一下，渲染时不会出现莫名的行尾空。
  body = body
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');

  if (body.isEmpty) {
    throw const ArticleFormatException('模型返回的正文是空的。');
  }
  if (!body.contains('**')) {
    throw const ArticleFormatException('正文里没有任何加粗标记（**word**），看不出哪些是目标词。');
  }
  if (words.isEmpty) {
    throw const ArticleFormatException('模型返回的末尾没有单词表（word|词性|释义）。');
  }

  // 标题缺失就退一步用正文首句开头几个词，比整篇扔掉强。
  if (title.isEmpty) title = _fallbackTitle(body);

  return RawArticle(title: title, body: body, words: words);
}

/// 去掉模型爱加的 ``` 围栏（带不带语言标记都认）。
String _stripFence(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final kept = <String>[];
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('```')) continue;
    kept.add(line);
  }
  return kept.join('\n');
}

/// 单词表第一行的下标；找不到返回 -1。
///
/// 优先策略：从尾部往上找**最近的纯分隔线**（`---`），它后面整块就是单词表。
/// 这样即使表中间夹着解析不了的行（模型偶尔漏一个字段），也不会把前半张表
/// 当成正文丢掉。
///
/// 退路：全文没有分隔线时，从尾部往上扫「连续能解析成词条」的行。
int _wordsStart(List<String> lines) {
  var end = lines.length - 1;
  while (end >= 0 && lines[end].trim().isEmpty) {
    end--;
  }
  if (end < 0) return -1;

  var sepAt = -1;
  for (var i = end; i >= 0; i--) {
    if (_isSeparator(lines[i])) {
      sepAt = i;
      break;
    }
  }
  if (sepAt >= 0 && sepAt < end) {
    var start = sepAt + 1;
    while (start <= end && lines[start].trim().isEmpty) {
      start++;
    }
    if (_countWordLines(lines, start, end) > 0) return start;
  }

  var start = end;
  var probe = end;
  while (probe >= 0) {
    final line = lines[probe];
    if (line.trim().isEmpty) break;
    if (_parseWordLine(line) == null && !_isWordHeader(line)) break;
    start = probe;
    probe--;
  }

  if (_countWordLines(lines, start, end) == 0) return -1;
  if (_countWordLines(lines, start, end) == 1 && end - start == 0) {
    // 只有一行：只在它前面紧挨着分隔线时才认（说明模型确实切了段）。
    if (start == 0 || !_isSeparator(lines[start - 1])) return -1;
  }
  return start;
}

int _countWordLines(List<String> lines, int from, int to) {
  var n = 0;
  for (var i = from; i <= to && i < lines.length; i++) {
    if (lines[i].trim().isEmpty || _isWordHeader(lines[i])) continue;
    if (_parseWordLine(lines[i]) != null) n++;
  }
  return n;
}

/// 是不是表头（`word|pos|meaning`）。
///
/// 判定看**第二格**，不看第一格 —— 第一格经常就是单词 `word` 本身
/// （`word|n.|词` 是词条不是表头），只看第一格会把真词条当表头丢掉。
bool _isWordHeader(String line) {
  final t = line.trim().toLowerCase();
  RegExp sep;
  if (t.contains('|')) {
    sep = RegExp(r'\|');
  } else if (t.contains('｜')) {
    sep = RegExp(r'｜');
  } else if (t.contains('\t')) {
    sep = RegExp(r'\t+');
  } else {
    return false;
  }

  final parts = t.split(sep).map((e) => e.trim()).toList();
  if (parts.length < 2) return false;
  const headers = {'pos', '词性', 'part of speech', 'meaning', '释义', '中文'};
  return headers.contains(parts[1]);
}

/// 一行词条：`abandon|v.|放弃` / `abandon\tv.\t放弃` / `abandon - 放弃`。
///
/// 前缀的编号（`1.` / `- `）也剥掉，模型偶尔会带着列表符号输出。
ArticleWord? _parseWordLine(String line) {
  var t = line.trim();
  if (t.isEmpty) return null;
  if (_isSeparator(t)) return null;

  t = t.replaceFirst(RegExp(r'^(?:\d+[.、)]|[-*•])\s*'), '').trim();
  if (t.isEmpty) return null;

  // 主路：竖线 / 全角竖线 / Tab 分三格。
  for (final sep in <RegExp>[
    RegExp(r'\s*[|｜]\s*'),
    RegExp(r'\t+'),
  ]) {
    final parts = t.split(sep);
    if (parts.length >= 2) {
      final word = _cleanWord(parts[0]);
      if (word == null) return null;
      final pos = parts.length >= 3 ? parts[1].trim() : '';
      final meaning = parts.length >= 3
          ? parts.sublist(2).join(' ').trim()
          : parts.sublist(1).join(' ').trim();
      if (meaning.isEmpty && pos.isEmpty) return null;
      return ArticleWord(word: word, pos: pos, meaning: meaning);
    }
  }

  // 退路：`word - 释义`（模型偶尔把分隔符换成破折号）。
  final dash = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(t);
  if (dash != null) {
    final word = _cleanWord(dash.group(1)!);
    if (word != null) {
      return ArticleWord(word: word, pos: '', meaning: dash.group(2)!.trim());
    }
  }

  return null;
}

/// 词形校验：只留字母 / 撇号 / 连字符 / 空格 / 圆括号，长度 1–60，最多 6 个词。
String? _cleanWord(String raw) {
  var w = raw.trim().toLowerCase();
  w = w.replaceAll(RegExp(r'[*_`]'), '').trim();
  w = w.replaceAll(RegExp(r'\s+'), ' ');
  if (w.isEmpty || w.length > 60) return null;
  if (!RegExp(r"^[a-z][a-z\s'\-()]*$").hasMatch(w)) return null;
  if (w.split(' ').length > 6) return null;

  var depth = 0;
  for (final ch in w.split('')) {
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth < 0) return null;
  }
  if (depth != 0) return null;

  return w;
}

bool _isSeparator(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  return RegExp(r'^[-=*_~·—]{2,}$').hasMatch(t);
}

/// 没有标题时，用正文第一句的前 6 个词。
String _fallbackTitle(String body) {
  final plain = body.replaceAll('**', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  final firstSentence = plain.split(RegExp(r'[.!?。！？]')).first.trim();
  final words = firstSentence.split(' ');
  final head = words.take(6).join(' ');
  final title = head.isEmpty ? 'Untitled' : head;
  return title.length > 48 ? '${title.substring(0, 48)}…' : title;
}
