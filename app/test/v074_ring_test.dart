import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/features/study/progress_ring.dart';
import 'package:mw_english/features/study/today_card.dart';

/// v0.7.4 进度环。
///
/// 断言取自需求原文：
/// - 直径 176、线宽 14、圆头端点，轨道墨 10%，填充 #E8490F（v0.7.8 放大，
///   原 132 / 12）
/// - 填充比例 = 今日新词已学 / 目标，与环里的数字同一份数据
/// - 动效走 LiquidGlass.spring（300 / 24 / 0.8），不是线性；数值变化时
///   从旧值扫到新值，不从 0 重播
void main() {
  TodayStats stats({
    int learned = 13,
    int target = 30,
    int due = 4,
    int wrong = 2,
  }) {
    return TodayStats(
      newLearned: learned,
      newTarget: target,
      dueReview: due,
      wrongToday: wrong,
      totalLearned: 0,
      mastered: 0,
      gapDays: 0,
      reduced: false,
    );
  }

  Future<void> pumpCard(WidgetTester tester, TodayCard card) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: card,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpRing(WidgetTester tester, double value) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: ProgressRing(value: value))),
      ),
    );
  }

  ProgressRingPainter painterOf(WidgetTester tester) {
    final paints = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(ProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .toList();
    return paints.first.painter! as ProgressRingPainter;
  }

  testWidgets('环的比例就是「已学 / 目标」，环里数字是同一份数据', (tester) async {
    await pumpCard(tester, TodayCard(stats: stats(), loading: false));

    final ring = tester.widget<ProgressRing>(find.byType(ProgressRing));
    expect(ring.value, closeTo(13 / 30, 1e-9));
    expect(painterOf(tester).progress, closeTo(13 / 30, 0.005),
        reason: '画出来的弧长要跟数字对得上');

    // 环里的数字。三格数字里也有一份「13」（新词），所以限定在环内找。
    expect(
      find.descendant(of: find.byType(ProgressRing), matching: find.text('13')),
      findsOneWidget,
    );
    expect(find.text('/ 30'), findsOneWidget);
  });

  testWidgets('断档削减配额时分母跟着变，不写死 30', (tester) async {
    // 断档 5 天回来，当天只给 6 个新词。上面写「目标 6 词」，
    // 环里就必须是「/ 6」、比例按 6 算。
    await pumpCard(
      tester,
      TodayCard(stats: stats(learned: 3, target: 6), loading: false),
    );

    final ring = tester.widget<ProgressRing>(find.byType(ProgressRing));
    expect(ring.value, closeTo(3 / 6, 1e-9));
    expect(find.text('/ 6'), findsOneWidget);
    expect(find.text('目标 6 词'), findsOneWidget);
  });

  testWidgets('超过目标时比例夹到 1，不会画回头', (tester) async {
    await pumpCard(
      tester,
      TodayCard(stats: stats(learned: 40, target: 30), loading: false),
    );
    expect(
      tester.widget<ProgressRing>(find.byType(ProgressRing)).value,
      1.0,
    );
  });

  testWidgets('尺寸与线宽：直径 176、线宽 14、轨道墨 10%、填充暖橙（v0.7.8 放大）',
      (tester) async {
    await pumpCard(tester, TodayCard(stats: stats(), loading: false));

    // v0.7.8 首页主角化：132 / 12 → 176 / 14（原值见 git 历史）。
    expect(ProgressRing.diameter, 176);
    expect(ProgressRing.stroke, 14);
    expect(ProgressRing.track, const Color(0x1A0B0C10));
    expect(AppColors.ringOrange, const Color(0xFFE8490F));
    expect(painterOf(tester).color, AppColors.ringOrange);

    final size = tester.getSize(find.byType(ProgressRing));
    expect(size.width, 176);
    expect(size.height, 176);
    expect(painterOf(tester).strokeWidth, 14);
  });

  test('落位走的是全 App 那条弹簧（300 / 24 / 0.8），不是别的曲线', () {
    final sim = ProgressRing.simulation(0, 1);
    expect(sim, isA<SpringSimulation>());

    // SpringSimulation 不暴露 spring 字段，直接拿同一个 SpringDescription
    // 造一条参照曲线，逐点比 x(t) —— 一样就说明参数一样。
    final reference = SpringSimulation(LiquidGlass.spring, 0, 1, 0);
    for (final t in <double>[0.02, 0.06, 0.12, 0.2, 0.3]) {
      expect(sim.x(t), closeTo(reference.x(t), 1e-9), reason: 't = $t');
    }

    expect(LiquidGlass.spring.stiffness, 300);
    expect(LiquidGlass.spring.damping, 24);
    expect(LiquidGlass.spring.mass, 0.8);
  });

  test('轨迹是曲线不是直线：二阶差分不为 0', () {
    final sim = ProgressRing.simulation(0, 1);
    final second = (sim.x(0.06) - 2 * sim.x(0.03) + sim.x(0)).abs();
    expect(second, greaterThan(0.01),
        reason: '匀速直线插值的二阶差分是 0；弹簧不该是 0');
  });

  testWidgets('首次出现从 0 扫到当前值', (tester) async {
    await pumpRing(tester, 0.6);
    await tester.pump();
    expect(painterOf(tester).progress, lessThan(0.05), reason: '起手是 0');

    await tester.pump(const Duration(milliseconds: 120));
    final mid = painterOf(tester).progress;
    expect(mid, greaterThan(0.1), reason: '120ms 应该已经扫出一段');
    expect(mid, lessThan(0.6), reason: '还没到终点');

    await tester.pumpAndSettle();
    expect(painterOf(tester).progress, closeTo(0.6, 0.005));
  });

  testWidgets('数值变化从旧值扫起，不从 0 重播', (tester) async {
    await pumpRing(tester, 0.2);
    await tester.pumpAndSettle();
    expect(painterOf(tester).progress, closeTo(0.2, 0.005));

    await pumpRing(tester, 0.5);
    await tester.pump();
    expect(painterOf(tester).progress, greaterThan(0.15),
        reason: '起点应该是 0.2，不是 0');

    await tester.pumpAndSettle();
    expect(painterOf(tester).progress, closeTo(0.5, 0.005));
  });

  testWidgets('细进度条已经撤掉', (tester) async {
    await pumpCard(tester, TodayCard(stats: stats(), loading: false));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
