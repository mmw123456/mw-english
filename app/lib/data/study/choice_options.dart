import 'dart:math';

/// 一个中文义项的短形式：取第一行、第一个分句，去掉域标签与词性前缀，最长 26 字。
///
/// 卡片上一次要并排四条，太长的释义读起来费劲；详情页另有一套完整展示。
/// 选项上一律去掉 `[化]` `v.` 这些前缀：正确项来自单词本 PDF、干扰项来自
/// ECDICT，两边前缀写法不一致，留着会让「哪条来自词典」变得可猜。
String shortGloss(String raw) {
  final first = raw.split('\n').first.trim();
  if (first.isEmpty) return '';
  final cut = first.split(RegExp(r'[；;]')).first.trim();
  final text = cleanOption(cut.isEmpty ? first : cut);
  return text.length > 26 ? '${text.substring(0, 26)}…' : text;
}

/// 领域标签，如 `[化]` `[医][计]`。
final RegExp _domainTag = RegExp(r'^\[[^\]]{0,6}\]\s*');

/// 释义里的词性前缀：`n.` `v.` `vt.` `adj.` `a.` …
final RegExp _posPrefix = RegExp(
  r'^(n|v|vt|vi|adj|a|ad|adv|prep|conj|pron|num|art|int|aux)\s*\.\s*',
  caseSensitive: false,
);

/// 去掉域标签与词性前缀，留下「义项本身」。
String cleanOption(String raw) {
  var text = raw.trim();
  while (_domainTag.hasMatch(text)) {
    text = text.replaceFirst(_domainTag, '');
  }
  text = text.replaceFirst(_posPrefix, '');
  return text.trim();
}

/// 比较释义时忽略的字符：标点、空白、括号、省略号。
final RegExp _noise = RegExp(r'[\s,，、.。·…（）()\[\]【】/／]');

/// 释义里带拉丁字母，多半是「xx 的过去式」「n. 牛( Bos taurus )」这类，
/// 放在选项里等于把答案写出来了，直接不要。
final RegExp _latin = RegExp('[A-Za-z]');

/// 把一条释义拆成若干「核心义项」：按逗号顿号切开，去词性前缀和标点。
List<String> _cores(String text) {
  final out = <String>[];
  for (final seg in text.split(RegExp(r'[,，、；;]'))) {
    final core = seg.replaceFirst(_posPrefix, '').replaceAll(_noise, '');
    if (core.isNotEmpty) out.add(core);
  }
  return out;
}

/// 两条释义是否说的是同一件事（任一段互相包含即算）。
///
/// 只看「是否完全相等」不够用：正确项是「n. 礼节」时，干扰项
/// 「n. 典礼, 仪式, 礼节」里也含着「礼节」，那这题就有两个正确答案。
bool _overlaps(String a, String b) {
  for (final x in _cores(a)) {
    for (final y in _cores(b)) {
      if (x.contains(y) || y.contains(x)) return true;
    }
  }
  return false;
}

/// 四选一的选项集合。
///
/// 「正确项只出现一次」「干扰项释义不与正确项重复」「不取本词」三条都在
/// [build] 里保证，页面只负责画。凑不出 3 个干扰项时返回 null —— 宁可退回
/// 别的处理，也不出一张有重复选项的题（那样等于直接送答案）。
class ChoiceOptions {
  const ChoiceOptions({required this.options, required this.answerIndex});

  /// 四个选项，顺序已打乱。
  final List<String> options;

  /// 正确项在 [options] 里的下标。
  final int answerIndex;

  /// 组装选项。[nearMeanings] 是形近词的释义（优先），[fallbackMeanings]
  /// 是同批 / 同首字母的释义（补齐用）。两个来源的顺序都会被保留。
  static ChoiceOptions? build({
    required String correct,
    required Iterable<String> nearMeanings,
    required Iterable<String> fallbackMeanings,
    required Random rng,
    int size = 4,
  }) {
    final target = correct.trim();
    if (target.isEmpty || size < 2) return null;

    final picked = <String>[];
    // 已占用的释义文本：正确项本身先占住，保证它只出现一次。
    final used = <String>{target};

    void take(Iterable<String> source) {
      for (final raw in source) {
        if (picked.length >= size - 1) return;
        final text = raw.trim();
        if (text.isEmpty) continue;
        if (_latin.hasMatch(text)) continue;
        if (_overlaps(target, text)) continue;
        if (!used.add(text)) continue;
        picked.add(text);
      }
    }

    take(nearMeanings);
    take(fallbackMeanings);
    if (picked.length < size - 1) return null;

    final options = <String>[...picked, target]..shuffle(rng);
    return ChoiceOptions(options: options, answerIndex: options.indexOf(target));
  }
}
