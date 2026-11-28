import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/features/study/progress_ring.dart';
import 'package:mw_english/features/study/study_heatmap.dart';
import 'package:mw_english/features/study/study_page.dart';

/// v0.7.5 首页暖冷分工配色。
///
/// 断言取自需求原文：
/// - 环填充 = 深一档橙 #E8490F（纸上 ≥3:1），不是 #2E4BFF、也不是 #FF5A1F
/// - 开始学习按钮 tint = 橙 10%；只复习按钮仍是无色白 tint，两按钮主次分开
/// - 热力图空格 = 墨 5% 底 + 保留边框；全空时标题下「从今天开始记」；
///   今天那格 1.5px 墨 60% 描边；蓝阶四档不动
/// - 12 列完整落在卡片内宽里（320 / 360 / 390 / 414 都不溢出）
void main() {
  /// 固定「今天」= 2026-11-26（周四）。
  final now = DateTime(2026, 11, 26);

  Future<void> pumpHeatmap(
    WidgetTester tester, {
    Map<String, DayTotal> totals = const {},
    int streak = 0,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StudyHeatmap(totals: totals, streak: streak, now: now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration decoOf(WidgetTester tester, String key) {
    final cell = tester.widget<Container>(find.byKey(ValueKey('heat-cell-$key')));
    return cell.decoration! as BoxDecoration;
  }

  test('橙 token：纸上 ≥3:1，亮橙 #FF5A1F 不达标所以不用', () {
    expect(AppColors.ringOrange, const Color(0xFFE8490F));
    expect(AppColors.ringOrange, isNot(AppColors.accentBlue));

    final onPaper = _contrast(AppColors.ringOrange, LiquidGlass.paper);
    expect(onPaper, greaterThanOrEqualTo(3.0),
        reason: '环是 12px 图元线，WCAG 非文本要求 3:1，实测 ${onPaper.toStringAsFixed(2)}');

    // 需求点名不让用的那支：纸上只有约 2.7:1。
    expect(
      _contrast(const Color(0xFFFF5A1F), LiquidGlass.paper),
      lessThan(3.0),
    );
    // 蓝原样保留，退到热力图。
    expect(AppColors.accentBlue, const Color(0xFF2E4BFF));
  });

  testWidgets('环画的是橙，不是蓝；轨道没动（尺寸 v0.7.8 放大到 176 / 14）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: ProgressRing(value: 0.5))),
      ),
    );
    await tester.pumpAndSettle();

    final paints = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(ProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .toList();
    final painter = paints.first.painter! as ProgressRingPainter;

    expect(painter.color, AppColors.ringOrange);
    expect(painter.strokeWidth, 14);
    expect(ProgressRing.diameter, 176);
    expect(ProgressRing.track, const Color(0x1A0B0C10));
  });

  testWidgets('开始学习按钮 = 橙 10%；只复习（v0.7.8 起是文字入口，不再上玻璃）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const StudyPage()),
    );
    // 首页顶部色洗是 24s 循环动画，不能 pumpAndSettle；读库在测试环境里
    // 直接抛 MissingPluginException，被页面 catch，两帧就够。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final primary = tester.widget<GlassSurface>(
      find.ancestor(
        of: find.text('开始学习'),
        matching: find.byType(GlassSurface),
      ),
    );
    expect(primary.tintColor, AppColors.ringOrange);
    expect(primary.tintAlpha, closeTo(0.10, 1e-9));

    // 次入口文案随 dueReview 变（测试环境读不到库 → 「没有待复习」）。
    // v0.7.8：它从玻璃胶囊降成文字按钮，所以祖先里不许再有 GlassSurface。
    // 三格里的「待复习」也会被文字匹配撞上，这里从按钮本身往下找。
    final secondary = find.byKey(const ValueKey('review-link'));
    expect(secondary, findsOneWidget);
    expect(
      find.ancestor(of: secondary, matching: find.byType(GlassSurface)),
      findsNothing,
      reason: '只复习不再上玻璃，首页只留一个玻璃控件',
    );
  });

  testWidgets('空格子：墨 5% 底 + 边框仍保留', (tester) async {
    await pumpHeatmap(tester);

    final deco = decoOf(tester, '2026-11-25');
    expect(deco.color, AppColors.heatmapEmpty);
    expect(deco.color!.a, closeTo(0.05, 0.005));
    expect(deco.border, isNotNull, reason: '只有底色没有格线，远看还是一整片');
    expect((deco.border! as Border).top.width, 0.5);
  });

  testWidgets('全空时标题下有「从今天开始记」，有一格数据就消失', (tester) async {
    await pumpHeatmap(tester);
    expect(find.text('从今天开始记'), findsOneWidget);

    await pumpHeatmap(
      tester,
      totals: <String, DayTotal>{
        '2026-11-24': const DayTotal(newWords: 3, reviews: 1),
      },
    );
    expect(find.text('从今天开始记'), findsNothing);
  });

  testWidgets('今天那格：1.5px 墨 60% 描边；其他格没有', (tester) async {
    await pumpHeatmap(tester);

    final today = tester
        .widget<Container>(find.byKey(const ValueKey('heat-cell-2026-11-26')))
        .foregroundDecoration! as BoxDecoration;
    final border = today.border! as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, StudyHeatmap.todayBorder);
    expect(StudyHeatmap.todayBorder.a, closeTo(0.60, 0.01));

    final yesterday = tester
        .widget<Container>(find.byKey(const ValueKey('heat-cell-2026-11-25')))
        .foregroundDecoration;
    expect(yesterday, isNull);
  });

  test('蓝阶四档没动', () {
    expect(StudyHeatmap.colorFor(0), AppColors.heatmapEmpty);
    expect(StudyHeatmap.colorFor(1).a, closeTo(0.25, 0.01));
    expect(StudyHeatmap.colorFor(10).a, closeTo(0.50, 0.01));
    expect(StudyHeatmap.colorFor(20).a, closeTo(0.75, 0.01));
    expect(StudyHeatmap.colorFor(30), AppColors.accentBlue);
  });

  testWidgets('12 列完整在卡片内宽里（含超窄分屏，全都不溢出）', (tester) async {
    for (final width in <double>[200, 320, 360, 390, 414]) {
      await pumpHeatmap(tester, width: width);

      final card = tester.getRect(find.byType(StudyHeatmap));
      // 卡片左右各 20 的内边距。
      final innerRight = card.right - 20;
      final last = tester.getRect(
        find.byKey(const ValueKey('heat-cell-2026-11-26')),
      );

      expect(last.right, lessThanOrEqualTo(innerRight + 0.01),
          reason: '$width 宽：最右列伸到 ${last.right}，卡片内边界 $innerRight');
      expect(last.width, closeTo(last.height, 0.01), reason: '格子必须是方的');
      expect(tester.takeException(), isNull, reason: '$width 宽有布局溢出');
    }
  });
}

/// WCAG 相对亮度对比度（同 theme_paper_test.dart）。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
