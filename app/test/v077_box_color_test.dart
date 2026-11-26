import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/box_colors.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/app/widgets/box_badge.dart';
import 'package:mw_english/data/models/word_entry.dart';
import 'package:mw_english/features/study/box_band.dart';
import 'package:mw_english/features/words/words_page.dart';

/// v0.7.7 六箱色彩系统。
///
/// 断言取自需求原文，不从实现里抄：
/// - 箱位 → 颜色七档：箱 0 墨 35% / 1 粉 / 2 紫 / 3 蓝 / 4 橙 / 5 深橙 / 6 薄荷
/// - 色点一律 8px 实心圆，靠色相区分，不加描边
/// - 词库行色点跟箱位走；自加词固定墨 35% 灰点
/// - 徽章 = 15% 淡底 + 色点 + 墨字，箱 0 写「新词」，不许白字
/// - 色带段宽按词数占比，0 词段只留固定色标
void main() {
  WordEntry myEntry(int no, String word) => WordEntry(
        no: no,
        word: word,
        wordKey: word,
        phonetic: 'test',
        meaningPdf: '释义',
        pdfTruncated: false,
        meaningEcdict: '完整释义',
        pos: 'n.',
        tag: '',
        collins: 0,
      );

  DictEntry dictEntry(String word) => DictEntry(
        word: word,
        phonetic: '',
        translation: '斑马',
        pos: 'n.',
        tag: '',
        collins: 0,
        frq: 0,
      );

  Widget page(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      );

  group('箱位 → 颜色', () {
    test('七档逐档对上（需求给死的色值）', () {
      expect(boxColor(0), BoxColors.newWord);
      expect(boxColor(1), const Color(0xFFFF2E7E), reason: '箱 1 粉');
      expect(boxColor(2), const Color(0xFF8B5CFF), reason: '箱 2 紫');
      expect(boxColor(3), const Color(0xFF2E4BFF), reason: '箱 3 蓝');
      expect(boxColor(4), const Color(0xFFE8490F), reason: '箱 4 橙 = 环那个橙');
      expect(boxColor(5), const Color(0xFFC43A06), reason: '箱 5 深橙');
      expect(boxColor(6), const Color(0xFF2BD9A0), reason: '箱 6 薄荷');
    });

    test('箱 0 是墨 35%，两头越界夹住', () {
      expect(boxColor(0).a, closeTo(0.35, 0.01));
      expect(boxColor(-3), boxColor(0), reason: '未进调度按新词算');
      expect(boxColor(7), boxColor(6), reason: '箱 6 以上都是已掌握');
    });

    test('七档互不相同：8px 色点靠色相分得开', () {
      final all = [for (var b = 0; b <= 6; b++) boxColor(b).toARGB32()];
      expect(all.toSet().length, 7);
    });

    test('淡底是箱位色 15%，箱 0 是墨 15% 而不是 35%×15%', () {
      expect(boxTint(4).a, closeTo(0.15, 0.005));
      expect(boxTint(4).toARGB32() & 0x00FFFFFF,
          boxColor(4).toARGB32() & 0x00FFFFFF);
      expect(boxTint(0).a, closeTo(0.15, 0.005));
    });
  });

  testWidgets('词库行：色点颜色跟箱位走，8px 实心圆', (tester) async {
    const boxes = [0, 1, 4, 6];
    await tester.pumpWidget(
      page(
        Column(
          children: [
            for (final b in boxes)
              WordRow(
                entry: myEntry(b + 1, 'word$b'),
                box: b,
                masked: false,
                revealed: false,
                onToggleMask: () {},
                onTap: () {},
              ),
          ],
        ),
      ),
    );

    for (var i = 0; i < boxes.length; i++) {
      final dot = find.byType(BoxDot).at(i);
      expect(tester.widget<BoxDot>(dot).box, boxes[i]);

      final box = tester.widget<Container>(
        find.descendant(of: dot, matching: find.byType(Container)),
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, boxColor(boxes[i]), reason: '第 $i 行的点色必须跟箱位一致');
      expect(deco.shape, BoxShape.circle);
      expect(tester.getSize(dot), const Size(8, 8));
    }
  });

  testWidgets('自加词行：固定墨 35% 灰点', (tester) async {
    await tester.pumpWidget(
      page(
        AddedRow(
          entry: dictEntry('zebra'),
          masked: false,
          revealed: false,
          onToggleMask: () {},
          onTap: () {},
          onRemove: () {},
        ),
      ),
    );

    final dot = find.byType(BoxDot);
    expect(tester.widget<BoxDot>(dot).box, 0);
    final box = tester.widget<Container>(
      find.descendant(of: dot, matching: find.byType(Container)),
    );
    expect((box.decoration! as BoxDecoration).color, BoxColors.newWord);
  });

  testWidgets('箱位徽章：15% 淡底 + 色点 + 墨字，箱 0 写「新词」', (tester) async {
    await tester.pumpWidget(
      page(
        const Column(
          children: [
            BoxBadge(key: ValueKey('b0'), box: 0),
            BoxBadge(key: ValueKey('b4'), box: 4),
            BoxBadge(key: ValueKey('b6'), box: 6),
          ],
        ),
      ),
    );

    expect(find.text('新词'), findsOneWidget);
    expect(find.text('箱 4'), findsOneWidget);
    expect(find.text('箱 6'), findsOneWidget);

    for (final b in [0, 4, 6]) {
      final root = find.byKey(ValueKey('b$b'));
      final shell = tester.widget<Container>(
        find.descendant(of: root, matching: find.byType(Container)).first,
      );
      final deco = shell.decoration! as BoxDecoration;
      expect(deco.color, boxTint(b), reason: '箱 $b 的徽章底色必须是箱位色 15%');
      expect(deco.color!.a, closeTo(0.15, 0.01));

      final label = tester.widget<Text>(
        find.descendant(of: root, matching: find.byType(Text)),
      );
      expect(label.style!.color, LiquidGlass.ink, reason: '薄荷底上不许用白字');
      expect(label.style!.fontSize, 11);
    }
  });

  testWidgets('色带：段宽按词数占比，0 词段只留固定色标', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const counts = {0: 700, 1: 0, 2: 50, 3: 30, 4: 20, 5: 0, 6: 20};
    await tester.pumpWidget(
      page(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: BoxBand(counts: counts),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('band-seg-6')), findsOneWidget,
        reason: '箱 0 + 箱 1–6 共七段');

    final segs = [
      for (var b = 0; b <= 6; b++) find.byKey(ValueKey('band-seg-$b')),
    ];
    for (var b = 0; b <= 6; b++) {
      expect(tester.widget<ColoredBox>(segs[b]).color, boxColor(b));
    }

    final widths = [
      for (var b = 0; b <= 6; b++) tester.getSize(segs[b]).width,
    ];
    // 高度也得是 10：ColoredBox 没有固有高度，Row 不 stretch 时整段会被压成 0 高，
    // 宽度全对但色带看不见。
    for (var b = 0; b <= 6; b++) {
      expect(tester.getSize(segs[b]).height, BoxBand.bandHeight,
          reason: '第 $b 段必须有高度，不能是 0');
    }
    expect(widths[1], BoxBand.stubWidth, reason: '箱 1 是 0 词，只留色标');
    expect(widths[5], BoxBand.stubWidth, reason: '箱 5 是 0 词，只留色标');
    expect(widths[0], greaterThan(widths[2]), reason: '700 词应比 50 词宽');

    // 剩余宽度按 700 : 50 : 30 : 20 : 20 分。
    expect(widths[2] / widths[0], closeTo(50 / 700, 0.01));
    expect(widths[3] / widths[2], closeTo(30 / 50, 0.02));
    expect(widths[4], closeTo(widths[6], 1.0), reason: '箱 4 与箱 6 同为 20 词');

    // 色带总宽 = 屏宽 390 - 左右 20 - 六道 2px 缝。
    final total = widths.fold<double>(0, (a, b) => a + b) + 6 * BoxBand.gap;
    expect(total, closeTo(350, 0.5));

    // 图例：七项都标「名字 · M 词」，箱 0 用「新词」。
    expect(find.text('新词 · 700 词'), findsOneWidget);
    expect(find.text('箱 1 · 0 词'), findsOneWidget);
    expect(find.text('箱 6 · 20 词'), findsOneWidget);
  });

  testWidgets('色带：全部为 0 词时七段都退成色标，不报错', (tester) async {
    await tester.pumpWidget(
      page(const BoxBand(counts: {})),
    );

    final segs = [
      for (var b = 0; b <= 6; b++) find.byKey(ValueKey('band-seg-$b')),
    ];
    for (var b = 0; b <= 6; b++) {
      expect(tester.getSize(segs[b]).width, BoxBand.stubWidth);
    }
    expect(find.text('新词 · 0 词'), findsOneWidget);
  });
}
