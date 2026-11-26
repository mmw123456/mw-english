import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mw_english/data/study/choice_options.dart';
import 'package:mw_english/data/study/study_flow.dart';

/// v0.6.0 四选一的规则测试。
///
/// 这一版把「答错还能继续选」「答对自动走」都做成纯状态，所以规则可以在这里
/// 直接压，不用起真机。
void main() {
  group('干扰项生成', () {
    test('正确答案出现且只出现一次，四个选项互不重复', () {
      for (var seed = 0; seed < 200; seed++) {
        final c = ChoiceOptions.build(
          correct: '放弃',
          nearMeanings: const ['离弃', '舍弃', '抛弃', '丢弃'],
          fallbackMeanings: const ['获得', '得到', '取得'],
          rng: Random(seed),
        );
        expect(c, isNotNull, reason: 'seed=$seed');
        expect(c!.options.length, 4);
        expect(c.options.where((o) => o == '放弃').length, 1);
        expect(c.options[c.answerIndex], '放弃');
        expect(c.options.toSet().length, 4, reason: '选项不能重复');
      }
    });

    test('形近词优先，不够才用同批/同首字母补', () {
      final c = ChoiceOptions.build(
        correct: '放弃',
        nearMeanings: const ['离弃'],
        fallbackMeanings: const ['获得', '得到', '取得'],
        rng: Random(1),
      )!;
      expect(c.options.contains('离弃'), isTrue, reason: '形近词的释义必须先进');
      expect(c.options.where((o) => o != '放弃' && o != '离弃').length, 2);
    });

    test('与正确答案同写法的干扰项被丢掉', () {
      final c = ChoiceOptions.build(
        correct: '放弃；抛弃',
        nearMeanings: const ['放弃', '抛弃', '离弃'],
        fallbackMeanings: const ['获得', '得到'],
        rng: Random(3),
      )!;
      // 「放弃」「抛弃」都是正确项的片段，不能出现在干扰项里。
      expect(c.options.contains('放弃'), isFalse);
      expect(c.options.contains('抛弃'), isFalse);
      expect(c.options.where((o) => o == '放弃；抛弃').length, 1);
    });

    test('凑不满三个干扰项就返回 null，不出残缺的题', () {
      final c = ChoiceOptions.build(
        correct: '放弃',
        nearMeanings: const ['离弃'],
        fallbackMeanings: const ['离弃'],
        rng: Random(0),
      );
      expect(c, isNull);
    });
  });

  group('作答状态机', () {
    test('首次点错：该选项禁用，记错，且不揭示正确答案', () {
      final p = CardProgress();
      final tap = p.tap(0, 2);

      expect(tap, CardTap.wrong);
      expect(p.recordedWrong, isTrue);
      expect(p.resolved, isFalse);
      expect(p.stateOf(0), OptionState.wrong);
      expect(p.stateOf(2), OptionState.neutral, reason: '答对前不能标出正确答案');
      expect(p.tap(0, 2), CardTap.ignored, reason: '点错过的选项不能重复点');
    });

    test('错过后选对：只算一次错，选对不覆盖', () {
      final p = CardProgress()..tap(1, 2);
      final tap = p.tap(2, 2);

      expect(tap, CardTap.correctAfterWrong);
      expect(p.recordedWrong, isTrue, reason: '首次答错即定案，后来选对不改判');
      expect(p.resolved, isTrue);
      expect(p.stateOf(2), OptionState.correct);
      expect(p.stateOf(0), OptionState.dimmed);
    });

    test('首次就选对：不记错', () {
      final p = CardProgress();
      final tap = p.tap(3, 3);

      expect(tap, CardTap.correctFirstTry);
      expect(p.recordedWrong, isFalse);
      expect(p.resolved, isTrue);
    });
  });

  group('「不认识」按钮（v0.6.2）', () {
    test('首次点：算一次记错，之后选对不改判', () {
      final p = CardProgress();
      expect(p.markUnknown(), isTrue, reason: '第一次点要真记错');
      expect(p.recordedWrong, isTrue);
      expect(p.tap(0, 0), CardTap.correctAfterWrong);
    });

    test('先点错再点：不重复记错', () {
      final p = CardProgress();
      expect(p.tap(1, 0), CardTap.wrong);
      expect(p.markUnknown(), isFalse, reason: '已经记过错，不能再记一次');
      expect(p.recordedWrong, isTrue);
    });

    test('答对之后再点：不记错（按钮此时也已隐藏）', () {
      final p = CardProgress();
      expect(p.tap(0, 0), CardTap.correctFirstTry);
      expect(p.markUnknown(), isFalse);
      expect(p.recordedWrong, isFalse);
    });
  });

  group('答对之后去哪', () {
    test('复习词第一次就答对 → 直接下一张', () {
      expect(
        exitAfterCorrect(isNew: false, hadWrong: false),
        CardExit.nextCard,
      );
    });

    test('复习词答错过 → 进详情页', () {
      expect(exitAfterCorrect(isNew: false, hadWrong: true), CardExit.detail);
    });

    test('新词答对 → 进详情页', () {
      expect(exitAfterCorrect(isNew: true, hadWrong: false), CardExit.detail);
    });
  });

  group('义项截断', () {
    test('取第一行第一个分句，过长截断', () {
      expect(shortGloss('放弃；抛弃\n第二行'), '放弃');
      expect(shortGloss('  获得  '), '获得');
      expect(shortGloss(''), '');
      expect(shortGloss('a' * 40).length, 27);
    });
  });
}
