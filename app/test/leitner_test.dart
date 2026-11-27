import 'package:flutter_test/flutter_test.dart';
import 'package:mw_english/data/study/leitner.dart';

/// Leitner 六箱规则的纯函数测试。
/// 这些规则是「背不背得下去」的核心，改动必须先让这里过。
void main() {
  group('新词第一次作答', () {
    test('答对：进 1 箱，当天收尾复习', () {
      final r = Leitner.apply(
        const LeitnerState(),
        correct: true,
        isFirstAnswer: true,
      );
      expect(r.box, 1);
      expect(r.streak, 1);
      expect(r.peakBox, 1);
      expect(r.retest, isTrue);
      expect(r.dueInDays, 0, reason: '当天要再出一次，不等明天');
    });

    test('答错：停在 0 箱，当天重测', () {
      final r = Leitner.apply(
        const LeitnerState(),
        correct: false,
        isFirstAnswer: true,
      );
      expect(r.box, 0);
      expect(r.retest, isTrue);
      expect(r.dueInDays, 0);
      expect(r.demoted, isFalse, reason: '本来就在 0 箱，不算降箱');
    });
  });

  group('当日重测 / 收尾复习过关', () {
    test('新词收尾复习答对：只回箱不升箱，下次 1 天后', () {
      final r = Leitner.apply(
        const LeitnerState(box: 1, streak: 1, peakBox: 1, correctCount: 1, retest: true),
        correct: true,
      );
      expect(r.box, 1);
      expect(r.retest, isFalse);
      expect(r.dueInDays, 1);
      expect(r.promoted, isFalse, reason: '收尾复习不该额外升箱');
    });

    test('答错降到 3 箱后重测过关：稳在 3 箱，4 天后', () {
      final r = Leitner.apply(
        const LeitnerState(box: 3, streak: 0, peakBox: 5, correctCount: 9, wrongCount: 1, retest: true),
        correct: true,
      );
      expect(r.box, 3);
      expect(r.dueInDays, 4);
      expect(r.retest, isFalse);
    });

    test('被降到 0 箱后重测过关：回到 1 箱', () {
      final r = Leitner.apply(
        const LeitnerState(box: 0, streak: 0, peakBox: 2, wrongCount: 2, retest: true),
        correct: true,
      );
      expect(r.box, 1);
      expect(r.dueInDays, 1);
    });

    test('重测又答错：再降一箱，仍标记当天重测', () {
      final r = Leitner.apply(
        const LeitnerState(box: 2, streak: 0, peakBox: 3, retest: true),
        correct: false,
      );
      expect(r.box, 1);
      expect(r.retest, isTrue);
      expect(r.dueInDays, 0);
    });
  });

  group('正常复习推进', () {
    test('答对升一箱，间隔按 1/2/4/7/15/30 走', () {
      var state = const LeitnerState(box: 1, streak: 3, peakBox: 1, correctCount: 3);
      final expected = <int, int>{2: 2, 3: 4, 4: 7, 5: 15, 6: 30};
      for (final entry in expected.entries) {
        final r = Leitner.apply(state, correct: true);
        expect(r.box, entry.key, reason: '从 ${state.box} 箱答对应到 ${entry.key} 箱');
        expect(r.dueInDays, entry.value);
        state = LeitnerState(
          box: r.box,
          streak: r.streak,
          peakBox: r.peakBox,
          correctCount: r.correctCount,
        );
      }
    });

    test('到顶箱不再往上，一直 30 天', () {
      final r = Leitner.apply(
        const LeitnerState(box: 6, streak: 9, peakBox: 6, correctCount: 20),
        correct: true,
      );
      expect(r.box, 6);
      expect(r.dueInDays, 30);
    });

    test('答错降一箱，不归零', () {
      final r = Leitner.apply(
        const LeitnerState(box: 3, streak: 4, peakBox: 3, correctCount: 8),
        correct: false,
      );
      expect(r.box, 2);
      expect(r.streak, 0);
      expect(r.retest, isTrue);
      expect(r.demoted, isTrue);
    });

    test('箱位 2 答错只降到 1，1 箱答错才到 0', () {
      expect(Leitner.demote(2), 1);
      expect(Leitner.demote(1), 0);
      expect(Leitner.demote(0), 0);
    });
  });

  group('熟词保护', () {
    test('4 箱答错只落到 3 箱，不再往下', () {
      final r = Leitner.apply(
        const LeitnerState(box: 4, streak: 5, peakBox: 5, correctCount: 12),
        correct: false,
      );
      expect(r.box, 3);
    });

    test('6 箱答错落到 5 箱（一次只降一箱）', () {
      final r = Leitner.apply(
        const LeitnerState(box: 6, streak: 6, peakBox: 6, correctCount: 20),
        correct: false,
      );
      expect(r.box, 5);
    });

    test('连续答错不会跌破 3 箱', () {
      var state = const LeitnerState(box: 4, streak: 0, peakBox: 4);
      for (var i = 0; i < 5; i++) {
        final r = Leitner.apply(state, correct: false);
        state = LeitnerState(box: r.box, peakBox: r.peakBox, retest: false);
      }
      expect(state.box, 3);
    });
  });

  group('新词门槛：连续答对 3 次才进 3 箱以上', () {
    test('连对 2 次还卡在 2 箱', () {
      final r = Leitner.apply(
        const LeitnerState(box: 2, streak: 1, peakBox: 2, correctCount: 2),
        correct: true,
      );
      expect(r.box, 2);
      expect(r.streak, 2);
    });

    test('第 3 次连对才放到 3 箱', () {
      final r = Leitner.apply(
        const LeitnerState(box: 2, streak: 2, peakBox: 2, correctCount: 3),
        correct: true,
      );
      expect(r.box, 3);
    });

    test('到过 3 箱以上的词再掉下来，不受门槛限制', () {
      final r = Leitner.apply(
        const LeitnerState(box: 2, streak: 1, peakBox: 4, correctCount: 9),
        correct: true,
      );
      expect(r.box, 3);
    });
  });

  group('每日配额与断档', () {
    final now = DateTime(2026, 11, 25, 20, 0);

    test('第一次用或今天已学：按默认 30', () {
      expect(Leitner.quota(now: now).newWords, 30);
      expect(
        Leitner.quota(lastStudyAt: DateTime(2026, 11, 25, 8, 0), now: now).newWords,
        30,
      );
      expect(
        Leitner.quota(lastStudyAt: DateTime(2026, 11, 24, 23, 0), now: now).newWords,
        30,
      );
    });

    test('断档 3 天：新词减半、复习优先', () {
      final q = Leitner.quota(lastStudyAt: DateTime(2026, 11, 22, 9, 0), now: now);
      expect(q.gapDays, 3);
      expect(q.newWords, 15);
      expect(q.reduced, isTrue);
      expect(q.reviewsFirst, isTrue);
    });

    test('断档 7 天：按天数摊薄', () {
      final q = Leitner.quota(lastStudyAt: DateTime(2026, 11, 18, 9, 0), now: now);
      expect(q.gapDays, 7);
      expect(q.newWords, 4);
      expect(q.reduced, isTrue);
    });

    test('断档很久：最低保底 3 个', () {
      final q = Leitner.quota(lastStudyAt: DateTime(2026, 10, 1, 9, 0), now: now);
      expect(q.newWords, 3);
      expect(q.reduced, isTrue);
    });
  });
}
