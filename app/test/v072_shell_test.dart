import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/shell/home_shell.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/features/profile/profile_page.dart';

/// v0.7.2 里**仍然成立**的那部分外壳约束。
///
/// 被 v0.7.3 推翻的两条已搬走，不在这里改写成别的东西：
/// - 「切页不重建（IndexedStack）」→ 换成 PageView + keep-alive，
///   验收改为「划走再回来状态还在」，见 `v073_shell_test.dart`；
/// - 「切 Tab 按下就震」→ 改成「页面落定才震」，同样在 v073 里。
///
/// 留在本文件的是：选中态 170ms 三处同步过渡、我的页版本行。
void main() {
  Future<void> bootShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeShell()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

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

    final base = _versionFromPubspec();
    final expected = GlassRefraction.supported
        ? '$base · 真折射开'
        : '$base · 玻璃回落';
    expect(find.text(expected), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
  });

  test('版本行两种状态文案（第三态只是探测中，不猜）', () {
    final base = _versionFromPubspec();
    expect(versionLabel(true), '$base · 真折射开');
    expect(versionLabel(false), '$base · 玻璃回落');
    expect(versionLabel(null), base);
  });
}

/// 从 pubspec 读出「0.7.x (20xx)」，省得每次发版手工改测试里的版本号。
///
/// Flutter 分架构构建会把 versionCode 再 +2000（本工程一直这么对：+19 → 2019）。
String _versionFromPubspec() {
  final pub = File('pubspec.yaml').readAsStringSync();
  final m = RegExp(r'version: (\d+\.\d+\.\d+)\+(\d+)').firstMatch(pub)!;
  return '${m.group(1)} (${int.parse(m.group(2)!) + 2000})';
}
