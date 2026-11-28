import 'dart:io';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/dao/spelling_dao.dart';
import 'package:mw_english/data/spelling/spelling_round.dart';
import 'package:mw_english/features/spelling/spelling_page.dart';
import 'package:mw_english/features/study/study_page.dart' show SpellingLink;

/// v0.13.0 听音拼写：判定规矩 + 一轮怎么组 + 题面 / 判对判错 / 小结 + 首页入口。
///
/// 拼写页依赖 SQLite，测试环境打不开库，所以题源与成绩单都走 [SpellingStore]
/// 注入；TTS 也注入，不碰 MethodChannel。
void main() {
  SpellingItem mkItem(
    String word, {
    String? phonetic,
    String? meaning,
    String? key,
  }) =>
      SpellingItem(
        wordKey: key ?? word.toLowerCase(),
        word: word,
        phonetic: phonetic ?? '/$word/',
        meaning: meaning ?? 'n. $word 的释义',
      );

  Widget wrapApp(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: child);

  // ------------------------------------------------------------ 判定规矩
  group('判定规矩', () {
    test('大小写不敏感', () {
      expect(SpellingJudge.isCorrect('abandon', 'abandon'), isTrue);
      expect(SpellingJudge.isCorrect('Abandon', 'abandon'), isTrue);
      expect(SpellingJudge.isCorrect('ABANDON', 'abandon'), isTrue);
      expect(SpellingJudge.isCorrect('Abandon', 'Abandon'), isTrue);
    });

    test('前后空格不算错，中间多个空格算一个', () {
      expect(SpellingJudge.isCorrect('  abandon  ', 'abandon'), isTrue);
      expect(SpellingJudge.isCorrect('\tabandon\n', 'abandon'), isTrue);
      expect(
        SpellingJudge.isCorrect('take   advantage of', 'take advantage of'),
        isTrue,
      );
      expect(
        SpellingJudge.isCorrect('Take  Advantage   Of', 'take advantage of'),
        isTrue,
      );
    });

    test('短语整串判，不拆词', () {
      expect(SpellingJudge.isCorrect('take advantage of', 'take advantage of'),
          isTrue);
      // 只拼一半、少一个词、中间插字都不算对
      expect(SpellingJudge.isCorrect('take', 'take advantage of'), isFalse);
      expect(SpellingJudge.isCorrect('advantage of', 'take advantage of'),
          isFalse);
      expect(SpellingJudge.isCorrect('take advantage', 'take advantage of'),
          isFalse);
      expect(SpellingJudge.isCorrect('in retrospect', 'in retrospect'), isTrue);
      expect(SpellingJudge.isCorrect('retrospect', 'in retrospect'), isFalse);
    });

    test('once (and) for all 的 (and) 可有可无', () {
      const answer = 'once (and) for all';
      expect(SpellingJudge.isCorrect('once for all', answer), isTrue);
      expect(SpellingJudge.isCorrect('once and for all', answer), isTrue);
      expect(SpellingJudge.isCorrect('once (and) for all', answer), isTrue);
      expect(SpellingJudge.isCorrect('Once  For  All', answer), isTrue);
      // 只留 and、只留 once、词序错都不算对
      expect(SpellingJudge.isCorrect('once all', answer), isFalse);
      expect(SpellingJudge.isCorrect('once for', answer), isFalse);
      expect(SpellingJudge.isCorrect('for all once', answer), isFalse);
    });

    test('拼错 / 空输入算错', () {
      expect(SpellingJudge.isCorrect('abandan', 'abandon'), isFalse);
      expect(SpellingJudge.isCorrect('abandn', 'abandon'), isFalse);
      expect(SpellingJudge.isCorrect('', 'abandon'), isFalse);
      expect(SpellingJudge.isCorrect('   ', 'abandon'), isFalse);
    });

    test('念出来的写法去掉括号、保留里面的词', () {
      expect(SpellingJudge.spokenForm('once (and) for all'),
          'once and for all');
      expect(SpellingJudge.spokenForm('take advantage of'),
          'take advantage of');
      expect(mkItem('once (and) for all').spoken, 'once and for all');
    });
  });

  // ------------------------------------------------------------ 组一轮
  group('组一轮', () {
    test('新词优先，复习补位，最多 cap 题', () {
      final learned = [mkItem('alpha'), mkItem('beta')];
      final queued = [mkItem('gamma'), mkItem('delta')];
      final due = [mkItem('epsilon'), mkItem('zeta')];

      final four = SpellingRound.compose(
        learnedToday: learned,
        queued: queued,
        due: due,
        cap: 4,
      );
      expect(four.map((e) => e.word), ['alpha', 'beta', 'gamma', 'delta']);

      final all = SpellingRound.compose(
        learnedToday: learned,
        queued: queued,
        due: due,
        cap: 30,
      );
      expect(all.length, 6);
      expect(all.last.word, 'zeta');
    });

    test('同一个词出现两批里只算一次', () {
      final items = SpellingRound.compose(
        learnedToday: [mkItem('alpha')],
        queued: [mkItem('Alpha', key: 'alpha'), mkItem('beta')],
        due: [mkItem('beta'), mkItem('gamma')],
        cap: 30,
      );
      expect(items.map((e) => e.wordKey), ['alpha', 'beta', 'gamma']);
    });

    test('cap 为 0（每日目标异常）时一轮为空', () {
      expect(
        SpellingRound.compose(
          learnedToday: [mkItem('alpha')],
          queued: const [],
          due: const [],
          cap: 0,
        ),
        isEmpty,
      );
    });
  });

  // ------------------------------------------------------------ 页面
  group('拼写页', () {
    testWidgets('首题：读一遍词、显示累计正确率与进度', (tester) async {
      final said = <String>[];
      final store = FakeStore(
        items: [mkItem('abandon'), mkItem('take advantage of')],
        stats: const SpellingStats(rounds: 12, total: 30, correct: 27),
      );
      await tester.pumpWidget(
        wrapApp(SpellingPage(store: store, speak: (t) async {
          said.add(t);
          return true;
        })),
      );
      await tester.pump();
      await tester.pump();

      expect(said, ['abandon']); // 进页面自动读一遍
      expect(find.text('第 1 / 2 题'), findsOneWidget);
      expect(find.text('累计正确率 90% · 12 轮 30 题'), findsOneWidget);
      expect(find.byKey(const ValueKey('spelling-input')), findsOneWidget);
    });

    testWidgets('重听不限次数、不扣分，答对照样算对', (tester) async {
      final said = <String>[];
      final store = FakeStore(items: [mkItem('abandon')]);
      await tester.pumpWidget(
        wrapApp(SpellingPage(store: store, speak: (t) async {
          said.add(t);
          return true;
        })),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('spelling-replay')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('spelling-replay')));
      await tester.pump();
      expect(said, ['abandon', 'abandon', 'abandon']);

      await tester.enterText(
        find.byKey(const ValueKey('spelling-input')),
        'abandon',
      );
      await tester.tap(find.byKey(const ValueKey('spelling-submit')));
      await tester.pump();
      expect(find.text('对了'), findsOneWidget);
      // 重听两次没有把这一题算错
      expect(store.calls, isNot(contains('saveRound(1,0)')));
      await tester.pump(SpellingPage.autoAdvance);
      await tester.pump();
      expect(find.byKey(const ValueKey('spelling-summary')), findsOneWidget);
      expect(store.calls, contains('saveRound(1,1)'));
    });

    testWidgets('判对：显示对了 + 正确拼写，1 秒后自动进下一题', (tester) async {
      final store = FakeStore(
        items: [mkItem('abandon'), mkItem('prompt')],
      );
      await tester.pumpWidget(wrapApp(SpellingPage(store: store, speak: _speakOk)));
      await tester.pump();
      await tester.pump();

      // 大小写 + 多余空格都算对
      await tester.enterText(
        find.byKey(const ValueKey('spelling-input')),
        '  ABANDON ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('对了'), findsOneWidget);
      expect(find.byKey(const ValueKey('spelling-answer')), findsOneWidget);
      expect(find.text('abandon'), findsOneWidget);
      expect(find.text('第 1 / 2 题'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 999));
      expect(find.text('第 1 / 2 题'), findsOneWidget); // 还没到 1 秒
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('第 2 / 2 题'), findsOneWidget);
      expect(find.text('对了'), findsNothing);
    });

    testWidgets('判对后也能手动提前下一题', (tester) async {
      final store = FakeStore(items: [mkItem('abandon'), mkItem('prompt')]);
      await tester.pumpWidget(wrapApp(SpellingPage(store: store, speak: _speakOk)));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('spelling-input')),
        'abandon',
      );
      await tester.tap(find.byKey(const ValueKey('spelling-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('spelling-next')));
      await tester.pump();
      expect(find.text('第 2 / 2 题'), findsOneWidget);
    });

    testWidgets('判错：正确拼写 + 音标 + 释义 + 你拼的是，且不自动跳', (tester) async {
      final store = FakeStore(
        items: [
          mkItem('abandon', phonetic: '/əˈbændən/', meaning: 'vt. 放弃，抛弃'),
          mkItem('prompt'),
        ],
      );
      await tester.pumpWidget(wrapApp(SpellingPage(store: store, speak: _speakOk)));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('spelling-input')),
        'abandan',
      );
      await tester.tap(find.byKey(const ValueKey('spelling-submit')));
      await tester.pump();

      expect(find.text('错了'), findsOneWidget);
      expect(find.text('abandon'), findsOneWidget);
      expect(find.text('/əˈbændən/'), findsOneWidget);
      expect(find.text('vt. 放弃，抛弃'), findsOneWidget);
      expect(find.text('你拼的是 abandan'), findsOneWidget);

      // 判错不自动跳：过两秒还停在这一题
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('第 1 / 2 题'), findsOneWidget);
      expect(find.text('错了'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spelling-next')));
      await tester.pump();
      expect(find.text('第 2 / 2 题'), findsOneWidget);
    });

    testWidgets('最后一题答完进小结，成绩只写一笔', (tester) async {
      final store = FakeStore(items: [mkItem('abandon')]);
      await tester.pumpWidget(wrapApp(SpellingPage(store: store, speak: _speakOk)));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('spelling-input')),
        'abandan',
      );
      await tester.tap(find.byKey(const ValueKey('spelling-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('spelling-next')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('spelling-summary')), findsOneWidget);
      expect(find.text('对了 0 题 / 共 1 题'), findsOneWidget);
      expect(find.text('正确率 0%'), findsOneWidget);
      expect(find.byKey(const ValueKey('spelling-wrong-abandon')),
          findsOneWidget);
      expect(store.saves, ['saveRound(1,0)']);
      // 存完成绩后顶部累计正确率跟着变成 0%
      expect(find.text('累计正确率 0% · 1 轮 1 题'), findsOneWidget);
    });

    testWidgets('没词可拼：页面明说「今天没词可拼」，不进死循环', (tester) async {
      final store = FakeStore(items: const []);
      await tester.pumpWidget(wrapApp(SpellingPage(store: store, speak: _speakOk)));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('spelling-empty')), findsOneWidget);
      expect(find.text('今天没词可拼'), findsOneWidget);
      expect(find.byKey(const ValueKey('spelling-input')), findsNothing);
    });

    testWidgets('320 宽：长短语判错也不溢出（真实字体）', (tester) async {
      // 测试默认字体是 Ahem 方块字，宽度不可信 —— 版式实测必须加载真字体
      // （踩坑：v0.7.9 用 Ahem 量出来「不溢出」，真机却不是那么回事）。
      final loader = FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.otf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Bold.otf'));
      await tester.runAsync(() async {
        await loader.load();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = FakeStore(
        items: [
          mkItem(
            'once (and) for all',
            phonetic: '/wʌns ænd fɔːr ɔːl/',
            meaning: 'phr. 一劳永逸地，一次性彻底地',
          ),
        ],
      );
      await tester.pumpWidget(wrapApp(SpellingPage(store: store, speak: _speakOk)));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('spelling-input')),
        'once for alll',
      );
      await tester.tap(find.byKey(const ValueKey('spelling-submit')));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 小结（错词行也是长短语）同样不能溢出。320×640 下结果块在折叠线以下，
      // 先滚到按钮再点 —— 真机上这一步由人滑。
      await tester.ensureVisible(find.byKey(const ValueKey('spelling-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('spelling-next')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('spelling-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 首页那颗入口在 320 宽下也不许挤
      await tester.pumpWidget(
        wrapApp(
          const Scaffold(
            body: SpellingLink(count: 30, onTap: _noop),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ 小结
  group('小结', () {
    testWidgets('对了 X / 共 N、正确率、错词清单点一条进详情页', (tester) async {
      final opened = <String>[];
      final attempts = [
        SpellingAttempt(item: mkItem('abandon'), input: 'abandan', correct: false),
        SpellingAttempt(item: mkItem('prompt'), input: 'PROMPT', correct: true),
        SpellingAttempt(
          item: mkItem('take advantage of', meaning: 'phr. 利用'),
          input: 'take advantage',
          correct: false,
        ),
      ];
      await tester.pumpWidget(
        wrapApp(
          SingleChildScrollView(
            child: SpellingSummary(
              attempts: attempts,
              onOpenWord: (item) => opened.add(item.wordKey),
              onRetry: () {},
              onDone: () {},
            ),
          ),
        ),
      );

      expect(find.text('这一轮拼完了'), findsOneWidget);
      expect(find.text('对了 1 题 / 共 3 题'), findsOneWidget);
      expect(find.text('正确率 33%'), findsOneWidget);
      expect(find.text('错词 2 个'), findsOneWidget);

      // 每条错词：错拼 → 正确拼写 + 音标 + 释义
      expect(find.text('你拼的是 abandan'), findsOneWidget);
      expect(find.text('abandon'), findsOneWidget);
      expect(find.text('/abandon/  n. abandon 的释义'), findsOneWidget);
      expect(find.text('你拼的是 take advantage'), findsOneWidget);
      expect(find.text('take advantage of'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spelling-wrong-abandon')));
      expect(opened, ['abandon']);
      await tester.tap(
        find.byKey(const ValueKey('spelling-wrong-take advantage of')),
      );
      expect(opened, ['abandon', 'take advantage of']);
    });

    testWidgets('全对时写「没有错词」', (tester) async {
      await tester.pumpWidget(
        wrapApp(
          SingleChildScrollView(
            child: SpellingSummary(
              attempts: [
                SpellingAttempt(
                  item: mkItem('prompt'),
                  input: 'prompt',
                  correct: true,
                ),
              ],
              onOpenWord: (_) {},
              onRetry: () {},
              onDone: () {},
            ),
          ),
        ),
      );
      expect(find.text('对了 1 题 / 共 1 题'), findsOneWidget);
      expect(find.text('正确率 100%'), findsOneWidget);
      expect(find.text('没有错词'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ 首页入口
  group('首页入口', () {
    test('文案：有词报数量，没词明说没词', () {
      expect(SpellingLink.labelFor(-1), '拼写练习');
      expect(SpellingLink.labelFor(0), '今天没词可拼');
      expect(SpellingLink.labelFor(30), '拼写练习 · 今天 30 词');
    });

    testWidgets('今天没词：置灰且点不动', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrapApp(
          Scaffold(
            body: SpellingLink(count: 0, onTap: null),
          ),
        ),
      );
      expect(find.text('今天没词可拼'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('spelling-link')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('spelling-link')));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('有词：显示数量、点了进拼写页', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrapApp(
          Scaffold(
            body: SpellingLink(count: 12, onTap: () => taps++),
          ),
        ),
      );
      expect(find.text('拼写练习 · 今天 12 词'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('spelling-link')));
      await tester.pump();
      expect(taps, 1);
    });
  });

  // ------------------------------------------------------------ 不动调度
  group('拼写不动调度', () {
    test('页面与数据层没有写学习数据的语句', () {
      // 只看代码行，注释里提到表名不算（这一层的文档就在说「不写这三张表」）。
      String codeOf(String path) => File(path)
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      final dao = codeOf('lib/data/dao/spelling_dao.dart');
      final page = codeOf('lib/features/spelling/spelling_page.dart');
      final model = codeOf('lib/data/spelling/spelling_round.dart');

      // 三张学习表一个字节都不写：拼写只用 SELECT 读词
      expect(dao.contains("insert('study_record'"), isFalse);
      expect(dao.contains("update('study_record'"), isFalse);
      expect(dao.contains('daily_stat'), isFalse);
      expect(dao.contains('study_log'), isFalse);
      expect(dao.contains('INSERT INTO study'), isFalse);
      expect(dao.contains('UPDATE study'), isFalse);
      expect(dao.contains('DELETE FROM study'), isFalse);
      // 不碰 Leitner、不碰答题方法
      expect(page.contains('Leitner'), isFalse);
      expect(model.contains('Leitner'), isFalse);
      expect(page.contains('.answer('), isFalse);
      // 唯一的写入目标是拼写自己的表
      expect(dao.contains("insert('spelling_round'"), isTrue);
    });

    testWidgets('一轮只交一笔成绩，没有别的写库动作', (tester) async {
      final store = FakeStore(
        items: [mkItem('abandon'), mkItem('prompt')],
      );
      await runRound(tester, store);
      expect(store.saves, ['saveRound(2,1)']);
      expect(
        store.calls.where(
          (c) => c != 'load' && c != 'stats' && c != 'saveRound(2,1)',
        ),
        isEmpty,
      );
    });
  });
}

/// 跑完一整轮（第一题错、第二题对），用来断言写库动作。
Future<void> runRound(WidgetTester tester, FakeStore store) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: SpellingPage(store: store, speak: _speakOk)),
  );
  await tester.pump();
  await tester.pump();

  await tester.enterText(
    find.byKey(const ValueKey('spelling-input')),
    'wrong',
  );
  await tester.tap(find.byKey(const ValueKey('spelling-submit')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('spelling-next')));
  await tester.pump();

  await tester.enterText(
    find.byKey(const ValueKey('spelling-input')),
    'prompt',
  );
  await tester.tap(find.byKey(const ValueKey('spelling-submit')));
  await tester.pump();
  await tester.pump(SpellingPage.autoAdvance);
  await tester.pump();
}

/// 假题源 / 假成绩单。
class FakeStore implements SpellingStore {
  FakeStore({
    this.items = const [],
    SpellingStats stats = SpellingStats.empty,
  }) {
    _stats = stats;
  }

  final List<SpellingItem> items;
  late SpellingStats _stats;

  /// 所有调用（含参数），用来断言「只写了成绩这一笔」。
  final List<String> calls = [];

  /// 只记保存，方便断言。
  final List<String> saves = [];

  @override
  Future<List<SpellingItem>> loadItems({DateTime? now}) async {
    calls.add('load');
    return items;
  }

  @override
  Future<SpellingStats> stats() async {
    calls.add('stats');
    return _stats;
  }

  @override
  Future<void> saveRound({
    required int total,
    required int correct,
    DateTime? now,
  }) async {
    final tag = 'saveRound($total,$correct)';
    calls.add(tag);
    saves.add(tag);
    _stats = SpellingStats(
      rounds: _stats.rounds + 1,
      total: _stats.total + total,
      correct: _stats.correct + correct,
    );
  }
}

/// 假 TTS：测试里永远读得出来，不碰 MethodChannel、不弹提示条。
Future<bool> _speakOk(String text) async => true;

void _noop() {}
