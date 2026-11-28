import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/features/study/progress_ring.dart';
import 'package:mw_english/features/study/study_heatmap.dart';
import 'package:mw_english/features/study/study_page.dart';
import 'package:mw_english/features/study/today_card.dart';

/// v0.7.8 首页主角化。
///
/// 断言取自需求原文：
/// - 环 176 / 14，环内数字 56pt（`/30` 保持小字），弹簧参数不变
/// - 环下一行 14pt 墨 70% 的今日状态：未开始 / 进行中 / 完成三态，
///   分母跟 `newTarget` 走（断档削减时不许写死 30）
/// - 「开始学习」= 全宽 56 高、橙 tint 10%、18pt w700；
///   「只复习」= 无玻璃文字按钮（墨 70%、16pt），首页只留一个玻璃控件
/// - 二级区块标题（学习足迹 / 怎么排的）统一 16pt w700 墨
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

  Future<void> pumpHome(WidgetTester tester) async {
    // 固定 390 宽（常见手机），才能断言「全宽」与「56 高」这两个尺寸。
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const StudyPage()),
    );
    // 顶部色洗是 24s 循环动画，不能 settle；读库在测试环境里抛
    // MissingPluginException，被页面 catch 后才是最终态。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Hero：环与数字', () {
    testWidgets('环 176 / 14，环内数字 56pt，/N 仍是小字', (tester) async {
      await pumpCard(tester, TodayCard(stats: stats(), loading: false));

      expect(ProgressRing.diameter, 176);
      expect(ProgressRing.stroke, 14);

      final ring = find.byType(ProgressRing);
      expect(tester.getSize(ring), const Size(176, 176));

      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(of: ring, matching: find.byType(CustomPaint)),
          )
          .first
          .painter! as ProgressRingPainter;
      expect(painter.strokeWidth, 14);

      final number = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('ring-count')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(number.style?.fontSize, 56, reason: '环内数字 44 → 56');
      expect(number.style?.fontWeight, FontWeight.w700);
      expect(number.data, '13');

      final denominator = tester.widget<Text>(find.text('/ 30'));
      expect(denominator.style?.fontSize, 13, reason: '/N 保持小字，不跟着放大');
    });

    testWidgets('放大后弹簧没换：还是 LiquidGlass.spring', (tester) async {
      // 尺寸变了，动效参数不许跟着动。
      expect(LiquidGlass.spring.stiffness, 300);
      expect(LiquidGlass.spring.damping, 24);
      expect(LiquidGlass.spring.mass, 0.8);
    });
  });

  group('Hero：今日状态行', () {
    test('三态文案：未开始 / 进行中 / 完成', () {
      expect(
        TodayCard(stats: stats(learned: 0, target: 30), loading: false)
            .statusLine(),
        '今天还没开始 · 目标 30 词',
      );
      expect(
        TodayCard(stats: stats(learned: 13, target: 30), loading: false)
            .statusLine(),
        '今日已学 13 / 30，还差 17 词',
      );
      expect(
        TodayCard(stats: stats(learned: 30, target: 30), loading: false)
            .statusLine(),
        '今日目标完成',
      );
      // 超额也算完成，不会出现「还差 -10 词」。
      expect(
        TodayCard(stats: stats(learned: 40, target: 30), loading: false)
            .statusLine(),
        '今日目标完成',
      );
    });

    test('分母跟 newTarget 走，断档削减时不许写死 30', () {
      expect(
        TodayCard(stats: stats(learned: 0, target: 6), loading: false)
            .statusLine(),
        '今天还没开始 · 目标 6 词',
      );
      expect(
        TodayCard(stats: stats(learned: 3, target: 6), loading: false)
            .statusLine(),
        '今日已学 3 / 6，还差 3 词',
      );
      expect(
        TodayCard(stats: stats(learned: 6, target: 6), loading: false)
            .statusLine(),
        '今日目标完成',
      );
    });

    testWidgets('状态行在环下方，14pt / 墨 70%', (tester) async {
      await pumpCard(tester, TodayCard(stats: stats(), loading: false));

      final line = find.text('今日已学 13 / 30，还差 17 词');
      expect(line, findsOneWidget);

      final style = tester.widget<Text>(line).style!;
      expect(style.fontSize, 14);
      expect(style.color, AppColors.textSecondary);
      expect(AppColors.textSecondary.a, closeTo(0.70, 0.01));

      expect(
        tester.getRect(line).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(ProgressRing)).bottom),
        reason: '状态行必须在环下面',
      );
    });

    testWidgets('读库中不先喊「今天还没开始」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: TodayCard(stats: TodayStats.empty, loading: true),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('今天还没开始'), findsNothing);
      expect(find.textContaining('今日已学'), findsNothing);
    });

    testWidgets('三格统计没动：新词 / 待复习 / 答错', (tester) async {
      await pumpCard(tester, TodayCard(stats: stats(), loading: false));
      expect(find.text('新词'), findsOneWidget);
      expect(find.text('待复习'), findsOneWidget);
      expect(find.text('答错'), findsOneWidget);
    });
  });

  group('CTA：主按钮 + 文字入口', () {
    testWidgets('开始学习：全宽 56 高、橙 tint 10%、18pt w700', (tester) async {
      await pumpHome(tester);

      final label = find.text('开始学习');
      expect(label, findsOneWidget);

      final surface = tester.widget<GlassSurface>(
        find.ancestor(of: label, matching: find.byType(GlassSurface)),
      );
      expect(surface.tintColor, AppColors.ringOrange);
      expect(surface.tintAlpha, closeTo(0.10, 1e-9));
      expect(surface.minHeight, 56);

      final size = tester.getSize(
        find.ancestor(of: label, matching: find.byType(GlassSurface)),
      );
      expect(size.height, closeTo(56, 0.01), reason: '主按钮高 56');
      // 全宽：跟页面内容同宽（左右各 20 边距）。
      expect(size.width, closeTo(390 - 40, 0.01));

      final text = tester.widget<Text>(label);
      expect(text.style?.fontSize, 18);
      expect(text.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('只复习：无玻璃文字按钮，墨 70% / 16pt', (tester) async {
      await pumpHome(tester);

      // 三格里也有「待复习」，所以从按钮本身往下找，不用全局文字匹配。
      final review = find.byKey(const ValueKey('review-link'));
      expect(review, findsOneWidget);

      expect(
        find.ancestor(of: review, matching: find.byType(GlassSurface)),
        findsNothing,
        reason: '只复习不再上玻璃',
      );

      final text = tester.widget<Text>(
        find.descendant(of: review, matching: find.byType(Text)),
      );
      expect(text.style?.fontSize, 16);
      // 测试环境读不到库 → 0 待复习 → 禁用态（墨 38%）。可点态是墨 70%，
      // 单独在下面那条用例里断言。
      expect(text.style?.color, LiquidGlass.textDisabled);
    });

    testWidgets('只复习：可点态是墨 70%，禁用态是墨 38%', (tester) async {
      Future<Text> pumpLink({required bool enabled}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ReviewLink(
                label: enabled ? '只复习待复习 12 词' : '没有待复习',
                onTap: enabled ? () {} : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.widget<Text>(find.byType(Text));
      }

      final on = await pumpLink(enabled: true);
      expect(on.style?.color, AppColors.textSecondary);
      expect(on.style?.fontSize, 16);

      final off = await pumpLink(enabled: false);
      expect(off.style?.color, LiquidGlass.textDisabled);
    });

    testWidgets('首页只留一个玻璃控件', (tester) async {
      await pumpHome(tester);
      expect(find.byType(GlassSurface), findsOneWidget);
    });

    testWidgets('主按钮在只复习上面，两者都还在原位置（三格之前）', (tester) async {
      await pumpHome(tester);

      final primary = tester.getRect(find.text('开始学习'));
      final review = tester.getRect(find.byKey(const ValueKey('review-link')));
      expect(primary.bottom, lessThan(review.top));
    });
  });

  group('层级：区块标题降级', () {
    testWidgets('「学习足迹」「怎么排的」统一 16pt w700 墨', (tester) async {
      await pumpHome(tester);

      for (final title in <String>['学习足迹', '怎么排的']) {
        final finder = find.text(title);
        expect(finder, findsOneWidget, reason: title);

        final style = tester.widget<Text>(finder).style!;
        expect(style.fontSize, 16, reason: '$title 字号');
        expect(style.fontWeight, FontWeight.w700, reason: '$title 字重');
        expect(style.color, LiquidGlass.ink, reason: '$title 用墨');
      }
    });

    testWidgets('标题比 Hero 数字小得多，视觉重心只有一个', (tester) async {
      await pumpHome(tester);

      final title = tester.widget<Text>(find.text('怎么排的')).style!.fontSize!;
      final hero = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('ring-count')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .style!
          .fontSize!;
      expect(hero, 56);
      expect(title, 16);
      expect(hero / title, greaterThanOrEqualTo(3.5));
    });
  });

  group('跨页一致：热力图标题同字阶', () {
    testWidgets('学习足迹 = 16pt w700 墨，且不撑坏热力图', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StudyHeatmap(
                totals: const {},
                streak: 0,
                now: DateTime(2026, 11, 26),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final style = tester.widget<Text>(find.text('学习足迹')).style!;
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w700);
      expect(tester.takeException(), isNull);
    });
  });
}
