import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/widgets/example_line.dart';
import 'package:mw_english/data/examples/example_bank.dart';
import 'package:mw_english/data/lookup/lookup_service.dart';
import 'package:mw_english/data/models/word_detail.dart';
import 'package:mw_english/data/models/word_example.dart';
import 'package:mw_english/features/lookup/lookup_result_card.dart';

/// v0.12.0 例句：资源口径 + 解析 + 两个界面的显示规矩。
///
/// 详情页整页要开 SQLite（测试环境开不了），所以例句区块抽成了
/// [ExampleSection] 单独测；查词卡本来就是无状态的，直接喂 [LookupResult]。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WordExample mkEx(String en, [String zh = '中文', String? hl]) =>
      WordExample(en: en, hl: hl ?? en.replaceAll('pulse', '**pulse**'), zh: zh);

  WordDetail mkDetail({
    String wordKey = 'pulse',
    List<WordExample> examples = const [],
  }) =>
      WordDetail(
        wordKey: wordKey,
        word: wordKey,
        phonetic: '',
        meaningPdf: 'n. 脉搏',
        pdfTruncated: false,
        meaningEcdict: '',
        pos: '',
        tag: '',
        collins: 0,
        no: 1,
        box: 0,
        isAdded: false,
        killed: false,
        starred: false,
        forms: const [],
        synonyms: const [],
        nearWords: const [],
        examples: examples,
      );

  Widget wrapApp(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  group('资源口径', () {
    late Map<String, List<WordExample>> bank;

    setUpAll(() async {
      final raw = await rootBundle.loadString(ExampleBank.assetPath);
      ExampleBank.hydrate(raw);
      bank = parseExamplesAsset(raw);
    });

    test('188 个词有例句，共 306 句，每词 1–3 条', () {
      expect(bank.length, 188);
      var total = 0;
      for (final entry in bank.entries) {
        expect(entry.value.length, inInclusiveRange(1, 3), reason: entry.key);
        total += entry.value.length;
      }
      expect(total, 306);
    });

    test('每条都有英文、中文、加粗标记，且都能溯源到 Tatoeba 句 id', () {
      for (final entry in bank.entries) {
        for (final s in entry.value) {
          expect(s.en.trim(), isNotEmpty, reason: entry.key);
          expect(s.zh.trim(), isNotEmpty, reason: entry.key);
          expect(s.hl.contains('**'), isTrue,
              reason: '${entry.key} 的例句没标出目标词：${s.en}');
          expect(s.tatoebaId, isNotNull, reason: entry.key);
          // 去掉标记后必须与原文一字不差
          expect(s.hl.replaceAll('**', ''), s.en, reason: entry.key);
        }
      }
    });

    test('署名文案带来源与许可', () {
      expect(kExampleAttribution, contains('Tatoeba'));
      expect(kExampleAttribution, contains('CC-BY 2.0 FR'));
    });

    test('多义词只用词书本义：pulse 三句都是「脉搏」，没有「脉冲」', () {
      final list = bank['pulse']!;
      expect(list.length, 3);
      for (final s in list) {
        expect(s.zh, contains('脉搏'));
        expect(s.zh, isNot(contains('脉冲')));
      }
    });

    test('短语按整串显例句：take advantage of', () {
      final list = bank['take advantage of']!;
      expect(list, isNotEmpty);
      for (final s in list) {
        expect(s.en.toLowerCase(), contains('advantage of'));
        expect(s.hl, contains('**'));
      }
    });

    test('没有例句的词就是空（632 个），不编也不拿别的词顶', () {
      for (final key in ['transmit', 'prevail', 'in retrospect', 'abortion']) {
        expect(bank.containsKey(key), isFalse, reason: key);
        expect(ExampleBank.forWord(key), isEmpty, reason: key);
      }
      expect(ExampleBank.forWord('pulse').length, 3);
      // 大小写不敏感
      expect(ExampleBank.forWord('Pulse').length, 3);
    });
  });

  group('解析', () {
    test('缺 en / zh 的条跳过，hl 缺省回落到 en', () {
      final raw = jsonEncode({
        'words': {
          'ok': [
            {'en': 'A pulse.', 'zh': '脉搏。', 'id': 7},
            {'en': 'No zh.'},
            {'zh': '没有英文。'},
          ],
        },
      });
      final bank = parseExamplesAsset(raw);
      expect(bank['ok']!.length, 1);
      expect(bank['ok']!.first.hl, 'A pulse.');
      expect(bank['ok']!.first.tatoebaId, 7);
    });

    test('结构不对返回空表，不抛', () {
      expect(parseExamplesAsset('[]'), isEmpty);
      expect(parseExamplesAsset('{"words": 3}'), isEmpty);
      expect(parseExamplesAsset('not json'), isEmpty);
    });

    test('spans 按 ** 切成普通 / 加粗交替', () {
      const e = WordExample(en: 'My pulse is fast.', hl: 'My **pulse** is fast.', zh: '脉搏。');
      final spans = e.spans;
      expect(spans.map((s) => s.text).toList(), ['My ', 'pulse', ' is fast.']);
      expect(spans.map((s) => s.bold).toList(), [false, true, false]);
    });
  });

  group('详情页例句区块', () {
    testWidgets('有例句：几条画几条 + 底部署名', (tester) async {
      await tester.pumpWidget(
        wrapApp(
          Scaffold(
            body: ExampleSection(
              examples: [
                mkEx('My pulse is fast.', '我的脉搏很快。'),
                mkEx('Check the pulse again.', '再检查一下脉搏。'),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('detail-example-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-example-1')), findsOneWidget);
      expect(find.text('我的脉搏很快。'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-example-source')), findsOneWidget);
      expect(find.text(kExampleAttribution), findsOneWidget);
    });

    testWidgets('没例句：一行「暂无例句」，不留空、不署名', (tester) async {
      await tester.pumpWidget(
        wrapApp(const Scaffold(body: ExampleSection(examples: []))),
      );
      expect(find.byKey(const ValueKey('detail-no-example')), findsOneWidget);
      expect(find.text('暂无例句'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-example-source')), findsNothing);
    });

    testWidgets('遮盖中文：译文换成提示，点一下才出', (tester) async {
      var revealed = false;
      await tester.pumpWidget(
        wrapApp(
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ExampleSection(
                examples: [mkEx('My pulse is fast.', '我的脉搏很快。')],
                maskedOf: (_) => !revealed,
                onReveal: (_) => setState(() => revealed = true),
              ),
            ),
          ),
        ),
      );
      expect(find.text('我的脉搏很快。'), findsNothing);
      expect(find.text('点一下显示中文'), findsOneWidget);
      await tester.tap(find.text('点一下显示中文'));
      await tester.pump();
      expect(find.text('我的脉搏很快。'), findsOneWidget);
    });
  });

  group('查词结果卡', () {
    testWidgets('有例句只显第一条，不展开', (tester) async {
      await tester.pumpWidget(
        wrapApp(
          Scaffold(
            body: LookupResultCard(
              result: LookupResult(
                detail: mkDetail(
                  examples: [
                    mkEx('My pulse is fast.', '我的脉搏很快。'),
                    mkEx('Check the pulse again.', '再检查一下脉搏。'),
                  ],
                ),
                source: LookupSource.book,
              ),
              onSpeak: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('lookup-example')), findsOneWidget);
      expect(find.text('我的脉搏很快。'), findsOneWidget);
      expect(find.text('再检查一下脉搏。'), findsNothing);
      expect(find.text('Tatoeba · CC-BY 2.0 FR'), findsOneWidget);
    });

    testWidgets('没例句整块不出现', (tester) async {
      await tester.pumpWidget(
        wrapApp(
          Scaffold(
            body: LookupResultCard(
              result: LookupResult(
                detail: mkDetail(wordKey: 'transmit'),
                source: LookupSource.dict,
              ),
              onSpeak: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('lookup-example')), findsNothing);
      expect(find.text('Tatoeba · CC-BY 2.0 FR'), findsNothing);
    });
  });
}
