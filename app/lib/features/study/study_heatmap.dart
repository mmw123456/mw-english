import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dao/study_dao.dart';

/// 学习热力图（v0.7.4）。
///
/// GitHub 式网格：最近 12 周 × 7 天，一格一天，列 = 自然周（周一开头），
/// 行 = 周一…周日。点一格，下方一行小字换成那天的数据。
///
/// 它是**内容层**，所以是纸面卡（[AppColors.surface] + 0.5px 描边），
/// 不是玻璃 —— 跟列表行、正文卡同一条规则。
///
/// 颜色只有一支蓝的单色阶（[AppColors.accentBlue]）：没学 = 墨 5% 底 +
/// 0.5px 描边；1–9 词 25%、10–19 词 50%、20–29 词 75%、30+ 词 100%。
/// 未来的格子（今天之后）**不画**，不是「没学」——留白比涂灰更不会骗人。
///
/// v0.7.5 空态三件：空格从纸面卡底改墨 5%（原来跟卡片同色，远看像没加载）；
/// 整张图一天都没记时，标题下多一行「从今天开始记」；今天那格加 1.5px
/// 墨 60% 描边，跟历史格分开。蓝阶四档没动；格子尺寸改为向下取到 0.1px，
/// 12 列严格不超可用宽（超窄容器里也不会缺一列）。
class StudyHeatmap extends StatefulWidget {
  const StudyHeatmap({
    required this.totals,
    required this.streak,
    this.now,
    super.key,
  });

  /// 按天完成量，key 是 `yyyy-MM-dd`（[StudyDao.dayKey]）。
  final Map<String, DayTotal> totals;

  /// 连续有记录的天数，直接显示在右上角。
  final int streak;

  /// 测试注入「今天」。生产环境留 null。
  @visibleForTesting
  final DateTime? now;

  /// 12 列 = 12 周。
  static const int weeks = 12;

  /// 7 行 = 一周七天。
  static const int daysPerWeek = 7;

  /// 格子与间距。
  static const double gap = 4;

  /// 今天那格的描边：墨 60%，1.5px（v0.7.5）。
  ///
  /// 用前景描边（`foregroundDecoration`）而不是普通 border：border 会从内部
  /// 吃掉 1.5px，22px 的格子上填充会明显缩一圈。前景描边不占布局，格子大小
  /// 与蓝阶色块都不变。色值在 [AppColors.heatmapTodayBorder]，这里不写 hex。
  static const Color todayBorder = AppColors.heatmapTodayBorder;

  /// 一格的填充色。0 走墨 5% 底（另加描边），其余按档。
  @visibleForTesting
  static Color colorFor(int total) {
    if (total <= 0) return AppColors.heatmapEmpty;
    if (total < 10) return AppColors.accentBlue.withValues(alpha: 0.25);
    if (total < 20) return AppColors.accentBlue.withValues(alpha: 0.50);
    if (total < 30) return AppColors.accentBlue.withValues(alpha: 0.75);
    return AppColors.accentBlue;
  }

  @override
  State<StudyHeatmap> createState() => _StudyHeatmapState();
}

class _StudyHeatmapState extends State<StudyHeatmap> {
  /// 点过哪一天。null = 还没点过，caption 显示今天。
  DateTime? _selected;

  /// 用 `DateTime(y, m, d ± n)` 位移，不用 `Duration(days: n)`：
  /// 后者跨夏令时会把日期带偏一小时，落到前一天。
  static DateTime _shift(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  DateTime get _today {
    final n = widget.now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// 网格左上角：本周周一往前推 (weeks - 1) 周。
  DateTime get _start {
    final t = _today;
    final monday = _shift(t, -(t.weekday - 1));
    return _shift(monday, -(StudyHeatmap.weeks - 1) * 7);
  }

  DateTime _dateAt(int col, int row) => _shift(_start, col * 7 + row);

  DayTotal _totalOf(DateTime d) => widget.totals[StudyDao.dayKey(d)] ??
      DayTotal.empty;

  /// 12 周窗口里有没有任何一天真的学过（v0.7.5）。
  ///
  /// 用来决定标题下要不要显示「从今天开始记」：一格填上就消失。
  /// 只看窗口内的格子，`totals` 里更早的记录不算 —— 图上没画的东西不能
  /// 影响图上的空态文案。
  bool get _hasAnyRecord {
    for (var i = 0; i < StudyHeatmap.weeks * StudyHeatmap.daysPerWeek; i++) {
      if (_totalOf(_shift(_start, i)).total > 0) return true;
    }
    return false;
  }

  /// 这一列要不要标月份：该列周一与上一列周一的月份不同就标。
  String? _monthLabel(int col) {
    if (col == 0) return '${_shift(_start, 0).month}月';
    final prev = _shift(_start, (col - 1) * 7).month;
    final cur = _shift(_start, col * 7).month;
    return prev == cur ? null : '$cur月';
  }

  String get _caption {
    final d = _selected ?? _today;
    final total = _totalOf(d).total;
    final label = '${d.month}月${d.day}日';
    return total == 0 ? '$label · 没学' : '$label · 学了 $total 词';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('学习足迹', style: text.titleSmall),
              Text(
                widget.streak == 0 ? '还没开始' : '连续 ${widget.streak} 天',
                style: text.labelSmall,
              ),
            ],
          ),
          if (!_hasAnyRecord) ...[
            const SizedBox(height: 6),
            Text(
              '从今天开始记',
              key: const ValueKey('heatmap-empty-hint'),
              style: text.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // 向下取到 0.1px，保证 12 列总宽**严格不超**可用宽（v0.7.5）。
              // 原写法直接拿除不尽的小数去排，正常屏宽刚好贴满、不出事；
              // 但 cell 的下限 12 在超窄容器里（分屏、显示缩放）会把总宽顶出
              // 卡片，最右列就真的被切了。宁可格子小一点，也不让 12 列缺一列。
              final raw = (constraints.maxWidth -
                      StudyHeatmap.gap * (StudyHeatmap.weeks - 1)) /
                  StudyHeatmap.weeks;
              final cell = math.min(
                30.0,
                math.max(4.0, (raw * 10).floorToDouble() / 10),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MonthRuler(cell: cell, labelAt: _monthLabel),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (var col = 0; col < StudyHeatmap.weeks; col++) ...[
                        if (col > 0)
                          const SizedBox(width: StudyHeatmap.gap),
                        Column(
                          children: [
                            for (var row = 0;
                                row < StudyHeatmap.daysPerWeek;
                                row++)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: row == 0 ? 0 : StudyHeatmap.gap,
                                ),
                                child: _cell(context, _dateAt(col, row), cell),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            _caption,
            key: const ValueKey('heatmap-caption'),
            style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DateTime date, double cell) {
    // 今天之后还没发生：不画、不可点。涂成「没学」会骗人。
    if (date.isAfter(_today)) {
      return const SizedBox.shrink();
    }

    final total = _totalOf(date).total;
    final key = StudyDao.dayKey(date);
    final selected = StudyDao.dayKey(_selected ?? _today) == key;
    final isToday = key == StudyDao.dayKey(_today);
    final radius = BorderRadius.circular(3);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = date),
      child: Semantics(
        label: '${date.month}月${date.day}日，$total 词',
        child: Container(
          key: ValueKey('heat-cell-$key'),
          width: cell,
          height: cell,
          decoration: BoxDecoration(
            color: StudyHeatmap.colorFor(total),
            borderRadius: radius,
            // 空格底色改墨 5%（v0.7.5）后边框仍保留，网格才有格线。
            border: total == 0
                ? Border.all(color: AppColors.divider, width: 0.5)
                : null,
            // 选中格加一圈墨边，点完知道点的是哪一个。
            // 用 boxShadow 不用 border：border 会挤压内部填充，格子大小不变。
            boxShadow: selected
                ? const <BoxShadow>[
                    BoxShadow(color: AppColors.textPrimary, spreadRadius: 1.2),
                  ]
                : null,
          ),
          // 今天：1.5px 墨 60% 前景描边。不占布局，不缩填充。
          foregroundDecoration: isToday
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: StudyHeatmap.todayBorder,
                    width: 1.5,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// 网格上方的月份小字。只在月份变化的那一列标，文字向右伸出去，
/// 后面的列本来是空的，不会撞。
class _MonthRuler extends StatelessWidget {
  const _MonthRuler({required this.cell, required this.labelAt});

  final double cell;
  final String? Function(int col) labelAt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var col = 0; col < StudyHeatmap.weeks; col++)
            if (labelAt(col) != null)
              Positioned(
                left: col * (cell + StudyHeatmap.gap),
                top: 0,
                child: Text(
                  labelAt(col)!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1.2,
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
        ],
      ),
    );
  }
}
