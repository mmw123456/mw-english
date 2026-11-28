import 'dart:io';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/dao/stats_dao.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/data/stats/stats_snapshot.dart';
import 'package:mw_english/data/study/mastery.dart';
import 'package:mw_english/features/stats/stats_page.dart';

/// v0.14.0 学习统计：口径统一 + 快照算法 + 五块内容 + 缺数据的显示。
///
/// 统计页依赖 SQLite，测试环境打不开库，所以数字全部走 [StatsStore] 注入。
/// 页面只管把 store 给的数摆出来 —— 所以「数字对不对」在这里验口径与算法，
/// 「查得对不对」在 `_source/check_v140.py` 里验 SQL 与不变量。
void main() {
  Widget wrapApp(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: child);

  StatsSnapshot mkSnap({
    String todayKey = '2026-11-28',
    Map<String, DayTotal> totals = const {},
    int totalDays = 0,
    int streak = 0,
    int learnedWords = 0,
    int mastered = 0,
    List<int> boxes = const [820, 0, 0, 0, 0, 0, 0],
    int killed = 0,
    int poolTotal = 820,
    int todaySpellTotal = 0,
    int todaySpellCorrect = 0,
    int spellAllTotal = 0,
    int spellAllCorrect = 0,
    int spell7Total = 0,
    int spell7Correct = 0,
  }) =>
      StatsSnapshot(
        todayKey: todayKey,
        totals: totals,
        totalDays: totalDays,
        streak: streak,
        learnedWords: learnedWords,
        mastered: mastered,
        boxes: boxes,
        killed: killed,
        poolTotal: poolTotal,
        todaySpellTotal: todaySpellTotal,
        todaySpellCorrect: todaySpellCorrect,
        spellAllTotal: spellAllTotal,
        spellAllCorrect: spellAllCorrect,
        spell7Total: spell7Total,
        spell7Correct: spell7Correct,
      );

  /// 五块内容一屏放不下（ListView 只建可见项），默认给一块够高的画布，
  /// 免得断言「找不到某块」是因为它还没被建出来。要验版式的用例自己传尺寸。
  Future<void> pumpPage(
    WidgetTester tester,
    StatsSnapshot snap, {
    Size size = const Size(420, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 同一个测试里换快照要重新挂载：State 复用会留着上一份 _snap。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      wrapApp(StatsPage(store: _FakeStats(snap), now: DateTime(2026, 11, 28))),
    );
    await tester.pump();
    await tester.pump();
  }

  // ------------------------------------------------------------ 已掌握口径
  group('已掌握口径（全 App 一处）', () {
    test('箱位到 5 就算（不必等箱 6）', () {
      expect(Mastery.of(5, 0), isTrue);
      expect(Mastery.of(6, 0), isTrue);
    });

    test('连对 3 次也算（箱位低但记住了）', () {
      expect(Mastery.of(0, 3), isTrue);
      expect(Mastery.of(4, 3), isTrue);
    });

    test('两个门槛都不够就不算', () {
      expect(Mastery.of(4, 2), isFalse);
      expect(Mastery.of(0, 0), isFalse);
    });

    test('SQL 片段与 Dart 判定用同一组门槛', () {
      final sql = Mastery.sqlWhere;
      expect(sql.contains('started = 1'), isTrue); // 空壳记录不算
      expect(sql.contains('killed = 0'), isTrue); // 已斩不算已掌握
      expect(sql.contains('box >= ${Mastery.boxCut}'), isTrue);
      expect(sql.contains('streak >= ${Mastery.streakCut}'), isTrue);
    });

    test('四处都走同一处口径，没人再写一遍 box >= 5', () {
      String codeOf(String path) => File(path)
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .where((line) => !line.trimLeft().startsWith('///'))
          .join('\n');

      // 学习页 / 我的页的「已掌握」来自 StudyDao.todayStats
      final study = codeOf('lib/data/dao/study_dao.dart');
      expect(study.contains(r'${Mastery.sqlWhere}'), isTrue);
      expect(study.contains('box >= ?'), isFalse); // 旧的单独门槛已删

      // 统计页
      final stats = codeOf('lib/data/dao/stats_dao.dart');
      expect(stats.contains(r'${Mastery.sqlWhere}'), isTrue);

      // 文章取词（决策 117）
      final picker = codeOf('lib/data/article/word_picker.dart');
      expect(picker.contains('Mastery.of(box, streak)'), isTrue);

      // 全库只有 mastery.dart 允许出现字面门槛
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('lib/data/study/mastery.dart')) continue;
        final code = codeOf(f.path);
        if (code.contains('box >= 5') || code.contains('streak >= 3')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '这些文件自己写了已掌握门槛：$offenders');
    });
  });

  // ------------------------------------------------------------ 快照算法
  group('快照算法', () {
    test('七段之和 + 已斩 = 学习池（验收口径）', () {
      final snap = mkSnap(
        boxes: const [574, 40, 39, 40, 40, 40, 39],
        killed: 10,
        poolTotal: 822,
      );
      expect(snap.boxSum, 812);
      expect(snap.boxSum + snap.killed, snap.poolTotal);
    });

    test('没拼过就是 null，不是 0%', () {
      expect(mkSnap().todaySpellPercent, isNull);
      expect(mkSnap().spellAllPercent, isNull);
      expect(mkSnap().spell7Percent, isNull);
    });

    test('正确率四舍五入，与拼写页同一套算法', () {
      expect(mkSnap(todaySpellTotal: 3, todaySpellCorrect: 2).todaySpellPercent, 67);
      expect(mkSnap(spellAllTotal: 480, spellAllCorrect: 418).spellAllPercent, 87);
      expect(mkSnap(spell7Total: 30, spell7Correct: 30).spell7Percent, 100);
    });

    test('没记录的日子 total 为 null，不补 0', () {
      final snap = mkSnap(
        totals: {
          '2026-11-26': const DayTotal(newWords: 12, reviews: 30),
          '2026-11-28': const DayTotal(newWords: 8, reviews: 4),
        },
      );
      final slots = snap.slots(7);
      expect(slots.length, 7);
      expect(slots.last.day, '2026-11-28');
      expect(slots[4].day, '2026-11-26');
      expect(slots[4].hasData, isTrue);
      expect(slots[4].total!.newWords, 12);
      // 11-27、11-25 都没记录：是「没有」不是「0」
      expect(slots[5].day, '2026-11-27');
      expect(slots[5].total, isNull);
      expect(slots[3].total, isNull);
      expect(snap.activeDays(7), 2);
    });

    test('跨月跨年往回数不越界', () {
      final snap = mkSnap(todayKey: '2026-01-01');
      final slots = snap.slots(7);
      expect(slots.first.day, '2025-12-26');
      expect(slots.last.day, '2026-01-01');
    });

    test('全空窗口的峰值是 0（页面不要拿它做除数）', () {
      expect(mkSnap().maxOf(7), 0);
      expect(mkSnap().maxOf(30), 0);
    });

    test('峰值取窗口内单日最大完成量', () {
      final snap = mkSnap(
        totals: {
          '2026-11-27': const DayTotal(newWords: 5, reviews: 10),
          '2026-11-28': const DayTotal(newWords: 30, reviews: 0),
        },
      );
      expect(snap.maxOf(7), 30);
      expect(snap.today.total, 30);
    });

    test('一条记录都没有时才算「没有历史」', () {
      expect(mkSnap().noHistory, isTrue);
      expect(mkSnap(totalDays: 3).noHistory, isFalse);
      expect(mkSnap(learnedWords: 1).noHistory, isFalse);
    });
  });

  // ------------------------------------------------------------ 页面
  group('页面五块', () {
    testWidgets('今日四个数来自 store', (tester) async {
      await pumpPage(
        tester,
        mkSnap(
          totals: {'2026-11-28': const DayTotal(newWords: 30, reviews: 47)},
          todaySpellTotal: 20,
          todaySpellCorrect: 17,
        ),
      );
      String? textOf(String key) => (tester.widget<Text>(
            find.byKey(ValueKey(key)),
          ))
          .data;

      expect(textOf('stats-today-new'), '30');
      expect(textOf('stats-today-review'), '47');
      expect(textOf('stats-today-spell'), '20');
      expect(textOf('stats-today-spell-percent'), '85%');
    });

    testWidgets('今天没拼过：正确率显「—」而不是 0%', (tester) async {
      await pumpPage(tester, mkSnap());
      final cell = tester.widget<Text>(
        find.byKey(const ValueKey('stats-today-spell-percent')),
      );
      expect(cell.data, '—');
    });

    testWidgets('累计四个数', (tester) async {
      await pumpPage(
        tester,
        mkSnap(totalDays: 12, streak: 4, learnedWords: 355, mastered: 96),
      );
      String? textOf(String key) =>
          tester.widget<Text>(find.byKey(ValueKey(key))).data;
      expect(textOf('stats-total-days'), '12');
      expect(textOf('stats-streak'), '4');
      expect(textOf('stats-learned'), '355');
      expect(textOf('stats-mastered'), '96');
    });

    testWidgets('箱 0–6 七行都显数字，含合计与已斩', (tester) async {
      await pumpPage(
        tester,
        mkSnap(
          boxes: const [574, 40, 39, 40, 40, 40, 39],
          killed: 10,
          poolTotal: 822,
        ),
      );
      for (var box = 0; box <= 6; box++) {
        expect(
          find.byKey(ValueKey('stats-box-$box')),
          findsOneWidget,
          reason: '箱 $box 没有数字',
        );
      }
      final sum = tester.widget<Text>(
        find.byKey(const ValueKey('stats-box-sum')),
      );
      expect(sum.data, contains('合计 812 词'));
      expect(sum.data, contains('已斩 10'));
      expect(sum.data, contains('学习池 822'));
      // 标题按箱位写，不写「六箱」
      expect(find.text('箱 0–6 分布'), findsOneWidget);
      expect(find.textContaining('箱 0 = 新词'), findsOneWidget);
    });

    testWidgets('趋势默认 7 天，可切到 30 天', (tester) async {
      await pumpPage(
        tester,
        mkSnap(
          totals: {'2026-11-28': const DayTotal(newWords: 8, reviews: 4)},
          totalDays: 1,
        ),
      );
      expect(find.text('最近 7 天'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-bar-2026-11-28')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stats-range-30')));
      await tester.pump();
      expect(find.text('最近 30 天'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-bar-2026-11-28')), findsOneWidget);
      // 30 天档里 7 天以前的空天不画柱
      expect(find.byKey(const ValueKey('stats-bar-2026-11-01')), findsNothing);
    });

    testWidgets('没记录的天不画柱（不是画 0 高柱）', (tester) async {
      await pumpPage(
        tester,
        mkSnap(
          totals: {
            '2026-11-26': const DayTotal(newWords: 0, reviews: 30),
            '2026-11-28': const DayTotal(newWords: 8, reviews: 0),
          },
          totalDays: 2,
        ),
      );
      expect(find.byKey(const ValueKey('stats-bar-2026-11-26')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-bar-2026-11-27')), findsNothing);
      expect(find.byKey(const ValueKey('stats-bar-2026-11-28')), findsOneWidget);
    });

    testWidgets('一条历史都没有：写「从今天起开始记录」', (tester) async {
      await pumpPage(tester, mkSnap());
      expect(find.byKey(const ValueKey('stats-empty-hint')), findsOneWidget);
      expect(find.text('从今天起开始记录'), findsOneWidget);
    });

    testWidgets('有历史但这一档全空：不冒充没有历史', (tester) async {
      await pumpPage(
        tester,
        mkSnap(totalDays: 40, learnedWords: 300),
      );
      expect(find.byKey(const ValueKey('stats-empty-hint')), findsNothing);
      expect(find.byKey(const ValueKey('stats-blank-window')), findsOneWidget);
      expect(find.text('最近 7 天没有学习记录'), findsOneWidget);
    });

    testWidgets('拼写：没记录写「暂无数据」，有记录给累计与最近 7 天', (tester) async {
      await pumpPage(tester, mkSnap());
      expect(find.byKey(const ValueKey('stats-spell-empty')), findsOneWidget);
      expect(find.text('暂无数据'), findsOneWidget);

      await pumpPage(
        tester,
        mkSnap(
          spellAllTotal: 480,
          spellAllCorrect: 418,
          spell7Total: 60,
          spell7Correct: 51,
        ),
      );
      String? textOf(String key) =>
          tester.widget<Text>(find.byKey(ValueKey(key))).data;
      expect(textOf('stats-spell-all'), '87%');
      expect(textOf('stats-spell-7'), '85%');
      expect(find.textContaining('共 480 题'), findsOneWidget);
    });

    testWidgets('读库失败不白屏：明说读不到', (tester) async {
      await tester.pumpWidget(
        wrapApp(StatsPage(store: _FailingStats(), now: DateTime(2026, 11, 28))),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('读不到统计数据'), findsOneWidget);
    });

    testWidgets('320 宽 + 真实字体：七行分布与 30 天档都不溢出', (tester) async {
      // 测试默认字体是 Ahem 方块字，宽度不可信 —— 版式结论必须用真字体跑。
      final loader = FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.otf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Bold.otf'));
      await tester.runAsync(() async {
        await loader.load();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      await pumpPage(
        tester,
        mkSnap(
          totals: {
            for (var i = 0; i < 30; i++)
              StudyDao.dayKey(DateTime(2026, 10, 30 + i)):
                  DayTotal(newWords: i, reviews: 30 - i),
          },
          totalDays: 30,
          streak: 30,
          learnedWords: 820,
          mastered: 400,
          boxes: const [420, 100, 100, 100, 50, 30, 20],
          killed: 0,
          poolTotal: 820,
          todaySpellTotal: 30,
          todaySpellCorrect: 27,
          spellAllTotal: 480,
          spellAllCorrect: 418,
          spell7Total: 60,
          spell7Correct: 51,
        ),
        size: const Size(320, 640),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 一路滑到底：七行分布、趋势、拼写三块在 320 宽下都要过一遍。
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -280));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '第 ${i + 1} 屏溢出');
      }

      // 30 天档也过一遍（柱子最密的时候）
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('stats-range-30')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stats-range-30')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ 入口
  group('入口', () {
    test('我的页有「学习统计」，点开进整页 StatsPage', () {
      final profile =
          File('lib/features/profile/profile_page.dart').readAsStringSync();
      expect(profile.contains("title: '学习统计'"), isTrue);
      expect(profile.contains('StatsPage()'), isTrue);
      expect(profile.contains('_openStats'), isTrue);
      // 不占新 Tab：外壳没动（门禁里另有冻结断言）
      expect(profile.contains('BottomNavigationBar'), isFalse);
    });

    test('统计页是整页 Scaffold，不是弹窗', () {
      final page = File('lib/features/stats/stats_page.dart').readAsStringSync();
      expect(page.contains("AppBar(title: const Text('学习统计'))"), isTrue);
      expect(page.contains('showDialog'), isFalse);
      expect(page.contains('showModalBottomSheet'), isFalse);
    });
  });
}

class _FakeStats implements StatsStore {
  _FakeStats(this.snap);

  final StatsSnapshot snap;

  @override
  Future<StatsSnapshot> load({DateTime? now}) async => snap;
}

class _FailingStats implements StatsStore {
  @override
  Future<StatsSnapshot> load({DateTime? now}) async =>
      throw StateError('db unavailable');
}
