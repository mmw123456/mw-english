import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/data/lookup/lookup_service.dart';
import 'package:mw_english/data/models/study_card.dart';
import 'package:mw_english/data/models/word_detail.dart';
import 'package:mw_english/data/models/word_entry.dart';
import 'package:mw_english/data/study/leitner.dart';
import 'package:mw_english/features/lookup/lookup_page.dart';
import 'package:mw_english/features/lookup/lookup_result_card.dart';
import 'package:mw_english/features/study/study_session_page.dart';

/// v0.11.0 统一查词。
///
/// 四入口共用一套：`LookupService`（规范化 + 中英分岔 + 三源合并 + 精确自动解析）
/// 与 `LookupResultCard`（词 / 音标 / 词性 / 两段式释义 / 发音 / 加入生词本）。
/// 这里全部用假库跑，不碰 sqflite、不打网络、不发音。
///
/// 验收八条对应关系：
/// 1. 820 词两段式 → group「两段式释义」
/// 2. 短语整串命中 → group「短语」
/// 3. 中文按释义查到 → group「中文查询」
/// 4. 英文前缀候选 → group「候选」
/// 5. ECDICT 没覆盖的 8 个词 → group「8 个词」
/// 6. 查不到明说未查到 → group「查不到」
/// 7. 已在库不重复加 → group「加入生词本」
/// 8. 学习页查词不记答题 → group「学习页」

// ---------------------------------------------------------------- 假库

class _FakeStore implements LookupStore {
  _FakeStore({
    this.book = const [],
    this.added = const [],
    this.dict = const [],
    this.details = const {},
  });

  final List<WordEntry> book;
  final List<DictEntry> added;
  final List<DictEntry> dict;
  final Map<String, WordDetail> details;

  int searchCalls = 0;
  String? lastQuery;
  final List<({String key, String meaning})> addedCalls = [];

  bool _hit(String word, String gloss, String q) => LookupService.isChinese(q)
      ? gloss.contains(q)
      : word.toLowerCase().startsWith(q);

  @override
  Future<LookupHits> search(String query) async {
    searchCalls++;
    lastQuery = query;
    return LookupHits(
      query: query,
      book: [
        for (final e in book)
          if (_hit(e.wordKey, '${e.meaningPdf}${e.meaningEcdict}', query)) e,
      ],
      added: [
        for (final e in added)
          if (_hit(e.word, e.translation, query)) e,
      ],
      dict: [
        for (final e in dict)
          if (_hit(e.word, e.translation, query)) e,
      ],
    );
  }

  @override
  Future<WordDetail?> resolve(String wordKey) async =>
      details[LookupService.normalize(wordKey)];

  @override
  Future<void> addToLibrary(String wordKey, String meaning) async {
    addedCalls.add((key: wordKey, meaning: meaning));
  }
}

// ---------------------------------------------------------------- 构造器

WordEntry _book({
  int no = 1,
  String word = 'transmit',
  String phonetic = 'trænzˈmɪt',
  String pdf = 'vt. 传送，传达',
  String ecdict = 'vt. 传输；传染；发射',
  String pos = 'v.',
}) {
  return WordEntry(
    no: no,
    word: word,
    wordKey: word.toLowerCase(),
    phonetic: phonetic,
    meaningPdf: pdf,
    pdfTruncated: false,
    meaningEcdict: ecdict,
    pos: pos,
    tag: '',
    collins: 0,
  );
}

DictEntry _dict({
  String word = 'transfer',
  String phonetic = 'trænsˈfɜː',
  String translation = 'n. 转移；转让\nvt. 转移',
  String pos = 'n.',
}) {
  return DictEntry(
    word: word,
    phonetic: phonetic,
    translation: translation,
    pos: pos,
    tag: '',
    collins: 0,
    frq: 2000,
  );
}

WordDetail _detail({
  String wordKey = 'transmit',
  String word = 'transmit',
  String phonetic = 'trænzˈmɪt',
  String pdf = '',
  String ecdict = '',
  String pos = '',
  int? no,
  int? box,
  bool added = false,
  bool killed = false,
}) {
  return WordDetail(
    wordKey: wordKey,
    word: word,
    phonetic: phonetic,
    meaningPdf: pdf,
    pdfTruncated: false,
    meaningEcdict: ecdict,
    pos: pos,
    tag: '',
    collins: 0,
    no: no,
    box: box,
    isAdded: added,
    killed: killed,
    starred: false,
    forms: const [],
    synonyms: const [],
    nearWords: const [],
  );
}

List<WordEntry> _manyBook(int n) => [
      for (var i = 0; i < n; i++)
        _book(no: i + 1, word: 'trail$i', pdf: '释义$i', ecdict: '释义$i'),
    ];

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

StudyCard _card(String key, String word) => StudyCard(
      wordKey: key,
      word: word,
      phonetic: '/$word/',
      meaning: '$word 的释义',
      meaningEcdict: '',
      box: 1,
      isNew: false,
      isRetest: false,
      options: <String>['$word 的释义', '干扰甲', '干扰乙', '干扰丙'],
      answerIndex: 0,
    );

StudySession _session(int n) => StudySession(
      cards: <StudyCard>[for (var i = 0; i < n; i++) _card('w$i', 'word$i')],
      quota: const DailyQuota(newWords: 0, reviewCap: 20, gapDays: 0),
      newCount: 0,
      reviewCount: n,
      retestCount: 0,
      learnedToday: 0,
    );

void main() {
  // ------------------------------------------------------------ 规范化
  group('输入规范化', () {
    test('去空白、压空格、转小写，括号与连字符保留', () {
      expect(
        LookupService.normalize('  Once  (and)   for All '),
        'once (and) for all',
      );
      expect(LookupService.normalize('take-away'), 'take-away');
    });

    test('空输入规范化后仍是空', () {
      expect(LookupService.normalize(''), '');
      expect(LookupService.normalize('   '), '');
    });

    test('汉字判中文，英文不判中文', () {
      expect(LookupService.isChinese('传送'), isTrue);
      expect(LookupService.isChinese('transmit'), isFalse);
      expect(LookupService.isChinese('transmit 传送'), isTrue);
    });
  });

  // ------------------------------------------------------------ 两段式
  group('两段式释义（820 词）', () {
    final r = LookupResult.of(
      _detail(
        no: 12,
        box: 2,
        pdf: 'vt. 传送，传达',
        ecdict: 'vt. 传输；传染；发射',
        pos: 'v.',
      ),
    );

    test('书上一段与词典一段分开保存', () {
      expect(r.bookMeaning, 'vt. 传送，传达');
      expect(r.dictMeaning, 'vt. 传输；传染；发射');
    });

    test('两段不同 → 界面分两段显示', () {
      expect(r.twoParts, isTrue);
    });

    test('两段一模一样 → 不分段（不重复两遍）', () {
      final same = LookupResult.of(
        _detail(no: 1, pdf: 'n. 二倍的', ecdict: 'n. 二倍的'),
      );
      expect(same.twoParts, isFalse);
    });

    test('来源是词书，箱位跟着库走', () {
      expect(r.source, LookupSource.book);
      expect(r.source.label, '词书');
      expect(r.box, 2);
      expect(r.inLibrary, isTrue);
    });

    test('两段都为空才算没有释义', () {
      expect(LookupResult.of(_detail()).hasMeaning, isFalse);
      expect(r.hasMeaning, isTrue);
    });
  });

  // ------------------------------------------------------------ 8 个词
  group('ECDICT 没覆盖的 8 个词仍显示词书释义', () {
    // 这 8 个词的 `words.translation` 是 820 强制并入时用 PDF 释义补的，
    // 但 `my_words.meaning_ecdict` 为空 —— 老实现（只看词典那一段）会显示
    // 「离线词典里没有释义」，本版必须显示书上那段原释。
    const cases = <String, String>{
      'duple': 'a. 二倍的，双重的',
      'graver': 'n. 雕刻师，雕刻刀',
      'utile': 'a. 有用的；有益的',
      'once (and) for all': 'phr. 只此一次，彻底地',
      'in retrospect': 'phr. 回顾往事；检讨过去',
      'meditating': 'a. 沉思的；冥想的',
      'diapers': 'n. 尿布',
      'plagued': 'v. 困扰',
    };

    for (final entry in cases.entries) {
      test('${entry.key} → 有释义，不判未查到', () {
        final r = LookupResult.of(
          _detail(
            wordKey: entry.key,
            word: entry.key,
            pdf: entry.value,
            ecdict: '',
            no: 100,
            box: 0,
          ),
        );
        expect(r.hasMeaning, isTrue);
        expect(r.bookMeaning, entry.value);
        expect(r.dictMeaning, '');
        expect(r.twoParts, isFalse, reason: '只有一段时不加小标');
      });
    }
  });

  // ------------------------------------------------------------ 短语
  group('短语整串命中', () {
    test('once (and) for all 整串能查到，括号不丢', () async {
      final store = _FakeStore(
        book: [_book(no: 1, word: 'once (and) for all', pdf: 'phr. 只此一次，彻底地')],
        details: {
          'once (and) for all': _detail(
            wordKey: 'once (and) for all',
            word: 'once (and) for all',
            pdf: 'phr. 只此一次，彻底地',
            no: 1,
            box: 0,
          ),
        },
      );
      final view = await LookupService(store: store).lookup('  Once (and)  for All ');
      expect(view.result, isNotNull);
      expect(view.query, 'once (and) for all');
      expect(view.result!.word, 'once (and) for all');
      expect(store.lastQuery, 'once (and) for all', reason: '短语不拆词');
    });

    test('in retrospect 同样整串命中', () async {
      final store = _FakeStore(
        book: [_book(no: 2, word: 'in retrospect', pdf: 'phr. 回顾往事')],
        details: {
          'in retrospect': _detail(
            wordKey: 'in retrospect',
            word: 'in retrospect',
            pdf: 'phr. 回顾往事',
            no: 2,
            box: 0,
          ),
        },
      );
      final view = await LookupService(store: store).lookup('in retrospect');
      expect(view.result?.word, 'in retrospect');
    });

    test('库里没有的短语照实说未查到，不拼凑', () async {
      // 需求里举的 take advantage of 在 43,350 词词典里并不存在（实测）。
      final store = _FakeStore(dict: [_dict(word: 'advantage')]);
      final view = await LookupService(store: store).lookup('take advantage of');
      expect(view.result, isNull);
      expect(view.candidates, isEmpty);
      expect(view.notFound, isTrue);
    });
  });

  // ------------------------------------------------------------ 中文
  group('中文按释义查到', () {
    test('搜「传送」命中，但要先选候选（词条键是英文）', () async {
      final store = _FakeStore(
        book: [_book(no: 12)],
        dict: [_dict(word: 'convey', translation: 'vt. 传送；运送')],
        details: {
          'transmit': _detail(no: 12, pdf: 'vt. 传送', box: 1),
          'convey': _detail(
            wordKey: 'convey',
            word: 'convey',
            ecdict: 'vt. 传送；运送',
          ),
        },
      );
      final view = await LookupService(store: store).lookup('传送');
      expect(view.notFound, isFalse);
      expect(view.result, isNull, reason: '中文不是词条键，得先选候选');
      expect(view.needsPick, isTrue);
      expect(view.candidates.map((h) => h.wordKey), contains('transmit'));
      expect(view.candidates.map((h) => h.wordKey), contains('convey'));
    });

    test('中文候选也带来源，能分清词书 / 词典', () async {
      final store = _FakeStore(
        book: [_book(no: 12)],
        dict: [_dict(word: 'convey', translation: 'vt. 传送；运送')],
      );
      final view = await LookupService(store: store).lookup('传送');
      final sources = {
        for (final h in view.candidates) h.wordKey: h.source,
      };
      expect(sources['transmit'], LookupSource.book);
      expect(sources['convey'], LookupSource.dict);
    });
  });

  // ------------------------------------------------------------ 候选
  group('英文前缀候选', () {
    test('最多 10 条，多的截掉', () async {
      final store = _FakeStore(book: _manyBook(12));
      final view = await LookupService(store: store).lookup('trail');
      expect(view.candidates.length, LookupService.candidateLimit);
      expect(LookupService.candidateLimit, 10);
    });

    test('顺序是 词书 → 自加 → 词典', () async {
      final store = _FakeStore(
        book: [_book(no: 1, word: 'transfer', pdf: 'n. 转移')],
        added: [_dict(word: 'transferee', translation: 'n. 受让人')],
        dict: [_dict(word: 'transferred')],
      );
      final view = await LookupService(store: store).lookup('transfer');
      expect(
        view.candidates.map((h) => h.source).toList(),
        [LookupSource.book, LookupSource.added, LookupSource.dict],
      );
    });

    test('同一个词三个来源都有 → 只留一条，词书优先', () async {
      final store = _FakeStore(
        book: [_book(no: 1, word: 'transfer', pdf: 'n. 转移')],
        added: [_dict(word: 'transfer')],
        dict: [_dict(word: 'transfer')],
      );
      final view = await LookupService(store: store).lookup('transfer');
      expect(view.candidates.length, 1);
      expect(view.candidates.single.source, LookupSource.book);
    });

    test('精确命中排到第 11 位之后也找得到（不被候选上限截掉）', () async {
      final store = _FakeStore(
        book: [
          for (var i = 0; i < 14; i++)
            _book(no: i + 1, word: 'tram$i', pdf: '释义$i'),
          // 精确命中的那条排在最后（第 15 位），候选只留前 10 条。
          _book(no: 15, word: 'tram', pdf: 'vt. 传送'),
        ],
        details: {'tram': _detail(wordKey: 'tram', word: 'tram', pdf: 'vt. 传送', no: 15)},
      );
      final view = await LookupService(store: store).lookup('tram');
      expect(view.hits.length, 15);
      expect(view.candidates.length, 10, reason: '候选仍是 10 条');
      expect(
        view.candidates.map((h) => h.wordKey),
        isNot(contains('tram')),
        reason: '精确命中本身已经在候选之外了',
      );
      expect(view.result, isNotNull, reason: '精确命中要自动解析，不能被截掉');
    });
  });

  // ------------------------------------------------------------ 查不到
  group('查不到就明说未查到', () {
    test('三源都没有 → notFound，不返回假结果', () async {
      final store = _FakeStore(book: [_book()]);
      final view = await LookupService(store: store).lookup('zzzzz');
      expect(view.notFound, isTrue);
      expect(view.result, isNull);
      expect(view.candidates, isEmpty);
    });

    test('空输入不查库', () async {
      final store = _FakeStore();
      final view = await LookupService(store: store).lookup('   ');
      expect(view.isEmptyQuery, isTrue);
      expect(store.searchCalls, 0);
    });
  });

  // ------------------------------------------------------------ 加词
  group('加入生词本', () {
    test('不在库 → 写进自加词，释义带上词典那一段', () async {
      final store = _FakeStore();
      final r = LookupResult.of(
        _detail(wordKey: 'convey', word: 'convey', ecdict: 'vt. 传送；运送'),
      );
      final ok = await LookupService(store: store).addToLibrary(r);
      expect(ok, isTrue);
      expect(store.addedCalls.single.key, 'convey');
      expect(store.addedCalls.single.meaning, 'vt. 传送；运送');
    });

    test('已在库（820 词）→ 一次都不写', () async {
      final store = _FakeStore();
      final r = LookupResult.of(_detail(no: 3, box: 3, pdf: 'vt. 传送'));
      final ok = await LookupService(store: store).addToLibrary(r);
      expect(ok, isFalse);
      expect(store.addedCalls, isEmpty);
    });

    test('已在库（自加词）→ 也不重复加', () async {
      final store = _FakeStore();
      final r = LookupResult.of(
        _detail(wordKey: 'convey', box: 0, added: true, ecdict: 'vt. 运送'),
      );
      expect(r.inLibrary, isTrue);
      expect(await LookupService(store: store).addToLibrary(r), isFalse);
      expect(store.addedCalls, isEmpty);
    });

    test('只有书上一段时用那一段当释义', () async {
      final store = _FakeStore();
      final r = LookupResult.of(
        _detail(wordKey: 'duple', word: 'duple', pdf: 'a. 二倍的，双重的'),
      );
      await LookupService(store: store).addToLibrary(r);
      expect(store.addedCalls.single.meaning, 'a. 二倍的，双重的');
    });
  });

  // ------------------------------------------------------------ 结果卡
  group('结果卡', () {
    Widget card({
      required WordDetail detail,
      VoidCallback? onAdd,
      VoidCallback? onOpenDetail,
      bool adding = false,
      bool justAdded = false,
    }) {
      return _app(
        Scaffold(
          body: SingleChildScrollView(
            child: LookupResultCard(
              result: LookupResult.of(detail),
              onSpeak: () {},
              onAdd: onAdd,
              onOpenDetail: onOpenDetail,
              adding: adding,
              justAdded: justAdded,
            ),
          ),
        ),
      );
    }

    testWidgets('两段式：词书原释与词典全释各一段，各带小标', (tester) async {
      await tester.pumpWidget(
        card(
          detail: _detail(
            no: 12,
            box: 1,
            pdf: 'vt. 传送，传达',
            ecdict: 'vt. 传输；传染；发射',
          ),
        ),
      );
      expect(find.byKey(const ValueKey('lookup-meaning-book')), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-meaning-dict')), findsOneWidget);
      expect(find.text('词书原释'), findsOneWidget);
      expect(find.text('词典全释'), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-meaning')), findsNothing);
    });

    testWidgets('单段：只画一段，不加小标', (tester) async {
      await tester.pumpWidget(
        card(detail: _detail(wordKey: 'convey', word: 'convey', ecdict: 'vt. 运送')),
      );
      expect(find.byKey(const ValueKey('lookup-meaning')), findsOneWidget);
      expect(find.text('词书原释'), findsNothing);
    });

    testWidgets('没有释义时明说，不留白', (tester) async {
      await tester.pumpWidget(card(detail: _detail(wordKey: 'x', word: 'x')));
      expect(find.byKey(const ValueKey('lookup-no-meaning')), findsOneWidget);
    });

    testWidgets('已在库：按钮写「已在词库 · 箱 3」且置灰', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        card(detail: _detail(no: 5, box: 3, pdf: 'vt. 传送'), onAdd: () => tapped++),
      );
      final btn = find.byKey(const ValueKey('lookup-in-lib'));
      expect(btn, findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-add')), findsNothing);
      expect(find.text('已在词库 · 箱 3'), findsOneWidget);
      await tester.tap(btn);
      await tester.pump();
      expect(tapped, 0, reason: '已在本里，按了也不许再加');
    });

    testWidgets('不在库：按钮写「加入生词本」，点一下回调一次', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        card(detail: _detail(wordKey: 'convey', word: 'convey', ecdict: 'vt. 运送'),
            onAdd: () => tapped++),
      );
      final btn = find.byKey(const ValueKey('lookup-add'));
      expect(btn, findsOneWidget);
      expect(find.text('加入生词本'), findsOneWidget);
      await tester.tap(btn);
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('刚加进去：立刻变「已在词库 · 箱 0」并置灰', (tester) async {
      await tester.pumpWidget(
        card(
          detail: _detail(wordKey: 'convey', word: 'convey', ecdict: 'vt. 运送'),
          justAdded: true,
          onAdd: () {},
        ),
      );
      expect(find.text('已在词库 · 箱 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-in-lib')), findsOneWidget);
    });

    testWidgets('音标为空就不画音标', (tester) async {
      await tester.pumpWidget(
        card(detail: _detail(wordKey: 'x', word: 'x', phonetic: '', ecdict: 'n. 叉')),
      );
      expect(find.byKey(const ValueKey('lookup-phonetic')), findsNothing);
    });

    testWidgets('词性为空就不画词性标签', (tester) async {
      await tester.pumpWidget(
        card(detail: _detail(wordKey: 'x', word: 'x', ecdict: 'n. 叉')),
      );
      expect(find.byKey(const ValueKey('lookup-pos')), findsNothing);
    });

    testWidgets('词性、来源、已斩三个标签按实际数据出现', (tester) async {
      await tester.pumpWidget(
        card(
          detail: _detail(
            no: 8,
            box: 0,
            pos: 'v.',
            pdf: 'vt. 传送',
            killed: true,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('lookup-pos')), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-source')), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-killed')), findsOneWidget);
      expect(find.text('词书'), findsOneWidget);
    });

    testWidgets('没给 onOpenDetail 就不画「查看完整词条」', (tester) async {
      await tester.pumpWidget(
        card(detail: _detail(wordKey: 'x', word: 'x', ecdict: 'n. 叉')),
      );
      expect(find.byKey(const ValueKey('lookup-detail')), findsNothing);
    });

    testWidgets('给了 onOpenDetail 就画，点一下回调', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        card(
          detail: _detail(wordKey: 'x', word: 'x', ecdict: 'n. 叉'),
          onOpenDetail: () => opened++,
        ),
      );
      final link = find.byKey(const ValueKey('lookup-detail'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pump();
      expect(opened, 1);
    });
  });

  // ------------------------------------------------------------ 查词页
  group('查词页', () {
    testWidgets('空态给用法，不空白', (tester) async {
      await tester.pumpWidget(
        _app(LookupPage(service: LookupService(store: _FakeStore()))),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('lookup-hint')), findsOneWidget);
      expect(find.text('输入单词、短语或中文'), findsOneWidget);
    });

    testWidgets('带词进来直接出结果卡，输入框预填', (tester) async {
      final store = _FakeStore(
        book: [_book(no: 12)],
        details: {'transmit': _detail(no: 12, box: 1, pdf: 'vt. 传送')},
      );
      await tester.pumpWidget(
        _app(LookupPage(initialQuery: 'transmit', service: LookupService(store: store))),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('lookup-word')), findsOneWidget);
      expect(find.text('transmit'), findsWidgets);
    });

    testWidgets('输入前缀先出候选，不出结果卡', (tester) async {
      final store = _FakeStore(book: _manyBook(3));
      await tester.pumpWidget(
        _app(LookupPage(service: LookupService(store: store))),
      );
      await tester.enterText(find.byType(TextField), 'trail');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byKey(const ValueKey('lookup-candidates')), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-hit-trail0')), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-word')), findsNothing);
    });

    testWidgets('点候选就出结果卡', (tester) async {
      final store = _FakeStore(
        book: _manyBook(2),
        details: {
          'trail1': _detail(wordKey: 'trail1', word: 'trail1', pdf: '释义1', no: 2),
        },
      );
      await tester.pumpWidget(
        _app(LookupPage(service: LookupService(store: store))),
      );
      await tester.enterText(find.byType(TextField), 'trail');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lookup-hit-trail1')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('lookup-word')), findsOneWidget);
    });

    testWidgets('查不到明说未查到，还解释不联网', (tester) async {
      final store = _FakeStore(book: [_book()]);
      await tester.pumpWidget(
        _app(LookupPage(service: LookupService(store: store))),
      );
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byKey(const ValueKey('lookup-not-found')), findsOneWidget);
      expect(find.textContaining('未查到'), findsOneWidget);
      expect(find.textContaining('不联网'), findsOneWidget);
    });

    testWidgets('候选最多 10 条', (tester) async {
      final store = _FakeStore(book: _manyBook(12));
      await tester.pumpWidget(
        _app(LookupPage(service: LookupService(store: store))),
      );
      await tester.enterText(find.byType(TextField), 'trail');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('候选 · 10'), findsOneWidget);
    });

    testWidgets('点加入生词本 → 写库一次、按钮变「已在词库 · 箱 0」', (tester) async {
      final store = _FakeStore(
        dict: [_dict(word: 'convey', translation: 'vt. 传送；运送')],
        details: {
          'convey': _detail(
            wordKey: 'convey',
            word: 'convey',
            ecdict: 'vt. 传送；运送',
          ),
        },
      );
      await tester.pumpWidget(
        _app(LookupPage(initialQuery: 'convey', service: LookupService(store: store))),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lookup-add')));
      await tester.pump();
      await tester.pump();
      expect(store.addedCalls.length, 1);
      expect(store.addedCalls.single.key, 'convey');
      expect(find.text('已在词库 · 箱 0'), findsOneWidget);
    });

    testWidgets('320 宽：结果卡不溢出', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = _FakeStore(
        book: [_book(no: 12)],
        details: {
          'transmit': _detail(
            no: 12,
            box: 1,
            pos: 'v.',
            pdf: 'vt. 传送，传达；传输；传染；发射；把（信号、声音等）发送出去',
            ecdict: 'vt. 传输；传染；发射；传送；传达；发报',
          ),
        },
      );
      await tester.pumpWidget(
        _app(LookupPage(initialQuery: 'transmit', service: LookupService(store: store))),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ 学习页
  group('学习页查词不记答题', () {
    testWidgets('卡片上有放大镜，点它只调查词、不动发音', (tester) async {
      var lookups = 0;
      var speaks = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: StudyWordCard(
              card: _card('transmit', 'transmit'),
              onSpeak: () => speaks++,
              onLookup: () => lookups++,
            ),
          ),
        ),
      );
      final magnifier = find.byKey(const ValueKey('card-lookup'));
      expect(magnifier, findsOneWidget);
      await tester.tap(magnifier);
      await tester.pump();
      expect(lookups, 1);
      expect(speaks, 0, reason: '查词与发音是两个独立入口');
    });

    testWidgets('放大镜画在单词卡里面，不额外多一层玻璃', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: StudyWordCard(
              card: _card('transmit', 'transmit'),
              onSpeak: () {},
              onLookup: () {},
            ),
          ),
        ),
      );
      // v0.6.6 起钉住的结构：单词正文一块 + 发音胶囊一块，共两层。
      expect(find.byType(GlassSurface), findsNWidgets(2));
    });

    testWidgets('会话页点放大镜 → 进查词页 → 返回后还是同一张卡、还没作答', (tester) async {
      await tester.pumpWidget(
        _app(StudySessionPage(debugSessionBuilder: () => _session(2))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('word0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('card-lookup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('查词'), findsOneWidget, reason: '打开了查词页');

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('word0'), findsOneWidget, reason: '回到同一张卡');
      expect(find.text('1 / 2'), findsOneWidget, reason: '进度没动');
      // 没答题 → 不会自动跳详情页（答完 500ms 才跳）
      expect(find.text('选出正确的中文意思'), findsOneWidget);
    });
  });
}
