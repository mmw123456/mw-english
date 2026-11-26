import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/models/study_card.dart';
import 'package:mw_english/data/study/leitner.dart';
import 'package:mw_english/features/study/study_session_page.dart';

/// v0.7.2 换卡首帧。
///
/// 现象：详情页点「下一个」回来，下一张卡有一瞬间四个选项是空的。
/// 这里把「换卡后的第一帧」钉住：选项必须在，且不透明度已经是 1。
StudyCard _card(int i) {
  return StudyCard(
    wordKey: 'w$i',
    word: 'word$i',
    phonetic: '/w$i/',
    meaning: '释义$i',
    meaningEcdict: '',
    box: 1,
    isNew: false,
    isRetest: false,
    options: <String>['释义$i', '干扰甲$i', '干扰乙$i', '干扰丙$i'],
    answerIndex: 0,
  );
}

StudySession _session(int n) {
  return StudySession(
    cards: <StudyCard>[for (var i = 0; i < n; i++) _card(i)],
    quota: const DailyQuota(newWords: 0, reviewCap: 20, gapDays: 0),
    newCount: 0,
    reviewCount: n,
    retestCount: 0,
    learnedToday: 0,
  );
}

/// 一个 Text 上所有 Opacity 祖先的乘积（= 实际绘制不透明度）。
///
/// 弹簧的终值是 0.99999 级别（tolerance 0.001），所以判定「不透明」用
/// >0.99 而不是 == 1.0。
double _paintedOpacity(WidgetTester tester, String text) {
  var value = 1.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
  )) {
    value *= o.opacity;
  }
  return value;
}

Future<void> _boot(WidgetTester tester, int n) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: StudySessionPage(debugSessionBuilder: () => _session(n)),
    ),
  );
  await tester.pump();
  // 第一张卡的入场 stagger 播完：先让弹簧的 ticker 起跑（动画的第一次
  // tick 只记起点、值是 0），再滚完（最晚 155ms + 弹簧）。
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> _answerCorrectAndAdvance(WidgetTester tester, int i) async {
  await tester.tap(find.text('释义$i'));
  await tester.pump();
  // 500ms 后自动走；这一次 pump 画出来的就是下一张卡的首帧。
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('换卡首帧：四个选项都在，且已经是不透明', (tester) async {
    await _boot(tester, 3);
    expect(_paintedOpacity(tester, '释义0'), greaterThan(0.99));

    await _answerCorrectAndAdvance(tester, 0);

    // 第一帧：四个选项必须已经在，并且不透明度是 1。
    expect(find.text('释义1'), findsOneWidget, reason: '换卡首帧没有正确选项');
    for (final label in <String>['干扰甲1', '干扰乙1', '干扰丙1']) {
      expect(find.text(label), findsOneWidget, reason: '换卡首帧缺选项 $label');
      expect(_paintedOpacity(tester, label), greaterThan(0.99),
          reason: '换卡首帧选项 $label 还是透明的（入场动画重播了）');
    }
    expect(_paintedOpacity(tester, '释义1'), greaterThan(0.99),
        reason: '换卡首帧正确选项还是透明的');
  });

  testWidgets('连点 10 次下一个：次次首帧都有四个选项', (tester) async {
    await _boot(tester, 12);

    for (var i = 0; i < 10; i++) {
      await _answerCorrectAndAdvance(tester, i);
      for (var k = 0; k < 4; k++) {
        final label = k == 0 ? '释义${i + 1}' : '干扰${const ['甲', '乙', '丙'][k - 1]}${i + 1}';
        expect(find.text(label), findsOneWidget,
            reason: '第 ${i + 1} 次下一个：首帧缺 $label');
        expect(_paintedOpacity(tester, label), greaterThan(0.99),
            reason: '第 ${i + 1} 次下一个：$label 首帧是透明的');
      }
    }
  });

  test('会话装配时整条队列的选项就已经算好（不是换卡时现算）', () {
    final session = _session(5);
    for (final card in session.cards) {
      expect(card.options.length, 4);
      expect(card.answerIndex, inInclusiveRange(0, 3));
    }
  });
}
