import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/shell/home_shell.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/features/profile/profile_page.dart';
import 'package:mw_english/features/study/study_page.dart';
import 'package:mw_english/features/study/study_session_page.dart';
import 'package:mw_english/features/words/word_detail_page.dart';
import 'package:mw_english/features/words/words_page.dart';

/// v0.7.0：全 App 换浅色纸底液态玻璃。
///
/// 断言取自需求原文：
/// - 全局主题是纸底浅色（纸 #F3F2EE、墨 #0B0C10、次要墨 70%），深色作废
/// - 首页 / 词库 / 详情 / 我的 四页都读到浅色主题，没有深色底残留
/// - 纸上正文与次要字对比 ≥4.5:1（纸面卡上也一样）
/// - Tab 栏是悬浮玻璃条，图标文字都是墨色
/// - M3 预览主题（study_preview_theme.dart）已删除
/// - 氛围渐变只留在学习卡片页
void main() {
  final theme = AppTheme.light;

  test('全局主题：浅色纸底 + 墨字，深色作废', () {
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, LiquidGlass.paper);
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.colorScheme.onSurface, LiquidGlass.ink);
    expect(theme.appBarTheme.backgroundColor, LiquidGlass.paper);
    // 调色板里不许再有深色底 / 深色面。
    expect(AppColors.background.computeLuminance(), greaterThan(0.8));
    expect(AppColors.surface.computeLuminance(), greaterThan(0.8));
    expect(AppColors.textPrimary.computeLuminance(), lessThan(0.1));
  });

  test('正文与次要字在纸上、纸面卡上都 ≥4.5:1', () {
    final backgrounds = <String, Color>{
      '纸': LiquidGlass.paper,
      '纸面卡': AppColors.surface,
    };
    for (final entry in backgrounds.entries) {
      final bg = entry.value;
      final primary = _contrast(LiquidGlass.ink, bg);
      final secondary = _contrast(_over(LiquidGlass.textSecondary, bg), bg);
      final tertiary = _contrast(_over(AppColors.textTertiary, bg), bg);

      expect(primary, greaterThanOrEqualTo(4.5),
          reason: '${entry.key}上正文只有 ${primary.toStringAsFixed(2)}:1');
      expect(secondary, greaterThanOrEqualTo(4.5),
          reason: '${entry.key}上次要字只有 ${secondary.toStringAsFixed(2)}:1');
      expect(tertiary, greaterThanOrEqualTo(4.5),
          reason: '${entry.key}上三级字只有 ${tertiary.toStringAsFixed(2)}:1');
    }
  });

  test('玻璃参数在合并后没被改动', () {
    expect(LiquidGlass.tint, inInclusiveRange(0, 0.02));
    expect(LiquidGlass.blur, inInclusiveRange(0, 2));
    expect(LiquidGlass.tintSelected, 0.36);
    expect(LiquidGlass.shadow.single.color.a, closeTo(0.20, 0.01));
    expect(LiquidGlass.shadowSelected.single.color.a, closeTo(0.28, 0.01));
  });

  testWidgets('首页读到浅色主题', (tester) async {
    await _pumpPaper(tester, const StudyPage());
  });

  testWidgets('词库页读到浅色主题', (tester) async {
    await _pumpPaper(tester, const WordsPage());
  });

  testWidgets('详情页读到浅色主题', (tester) async {
    await _pumpPaper(
      tester,
      const WordDetailPage(wordKey: 'transmit', displayWord: 'transmit'),
    );
  });

  testWidgets('我的页读到浅色主题', (tester) async {
    await _pumpPaper(tester, const ProfilePage());
  });

  testWidgets('学习卡片页仍带氛围层（只有这一页有）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StudySessionPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LiquidGlassBackdrop), findsOneWidget,
        reason: '玻璃后面得有东西可弯；氛围渐变只保留在学卡片页');
  });

  testWidgets('Tab 栏是悬浮玻璃条，图标文字都用墨色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeShell()),
    );
    await tester.pump();

    final shell = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(shell.extendBody, isTrue, reason: '玻璃条要压在内容上，内容从底下穿过去');

    // 「我的」只在 Tab 栏出现，用它反查整条玻璃。
    final barFinder = find.ancestor(
      of: find.text('我的'),
      matching: find.byType(GlassSurface),
    );
    expect(barFinder, findsWidgets, reason: '底部栏必须是一块玻璃');
    final bar = tester.widget<GlassSurface>(barFinder.first);
    expect(bar.radius, 28);
    expect(bar.blur, lessThanOrEqualTo(2));

    for (final label in ['学习', '词库', '阅读', '我的']) {
      expect(
        find.descendant(of: barFinder.first, matching: find.text(label)),
        findsOneWidget,
        reason: '$label 应该在同一条玻璃里',
      );
    }

    // 选中 = 纯墨，未选中 = 墨 70%（都用墨系，不引第二个颜色）。
    //
    // v0.7.2：文字改用 AnimatedDefaultTextStyle 做隐式过渡，颜色落在
    // 那一层（Text 自己不再带 style），所以从祖先上读。
    TextStyle labelStyle(String label) {
      final box = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.descendant(
                  of: barFinder.first, matching: find.text(label)),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      return box.style;
    }

    expect(labelStyle('学习').color, LiquidGlass.ink);
    expect(labelStyle('词库').color, LiquidGlass.textSecondary);
    expect(labelStyle('学习').fontWeight, FontWeight.w700);
  });

  test('M3 预览主题与它的专属测试已删除', () {
    // 测试进程的 cwd 是包根目录（app/）。
    expect(File('lib/app/theme/study_preview_theme.dart').existsSync(), isFalse,
        reason: '液态玻璃已定稿，M3 预览主题是死代码');
    expect(File('test/theme_m3_test.dart').existsSync(), isFalse);
  });
}

/// 四页共用的检查：读到浅色主题、Scaffold 不留深色底、没有氛围层。
Future<void> _pumpPaper(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold)).toList();
  expect(scaffolds, isNotEmpty);

  for (final scaffold in scaffolds) {
    final bg = scaffold.backgroundColor;
    if (bg == null) continue;
    expect(bg.computeLuminance(), greaterThan(0.8),
        reason: '页面还留着深色底：$bg');
  }

  final context = tester.element(find.byType(Scaffold).first);
  expect(Theme.of(context).brightness, Brightness.light);
  expect(Theme.of(context).scaffoldBackgroundColor, LiquidGlass.paper);
  expect(find.byType(LiquidGlassBackdrop), findsNothing,
      reason: '列表页背景有颜色会干扰阅读，氛围只留在学习卡片页');
}

/// WCAG 相对亮度对比度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 把带 alpha 的前景压到背景上。
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);
