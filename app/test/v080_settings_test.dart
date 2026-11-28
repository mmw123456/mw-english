import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/app.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/dao/settings_dao.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/data/models/killed_word.dart';
import 'package:mw_english/data/models/study_card.dart';
import 'package:mw_english/data/study/leitner.dart';
import 'package:mw_english/features/profile/settings_page.dart';
import 'package:mw_english/features/study/study_session_page.dart';
import 'package:mw_english/features/study/today_card.dart';
import 'package:mw_english/features/words/words_page.dart';

/// v0.8.0：自加词进调度 + 斩词入口 + 设置页第一版。
///
/// 纯逻辑与可单独喂数据的 widget 在这里断言；依赖 sqflite 的页面
/// （`SettingsPage` / `WordsPage` / `StudyPage`）不在 `flutter test` 里开库，
/// 只能测它们的公开子组件（同 `TodayCard` / `WordRow` 的处理方式）。
Widget _page(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

StudyCard _card(int i) {
  return StudyCard(
    wordKey: 'w$i',
    word: 'word$i',
    phonetic: '',
    meaning: '释义$i',
    meaningEcdict: '',
    box: 1,
    isNew: false,
    isRetest: false,
    options: <String>['释义$i', '干扰甲$i', '干扰乙$i', '干扰丙$i'],
    answerIndex: 0,
  );
}

void main() {
  group('每日目标', () {
    test('clamp 到 10–50', () {
      expect(SettingsDao.clampDailyTarget(5), 10);
      expect(SettingsDao.clampDailyTarget(10), 10);
      expect(SettingsDao.clampDailyTarget(30), 30);
      expect(SettingsDao.clampDailyTarget(50), 50);
      expect(SettingsDao.clampDailyTarget(99), 50);
    });

    test('断档削减按设置的目标算，不写死 30', () {
      final now = DateTime(2026, 11, 27, 9);
      final base = Leitner.quota(
        lastStudyAt: DateTime(2026, 11, 26, 21),
        now: now,
        base: 15,
      );
      expect(base.newWords, 15);

      final half = Leitner.quota(
        lastStudyAt: DateTime(2026, 11, 24, 21),
        now: now,
        base: 15,
      );
      expect(half.newWords, 8, reason: '断档 3 天：15 的一半向上取整');
      expect(half.reduced, isTrue);

      final spread = Leitner.quota(
        lastStudyAt: DateTime(2026, 11, 19, 21),
        now: now,
        base: 15,
      );
      expect(spread.newWords, 3, reason: '断档 8 天：15/8=1，最低 3');
    });

    testWidgets('目标卡：范围 10–50，松手才回调', (tester) async {
      var saved = 0;
      await tester.pumpWidget(
        _page(DailyTargetCard(target: 30, onChanged: (v) => saved = v)),
      );

      expect(find.text('30 词'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 10);
      expect(slider.max, 50);
      expect(slider.divisions, 40);

      slider.onChanged!(42);
      await tester.pump();
      expect(find.text('42 词'), findsOneWidget);
      expect(saved, 0, reason: '拖动过程中不写库');

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(42);
      expect(saved, 42);
    });

    testWidgets('首页环 / 状态行 / 分母都跟 newTarget 走', (tester) async {
      const stats = TodayStats(
        newLearned: 5,
        newTarget: 15,
        dueReview: 2,
        wrongToday: 1,
        totalLearned: 100,
        mastered: 3,
        gapDays: 0,
        reduced: false,
      );
      await tester.pumpWidget(
        _page(const TodayCard(stats: stats, loading: false)),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('目标 15 词'), findsOneWidget);
      expect(find.text('/ 15'), findsOneWidget);
      expect(find.text('今日已学 5 / 15，还差 10 词'), findsOneWidget);
      expect(find.text('目标 30 词'), findsNothing);
    });
  });

  group('设置行', () {
    testWidgets('整行可点，回调拿到相反值', (tester) async {
      var value = false;
      await tester.pumpWidget(
        _page(
          SettingSwitchRow(
            title: '遮盖中文',
            subtitle: '词库与详情页默认盖住中文释义',
            value: value,
            onChanged: (v) => value = v,
          ),
        ),
      );

      await tester.tap(find.text('遮盖中文'));
      await tester.pump();
      expect(value, isTrue);
    });
  });

  group('已斩', () {
    testWidgets('行内「恢复」能点，箱位点仍在', (tester) async {
      var restored = 0;
      await tester.pumpWidget(
        _page(
          KilledRow(
            entry: const KilledWord(
              wordKey: 'zebra',
              word: 'zebra',
              phonetic: 'zi:brə',
              meaning: '斑马',
              inWorkbook: false,
              isAdded: true,
              box: 3,
            ),
            masked: false,
            revealed: false,
            onToggleMask: () {},
            onRestore: () => restored++,
          ),
        ),
      );

      expect(find.text('zebra'), findsOneWidget);
      expect(find.text('自加'), findsOneWidget);
      await tester.tap(find.text('恢复'));
      expect(restored, 1);
    });

    test('色带箱 0 扣掉已斩：total − 已进箱 − 已斩', () {
      final counts = StudyDao.bandCountsFrom(
        total: 10,
        boxes: <int, int>{1: 2, 3: 1},
        killed: 1,
      );
      expect(counts[0], 6);
      expect(counts[1], 2);
      expect(counts[3], 1);
      expect(counts[2], 0);
      expect(counts[6], 0);
    });

    test('已斩数大于池子时箱 0 兜回 0，不出现负数', () {
      final counts = StudyDao.bandCountsFrom(
        total: 1,
        boxes: <int, int>{1: 1},
        killed: 1,
      );
      expect(counts[0], 0);
      expect(counts.values.every((v) => v >= 0), isTrue);
    });
  });

  group('学习卡片', () {
    testWidgets('「不认识」旁有「斩词」，点开一次确认，取消后不撤卡', (tester) async {
      final session = StudySession(
        cards: <StudyCard>[_card(0)],
        quota: const DailyQuota(newWords: 0, reviewCap: 20, gapDays: 0),
        newCount: 0,
        reviewCount: 1,
        retestCount: 0,
        learnedToday: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StudySessionPage(debugSessionBuilder: () => session),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('不认识'), findsOneWidget);
      expect(find.text('斩词'), findsOneWidget);

      await tester.tap(find.text('斩词'));
      // 不用 pumpAndSettle：学习页的氛围层是 24s 循环动画，永远等不到静止。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('斩掉这个词？'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('斩掉这个词？'), findsNothing);
      expect(find.text('释义0'), findsOneWidget, reason: '取消不该把卡撤掉');
    });
  });

  group('入口与版式', () {
    testWidgets('我的页 → 设置页：三项都在', (tester) async {
      await tester.pumpWidget(const MwEnglishApp());
      await tester.tap(find.text('我的'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('每日新词目标'), findsOneWidget);
      expect(find.text('遮盖中文'), findsOneWidget);
      expect(find.text('自动朗读'), findsOneWidget);
    });

    testWidgets('320 宽：设置卡与已斩行不溢出（真实字体）', (tester) async {
      final loader = FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.otf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Bold.otf'));
      // 字体加载要用真实异步：它随后会发一条「系统字体变了」的消息并排一帧
      // 回调，在 fake async 里等不到。用 runAsync 让它跑完，再泵掉那一帧。
      await tester.runAsync(() async {
        await loader.load();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              children: [
                DailyTargetCard(target: 30, onChanged: (_) {}),
                SettingSwitchRow(
                  title: '自动朗读',
                  subtitle: '每张新卡出现时读一遍单词',
                  value: true,
                  onChanged: (_) {},
                ),
                KilledRow(
                  entry: const KilledWord(
                    wordKey: 'once (and) for all',
                    word: 'once (and) for all',
                    phonetic: 'wʌns ænd fɔːr ɔːl',
                    meaning: '一劳永逸地；一次性彻底解决',
                    inWorkbook: true,
                    isAdded: false,
                    box: 5,
                  ),
                  masked: false,
                  revealed: false,
                  onToggleMask: () {},
                  onRestore: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('320 宽：学习卡两个次按钮并排不溢出（真实字体）', (tester) async {
      final loader = FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.otf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Bold.otf'));
      // 字体加载要用真实异步：它随后会发一条「系统字体变了」的消息并排一帧
      // 回调，在 fake async 里等不到。用 runAsync 让它跑完，再泵掉那一帧。
      await tester.runAsync(() async {
        await loader.load();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = StudySession(
        cards: <StudyCard>[_card(0)],
        quota: const DailyQuota(newWords: 0, reviewCap: 20, gapDays: 0),
        newCount: 0,
        reviewCount: 1,
        retestCount: 0,
        learnedToday: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StudySessionPage(debugSessionBuilder: () => session),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('不认识'), findsOneWidget);
      expect(find.text('斩词'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
