/// 把「一行一行的纯文本」解析成词条（v0.9.0 导入用）。
///
/// 这一层是纯函数：不碰文件、不碰数据库、不碰 pdfium。PDF / docx / txt 三种来源
/// 各自只负责把内容变成 `List<String>`，之后统统走 [parseWordLines]。
/// 这样「解析规则」可以在 `flutter test` 里全部覆盖到，不用等真机。
///
/// 支持的排版（需求原文）：
/// - 编号列表：`1. abandon`、`1、abandon`、`(1) abandon`、`- abandon`
/// - 一行一词：`abandon`
/// - 词 + 词性 + 中文释义：`abandon v. 放弃；抛弃`
/// - 逗号 / 分号分隔：`abandon, 放弃`
/// - Tab 分隔：`abandon\t放弃`
///
/// 原则：**宁可少解析、别乱导**。认不出的行不猜，记进 [ParseOutcome.unparsedLines]
/// 让用户在预览页里看到；短语整串保留，不按空格拆。
library;

/// 一条解析出来的词。
class ParsedWord {
  const ParsedWord({
    required this.word,
    required this.meaning,
    required this.rawLine,
    required this.meaningFromFile,
  });

  /// 归一化后的词形：小写、去首尾空格、多空格压成一个。
  ///
  /// 小写是刻意的 —— 内置词典 `words` 与 `my_words` 的键都是小写，
  /// 统一到小写才能命中去重与补释义（需求：大小写不敏感去重）。
  final String word;

  /// 文件里自带的释义；没有就是空串（后面再查 ECDICT 补，查不到标「未查到」）。
  final String meaning;

  /// 原始行，预览页出错时给用户看「是哪一行没解析对」。
  final String rawLine;

  /// [meaning] 是否来自文件（false = 需要查词典）。
  final bool meaningFromFile;
}

/// 解析结果。
class ParseOutcome {
  const ParseOutcome({
    required this.words,
    required this.duplicates,
    required this.unparsedLines,
    required this.skippedLines,
  });

  final List<ParsedWord> words;

  /// 文件内重复（大小写不同算同一个词）被合掉的条数。
  final int duplicates;

  /// 看起来像词条、但没通过校验的行。
  final List<String> unparsedLines;

  /// 明确忽略的行数：空行、表头、页码、标题这些。
  final int skippedLines;
}

// ---- 词性缩写：出现在这些 token 处就是「英文部分到此结束」 ----
const Set<String> _posTokens = {
  'n', 'v', 'vt', 'vi', 'adj', 'adv', 'prep', 'conj', 'pron', 'num',
  'art', 'int', 'aux', 'abbr', 'pl', 'phr',
};

final RegExp _leadingNumbering = RegExp(
  r'^\s*(?:[（(]\s*\d{1,4}\s*[)）]|\[\s*\d{1,4}\s*\]|\d{1,4}\s*[.、)．:：]|\d{1,4}\s+|[-–—•·*]\s+)\s*',
);

final RegExp _pageNumberLike = RegExp(
  r'^\s*(?:[-–—]\s*\d{1,4}\s*|\d{1,4}\s*/\s*\d{1,4}|第?\s*\d{1,4}\s*页)\s*$',
);

/// 表头 / 标题 / 日期这类行，出现就整行跳过（不计入「无法解析」）。
final List<RegExp> _headerLike = [
  RegExp(r'^\s*(?:no\.?|序号|编号)\s*$', caseSensitive: false),
  RegExp(r'word\s+meaning', caseSensitive: false),
  RegExp(r'^\s*(?:classic\s+)?vocabulary\s+list', caseSensitive: false),
  RegExp(r'^\s*(?:title|date)\s*[:：]', caseSensitive: false),
  RegExp(r'^\s*(?:单词本|词汇表|词表|收藏的单词)\s*$'),
];

final RegExp _cjk = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');
final RegExp _hasLatinLetter = RegExp(r'[A-Za-z]');

/// 词形允许的字符：字母、撇号、连字符、点（缩写）、斜杠、空格、圆括号。
/// 圆括号是为了 `once (and) for all` 这种整体短语。
final RegExp _allowedWordShape = RegExp(r"^[A-Za-z][A-Za-z'’\-./ ()]*$");

/// 解析词条行。
///
/// [lines] 是各来源拆好的行。跨行的续行（只有中文、没有英文的那一行）会接到
/// 上一条释义后面 —— 种子 PDF 里「…说下去； / adj. 迅速的」就是这种断行。
ParseOutcome parseWordLines(Iterable<String> lines) {
  final words = <ParsedWord>[];
  final seen = <String>{};
  final unparsed = <String>[];
  var duplicates = 0;
  var skipped = 0;

  ParsedWord? last; // 允许续行往上一条的释义追加

  for (final raw in lines) {
    final line = _normalize(raw);
    if (line.isEmpty) {
      skipped++;
      continue;
    }
    if (_pageNumberLike.hasMatch(line) || _headerLike.any((r) => r.hasMatch(line))) {
      skipped++;
      continue;
    }

    final body = line.replaceFirst(_leadingNumbering, '').trim();
    if (body.isEmpty) {
      skipped++;
      continue;
    }

    // 续行：整行没有拉丁字母（纯中文 / 标点），接到上一条释义后面。
    // 接不上（上一行不是词条）时：带中文的原样列进「没认出来」，纯标点才算跳过 ——
    // 标题行、页码行已经在上面筛掉了，这里剩下的多半是真没解出来的内容。
    if (!_hasLatinLetter.hasMatch(body)) {
      final prev = last;
      if (prev != null && _cjk.hasMatch(body)) {
        final merged = _joinMeaning(prev.meaning, body);
        final replaced = ParsedWord(
          word: prev.word,
          meaning: merged,
          rawLine: prev.rawLine,
          meaningFromFile: true,
        );
        words[words.length - 1] = replaced;
        last = replaced;
      } else if (_cjk.hasMatch(body)) {
        unparsed.add(line);
      } else {
        skipped++;
      }
      continue;
    }

    final split = _splitWordAndMeaning(body);
    final word = _normalizeWord(split.word);
    if (word == null) {
      // 这一行没有词，只有释义 —— 种子 PDF 里 `3 prompt` / `v. 导致，敦促…`
      // 就是这种断行：词单占一行，释义从下一行接着写。
      // 能接到上一条就接（宁可要残缺的释义，也别把 `v.` 当成一个词导进去），
      // 接不上（上一行不是词条）才算「没认出来」。
      final prev = last;
      // 只有「像释义」的行才往上接：带中文，或者整行是 `v. …` 这种纯词性开头。
      // 像 `abc123` 这种带数字的怪行不能接，得原样列进「没认出来」。
      final meaningOnly = split.word.isEmpty || _cjk.hasMatch(body);
      if (prev != null && meaningOnly) {
        final replaced = ParsedWord(
          word: prev.word,
          meaning: _joinMeaning(prev.meaning, body),
          rawLine: prev.rawLine,
          meaningFromFile: true,
        );
        words[words.length - 1] = replaced;
        last = replaced;
      } else {
        unparsed.add(line);
      }
      continue;
    }

    if (!seen.add(word)) {
      // 文件内重复：不新增，但如果原条没释义、这条有，就把释义补上。
      duplicates++;
      final idx = words.indexWhere((w) => w.word == word);
      if (idx >= 0 && words[idx].meaning.isEmpty && split.meaning.isNotEmpty) {
        final fixed = ParsedWord(
          word: word,
          meaning: split.meaning,
          rawLine: words[idx].rawLine,
          meaningFromFile: true,
        );
        words[idx] = fixed;
        last = fixed;
      }
      continue;
    }

    final entry = ParsedWord(
      word: word,
      meaning: split.meaning,
      rawLine: line,
      meaningFromFile: split.meaning.isNotEmpty,
    );
    words.add(entry);
    last = entry;
  }

  return ParseOutcome(
    words: words,
    duplicates: duplicates,
    unparsedLines: unparsed,
    skippedLines: skipped,
  );
}

class _Split {
  const _Split(this.word, this.meaning);
  final String word;
  final String meaning;
}

/// 把一行的「英文部分」与「释义部分」切开。
_Split _splitWordAndMeaning(String body) {
  // 1) Tab 分隔最明确，直接用。
  final tab = body.indexOf('\t');
  if (tab > 0) {
    return _Split(body.substring(0, tab).trim(), body.substring(tab + 1).trim());
  }

  // 2) 找第一个中文字符：它前面是英文（可能带词性），后面是释义。
  final cjkAt = body.indexOf(_cjk);
  if (cjkAt > 0) {
    // 去掉紧贴中文的词性缩写：`transmit v.` → `transmit`。
    // 词性本身留在释义里（`v. 传播；播送`），预览页与原词表长得一样。
    final head = _stripTrailingPos(body.substring(0, cjkAt).trim());
    final meaningAt = head.isEmpty ? cjkAt : body.indexOf(head) + head.length;
    final meaning = body.substring(meaningAt).trim();
    return _Split(head, meaning);
  }

  // 3) 没有中文：按词性缩写 token 切（`abandon v. give up` / `abandon n.`）。
  //    第 0 个 token 就是词性（`v. 放弃`）时，这一行没有词，先给空串，
  //    由调用方当成「释义续行」处理。
  final tokens = body.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  for (var i = 0; i < tokens.length; i++) {
    final bare = tokens[i].toLowerCase().replaceAll(RegExp(r'[.．]$'), '');
    if (!_posTokens.contains(bare) || !_isPosToken(tokens[i])) continue;
    if (i == 0) {
      // 只认带点的（`v.`），不认 `art` / `int` / `num` 这类本身也是词的缩写，
      // 否则一行一个词的词表里 `art`（艺术）会被当成词性吞掉。
      if (!tokens[0].endsWith('.') && !tokens[0].endsWith('．')) break;
      return _Split('', body);
    }
    final wordPart = tokens.sublist(0, i).join(' ');
    final rest = tokens.sublist(i).join(' ');
    return _Split(wordPart, rest);
  }

  // 4) 逗号 / 分号分隔：`abandon, give up`
  final sep = body.indexOf(RegExp(r'[,，;；]'));
  if (sep > 0) {
    return _Split(body.substring(0, sep).trim(), body.substring(sep + 1).trim());
  }

  // 5) 一行一词。
  return _Split(body, '');
}

/// 词性 token 必须长得像 `v.` / `adj.` / `n` 这种短标记，不能是单词。
bool _isPosToken(String token) {
  final t = token.toLowerCase().replaceAll(RegExp(r'[.．]$'), '');
  if (!_posTokens.contains(t)) return false;
  // 带点的（`v.`）直接认；不带点的要求 token 本身就是短小写（`n`），
  // 避免把正常单词当成词性（比如句子里的 `art`）。
  return token.endsWith('.') || token.endsWith('．') || t.length <= 3;
}

/// 去掉紧贴中文尾巴上的词性缩写：`transmit v.` → `transmit`。
///
/// 允许剥到空串（`adj. 恶劣的` 里的 `adj.`）—— 那种情况的正确归属是「上一行的
/// 释义续行」，不是「有个词叫 adj」。剥到空只认带点的 token：`art` / `int` /
/// `num` 不带点时可能就是词本身（艺术 / 整数 / 数字），不能吞。
String _stripTrailingPos(String head) {
  final tokens = head.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  while (tokens.isNotEmpty) {
    final lastToken = tokens.last;
    if (!_posTokens.contains(_barePos(lastToken)) || !_isPosToken(lastToken)) break;
    final dotted = lastToken.endsWith('.') || lastToken.endsWith('．');
    if (tokens.length == 1 && !dotted) break;
    tokens.removeLast();
  }
  return tokens.join(' ').trim();
}

String _barePos(String token) => token.toLowerCase().replaceAll(RegExp(r'[.．]$'), '');

String? _normalizeWord(String raw) {
  var w = raw
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  w = w.replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '').trim(); // 去掉残留的标点（不动数字）
  w = w.replaceAll(RegExp(r'[,;:，；：]$'), '').trim();
  if (w.isEmpty) return null;
  if (w.length > 60) return null;
  if (!_hasLatinLetter.hasMatch(w)) return null;
  if (RegExp(r'\d').hasMatch(w)) return null;
  if (!_allowedWordShape.hasMatch(w)) return null;
  final parts = w.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || parts.length > 6) return null;
  // 去掉不配对的圆括号（常见于断行残缺），避免生成怪词形。
  final open = '('.allMatches(w).length;
  final close = ')'.allMatches(w).length;
  if (open != close) return null;
  return w.toLowerCase();
}

String _normalize(String raw) {
  return raw
      .replaceAll('\u00a0', ' ') // NBSP
      .replaceAll('\u3000', ' ') // 全角空格
      .replaceAll('\r', '')
      .trim();
}

String _joinMeaning(String a, String b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  // 中文之间不留空格，中英之间留一个
  final needSpace = !_cjk.hasMatch(_lastChar(a)) && !_cjk.hasMatch(b[0]);
  return needSpace ? '$a $b' : '$a$b';
}

String _lastChar(String s) => s.isEmpty ? '' : s[s.length - 1];
