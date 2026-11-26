import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/data/models/study_card.dart';
import 'package:mw_english/features/study/study_session_page.dart';

/// 液态玻璃预览的约束测试。
///
/// 断言直接取自需求原文，不从实现里抄：
/// - v0.6.8 起页面底色是风格里的纸 #F3F2EE，正文用墨 #0B0C10
/// - v0.6.9 起玻璃洗干净：磨砂 ≤2px、白 tint ≤2%，靠亮边 + 投影 + 背后颜色
/// - 选中 36% 白 tint + 投影加深（.28），点错用 #FF2E7E，投影常态 .20
/// - 纸上 / 彩色氛围上的正文对比 ≥4.5:1（按最差叠色算）
/// - 顶部是一条悬浮胶囊（X + 进度 + 书本），下面 2px 进度线
/// - v0.7.0 起纸底玻璃提成全局主题，学习页不再局部覆盖
void main() {
  // v0.7.0 起纸底玻璃就是全局主题，不再有预览专用的一套。
  final theme = AppTheme.light;

  // v0.6.6 单词框玻璃用例
  wordCardTests();

  test('页面底色是风格里的纸 #F3F2EE，正文是墨 #0B0C10', () {
    expect(LiquidGlass.paper, const Color(0xFFF3F2EE));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F2EE));
    expect(LiquidGlass.ink, const Color(0xFF0B0C10));
    expect(LiquidGlass.textPrimary, const Color(0xFF0B0C10));
  });

  test('纸上正文对比 ≥4.5:1', () {
    expect(_contrast(LiquidGlass.textPrimary, LiquidGlass.paper),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(_over(LiquidGlass.textSecondary, LiquidGlass.paper),
            LiquidGlass.paper),
        greaterThanOrEqualTo(4.5));
  });

  test('压在氛围色块上的字也 ≥4.5:1（按 25% 峰值算最差）', () {
    // 氛围一浓，字就可能正好落在某团光的中心。这里逐色算最差叠色：
    // 纸 ← 光圈 25% ← 玻璃 2% 白 tint，再把带 alpha 的字压上去。
    for (final aura in LiquidGlass.aura) {
      final bg = _worstCaseBackdrop(aura);
      final primary = _contrast(LiquidGlass.textPrimary, bg);
      final secondary =
          _contrast(_over(LiquidGlass.textSecondary, bg), bg);
      expect(primary, greaterThanOrEqualTo(4.5),
          reason: '正文压在 ${_hex(aura)} 上只有 ${primary.toStringAsFixed(2)}:1');
      expect(secondary, greaterThanOrEqualTo(4.5),
          reason: '次要字压在 ${_hex(aura)} 上只有 ${secondary.toStringAsFixed(2)}:1');
    }
  });

  test('磨砂 0–2px、白 tint 0–2%（不再整块上底色）', () {
    expect(LiquidGlass.blur, inInclusiveRange(0, 2));
    expect(LiquidGlass.tint, inInclusiveRange(0, 0.02));
    // 选中态与点错态不动。
    expect(LiquidGlass.tintSelected, 0.36);
    expect(LiquidGlass.wrongPink, const Color(0xFFFF2E7E));
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

  test('选中态投影比常态深（.28）', () {
    expect(
      LiquidGlass.shadowSelected.single.color.a,
      closeTo(0.28, 0.01),
      reason: '选中态要浮起来，投影必须比常态重',
    );
  });

  test('氛围色还是那五支，漂移周期在 20–30 秒', () {
    expect(LiquidGlass.aura, <Color>[
      const Color(0xFFFF5A1F),
      const Color(0xFFFF2E7E),
      const Color(0xFF2BD9A0),
      const Color(0xFF8B5CFF),
      const Color(0xFF2E4BFF),
    ]);
    expect(LiquidGlass.auraDrift.inSeconds, inInclusiveRange(20, 30));
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

  testWidgets('磨砂为 0 时不开 BackdropFilter，>0 才开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Column(
            children: [
              GlassSurface(blur: 0, child: Text('无磨砂')),
              GlassSurface(child: Text('默认磨砂')),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget,
        reason: '只有默认那层需要模糊；0 的那层不该付 saveLayer 的代价');
    expect(tester.widget<GlassSurface>(find.byType(GlassSurface).first).blur, 0);
    expect(
      tester.widget<GlassSurface>(find.byType(GlassSurface).last).blur,
      LiquidGlass.blur,
    );
  });

  testWidgets('顶部胶囊条：X、进度、书本都在同一条玻璃里', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: StudyTopCapsule(
            label: '1 / 28',
            onClose: () {},
            onDetail: () {},
          ),
        ),
      ),
    );

    final capsule = find.byType(GlassSurface);
    expect(capsule, findsOneWidget, reason: '整条只有一个玻璃外壳');

    // 三样东西都在胶囊内部，不是裸摆在纸上。
    for (final finder in <Finder>[
      find.text('1 / 28'),
      find.byIcon(Icons.close_rounded),
      find.byIcon(Icons.menu_book_outlined),
    ]) {
      expect(
        find.descendant(of: capsule, matching: finder),
        findsOneWidget,
        reason: '胶囊里少了 $finder',
      );
    }

    // 胶囊形（radius 999）且浮起来：投影是常态 .20。
    final glass = tester.widget<GlassSurface>(capsule);
    expect(glass.radius, greaterThanOrEqualTo(24));
    expect(glass.blur, 0, reason: '小胶囊不上磨砂');
    expect(glass.shadow.single.color.a, closeTo(0.20, 0.01));

    // 数字是小字，不跟单词抢视线。
    final label = tester.widget<Text>(find.text('1 / 28'));
    expect(label.style?.fontSize, lessThanOrEqualTo(14));
  });

  testWidgets('没有可跳词条时书本图标不显示，但右侧留白对称', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: StudyTopCapsule(label: '完成', onClose: () {}),
        ),
      ),
    );
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('胶囊下面那根进度线是 2px，按 1/28 填充', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: SizedBox(width: 280, child: StudyProgressLine(value: 1 / 28)),
        ),
      ),
    );

    final line = tester.widget<StudyProgressLine>(find.byType(StudyProgressLine));
    expect(line.thickness, 2);

    final bar = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(StudyProgressLine),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(bar.height, 2);

    final fill = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byType(StudyProgressLine),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(fill.widthFactor, closeTo(1 / 28, 1e-9));
  });

  testWidgets('状态与箱数是两颗小标签胶囊，字号层级拉开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StudyTagPill(label: '今日重测', emphasized: true),
              StudyTagPill(label: '箱 1'),
            ],
          ),
        ),
      ),
    );

    final pills = find.byType(GlassSurface);
    expect(pills, findsNWidgets(2), reason: '两颗各是一个胶囊');
    for (final e in tester.widgetList<GlassSurface>(pills)) {
      expect(e.radius, greaterThanOrEqualTo(24));
      expect(e.blur, 0);
    }

    final status = tester.widget<Text>(find.text('今日重测'));
    final box = tester.widget<Text>(find.text('箱 1'));
    expect(status.style!.fontSize! - box.style!.fontSize!, greaterThanOrEqualTo(2),
        reason: '13 / 11 —— 主次靠字号差，不靠颜色');
  });

  testWidgets('投影只画在形状外面：玻璃内部不会被压灰', (tester) async {
    // v0.6.9 踩到的坑：BoxShadow 会把 20% 黑涂进形状内部，tint 降到 2% 后
    // 整块玻璃变成灰板（纸 243 → 195）。这里直接量像素。
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 280,
                height: 160,
                color: Colors.white,
                child: const Center(
                  child: SizedBox(
                    width: 200,
                    height: 80,
                    child: GlassSurface(blur: 0, child: SizedBox.expand()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = key.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });

    int channel(int x, int y, int c) => bytes!.getUint8((y * 280 + x) * 4 + c);

    // 玻璃中心（140, 80）：三通道都要 ≥250 才算没被投影压灰。
    for (var c = 0; c < 3; c++) {
      expect(channel(140, 80, c), greaterThan(248),
          reason: '玻璃内部被投影压灰了（通道 $c = ${channel(140, 80, c)}）');
    }
    // 玻璃下方 46px（y=126，仍在圆角外）：应该有影，不是纯白。
    expect(channel(140, 126, 0), lessThan(250), reason: '形状外应当有投影');
  });

  testWidgets('学习页读到浅色纸底玻璃主题（全局主题生效）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const StudySessionPage()),
    );
    // 不 pumpAndSettle：加载圈与氛围漂移都是无限动画。等数据层报错即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final themed = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(themed.scaffoldBackgroundColor, LiquidGlass.paper);
    expect(themed.colorScheme.brightness, Brightness.light,
        reason: '纸底是浅色，主题必须跟着切 light，否则系统控件会用白字');
    expect(themed.textTheme.titleMedium?.fontSize, 16);
    expect(find.byType(LiquidGlassBackdrop), findsOneWidget,
        reason: '玻璃后面得有氛围层，否则玻璃没有东西可弯');
    expect(find.byType(StudyTopCapsule), findsOneWidget,
        reason: 'v0.6.9 顶栏是一条悬浮胶囊');
    expect(find.byType(AppBar), findsNothing,
        reason: 'AppBar 撤了，字和图标不再裸摆在纸上');
    expect(find.byType(StudyProgressLine), findsOneWidget);
  });

  testWidgets('全局主题就是纸底玻璃，深色主题已作废', (tester) async {
    late ThemeData shellTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            shellTheme = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(shellTheme.scaffoldBackgroundColor, LiquidGlass.paper);
    expect(shellTheme.colorScheme.brightness, Brightness.light,
        reason: '深色主题作废，全局只剩浅色一套');
    // 旧的深色底、深色面不许再出现在调色板里。
    expect(AppColors.background.computeLuminance(), greaterThan(0.8));
    expect(AppColors.surface.computeLuminance(), greaterThan(0.8));
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

/// 把带 alpha 的前景压到背景上。
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// 最差底色：纸 ← 某支氛围色 25% 峰值 ← 玻璃 2% 白 tint。
Color _worstCaseBackdrop(Color aura) {
  final auraOverPaper = Color.alphaBlend(
    aura.withValues(alpha: 0.25),
    LiquidGlass.paper,
  );
  return Color.alphaBlend(
    Colors.white.withValues(alpha: LiquidGlass.tint),
    auraOverPaper,
  );
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

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
        theme: AppTheme.light,
        home: const Scaffold(body: StudyWordCard(card: card)),
      ),
    );

    final glasses = find.byType(GlassSurface);
    expect(glasses, findsNWidgets(2),
        reason: '单词正文一块 + 发音胶囊一块');
    // 正文那块用的是标准玻璃参数：2% 白 tint、26 圆角、1.5px 磨砂。
    final block = tester.widget<GlassSurface>(glasses.first);
    expect(block.tintAlpha, LiquidGlass.tint);
    expect(block.radius, 26);
    expect(block.blur, lessThanOrEqualTo(2));
    expect(block.tintColor, isNull, reason: '玻璃本身不上色');
  });

  testWidgets('单词 36pt、音标小字，字体仍是 NotoSansSC', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
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
