import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_colors.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/app/widgets/box_badge.dart';
import 'package:mw_english/data/dao/study_dao.dart';
import 'package:mw_english/data/models/word_entry.dart';
import 'package:mw_english/features/study/box_band.dart';
import 'package:mw_english/features/study/study_heatmap.dart';
import 'package:mw_english/features/study/study_page.dart';
import 'package:mw_english/features/study/study_session_page.dart';
import 'package:mw_english/features/study/today_card.dart';
import 'package:mw_english/features/words/words_page.dart';

/// v0.7.9 字重对比拉开。
///
/// 四档（包里只有 400 / 700，中间档一律不许写）：
/// - T1 主角数字：700
/// - T2 标题（区块标题 / 单词 / 按钮文字）：700
/// - T3 正文（释义 / 说明 / 状态行）：400 + 墨 70%
/// - T4 次要（时间 / 备注 / 计数小字 / `/N`）：400 + 墨 62%
///
/// 断言全部来自需求原文，不从实现里抄样式值。
void main() {
  TodayStats stats({
    int learned = 13,
    int target = 30,
    int due = 4,
    int wrong = 2,
  }) {
    return TodayStats(
      newLearned: learned,
      newTarget: target,
      dueReview: due,
      wrongToday: wrong,
      totalLearned: 0,
      mastered: 0,
      gapDays: 0,
      reduced: false,
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextStyle styleOf(WidgetTester tester, Finder finder) {
    return tester.widget<Text>(finder.first).style!;
  }

  group('主题：四档只有 400 / 700', () {
    test('T1 / T2 = 700，T3 / T4 = 400', () {
      final t = AppTheme.light.textTheme;

      // T1 主角数字：环、三格统计用的字阶。
      expect(t.displayLarge?.fontWeight, FontWeight.w700);
      expect(t.titleLarge?.fontWeight, FontWeight.w700);

      // T2 标题：区块标题、单词、按钮文字。
      expect(t.displaySmall?.fontWeight, FontWeight.w700);
      expect(t.headlineSmall?.fontWeight, FontWeight.w700);
      expect(t.titleMedium?.fontWeight, FontWeight.w700);
      expect(t.titleSmall?.fontWeight, FontWeight.w700);
      expect(t.labelLarge?.fontWeight, FontWeight.w700);

      // T3 正文。
      expect(t.bodyLarge?.fontWeight, FontWeight.w400);
      expect(t.bodyMedium?.fontWeight, FontWeight.w400);
      expect(t.bodySmall?.fontWeight, FontWeight.w400);

      // T4 次要。
      expect(t.labelMedium?.fontWeight, FontWeight.w400);
      expect(t.labelSmall?.fontWeight, FontWeight.w400);
    });

    test('全 App 源码没有 w300 / w500 / w600 / w900', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final pattern = RegExp(r'FontWeight\.w(\d+)');
      final used = <int>{};
      final bad = <String>[];

      for (final file in files) {
        for (final m in pattern.allMatches(file.readAsStringSync())) {
          final weight = int.parse(m.group(1)!);
          used.add(weight);
          if (weight != 400 && weight != 700) {
            bad.add('${file.path}: w$weight');
          }
        }
      }

      expect(bad, isEmpty, reason: '包里只有 400 / 700，中间档写了也是白写');
      expect(used, <int>{400, 700});
    });
  });

  group('T1 主角数字 = 700', () {
    testWidgets('环内数字与三格统计数字 700', (tester) async {
      await pump(tester, TodayCard(stats: stats(), loading: false));

      final ringNumber = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('ring-count')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(ringNumber.style?.fontSize, 56);
      expect(ringNumber.style?.fontWeight, FontWeight.w700);

      // 三格统计数字 = 20pt titleLarge，共三处。
      final metrics = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(TodayCard),
              matching: find.byType(Text),
            ),
          )
          .where((text) => text.style?.fontSize == 20)
          .toList();
      expect(metrics, hasLength(3));
      for (final metric in metrics) {
        expect(metric.style?.fontWeight, FontWeight.w700);
      }
    });
  });

  group('T2 标题 / 按钮 = 700', () {
    testWidgets('只复习是按钮文字，700', (tester) async {
      await pump(
        tester,
        ReviewLink(label: '只复习待复习 4 词', onTap: () {}),
      );

      final style = styleOf(tester, find.text('只复习待复习 4 词'));
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w700);
    });

    testWidgets('单词行与区块标题 700', (tester) async {
      final entry = WordEntry(
        no: 1,
        word: 'transmit',
        wordKey: 'transmit',
        phonetic: 'trænzˈmɪt',
        meaningPdf: '传送；传播',
        pdfTruncated: false,
        meaningEcdict: '',
        pos: 'v.',
        tag: '',
        collins: 0,
      );

      await pump(
        tester,
        WordRow(
          entry: entry,
          box: 3,
          masked: false,
          revealed: false,
          onToggleMask: () {},
          onTap: () {},
        ),
      );

      expect(styleOf(tester, find.text('transmit')).fontWeight, FontWeight.w700);
      expect(styleOf(tester, find.text('transmit')).fontSize, 14);
    });

    testWidgets('状态胶囊（强调）700', (tester) async {
      await pump(tester, const StudyTagPill(label: '今日重测', emphasized: true));

      final style = styleOf(tester, find.text('今日重测'));
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, LiquidGlass.ink);
    });

    testWidgets('热力图区块标题 700 墨', (tester) async {
      await pump(
        tester,
        StudyHeatmap(totals: const {}, streak: 0, now: DateTime(2026, 11, 26)),
      );

      final style = styleOf(tester, find.text('学习足迹'));
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, LiquidGlass.ink);
    });
  });

  group('T3 正文 = 400 / 墨 70%', () {
    testWidgets('今日状态行 400 + 墨 70%，颜色没加深', (tester) async {
      await pump(tester, TodayCard(stats: stats(), loading: false));

      final style = styleOf(tester, find.text('今日已学 13 / 30，还差 17 词'));
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, AppColors.textSecondary,
          reason: 'v0.7.9 只统一 T4 到 62%，正文仍墨 70%');
    });

    testWidgets('词表释义 400 + 墨 70%', (tester) async {
      final entry = WordEntry(
        no: 1,
        word: 'transmit',
        wordKey: 'transmit',
        phonetic: 'trænzˈmɪt',
        meaningPdf: '传送；传播',
        pdfTruncated: false,
        meaningEcdict: '',
        pos: 'v.',
        tag: '',
        collins: 0,
      );

      await pump(
        tester,
        WordRow(
          entry: entry,
          box: 3,
          masked: false,
          revealed: false,
          onToggleMask: () {},
          onTap: () {},
        ),
      );

      final style = styleOf(tester, find.text('传送；传播'));
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, AppColors.textSecondary);
    });
  });

  group('T4 次要 = 400 / 墨 62%', () {
    testWidgets('环的标签与 /N：400 + 墨 62%', (tester) async {
      await pump(tester, TodayCard(stats: stats(), loading: false));

      for (final label in <String>['今日新词', '目标 30 词', '/ 30', '新词', '待复习', '答错']) {
        final style = styleOf(tester, find.text(label));
        expect(style.fontWeight, FontWeight.w400, reason: label);
        expect(style.color, AppColors.textTertiary, reason: '$label 墨 62%');
      }
    });

    testWidgets('热力图连续天数与说明：400 + 墨 62%', (tester) async {
      await pump(
        tester,
        StudyHeatmap(totals: const {}, streak: 0, now: DateTime(2026, 11, 26)),
      );

      final streak = styleOf(tester, find.text('还没开始'));
      expect(streak.fontWeight, FontWeight.w400);
      expect(streak.color, AppColors.textTertiary);

      final caption = styleOf(
        tester,
        find.byKey(const ValueKey('heatmap-caption')),
      );
      expect(caption.fontWeight, FontWeight.w400);
      expect(caption.color, AppColors.textTertiary);
    });

    testWidgets('色带图例：400 + 墨 62%', (tester) async {
      await pump(tester, BoxBand(counts: const {0: 820, 1: 3}));

      final style = styleOf(tester, find.text('新词 · 820 词'));
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, AppColors.textTertiary);
    });

    testWidgets('词表序号与音标：400 + 墨 62%', (tester) async {
      final entry = WordEntry(
        no: 7,
        word: 'transmit',
        wordKey: 'transmit',
        phonetic: 'trænzˈmɪt',
        meaningPdf: '传送；传播',
        pdfTruncated: false,
        meaningEcdict: '',
        pos: 'v.',
        tag: '',
        collins: 0,
      );

      await pump(
        tester,
        WordRow(
          entry: entry,
          box: 3,
          masked: false,
          revealed: false,
          onToggleMask: () {},
          onTap: () {},
        ),
      );

      for (final label in <String>['7', '/trænzˈmɪt/']) {
        final style = styleOf(tester, find.text(label));
        expect(style.fontWeight, FontWeight.w400, reason: label);
        expect(style.color, AppColors.textTertiary, reason: '$label 墨 62%');
      }
    });

    testWidgets('普通状态胶囊：400 + 墨 62%', (tester) async {
      await pump(tester, const StudyTagPill(label: '旧复习'));

      final style = styleOf(tester, find.text('旧复习'));
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, AppColors.textTertiary);
    });

    testWidgets('箱位徽章：400；文字仍用墨（决策 96，不降 62%）', (tester) async {
      await pump(tester, const BoxBadge(box: 3));

      final style = styleOf(tester, find.text('箱 3'));
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, LiquidGlass.ink);
    });
  });
}
