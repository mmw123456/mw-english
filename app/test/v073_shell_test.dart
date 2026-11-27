import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/shell/home_shell.dart';
import 'package:mw_english/app/shell/spring_page_physics.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/features/profile/profile_page.dart';
import 'package:mw_english/features/study/study_page.dart';
import 'package:mw_english/features/words/words_page.dart';

/// v0.7.3：左右划切页（PageView + 弹簧）+ 四个 Tab 页 keep-alive + 玻璃加深。
///
/// 断言取自需求原文：
/// - 四个 Tab 页走 PageView + PageController，左右划切换，点 Tab 也能切，两边同步
/// - 状态不丢：划走再划回来，滚动位置 / 搜索框内容都在，State 不重建
/// - 手感：过半到下一页，不到一半弹回；落位走 stiffness 300 / damping 24 / mass 0.8
/// - 震动：落定一次 lightImpact，划动过程中不震
/// - Tab 栏与按钮的白 tint 6%（选中 36% 不变）
/// - 首页顶部有一层色洗（五色 8–12%），词库页与我的页没有
void main() {
  final haptics = <MethodCall>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> bootShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeShell()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  PageController controllerOf(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!;

  /// 词库页的搜索输入框（八百年不变的那一个）。
  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('左右划到下一页：划过大半就翻页，落定震一次', (tester) async {
    await bootShell(tester);
    expect(controllerOf(tester).page, 0);

    await tester.drag(find.byType(PageView), const Offset(-520, 0));
    await tester.pumpAndSettle();

    expect(controllerOf(tester).page!, closeTo(1, 0.01),
        reason: '划过大半松手应该停在下一页');
    expect(haptics.length, 1, reason: '落定时震一次，不要多');
    expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact',
        reason: '力度与 Tab 点按 / 答对同款');
  });

  testWidgets('划不到一半松手弹回原页，不震', (tester) async {
    await bootShell(tester);

    await tester.drag(find.byType(PageView), const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(controllerOf(tester).page!, closeTo(0, 0.01),
        reason: '没过半就该回原页');
    expect(haptics, isEmpty, reason: '没换页就没有可确认的东西，不该震');
  });

  testWidgets('划动过程中不震，松手落定才震一次', (tester) async {
    await bootShell(tester);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PageView)));
    // 先越过 touch slop（这段被手势识别吃掉，不进位移），再走真正的一段。
    await gesture.moveBy(const Offset(-24, 0));
    await gesture.moveBy(const Offset(-430, 0));
    await tester.pump();
    expect(controllerOf(tester).page!, greaterThan(0.3),
        reason: '手指动多少页面动多少');
    expect(haptics, isEmpty, reason: '划动过程中一律不震');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics.length, 1);
  });

  testWidgets('划动时 Tab 选中态跟着走（过半就换高亮）', (tester) async {
    await bootShell(tester);

    Color? tintNow(int i) {
      final c = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ValueKey('tab-$i')),
              matching: find.byType(Container),
            )
            .first,
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await gesture.moveBy(const Offset(-24, 0));
    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump(); // 这一帧把 setState 消化掉、起跑隐式动画
    await tester.pump(const Duration(milliseconds: 200));

    expect(controllerOf(tester).page!, lessThan(0.5));
    expect(tintNow(0)?.a ?? 0, greaterThan(0), reason: '没过半，仍高亮第 0 页');
    expect(tintNow(1)?.a ?? 0, 0, reason: '没过半就不该亮第 1 页');

    await gesture.moveBy(const Offset(-260, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controllerOf(tester).page!, greaterThan(0.5));
    expect(tintNow(1)?.a ?? 0, greaterThan(0), reason: '过半了，高亮要跟着走');
    expect(haptics, isEmpty, reason: '还没松手，不震');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics.length, 1);
  });

  testWidgets('划走再划回来：State 不重建，滚动位置还在', (tester) async {
    await bootShell(tester);

    Finder studyScrollable() => find.descendant(
          of: find.byType(StudyPage, skipOffstage: false),
          matching: find.byType(Scrollable, skipOffstage: false),
        ).first;

    final stateBefore = tester.state<ScrollableState>(studyScrollable());

    // 先把首页滚下去一段（纵向手势只归 ListView，PageView 不参与）。
    await tester.drag(find.byType(StudyPage), const Offset(0, -180));
    await tester.pumpAndSettle();
    final offset = stateBefore.position.pixels;
    expect(offset, greaterThan(0), reason: '先得真的滚动起来，否则这条用例是空转');
    expect(controllerOf(tester).page, 0, reason: '纵向滑不该带动翻页');

    await tester.drag(find.byType(PageView), const Offset(-520, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(520, 0));
    await tester.pumpAndSettle();

    expect(identical(tester.state<ScrollableState>(studyScrollable()), stateBefore),
        isTrue,
        reason: '划走再回来 State 被重建了 —— keep-alive 没生效');
    expect(stateBefore.position.pixels, closeTo(offset, 0.01),
        reason: '滚动位置没保住');
  });

  testWidgets('词库搜索框内容：划走再划回来还在', (tester) async {
    await bootShell(tester);

    await tester.drag(find.byType(PageView), const Offset(-520, 0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tra');
    await tester.pump(const Duration(milliseconds: 400));
    expect(searchField(tester).controller!.text, 'tra');

    // 词库 → 阅读 → 词库
    await tester.drag(find.byType(PageView), const Offset(-520, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(520, 0));
    await tester.pumpAndSettle();

    expect(find.byType(WordsPage), findsOneWidget);
    expect(searchField(tester).controller!.text, 'tra',
        reason: '搜索框内容没保住');
  });

  testWidgets('点 Tab：页面滑过去、选中态立刻跟上、落定震一次', (tester) async {
    await bootShell(tester);

    Color? tintNow(int i) {
      final c = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ValueKey('tab-$i')),
              matching: find.byType(Container),
            )
            .first,
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump(); // 起跑
    await tester.pump(const Duration(milliseconds: 60)); // 页面还在路上

    expect(haptics, isEmpty, reason: '按下那一刻不震，等页面落定');
    expect(controllerOf(tester).page!, lessThan(1.9),
        reason: '这一帧页面还没滑到位，选中态不该等它');
    expect(tintNow(2)?.a ?? 0, greaterThan(0),
        reason: '选中态要立刻跟上，不等动画');

    await tester.pumpAndSettle();
    expect(controllerOf(tester).page!.round(), 2, reason: '页面要真的滑过去');
    expect(haptics.length, 1);
  });

  testWidgets('点当前页不震、不重跑动画', (tester) async {
    await bootShell(tester);

    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await tester.pumpAndSettle();

    expect(haptics, isEmpty);
    expect(controllerOf(tester).page, 0);
  });

  testWidgets('IndexedStack 已撤，四页都在 PageView 里，Tab 栏 tint 6%', (tester) async {
    await bootShell(tester);

    expect(find.byType(IndexedStack), findsNothing,
        reason: 'v0.7.3 起外壳是 PageView');
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.childrenDelegate.estimatedChildCount, 4);

    // 「我的」只在 Tab 栏出现，用它反查整条玻璃。
    final bar = tester.widget<GlassSurface>(
      find
          .ancestor(
            of: find.text('我的'),
            matching: find.byType(GlassSurface),
          )
          .first,
    );
    expect(bar.tintAlpha, 0.06, reason: 'Tab 栏白 tint 从 2% 提到 6%');
    expect(LiquidGlass.tintSelected, 0.36, reason: '选中态 36% 不变');
  });

  testWidgets('首页顶部有色洗，词库页 / 我的页没有', (tester) async {
    await bootShell(tester);

    expect(
      find.descendant(
        of: find.byType(StudyPage),
        matching: find.byType(LiquidTopWash),
      ),
      findsOneWidget,
      reason: '首页要有东西可弯',
    );

    for (final page in <Widget>[const WordsPage(), const ProfilePage()]) {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: page),
      );
      await tester.pump();
      expect(find.byType(LiquidTopWash), findsNothing,
          reason: '${page.runtimeType} 不该有色洗，保持干净纸面');
    }
  });

  test('色洗是五色、8%–12%、只铺顶部一条', () {
    expect(LiquidGlass.washOpacity.length, LiquidGlass.aura.length);
    for (final o in LiquidGlass.washOpacity) {
      expect(o, inInclusiveRange(0.08, 0.12));
    }
    expect(LiquidGlass.washHeight, lessThanOrEqualTo(480),
        reason: '只盖标题栏 + 任务卡 + 两个按钮这一带，不铺满屏');
  });

  group('SpringPagePhysics 落点', () {
    const physics = SpringPagePhysics();

    ScrollMetrics at(double pixels, {double viewport = 400, int pages = 4}) {
      return FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: (pages - 1) * viewport,
        pixels: pixels,
        viewportDimension: viewport,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1,
      );
    }

    test('0.4 页就算甩得很快也回原页', () {
      final sim = physics.createBallisticSimulation(at(160), 3000)!;
      expect(sim.x(2), closeTo(0, 1));
    });

    test('0.6 页就去下一页', () {
      final sim = physics.createBallisticSimulation(at(240), -3000)!;
      expect(sim.x(2), closeTo(400, 1));
    });

    test('已经在整页上：速度不翻页（不交回父物理）', () {
      expect(physics.createBallisticSimulation(at(400), 4000), isNull);
      expect(physics.createBallisticSimulation(at(800), -4000), isNull);
    });

    test('落位用的是全 App 那条弹簧，不是默认的 ScrollPhysics.spring', () {
      final sim = physics.createBallisticSimulation(at(240), 0);
      expect(sim, isA<ScrollSpringSimulation>());

      // 同起点同终点的参考弹簧：轨迹必须逐点吻合（默认 spring 是
      // mass 0.5 / stiffness 100，跑出来完全不同）。
      final ref = ScrollSpringSimulation(
        LiquidGlass.spring,
        240,
        400,
        0,
        tolerance: SpringPagePhysics.pageTolerance,
      );
      for (final t in <double>[0.02, 0.06, 0.12]) {
        expect(sim!.x(t), closeTo(ref.x(t), 0.5), reason: 't=$t 的轨迹对不上');
      }
    });

    test('applyTo 之后还是这套物理', () {
      expect(const SpringPagePhysics().applyTo(const ClampingScrollPhysics()),
          isA<SpringPagePhysics>());
    });
  });
}
