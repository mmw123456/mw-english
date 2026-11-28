import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/box_colors.dart';
import '../../data/dao/stats_dao.dart';
import '../../data/stats/stats_snapshot.dart';

/// 学习统计（v0.14.0）。
///
/// 入口在我的页（`ProfilePage` 的「学习统计」）。**不占新 Tab**，不动学习、
/// 词库、阅读三条流程。
///
/// 只做五块：今日 / 累计 / 箱 0–6 分布 / 最近 7·30 天趋势 / 拼写。
/// 页面不查库，数字全部来自 [StatsStore]（生产实现是 [SqlStatsStore]），
/// 所以每个数字都能追到一条 SQL —— 见 `stats_snapshot.dart` 顶部的来源表。
///
/// 三条显示规矩：
/// 1. 查不到就写「暂无数据」，**不补 0、不编历史、不画假曲线**；
/// 2. 没记录的日子在趋势图里不画柱（不是画一根 0 高的柱）；
/// 3. 一条学习记录都没有时，趋势图下写「从今天起开始记录」。
class StatsPage extends StatefulWidget {
  const StatsPage({this.store = const SqlStatsStore(), this.now, super.key});

  /// 数据来源。测试注入假数据，生产走 SQLite。
  final StatsStore store;

  /// 测试注入「今天」，生产留 null。
  @visibleForTesting
  final DateTime? now;

  /// 趋势图的柱子高度（px）。
  static const double chartHeight = 96;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsSnapshot? _snap;
  bool _failed = false;

  /// 趋势档位：7 或 30。默认 7 天。
  int _range = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await widget.store.load(now: widget.now);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(title: const Text('学习统计')),
      body: _failed
          ? const Center(child: Text('读不到统计数据'))
          : snap == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: ShellPadding.scroll(context),
                  children: [
                    _TodayCard(snap),
                    const SizedBox(height: 14),
                    _TotalCard(snap),
                    const SizedBox(height: 14),
                    _BoxCard(snap),
                    const SizedBox(height: 14),
                    _TrendCard(
                      snap: snap,
                      range: _range,
                      onRange: (days) => setState(() => _range = days),
                    ),
                    const SizedBox(height: 14),
                    _SpellCard(snap),
                    const SizedBox(height: 18),
                    Text(
                      '数字全部来自本机记录：学习量与天数读 daily_stat'
                      '（v0.7.4 起按天记），拼写读 spelling_round'
                      '（v0.13.0 起一轮一行）。没记过的日子不补数。',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                            height: 1.5,
                          ),
                    ),
                  ],
                ),
    );
  }
}

/// 纸面卡（内容层）。与我的页、词库页同一套：surface + 0.5px 描边。
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.note});

  final String title;
  final Widget child;

  /// 标题下面的一行小字（口径说明）。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: text.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 一格数字：上面数字，下面标签。
class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.label,
    required this.valueKey,
  });

  final String value;
  final String label;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          key: ValueKey(valueKey),
          style: AppTheme.numeric(text.headlineSmall)
              .copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// 2×2 网格，两行两列。320 宽下每格 120px 出头，`headlineSmall` 放得下。
class _Grid extends StatelessWidget {
  const _Grid({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < cells.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[i]),
              const SizedBox(width: 12),
              Expanded(child: cells[i + 1]),
            ],
          ),
        ],
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard(this.snap);

  final StatsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final percent = snap.todaySpellPercent;
    return _Card(
      title: '今日',
      child: _Grid(
        cells: [
          _Cell(
            value: '${snap.today.newWords}',
            label: '新学词（词）',
            valueKey: 'stats-today-new',
          ),
          _Cell(
            value: '${snap.today.reviews}',
            label: '复习词（词）',
            valueKey: 'stats-today-review',
          ),
          _Cell(
            value: '${snap.todaySpellTotal}',
            label: '拼写题（题）',
            valueKey: 'stats-today-spell',
          ),
          _Cell(
            // 今天没拼过就不是 0%，是「还没有」。
            value: percent == null ? '—' : '$percent%',
            label: '拼写正确率',
            valueKey: 'stats-today-spell-percent',
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard(this.snap);

  final StatsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '累计',
      child: _Grid(
        cells: [
          _Cell(
            value: '${snap.totalDays}',
            label: '学习天数（天）',
            valueKey: 'stats-total-days',
          ),
          _Cell(
            value: '${snap.streak}',
            label: '连续打卡（天）',
            valueKey: 'stats-streak',
          ),
          _Cell(
            value: '${snap.learnedWords}',
            label: '学过词（词）',
            valueKey: 'stats-learned',
          ),
          _Cell(
            value: '${snap.mastered}',
            label: '已掌握（词）',
            valueKey: 'stats-mastered',
          ),
        ],
      ),
    );
  }
}

/// 箱 0–6 分布：七行横条。
///
/// 七段只数**未斩**的词：已斩的词不进任何一段，另起一行「已斩 N」。
/// `七段之和 + 已斩 = 学习池`（820 + 自加词），这两行数字就是这么对上的。
class _BoxCard extends StatelessWidget {
  const _BoxCard(this.snap);

  final StatsSnapshot snap;

  /// 条形最大宽度占可用宽的比例。留白给右边的数字。
  static const double barMax = 0.62;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final maxCount = snap.boxes.fold<int>(0, (a, b) => math.max(a, b));

    return _Card(
      title: '箱 0–6 分布',
      note: '箱 0 = 新词（还没进调度），箱 1–6 = 调度箱'
          '（间隔 1 / 2 / 4 / 7 / 15 / 30 天）。已斩的词不进任何一段。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var box = 0; box < snap.boxes.length; box++)
            Padding(
              padding: EdgeInsets.only(bottom: box == snap.boxes.length - 1 ? 0 : 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      // 分布里写「箱 0」而不是「新词」：这一块的读法是箱位，
                      // 「箱 0 是新词」由上面的小字交代。
                      '箱 $box',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final count = snap.boxes[box];
                        final ratio = maxCount <= 0 ? 0.0 : count / maxCount;
                        final width = math.max(
                          count > 0 ? 6.0 : 0.0,
                          constraints.maxWidth * barMax * ratio,
                        );
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            key: ValueKey('stats-box-bar-$box'),
                            height: 9,
                            width: width,
                            decoration: BoxDecoration(
                              color: boxColor(box),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${snap.boxes[box]}',
                      key: ValueKey('stats-box-$box'),
                      textAlign: TextAlign.right,
                      style: AppTheme.numeric(text.labelMedium)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '合计 ${snap.boxSum} 词（未斩）· 已斩 ${snap.killed} · '
            '学习池 ${snap.poolTotal}',
            key: const ValueKey('stats-box-sum'),
            style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 最近 7 / 30 天趋势：一天一根柱，新学在下、复习在上。
///
/// 两根柱用同一支蓝的两个明度（[AppColors.accentBlue] 100% / 35%），
/// 与首页热力图同一套色，不新增色相。
/// **没记录的天不画柱**：只留空槽，绝不用 0 高柱冒充「学过但 0 个」。
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.snap,
    required this.range,
    required this.onRange,
  });

  final StatsSnapshot snap;
  final int range;
  final ValueChanged<int> onRange;

  static const Color learnedColor = AppColors.accentBlue;
  static Color get reviewColor => AppColors.accentBlue.withValues(alpha: 0.35);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final slots = snap.slots(range);
    final maxCount = snap.maxOf(range);
    final active = snap.activeDays(range);

    return _Card(
      title: '最近 $range 天',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RangeButton(
                days: 7,
                selected: range == 7,
                onTap: onRange,
              ),
              const SizedBox(width: 8),
              _RangeButton(
                days: 30,
                selected: range == 30,
                onTap: onRange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const _Dot(color: learnedColor),
                    const SizedBox(width: 4),
                    Text('新学',
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textTertiary)),
                    const SizedBox(width: 10),
                    _Dot(color: reviewColor),
                    const SizedBox(width: 4),
                    Text('复习',
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: StatsPage.chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final slot in slots) ...[
                  Expanded(
                    child: _Bar(slot: slot, maxCount: maxCount),
                  ),
                  if (slot != slots.last) SizedBox(width: range > 7 ? 2 : 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 横轴：7 天档标首尾两天；30 天档只标区间（30 个日期挤不下）。
          Row(
            children: [
              Text(
                slots.first.day.substring(5),
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              const Spacer(),
              Text(
                '今天',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          if (snap.noHistory) ...[
            const SizedBox(height: 10),
            Text(
              '从今天起开始记录',
              key: const ValueKey('stats-empty-hint'),
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ] else if (active == 0) ...[
            const SizedBox(height: 10),
            Text(
              '最近 $range 天没有学习记录',
              key: const ValueKey('stats-blank-window'),
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.days,
    required this.selected,
    required this.onTap,
  });

  final int days;
  final bool selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      key: ValueKey('stats-range-$days'),
      onTap: () => onTap(days),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$days 天',
          style: text.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? AppColors.textPrimary : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// 一天的两段柱。没记录 → 什么都不画（不能画 0 高柱）。
class _Bar extends StatelessWidget {
  const _Bar({required this.slot, required this.maxCount});

  final DaySlot slot;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final data = slot.total;
    if (data == null || maxCount <= 0) {
      // 空槽：留一条极浅的底，让「这天没记录」和「这天不存在」分得开。
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 1,
          color: AppColors.heatmapEmpty,
        ),
      );
    }

    double h(int v) => StatsPage.chartHeight * (v / maxCount);

    return Column(
      key: ValueKey('stats-bar-${slot.day}'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (data.reviews > 0)
          Container(
            height: math.max(2, h(data.reviews)),
            decoration: BoxDecoration(
              color: _TrendCard.reviewColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ),
        if (data.newWords > 0)
          Container(
            height: math.max(2, h(data.newWords)),
            decoration: BoxDecoration(
              color: _TrendCard.learnedColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(data.reviews > 0 ? 0 : 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SpellCard extends StatelessWidget {
  const _SpellCard(this.snap);

  final StatsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final all = snap.spellAllPercent;
    final week = snap.spell7Percent;
    final none = snap.spellAllTotal <= 0;

    return _Card(
      title: '拼写',
      child: none
          ? Text(
              '暂无数据',
              key: const ValueKey('stats-spell-empty'),
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          : _Grid(
              cells: [
                _Cell(
                  // 一题没拼不是 0%，是「还没有」—— 与拼写页顶部一个口径。
                  value: all == null ? '—' : '$all%',
                  label: '累计正确率（共 ${snap.spellAllTotal} 题）',
                  valueKey: 'stats-spell-all',
                ),
                _Cell(
                  value: week == null ? '—' : '$week%',
                  label: '最近 7 天（共 ${snap.spell7Total} 题）',
                  valueKey: 'stats-spell-7',
                ),
              ],
            ),
    );
  }
}
