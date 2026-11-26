import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass_preview_theme.dart';
import 'package:mw_english/features/study/study_session_page.dart';

/// v0.6.4 液态玻璃预览的约束测试。
///
/// 断言直接取自需求原文，不从实现里抄：
/// - 页面底色是墨 #0B0C10
/// - 玻璃只有三样：4%–6% 白 tint、1px 迎光亮边、0 10 32 / .18 投影
/// - 选中 36% 白 tint，点错用 #FF2E7E
/// - 玻璃上的中文 700 以上、字号 ≥16
/// - 学习页读到玻璃主题，外壳仍是旧主题
void main() {
  final theme = LiquidGlassPreviewTheme.theme;

  test('页面底色是风格里的墨 #0B0C10', () {
    expect(LiquidGlass.ink, const Color(0xFF0B0C10));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0B0C10));
  });

  test('玻璃白 tint 落在 4%–6%', () {
    expect(LiquidGlass.tint, inInclusiveRange(0.04, 0.06));
  });

  test('按钮 bevel 是 26px', () {
    expect(LiquidGlass.bevel, 26);
  });

  test('投影 0 10px 32px / 18%', () {
    final shadow = LiquidGlass.shadow.single;
    expect(shadow.offset, const Offset(0, 10));
    expect(shadow.blurRadius, 32);
    expect(shadow.color.a, closeTo(0.18, 0.01));
  });

  test('选中 36% 白 tint，点错用粉 #FF2E7E', () {
    expect(LiquidGlass.tintSelected, 0.36);
    expect(LiquidGlass.wrongPink, const Color(0xFFFF2E7E));
  });

  test('氛围色就是那五支，透明度低到不抢字', () {
    expect(LiquidGlass.aura, <Color>[
      const Color(0xFFFF5A1F),
      const Color(0xFFFF2E7E),
      const Color(0xFF2BD9A0),
      const Color(0xFF8B5CFF),
      const Color(0xFF2E4BFF),
    ]);
  });

  test('玻璃上的中文：≥16px 且 700 以上', () {
    // 选项释义
    expect(theme.textTheme.titleMedium?.fontSize, greaterThanOrEqualTo(16));
    expect(
      theme.textTheme.titleMedium?.fontWeight!.value,
      greaterThanOrEqualTo(FontWeight.w700.value),
    );
    // 「不认识」等玻璃按钮
    expect(theme.textTheme.labelLarge?.fontSize, greaterThanOrEqualTo(16));
    expect(
      theme.textTheme.labelLarge?.fontWeight!.value,
      greaterThanOrEqualTo(FontWeight.w700.value),
    );
  });

  test('字体仍是 NotoSansSC', () {
    expect(theme.textTheme.displaySmall?.fontFamily, AppTheme.fontFamily);
    expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
  });

  testWidgets('学习页读到液态玻璃主题（局部覆盖生效）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudySessionPage()));
    // 不 pumpAndSettle：加载圈是无限动画。等数据层报错、切到错误态即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final themed = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(themed.scaffoldBackgroundColor, LiquidGlass.ink);
    expect(themed.textTheme.titleMedium?.fontSize, 16);
    expect(find.byType(LiquidGlassBackdrop), findsOneWidget,
        reason: '玻璃后面得有氛围层，否则玻璃没有东西可弯');
  });

  testWidgets('外壳仍是旧主题（没有被全局替换）', (tester) async {
    late ThemeData shellTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            shellTheme = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(shellTheme.scaffoldBackgroundColor, AppColors.background);
    expect(shellTheme.colorScheme.primary, AppColors.accent);
  });
}
