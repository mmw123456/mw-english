import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/study_preview_theme.dart';
import 'package:mw_english/features/study/study_session_page.dart';

/// v0.6.3 预览主题的约束测试。
///
/// 断言来自需求原文，不从实现里抄：
/// - 必须是 Material 3（`useMaterial3 = true`）
/// - 必须是深色（`Brightness.dark`）
/// - 种子必须是现有那支冷白强调色，生成结果不许变成艳色
/// - 三级深浅必须真的分三级（亮度递增）
/// - 字号必须是 M3 默认那一套，不许自己发明
void main() {
  final theme = StudyPreviewTheme.m3;
  final scheme = theme.colorScheme;

  test('走 Material 3 + 深色', () {
    expect(theme.useMaterial3, isTrue);
    expect(scheme.brightness, Brightness.dark);
  });

  test('种子颜色就是现有强调色，且没被拉成艳色', () {
    final seed = HSLColor.fromColor(AppColors.accent);
    final primary = HSLColor.fromColor(scheme.primary);
    final dh = (seed.hue - primary.hue).abs();
    expect(dh < 30 || dh > 330, isTrue,
        reason: '色相差 ${dh.toStringAsFixed(1)}°，说明种子不是这支冷白');
    // 用 HSV 判「艳不艳」：HSL 的饱和度在近白/近黑处会虚高。
    // 默认 tonalSpot 会把这支种子拉成 #A0CAFD（HSV 饱和度 0.37 的天蓝）。
    final hsv = HSVColor.fromColor(scheme.primary);
    expect(hsv.saturation, lessThan(0.15),
        reason: 'primary HSV 饱和度 ${hsv.saturation.toStringAsFixed(2)}，已经不是冷白那一系');
    expect(hsv.value, greaterThan(0.7),
        reason: 'primary 应该是浅色（近白），现在亮度 ${hsv.value.toStringAsFixed(2)}');
  });

  test('三级深浅真的是三档，且逐级抬起', () {
    final low = scheme.surfaceContainerLow.computeLuminance();
    final mid = scheme.surfaceContainer.computeLuminance();
    final high = scheme.surfaceContainerHigh.computeLuminance();
    expect(low, lessThan(mid));
    expect(mid, lessThan(high));
  });

  test('选中态容器与未选中容器可区分', () {
    final selected = HSLColor.fromColor(scheme.primaryContainer);
    final unselected = HSLColor.fromColor(scheme.surfaceContainerHigh);
    expect(
      (selected.lightness - unselected.lightness).abs(),
      greaterThan(0.2),
      reason: '选中态与未选中态亮度差太小，看不出选了哪个',
    );
  });

  testWidgets('字号吃 M3 默认（36 / 24 / 16 / 14）', (tester) async {
    late TextTheme textTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            textTheme = Theme.of(context).textTheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // M3 的尺寸在 MaterialApp 里由 Localizations 叠加，裸 ThemeData 上不带 fontSize。
    expect(textTheme.displaySmall?.fontSize, 36);
    expect(textTheme.headlineSmall?.fontSize, 24);
    expect(textTheme.titleMedium?.fontSize, 16);
    expect(textTheme.labelLarge?.fontSize, 14);
  });

  test('字体仍是 NotoSansSC（中文不落回系统字体）', () {
    expect(theme.textTheme.displaySmall?.fontFamily, AppTheme.fontFamily);
    expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
  });

  testWidgets('学习页整页读到的是 M3 主题（局部覆盖生效）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudySessionPage()));
    // 不要 pumpAndSettle：加载圈是无限动画。这里只等数据层报错、切到错误态。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final themed = Theme.of(tester.element(find.byType(Scaffold)));
    expect(themed.useMaterial3, isTrue);
    expect(themed.colorScheme.brightness, Brightness.dark);
    expect(themed.colorScheme.primaryContainer, scheme.primaryContainer,
        reason: '页面里读到的配色必须就是预览主题那一套');
  });

  testWidgets('其他页面仍是旧主题（没有被全局替换）', (tester) async {
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
    expect(shellTheme.colorScheme.primary, AppColors.accent,
        reason: '全局主题的 primary 仍是手写强调色，说明没换成 M3 生成色');
  });
}
