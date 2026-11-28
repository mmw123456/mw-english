import '../db/app_database.dart';
import 'article_metrics.dart';

/// 判断「这个词读者认不认识」。
///
/// 依据是内置词典的 `frq` 词频排名 —— `the` 排 1、`abandon` 2182、
/// `significant` 719，都算认识；`algorithm` 8230、`photosynthesis` 17755 算生词。
/// 排名 ≤ [SqlRareWordLookup.rankThreshold] 的算 CET-4 以内。
///
/// 难点在变形：正文里是 `decided` / `studying` / `students`，词典里只有原形。
/// 所以要先剥后缀查原形（[lemmaCandidates]），不然生词率会虚高到 20%+ —— 那是
/// 「统计口径坏了」，不是「模型用得难」。
abstract class RareWordLookup {
  /// 给一批正文词，返回判定函数。查不到的算生词。
  Future<IsRareWord> prepare(Iterable<String> tokens);
}

/// 查 SQLite 的实现。
class SqlRareWordLookup implements RareWordLookup {
  const SqlRareWordLookup();

  /// 排名阈值：≤5000 算 CET-4 以内。
  static const int rankThreshold = 5000;

  @override
  Future<IsRareWord> prepare(Iterable<String> tokens) async {
    final unique = tokens.map((t) => t.toLowerCase()).toSet().toList();

    // 每个词都生成「原形候选」，一次性查回来，避免正文 400 个词查 400 次库。
    final candidates = <String>{};
    for (final t in unique) {
      candidates.addAll(lemmaCandidates(t));
    }

    final ranks = await _ranks(candidates.toList());

    return (String word) {
      final w = word.toLowerCase();
      for (final c in lemmaCandidates(w)) {
        final frq = ranks[c];
        if (frq == null) continue;
        return !(frq > 0 && frq <= rankThreshold);
      }
      // 一个候选都不在词典里 —— 生僻词、专有名词、拼错的，一律算生词。
      return true;
    };
  }

  Future<Map<String, int?>> _ranks(List<String> words) async {
    final out = <String, int?>{};
    if (words.isEmpty) return out;

    final db = await AppDatabase.open();
    const chunk = 300; // SQLite 默认变量上限 999，300 一拼留足余量
    for (var i = 0; i < words.length; i += chunk) {
      final slice = words.sublist(i, (i + chunk).clamp(0, words.length));
      final marks = List.filled(slice.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT word, frq FROM words WHERE word IN ($marks)',
        slice,
      );
      for (final r in rows) {
        final w = (r['word'] as String?)?.toLowerCase();
        if (w == null) continue;
        out[w] = (r['frq'] as num?)?.toInt();
      }
    }
    return out;
  }
}

/// 高频功能词：词典里查不到或排名不靠谱，直接算「认识」。
///
/// 不写这一张表的话，`was` 会被剥成 `wa` 查不到 → 判成生词，
/// 而 `was` 在一篇 400 词的文章里能出现十几次。
const Set<String> _functionWords = {
  'a', 'an', 'the', 'and', 'or', 'but', 'if', 'so', 'as', 'at', 'by', 'for',
  'from', 'in', 'into', 'of', 'on', 'onto', 'to', 'up', 'upon', 'with', 'within',
  'without', 'about', 'above', 'across', 'after', 'against', 'along', 'among',
  'around', 'before', 'behind', 'below', 'beneath', 'beside', 'between',
  'beyond', 'during', 'except', 'inside', 'near', 'off', 'out', 'outside',
  'over', 'past', 'since', 'through', 'throughout', 'till', 'toward', 'towards',
  'under', 'until', 'via', 'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me',
  'him', 'her', 'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their',
  'mine', 'yours', 'hers', 'ours', 'theirs', 'this', 'that', 'these', 'those',
  'who', 'whom', 'whose', 'which', 'what', 'when', 'where', 'why', 'how',
  'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has',
  'had', 'having', 'do', 'does', 'did', 'done', 'doing', 'will', 'would',
  'shall', 'should', 'can', 'could', 'may', 'might', 'must', 'not', 'no',
  'nor', 'none', 'any', 'some', 'all', 'both', 'each', 'every', 'few',
  'more', 'most', 'much', 'many', 'other', 'another', 'such', 'same', 'own',
  'only', 'just', 'very', 'too', 'also', 'then', 'than', 'there', 'here',
  'now', 'soon', 'later', 'again', 'once', 'twice', 'ever', 'never', 'always',
  'often', 'sometimes', 'still', 'yet', 'already', 'almost', 'enough', 'even',
  'well', 'back', 'down', 'away', 'one', 'two', 'three', 'first', 'second',
  'last', 'next', 'new', 'old', 'good', 'bad', 'big', 'small', 'long',
  'short', 'high', 'low', 'young', 'day', 'days', 'night', 'time', 'times',
  'year', 'years', 'man', 'men', 'woman', 'women', 'people', 'thing', 'things',
  'way', 'ways', 'part', 'place', 'work', 'life', 'hand', 'eyes', 'face',
  'yes', 'oh', 'hey', 'hi', 'hello', 'mr', 'mrs', 'ms', 'dr',
};

/// 一个词的「原形候选」，按可信度从高到低。
///
/// 剥后缀是粗糙的词形还原 —— 不做它，`decided` / `students` / `running`
/// 全都查不到，生词率直接翻几倍。做了它，覆盖绝大多数规则变形，
/// 剩下的不规则变形（`went` / `children`）由功能词表与词典本身兜。
List<String> lemmaCandidates(String word) {
  final w = word.trim().toLowerCase();
  if (w.isEmpty) return const [];

  final out = <String>[w];
  if (_functionWords.contains(w)) return out;

  void add(String s) {
    if (s.length >= 2 && s != w && !out.contains(s)) out.add(s);
  }

  // 复数 / 三单
  if (w.endsWith('ies') && w.length > 4) add('${w.substring(0, w.length - 3)}y');
  if (w.endsWith('es') && w.length > 3) add(w.substring(0, w.length - 2));
  if (w.endsWith('s') && !w.endsWith('ss') && w.length > 3) {
    add(w.substring(0, w.length - 1));
  }

  // 过去式 / 过去分词
  if (w.endsWith('ied') && w.length > 4) add('${w.substring(0, w.length - 3)}y');
  if (w.endsWith('ed') && w.length > 3) {
    final stem = w.substring(0, w.length - 2);
    add(stem);
    add('${stem}e');
    if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1)); // running → run
    }
  }

  // 现在分词
  if (w.endsWith('ing') && w.length > 4) {
    final stem = w.substring(0, w.length - 3);
    add(stem);
    add('${stem}e');
    if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1));
    }
  }

  // 副词 / 比较级 / 最高级
  if (w.endsWith('ly') && w.length > 4) add(w.substring(0, w.length - 2));
  if (w.endsWith('ily') && w.length > 5) {
    add('${w.substring(0, w.length - 3)}y');
  }
  if (w.endsWith('est') && w.length > 5) {
    final stem = w.substring(0, w.length - 3);
    add(stem);
    if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1)); // biggest → big
    }
  }
  if (w.endsWith('er') && w.length > 4) {
    final stem = w.substring(0, w.length - 2);
    add(stem);
    if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1)); // bigger → big
    }
  }

  return out;
}
