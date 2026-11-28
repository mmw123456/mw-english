import '../dao/detail_dao.dart';
import '../dao/word_dao.dart';
import '../models/word_detail.dart';
import '../models/word_entry.dart';

/// 查词来源。**这个顺序就是释义优先级**，与 [DetailDao.load] 的取释义规则一致。
///
/// - [book]：820 词单词本。命中时显示两段式（词书原释 + ECDICT 全释）。
/// - [added]：自加 / 导入词。显示入库时存下的 `user_added_words.meaning`。
/// - [dict]：43,350 词离线词典，兜底。
enum LookupSource {
  book('词书'),
  added('自加'),
  dict('词典');

  const LookupSource(this.label);

  final String label;
}

/// 候选行。查词页的候选列表、以及合并排序都用它。
class LookupHit {
  const LookupHit({
    required this.wordKey,
    required this.word,
    required this.source,
    required this.gloss,
    this.phonetic = '',
    this.pos = '',
  });

  /// 小写关联键。所有表都用它串。
  final String wordKey;

  /// 要显示的写法（保留大小写与词组括号）。
  final String word;

  final LookupSource source;

  /// 一行释义，列表里只显示这一行。
  final String gloss;

  final String phonetic;
  final String pos;

  /// 英文查询时，这个词是不是以输入开头（用来把精确命中排到最前）。
  bool startsWithQuery(String q) => wordKey.startsWith(q);
}

/// 一次搜索的三源结果。
///
/// 词库页要**按来源分组画三种行**（我的词表 / 自加词 / 离线词典，行样式各不同，
/// 带遮盖、箱位、移除），所以这里保留原始类型；查词页只要合并后的候选，
/// 用 [candidates] 拿。两边吃同一份搜索结果，不各查一遍库。
class LookupHits {
  const LookupHits({
    required this.query,
    this.book = const [],
    this.added = const [],
    this.dict = const [],
  });

  const LookupHits.empty(this.query)
      : book = const [],
        added = const [],
        dict = const [];

  final String query;
  final List<WordEntry> book;
  final List<DictEntry> added;
  final List<DictEntry> dict;

  bool get isEmpty => book.isEmpty && added.isEmpty && dict.isEmpty;
  bool get isNotEmpty => !isEmpty;
  int get length => book.length + added.length + dict.length;

  /// 精确命中：wordKey 与输入完全相同的第一个（词书 > 自加 > 词典）。
  ///
  /// 走 [all] 而不是候选：候选只留 10 条，精确命中的词万一排到 11 位之后
  /// （比如搜 `a` 这种极短前缀）就会被判定成「没有精确命中」。
  LookupHit? get exact {
    for (final h in all) {
      if (h.wordKey == query) return h;
    }
    return null;
  }

  /// 合并成一条候选列表：词书 → 自加 → 词典，按 wordKey 去重（前面的赢）。
  ///
  /// 排序不在这里做：三个 DAO 已经各自排好（820 按序号、自加按添加时间倒序、
  /// 词典按前缀命中 + 词频），合并时保持原序就够，再排一次反而会把
  /// 「搜 no 时 no 排第一」这种精确命中顶掉。
  List<LookupHit> get all {
    final out = <LookupHit>[];
    final seen = <String>{};
    void take(LookupHit h) {
      if (seen.add(h.wordKey)) out.add(h);
    }

    for (final e in book) {
      take(
        LookupHit(
          wordKey: e.wordKey,
          word: e.word,
          source: LookupSource.book,
          // 820 词两段式里的第一段就是词书原释，列表里先显示它。
          gloss: _firstLine(
            e.meaningPdf.trim().isEmpty ? e.meaningEcdict : e.meaningPdf,
          ),
          phonetic: e.phonetic.trim(),
          pos: e.pos.trim(),
        ),
      );
    }
    for (final e in added) {
      take(
        LookupHit(
          wordKey: e.word.toLowerCase(),
          word: e.word,
          source: LookupSource.added,
          gloss: _firstLine(e.translation),
          phonetic: e.phonetic.trim(),
          pos: e.pos.trim(),
        ),
      );
    }
    for (final e in dict) {
      take(
        LookupHit(
          wordKey: e.word.toLowerCase(),
          word: e.word,
          source: LookupSource.dict,
          gloss: _firstLine(e.translation),
          phonetic: e.phonetic.trim(),
          pos: e.pos.trim(),
        ),
      );
    }
    return out;
  }

  /// 查词页的候选，最多 [limit] 条。
  List<LookupHit> candidates({int limit = LookupService.candidateLimit}) {
    final out = all;
    return out.length <= limit ? out : out.sublist(0, limit);
  }

  static String _firstLine(String s) {
    final line = s.split('\n').first.trim();
    return line;
  }
}

/// 解析好的一个词条。
///
/// 只是 [WordDetail] 的一层「查词视角」的皮：不重新拼数据，也不复制字段，
/// 所以释义优先级、音标、箱位、是否在库永远与词条详情页同源。
class LookupResult {
  const LookupResult({required this.detail, required this.source});

  final WordDetail detail;
  final LookupSource source;

  factory LookupResult.of(WordDetail detail) =>
      LookupResult(detail: detail, source: sourceOf(detail));

  /// 来源判定：820 词有 `no`，自加词在 `user_added_words` 里，其余算词典。
  static LookupSource sourceOf(WordDetail d) {
    if (d.no != null) return LookupSource.book;
    if (d.isAdded) return LookupSource.added;
    return LookupSource.dict;
  }

  String get wordKey => detail.wordKey;

  String get word {
    final w = detail.word.trim();
    return w.isEmpty ? detail.wordKey : w;
  }

  String get phonetic => detail.phonetic.trim();
  String get pos => detail.pos.trim();

  /// 第一段：820 词的书上原释。词典里的词没有这一段。
  String get bookMeaning => detail.meaningPdf.trim();

  /// 第二段：ECDICT 全释 / 自加词入库时存的释义。
  ///
  /// [DetailDao.load] 已经做过「820 补充释义 > 导入自带释义 > 词典释义」，
  /// 这里拿到的是最后那一段，不再重复判断。
  String get dictMeaning => detail.meaningEcdict.trim();

  /// 两段都有且不一样时才分两段显示（一样就没必要重复两遍）。
  bool get twoParts =>
      bookMeaning.isNotEmpty && dictMeaning.isNotEmpty && bookMeaning != dictMeaning;

  /// 没有释义（820 里那 8 个 ECDICT 没覆盖的词只有书上一段）。
  bool get hasMeaning => bookMeaning.isNotEmpty || dictMeaning.isNotEmpty;

  /// 一行摘要，加入生词本时写进 `user_added_words.meaning`。
  ///
  /// 取**词典那一段**优先：查词加入的词都不会在 820 里（820 本来就在库），
  /// 所以这一段就是它唯一的释义；万一为空再退到书上一段。
  String get meaning => dictMeaning.isNotEmpty ? dictMeaning : bookMeaning;

  int? get box => detail.box;

  /// 在库里（820 或自加）。纯词典词不在学习池里，也就没有箱位。
  bool get inLibrary => detail.inMyList;
  bool get killed => detail.killed;
}

/// 一次查词的完整结果。
class LookupView {
  const LookupView({
    required this.query,
    required this.hits,
    this.result,
  });

  /// 规范化之后的输入（去空白、压空格、小写）。
  final String query;
  final LookupHits hits;

  /// 输入与某个词条完全一致时自动解析出来的结果，否则为空。
  final LookupResult? result;

  bool get isEmptyQuery => query.isEmpty;
  List<LookupHit> get candidates => hits.candidates();

  /// 查不到：三个来源都没有，也没有解析结果。
  bool get notFound => query.isNotEmpty && result == null && hits.isEmpty;

  /// 有候选但还没选，等用户点一条。
  bool get needsPick => result == null && hits.isNotEmpty;
}

/// 查词的存储层。抽成接口是为了 `flutter test` 能不开 sqflite 就跑整条链
/// （与 v0.10.0 的 `ArticleStore` / `WordPool` 同一套做法）。
abstract class LookupStore {
  Future<LookupHits> search(String query);

  /// 读一个词的完整详情。查不到返回 null。
  Future<WordDetail?> resolve(String wordKey);

  /// 加入生词本（自加词口径：同一张 `user_added_words`、0 箱起步）。
  Future<void> addToLibrary(String wordKey, String meaning);
}

/// 真库实现。三个搜索直接调 [WordDao]（英文前缀 / 中文释义包含的规则
/// 都在那三条 SQL 里，`check_search_v067.py` 还盯着它们），解析调 [DetailDao]。
class SqlLookupStore implements LookupStore {
  const SqlLookupStore({this.words = const WordDao(), this.details = const DetailDao()});

  final WordDao words;
  final DetailDao details;

  @override
  Future<LookupHits> search(String query) async {
    if (query.isEmpty) return LookupHits.empty(query);
    final r = await Future.wait<Object>([
      words.searchMyWords(query),
      words.searchAddedWords(query),
      words.searchDictionary(query),
    ]);
    return LookupHits(
      query: query,
      book: r[0] as List<WordEntry>,
      added: r[1] as List<DictEntry>,
      dict: r[2] as List<DictEntry>,
    );
  }

  @override
  Future<WordDetail?> resolve(String wordKey) => details.load(wordKey);

  @override
  Future<void> addToLibrary(String wordKey, String meaning) =>
      details.addToMyList(wordKey, meaning: meaning);
}

/// 统一查词。
///
/// 四个入口（首页 / 词库页 / 学习会话 / 文章双击）都走这里，只此一份：
/// - 输入规范化：去首尾空白、内部连续空白压成一个、转小写；
/// - 中英分岔：汉字走释义包含，英文（含短语）走整串前缀，规则在 [WordDao]；
/// - 精确命中自动解析：输入就是某个词条时直接出结果卡，不用再点一次；
/// - 候选上限 [candidateLimit] 条。
class LookupService {
  LookupService({LookupStore? store}) : _store = store ?? const SqlLookupStore();

  final LookupStore _store;

  /// 候选最多给几条（需求写死 10）。
  static const int candidateLimit = 10;

  static final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// 规范化。短语里的括号与连字符保留 —— `once (and) for all` 是库里真实存在的
  /// 词条，把括号吃掉就查不到了。
  static String normalize(String raw) =>
      raw.trim().replaceAll(_spaces, ' ').toLowerCase();

  static bool isChinese(String q) => _cjk.hasMatch(q);

  Future<LookupHits> search(String raw) => _store.search(normalize(raw));

  Future<LookupResult?> resolve(String wordKey) async {
    final key = normalize(wordKey);
    if (key.isEmpty) return null;
    final detail = await _store.resolve(key);
    return detail == null ? null : LookupResult.of(detail);
  }

  /// 一次查词。输入为空时返回空视图，不碰库。
  Future<LookupView> lookup(String raw) async {
    final q = normalize(raw);
    if (q.isEmpty) return LookupView(query: '', hits: LookupHits.empty(''));

    final hits = await _store.search(q);
    final hit = hits.exact;
    if (hit == null) return LookupView(query: q, hits: hits);

    final result = await resolve(hit.wordKey);
    return LookupView(query: q, hits: hits, result: result);
  }

  /// 加入生词本。已在库里（820 或自加）就什么都不做 —— 防重复加。
  ///
  /// 注意：820 的词永远走不到这里，「加入」按钮对它们本来就是置灰的。
  Future<bool> addToLibrary(LookupResult result) async {
    if (result.inLibrary) return false;
    await _store.addToLibrary(result.wordKey, result.meaning);
    return true;
  }
}
