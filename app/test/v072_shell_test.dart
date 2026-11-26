import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/shell/home_shell.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/features/profile/profile_page.dart';
import 'package:mw_english/features/words/words_page.dart';

/// v0.7.2 外壳：切 Tab 的触觉、选中态过渡、IndexedStack 不重建，
/// 以及我的页版本行的 shader 状态。
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

  Future<void> tapTab(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(ValueKey('tab-$i')));
    await tester.pump();
  }

  testWidgets('切 Tab 震一次 lightImpact，点当前页不震，连点不吞', (tester) async {
    await bootShell(tester);
    expect(haptics, isEmpty, reason: '刚进来不该震');

    await tapTab(tester, 1);
    expect(haptics.length, 1, reason: '真切页要震');
    expect(haptics.single.method, 'HapticFeedback.vibrate');
    expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact',
        reason: '力度必须和答对同款（lightImpact）');

    await tapTab(tester, 1);
    expect(haptics.length, 1, reason: '点当前页不该震');

    // 连续快速切换 5 次，一次都不能被节流吞掉。
    for (final i in <int>[2, 3, 0, 2, 1]) {
      await tapTab(tester, i);
    }
    expect(haptics.length, 6, reason: '连点 5 次应各震一次（1 + 5）');
  });

  testWidgets('切 Tab 只换显示：IndexedStack 不动，目标页 state 不重建', (tester) async {
    await bootShell(tester);

    final before = tester.widget<IndexedStack>(find.byType(IndexedStack));
    final stateBefore = tester.state(find.byType(WordsPage, skipOffstage: false));

    await tapTab(tester, 1);
    await tester.pump(const Duration(milliseconds: 200));

    final after = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(after.index, 1, reason: '切页只改 IndexedStack 的 index');
    expect(identical(after.children[1], before.children[1]), isTrue,
        reason: '目标页 widget 还是同一个 const 实例 → 不会重新 build');
    expect(
      identical(tester.state(find.byType(WordsPage, skipOffstage: false)),
          stateBefore),
      isTrue,
      reason: '目标页 state 被重建了（会重新读库）',
    );
  });

  testWidgets('选中态是 150–200ms 的隐式动画，不是瞬切', (tester) async {
    await bootShell(tester);

    Finder inTab(int i, Type type) => find.descendant(
          of: find.byKey(ValueKey('tab-$i')),
          matching: find.byType(type),
        );

    // 三处过渡都在 150–200ms 区间，且共用同一个时长。
    final tint = tester.widget<AnimatedContainer>(inTab(1, AnimatedContainer));
    final icon = tester.widget<AnimatedSwitcher>(inTab(1, AnimatedSwitcher));
    final label =
        tester.widget<AnimatedDefaultTextStyle>(inTab(1, AnimatedDefaultTextStyle));
    for (final ms in <int>[
      tint.duration.inMilliseconds,
      icon.duration.inMilliseconds,
      label.duration.inMilliseconds,
    ]) {
      expect(ms, inInclusiveRange(150, 200));
    }

    Color? tintNow(int i) {
      final c = tester.widget<Container>(
        inTab(i, Container).first,
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    // 未选中：没有 tint。
    expect(tintNow(1)?.a ?? 0, 0);

    final target = Colors.white
        .withValues(alpha: LiquidGlass.tintSelected)
        .a;

    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump(); // 起跑
    await tester.pump(const Duration(milliseconds: 80)); // 半途

    final mid = tintNow(1)?.a ?? 0;
    expect(mid, greaterThan(0), reason: '半途 tint 还没开始 = 瞬切');
    expect(mid, lessThan(target), reason: '半途已经到终值 = 瞬切');

    await tester.pump(const Duration(milliseconds: 200));
    expect(tintNow(1)?.a, closeTo(target, 0.001));
  });

  testWidgets('我的页版本行显示 shader 状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfilePage()),
    );
    await tester.pumpAndSettle();

    final expected = GlassRefraction.supported
        ? '0.7.2 (2017) · 真折射开'
        : '0.7.2 (2017) · 玻璃回落';
    expect(find.text(expected), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
  });

  test('版本行两种状态文案（第三态只是探测中，不猜）', () {
    expect(versionLabel(true), '0.7.2 (2017) · 真折射开');
    expect(versionLabel(false), '0.7.2 (2017) · 玻璃回落');
    expect(versionLabel(null), '0.7.2 (2017)');
  });
}
