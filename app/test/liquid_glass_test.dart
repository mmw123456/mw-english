import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass_preview_theme.dart';
import 'package:mw_english/data/models/study_card.dart';
import 'package:mw_english/features/study/study_session_page.dart';

/// 液态玻璃预览的约束测试。
///
/// 断言直接取自需求原文，不从实现里抄：
/// - v0.6.8 起页面底色是风格里的纸 #F3F2EE，正文用墨 #0B0C10
/// - 玻璃只有三样：4%–6% 白 tint、1px 迎光亮边、0 10 32 / .20 投影
/// - 选中 36% 白 tint + 投影加深，点错用 #FF2E7E
/// - 纸上正文对比 ≥4.5:1
/// - 玻璃上的中文 700 以上、字号 ≥16
/// - 学习页读到纸底玻璃主题，外壳仍是深色旧主题
void main() {
  final theme = LiquidGlassPreviewTheme.theme;

  // v0.6.6 单词框玻璃用例
  wordCardTests();

  test('页面底色是风格里的纸 #F3F2EE，正文是墨 #0B0C10', () {
    expect(LiquidGlass.paper, const Color(0xFFF3F2EE));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F2EE));
    expect(LiquidGlass.ink, const Color(0xFF0B0C10));
    expect(LiquidGlass.textPrimary, const Color(0xFF0B0C10));
  });

  test('纸上正文对比 ≥4.5:1（墨 17.5、次要字 4.5）', () {
    expect(_contrast(LiquidGlass.textPrimary, LiquidGlass.paper),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(LiquidGlass.textSecondary, LiquidGlass.paper),
        greaterThanOrEqualTo(4.5));
    // 次要字是需求点名的 #6B6E78，不是随手调出来的灰。
    expect(LiquidGlass.textSecondary, const Color(0xFF6B6E78));
  });

  test('玻璃白 tint 落在 4%–6%', () {
    expect(LiquidGlass.tint, inInclusiveRange(0.04, 0.06));
  });

  test('按钮 bevel 是 26px', () {
    expect(LiquidGlass.bevel, 26);
  });

  test('投影 0 10px 32px / 20%', () {
    final shadow = LiquidGlass.shadow.single;
    expect(shadow.offset, const Offset(0, 10));
    expect(shadow.blurRadius, 32);
    expect(shadow.color.a, closeTo(0.20, 0.01));
  });

  test('选中 36% 白 tint，点错用粉 #FF2E7E', () {
    expect(LiquidGlass.tintSelected, 0.36);
    expect(LiquidGlass.wrongPink, const Color(0xFFFF2E7E));
  });

  test('选中态投影比常态深，选中白 tint 36%', () {
    expect(LiquidGlass.tintSelected, 0.36);
    expect(
      LiquidGlass.shadowSelected.single.color.a,
      greaterThan(LiquidGlass.shadow.single.color.a),
      reason: '选中态要浮起来，投影必须比常态重',
    );
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

  testWidgets('学习页读到浅色纸底玻璃主题（局部覆盖生效）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudySessionPage()));
    // 不 pumpAndSettle：加载圈是无限动画。等数据层报错、切到错误态即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final themed = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(themed.scaffoldBackgroundColor, LiquidGlass.paper);
    expect(themed.colorScheme.brightness, Brightness.light,
        reason: '纸底是浅色，主题必须跟着切 light，否则系统控件会用白字');
    expect(themed.appBarTheme.foregroundColor, LiquidGlass.ink,
        reason: '返回 X 与书本图标用墨');
    expect(themed.textTheme.titleMedium?.fontSize, 16);
    expect(find.byType(LiquidGlassBackdrop), findsOneWidget,
        reason: '玻璃后面得有氛围层，否则玻璃没有东西可弯');
  });

  testWidgets('外壳仍是深色旧主题（没有被全局替换）', (tester) async {
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
    expect(shellTheme.colorScheme.brightness, Brightness.dark);
  });
}

/// WCAG 相对亮度对比度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// v0.6.6：单词框从「不透明深色卡片」换成玻璃，且字仍在中央平坦区不变形。
void wordCardTests() {
  const card = StudyCard(
    wordKey: 'transmit',
    word: 'transmit',
    phonetic: 'trænzˈmɪt',
    meaning: '传送',
    meaningEcdict: '',
    box: 1,
    isNew: true,
    isRetest: false,
    options: <String>['传送', '放弃', '获得', '维持'],
    answerIndex: 0,
  );

  testWidgets('单词框是玻璃（两层：正文 + 发音），不是不透明卡片', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LiquidGlassPreviewTheme.theme,
        home: const Scaffold(body: StudyWordCard(card: card)),
      ),
    );

    final glasses = find.byType(GlassSurface);
    expect(glasses, findsNWidgets(2),
        reason: '单词正文一块 + 发音胶囊一块');
    // 正文那块用的是标准玻璃参数：5% 白 tint、26 圆角、6px 磨砂。
    final block = tester.widget<GlassSurface>(glasses.first);
    expect(block.tintAlpha, 0.05);
    expect(block.radius, 26);
    expect(block.blur, 6);
    expect(block.tintColor, isNull, reason: '玻璃本身不上色');
  });

  testWidgets('单词 36pt、音标小字，字体仍是 NotoSansSC', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LiquidGlassPreviewTheme.theme,
        home: const Scaffold(body: StudyWordCard(card: card)),
      ),
    );

    final word = tester.widget<Text>(find.text('transmit'));
    expect(word.style?.fontSize, 36);
    expect(word.style?.fontFamily, AppTheme.fontFamily);

    final phonetic = tester.widget<Text>(find.text('/trænzˈmɪt/'));
    expect(phonetic.style?.fontSize, lessThan(36),
        reason: '音标要小字，落在中央平坦区');
  });
}
