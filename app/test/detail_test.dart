import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/dao/detail_dao.dart';
import 'package:mw_english/data/morphology/root_whitelist.dart';
import 'package:mw_english/features/words/word_detail_page.dart';

/// 这里只测纯函数：解析与数据表本身。
/// 需要 SQLite 的部分（详情装配、形近词）在真机上验，测试环境没有 platform channel。
void main() {
  test('exchange 解析：过去式/过去分词/现在分词/三单/复数/比较级', () {
    final forms = DetailDao.parseExchange(
      'p:prompted/d:prompted/i:prompting/3:prompts/s:prompts/r:prompter',
    );
    expect(forms.length, 6);
    expect(forms.map((f) => f.label).toList(), [
      '过去式',
      '过去分词',
      '现在分词',
      '第三人称单数',
      '复数',
      '比较级',
    ]);
    expect(forms.first.value, 'prompted');
  });

  test('exchange 解析：忽略 ECDICT 内部标记 0/1，空串返回空表', () {
    expect(DetailDao.parseExchange('0:abandon/1:dp'), isEmpty);
    expect(DetailDao.parseExchange(''), isEmpty);
    expect(DetailDao.parseExchange('   '), isEmpty);
  });

  test('exchange 解析：最高级与比较级都识别', () {
    final forms = DetailDao.parseExchange('r:harsher/t:harshest');
    expect(forms.map((f) => f.label).toList(), ['比较级', '最高级']);
  });

  test('词根白名单：条目都在 100 条以上，键都是小写单词', () {
    expect(kRootWhitelist.length, greaterThan(100));
    for (final key in kRootWhitelist.keys) {
      expect(key, key.toLowerCase(), reason: '$key 不是小写');
      expect(key.contains(' '), isFalse, reason: '$key 是词组，不该进白名单');
      expect(kRootWhitelist[key]!.parts, isNotEmpty);
      expect(kRootWhitelist[key]!.note, isNotEmpty);
    }
  });

  test('词根白名单：拆解成分的显示文本带对连字符', () {
    final analysis = kRootWhitelist['transmit']!;
    expect(analysis.parts.first.label.endsWith('-'), isTrue);
  });

  testWidgets('详情页在无数据库时走错误态，不白屏', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const WordDetailPage(wordKey: 'transmit'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 测试环境没有 sqflite platform channel，应落到「词库打不开」
    expect(find.text('词库打不开'), findsOneWidget);
  });
}
