import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/features/study/study_heatmap.dart';

/// v0.7.4 学习热力图。
///
/// 断言取自需求原文：
/// - 最近 12 周 × 7 天，一格一天；月份小字在上方
/// - 没学 = 纸面卡底 + 0.5px 描边；1–9 / 10–19 / 20–29 / 30+ 四档 25/50/75/100%
/// - 点一格，下方小字换成那天的数据
/// - 右上角「连续 N 天」
/// - 区块是纸面卡，不是玻璃
void main() {
  /// 固定「今天」= 2026-11-26（周四）。周四之前 81 天在网格里，之后 3 格空着。
  final now = DateTime(2026, 11, 26);

  Future<void> pumpHeatmap(
    WidgetTester tester, {
    Map<String, DayTotal> totals = const {},
    int streak = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: StudyHeatmap(totals: totals, streak: streak, now: now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cells() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('heat-cell-'),
      );

  testWidgets('12 周 × 7 天：84 个格子，未来那几天不画', (tester) async {
    expect(StudyHeatmap.weeks, 12);
    expect(StudyHeatmap.daysPerWeek, 7);

    await pumpHeatmap(tester);

    // 2026-11-26 是周四（weekday = 4），本周只剩周五 / 周六 / 周日没到。
    expect(cells(), findsNWidgets(84 - 3));
    expect(find.byKey(const ValueKey('heat-cell-2026-11-26')), findsOneWidget);
    expect(find.byKey(const ValueKey('heat-cell-2026-11-27')), findsNothing,
        reason: '明天还没发生，不能画成「没学」');
  });

  testWidgets('没学的那天：纸面卡底 + 0.5px 描边', (tester) async {
    await pumpHeatmap(tester);

    final cell = tester.widget<Container>(
      find.byKey(const ValueKey('heat-cell-2026-11-25')),
    );
    final deco = cell.decoration! as BoxDecoration;
    expect(deco.color, AppColors.surface);
    expect(deco.border, isNotNull);
    expect((deco.border! as Border).top.width, 0.5);
  });

  testWidgets('有数据的天按四档上色，学习量为新词 + 复习', (tester) async {
    await pumpHeatmap(
      tester,
      totals: <String, DayTotal>{
        '2026-11-25': const DayTotal(newWords: 20, reviews: 8), // 28 → 75%
        '2026-11-24': const DayTotal(newWords: 4, reviews: 2), // 6 → 25%
      },
    );

    final d75 = tester
        .widget<Container>(find.byKey(const ValueKey('heat-cell-2026-11-25')))
        .decoration! as BoxDecoration;
    expect(d75.color, AppColors.accentBlue.withValues(alpha: 0.75));

    final d25 = tester
        .widget<Container>(find.byKey(const ValueKey('heat-cell-2026-11-24')))
        .decoration! as BoxDecoration;
    expect(d25.color, AppColors.accentBlue.withValues(alpha: 0.25));
    expect(d25.border, isNull, reason: '有颜色就不再加描边');
  });

  test('色阶四档的边界', () {
    expect(StudyHeatmap.colorFor(0), AppColors.surface);
    expect(StudyHeatmap.colorFor(1).a, closeTo(0.25, 0.01));
    expect(StudyHeatmap.colorFor(9).a, closeTo(0.25, 0.01));
    expect(StudyHeatmap.colorFor(10).a, closeTo(0.50, 0.01));
    expect(StudyHeatmap.colorFor(19).a, closeTo(0.50, 0.01));
    expect(StudyHeatmap.colorFor(20).a, closeTo(0.75, 0.01));
    expect(StudyHeatmap.colorFor(29).a, closeTo(0.75, 0.01));
    expect(StudyHeatmap.colorFor(30), AppColors.accentBlue);
    expect(StudyHeatmap.colorFor(120), AppColors.accentBlue);
  });

  testWidgets('点一格，下方小字换成那天的数据', (tester) async {
    await pumpHeatmap(
      tester,
      totals: <String, DayTotal>{
        '2026-11-25': const DayTotal(newWords: 20, reviews: 8),
      },
    );

    expect(find.text('11月26日 · 没学'), findsOneWidget,
        reason: '没点之前显示今天');

    await tester.tap(find.byKey(const ValueKey('heat-cell-2026-11-25')));
    await tester.pumpAndSettle();

    expect(find.text('11月25日 · 学了 28 词'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('heatmap-caption')),
      findsOneWidget,
    );
  });

  testWidgets('标题与「连续 N 天」', (tester) async {
    await pumpHeatmap(tester, streak: 5);
    expect(find.text('学习足迹'), findsOneWidget);
    expect(find.text('连续 5 天'), findsOneWidget);
  });

  testWidgets('没有记录时右上角说「还没开始」，不说「连续 0 天」', (tester) async {
    await pumpHeatmap(tester, streak: 0);
    expect(find.text('还没开始'), findsOneWidget);
  });

  testWidgets('区块是纸面卡，不是玻璃', (tester) async {
    await pumpHeatmap(tester);
    expect(find.byType(GlassSurface), findsNothing,
        reason: '内容层不上玻璃，这是全 App 的规则');
  });
}
