import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/app/widgets/press_scale.dart';
import 'package:mw_english/app/widgets/rolling_int.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/features/study/study_heatmap.dart';
import 'package:mw_english/features/study/study_page.dart';
import 'package:mw_english/features/study/today_card.dart';

/// v0.7.6 细节打磨。
///
/// 断言取自需求原文：
/// - 今天格不许实心黑：底色与空格一致，今天只有一圈 1.5px 描边
/// - 关键数字带 tabular figures（环内数字 / 三格 / 首页三卡）
/// - 环内数字变化时是动画递增，不是瞬间跳变；用的还是那条弹簧
/// - 首页两玻璃按钮有按压缩放（90ms、0.96）
/// - 卡片圆角统一到 [AppTheme.cardRadius]
void main() {
  /// 固定「今天」= 2026-11-26（周四）。
  final now = DateTime(2026, 11, 26);

  TodayStats stats({int learned = 13, int target = 30}) => TodayStats(
        newLearned: learned,
        newTarget: target,
        dueReview: 4,
        wrongToday: 2,
        totalLearned: 0,
        mastered: 0,
        gapDays: 0,
        reduced: false,
      );

  /// 同一个 widget 树反复 pump：状态才留得住（数字要跨 build 滚动）。
  Widget cardApp(TodayCard card) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: card,
          ),
        ),
      );

  Future<void> pumpHeatmap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StudyHeatmap(totals: const {}, streak: 0, now: now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration cellDeco(WidgetTester tester, String day) =>
      tester
          .widget<Container>(find.byKey(ValueKey('heat-cell-$day')))
          .decoration! as BoxDecoration;

  /// 一个 Text 是不是等宽数字。
  bool isTabular(Text t) =>
      t.style?.fontFeatures?.any((f) => f.feature == 'tnum') ?? false;

  Finder ringCountText() => find.descendant(
        of: find.byKey(const ValueKey('ring-count')),
        matching: find.byType(Text),
      );

  testWidgets('今天格：底色跟空格一样，只有一圈描边，不是实心黑', (tester) async {
    await pumpHeatmap(tester);

    final today = cellDeco(tester, '2026-11-26');
    final empty = cellDeco(tester, '2026-11-25');

    // 需求：今天那格的底色 = 空格子底色（墨 5%），热力图的深浅只表示学习量。
    expect(today.color, empty.color);
    expect(today.color, AppColors.heatmapEmpty);
    expect(today.color!.a, closeTo(0.05, 0.005),
        reason: '底色是半透明的，所以背后不能再垫实心墨');

    // v0.7.5 的实心黑就是这条 boxShadow：半透明底色挡不住它，整格发黑。
    expect(today.boxShadow, isNull, reason: '实心墨投影会把今天画成「学得最多」');

    final ring = tester
        .widget<Container>(find.byKey(const ValueKey('heat-cell-2026-11-26')))
        .foregroundDecoration! as BoxDecoration;
    expect(ring.color, isNull, reason: '前景层只画边，不铺填充');
    final border = ring.border! as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, StudyHeatmap.todayBorder);
  });

  testWidgets('有数据的天仍然按蓝阶上色，没被这轮改动波及', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StudyHeatmap(
              totals: <String, DayTotal>{
                '2026-11-24': const DayTotal(newWords: 20, reviews: 8),
              },
              streak: 1,
              now: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(cellDeco(tester, '2026-11-24').color!.a, closeTo(0.75, 0.01));
  });

  testWidgets('环内数字、/目标、三格数字都带 tabular figures', (tester) async {
    await tester.pumpWidget(cardApp(TodayCard(stats: stats(), loading: false)));
    await tester.pumpAndSettle();

    // 纯数字（或 / 目标）的 Text，全部得是等宽。
    final numeric = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(TodayCard),
            matching: find.byType(Text),
          ),
        )
        .where((t) => t.data != null && RegExp(r'^[\d/\s,]+$').hasMatch(t.data!))
        .toList();

    expect(numeric.length, greaterThanOrEqualTo(5),
        reason: '环内 13、/ 30、新词 / 待复习 / 答错 三格');
    for (final t in numeric) {
      expect(isTabular(t), isTrue, reason: '「${t.data}」没有 tabular figures');
    }
  });

  testWidgets('首页三张卡的数字也带 tabular figures', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const StudyPage()),
    );
    // 顶部色洗是 24s 循环动画，不能 settle；读库在测试环境失败，两帧就够。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final numeric = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(StudyPage),
            matching: find.byType(Text),
          ),
        )
        .where((t) => t.data != null && RegExp(r'^[\d,]+$').hasMatch(t.data!))
        .toList();

    expect(numeric, isNotEmpty);
    for (final t in numeric) {
      expect(isTabular(t), isTrue, reason: '「${t.data}」没有 tabular figures');
    }
  });

  test('等宽用的是思源黑体的 tnum，不换字体、不加字体文件', () {
    expect(AppTheme.tabular.length, 1);
    expect(AppTheme.tabular.single.feature, 'tnum');

    final styled = AppTheme.numeric(const TextStyle(fontSize: 44));
    expect(styled.fontSize, 44, reason: '只加特性，不动其余属性');
    expect(isTabular(Text('1', style: styled)), isTrue);
  });

  testWidgets('环内数字是滚动递增，不是瞬间跳变', (tester) async {
    await tester.pumpWidget(
      cardApp(TodayCard(stats: stats(learned: 3), loading: false)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(ringCountText()).data, '3');

    await tester.pumpWidget(
      cardApp(TodayCard(stats: stats(learned: 13), loading: false)),
    );
    await tester.pump(); // 起手
    await tester.pump(const Duration(milliseconds: 150));

    final mid = int.parse(tester.widget<Text>(ringCountText()).data!);
    expect(mid, greaterThan(3), reason: '起点应该是旧值 3，不是 0 也不是 13');
    expect(mid, lessThan(13), reason: '150ms 还没到终点');

    await tester.pumpAndSettle();
    expect(tester.widget<Text>(ringCountText()).data, '13');
  });

  test('数字滚动用的还是那条弹簧（300 / 24 / 0.8）', () {
    final sim = RollingInt.simulation(3, 13);
    expect(sim, isA<SpringSimulation>());

    final reference = SpringSimulation(LiquidGlass.spring, 3, 13, 0);
    for (final t in <double>[0.02, 0.06, 0.12, 0.2, 0.3]) {
      expect(sim.x(t), closeTo(reference.x(t), 1e-9), reason: 't = $t');
    }
  });

  testWidgets('首页两玻璃按钮按压缩放 0.96，松开回弹到 1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const StudyPage()),
    );
    // 顶部色洗是 24s 循环动画，不能 settle；读库在测试环境里抛
    // MissingPluginException，被页面 catch 后按钮才从禁用变可点。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PressScale), findsNWidgets(2),
        reason: '开始学习 + 只复习');

    final primary = find.ancestor(
      of: find.text('开始学习'),
      matching: find.byType(PressScale),
    );
    expect(tester.widget<PressScale>(primary).enabled, isTrue,
        reason: '按钮得先可点，否则按下不缩');

    // 读矩阵左上角，不用 getMaxScaleOnAxis：后者把 z 轴的 1.0 也算进去，
    // 永远返回 1（踩过一次）。
    double scaleOf() => tester
        .widget<Transform>(
          find
              .descendant(of: primary, matching: find.byType(Transform))
              .first,
        )
        .transform
        .entry(0, 0);

    expect(scaleOf(), closeTo(1.0, 1e-6));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('开始学习')),
    );
    await tester.pump();
    await tester.pump(PressScale.duration);
    expect(scaleOf(), closeTo(PressScale.pressed, 0.005));
    expect(PressScale.pressed, 0.96);

    // 取消而不是抬起：抬起会真的进会话页。
    await gesture.cancel();
    // 第一帧只定起点（ticker 的 elapsed 从 0 开始），第二帧才真的走时间。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(scaleOf(), closeTo(1.0, 0.01));
  });

  test('圆角只有一个值：AppTheme.cardRadius = 18', () {
    expect(AppTheme.cardRadius, 18);
    expect(AppTheme.light.cardTheme.shape,
        isA<RoundedRectangleBorder>().having(
          (s) => s.borderRadius,
          'borderRadius',
          BorderRadius.circular(AppTheme.cardRadius),
        ));
  });

  testWidgets('任务卡与热力图卡用的是同一个圆角', (tester) async {
    await tester.pumpWidget(cardApp(TodayCard(stats: stats(), loading: false)));
    await tester.pumpAndSettle();

    final card = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(TodayCard),
            matching: find.byType(Container),
          ),
        )
        .first;
    final deco = card.decoration! as BoxDecoration;
    expect(deco.borderRadius, BorderRadius.circular(AppTheme.cardRadius));

    await pumpHeatmap(tester);
    final heat = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(StudyHeatmap),
            matching: find.byType(Container),
          ),
        )
        .first;
    expect((heat.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(AppTheme.cardRadius));
  });
}
