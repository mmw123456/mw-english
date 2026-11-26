import 'dart:math';

import 'package:sqflite/sqflite.dart' show Database;

import 'choice_options.dart';
import 'near_words.dart';

/// 词库里的一个候选词条（只要首条中文释义）。
class LexEntry {
  const LexEntry(this.word, this.gloss);

  final String word;
  final String gloss;
}

/// 43,350 词典的内存切片，按首字母分组。
///
/// 为什么要一次性读进内存：出干扰项要先算形近词，而形近词必须拿同首字母的
/// 候选逐个算编辑距离。每张卡去数据库捞一次「同首字母 + 长度 ±2」的几千行，
/// 一场会话要捞上百次；一次读进来之后每张卡只是内存里扫一遍，快一个量级。
/// 词典是只读的，进程内缓存一份就够，不需要失效。
class WordLexicon {
  WordLexicon._(this._byInitial, this.batchGlosses);

  final Map<String, List<LexEntry>> _byInitial;

  /// 820 词（我的词表）的释义。形近词不够时优先从这里补干扰项：
  /// 同批词的难度接近，比词典里随便捞一个更像选项。
  final List<String> batchGlosses;

  static WordLexicon? _cache;

  static Future<WordLexicon> load(Database db) async {
    final cached = _cache;
    if (cached != null) return cached;

    // 只取前 40 个字符：选项最多个 26 字，整条释义传过来是白搭 ——
    // 43,350 行，传输量砍一半，首场会话的加载快不少。
    final rows = await db.rawQuery(
      "SELECT word, substr(translation, 1, 40) AS translation "
      "FROM words WHERE translation <> ''",
    );
    final map = <String, List<LexEntry>>{};
    for (final r in rows) {
      final w = ((r['word'] as String?) ?? '').trim().toLowerCase();
      if (w.isEmpty || w.contains(' ')) continue;
      final gloss = shortGloss((r['translation'] as String?) ?? '');
      if (gloss.isEmpty) continue;
      map.putIfAbsent(w[0], () => <LexEntry>[]).add(LexEntry(w, gloss));
    }

    final mine = await db.rawQuery(
      'SELECT meaning_pdf, meaning_ecdict FROM my_words ORDER BY no',
    );
    final batch = <String>[];
    for (final r in mine) {
      final pdf = ((r['meaning_pdf'] as String?) ?? '').trim();
      final gloss =
          shortGloss(pdf.isNotEmpty ? pdf : ((r['meaning_ecdict'] as String?) ?? ''));
      if (gloss.isEmpty) continue;
      batch.add(gloss);
    }

    return _cache = WordLexicon._(map, batch);
  }

  /// 仅供测试清理缓存。
  static void resetCache() => _cache = null;

  /// 形近词：同首字母、长度 ±2、编辑距离 ≤ 3，排除派生词，按距离升序。
  List<LexEntry> near(String word, {int want = 10}) {
    final key = word.trim().toLowerCase();
    if (key.length < 3) return const [];
    final bucket = _byInitial[key[0]];
    if (bucket == null) return const [];

    final scored = <(int, String, LexEntry)>[];
    for (final e in bucket) {
      if (e.word == key) continue;
      if ((e.word.length - key.length).abs() > 2) continue;
      if (isDerived(key, e.word)) continue;
      final d = editDistance(key, e.word, cap: 3);
      if (d <= 0 || d > 3) continue;
      scored.add((d, e.word, e));
    }
    scored.sort((a, b) {
      final byDist = a.$1.compareTo(b.$1);
      if (byDist != 0) return byDist;
      return a.$2.compareTo(b.$2);
    });
    return scored.take(want).map((e) => e.$3).toList();
  }

  /// 同首字母的随机样本，形近词不够时补齐用。
  List<LexEntry> sampleInitial(String word, Random rng, {int want = 24}) {
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final bucket = _byInitial[key[0]];
    if (bucket == null || bucket.isEmpty) return const [];
    final copy = List<LexEntry>.of(bucket)..shuffle(rng);
    return copy.take(want).toList();
  }

  /// 全库随机样本，最后一道兜底（首字母是生僻字母时用）。
  List<LexEntry> sampleAny(Random rng, {int want = 24}) {
    final all = <LexEntry>[];
    for (final bucket in _byInitial.values) {
      if (bucket.isEmpty) continue;
      all.add(bucket[rng.nextInt(bucket.length)]);
      if (all.length >= want) break;
    }
    all.shuffle(rng);
    return all;
  }
}
