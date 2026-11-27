import 'package:material_ui/material_ui.dart';

import '../../app/app_defaults.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/rolling_int.dart';
import '../../data/dao/study_dao.dart';
import 'progress_ring.dart';

/// 首页任务卡（v0.7.4 起独立成文件，好单测）。
///
/// 结构：顶部一对标签（今日新词 / 目标 N 词）→ 居中的进度环（环里是
/// 「已学 / 目标」）→ 环下今日状态一行 → 三格数字（新词 / 待复习 / 答错）。
///
/// v0.7.4 撤掉了原来的细进度条和中间那行大数字 —— 那两样讲的是同一件事，
/// 挤在一张卡里谁都不是主角。现在主角是环。
///
/// v0.7.8 首页主角化：环 176 / 14、环内数字 56pt，环下补一行 14pt 状态文案
/// 直说「今天还差多少」。三格数字与顶部标签没动。
///
/// **分母用 [TodayStats.newTarget]，不是硬编码 30**：断档会削减当日配额，
/// 那时顶部写「目标 6 词」、环里写「/6」、状态行写「还差 3 词」，三处一致；
/// 写死 30 会自相矛盾。
class TodayCard extends StatelessWidget {
  const TodayCard({required this.stats, required this.loading, super.key});

  final TodayStats stats;
  final bool loading;

  /// 环里那枚数字的字号（v0.7.8）。44 → 56，与 176 的环同比例放大。
  static const double numberSize = 56;

  /// 今日目标。配额异常（0）时退回默认值，避免除零。
  int get target =>
      stats.newTarget <= 0 ? AppDefaults.dailyNewWordTarget : stats.newTarget;

  /// 环的填充比例。与环里的数字是同一对 (done, target)。
  double get ratio => (stats.newLearned / target).clamp(0.0, 1.0);

  /// 环下那行状态文案（v0.7.8）。三态，全部以 [target] 为分母：
  /// - 未开始（今日新词 0）：`今天还没开始 · 目标 N 词`
  /// - 进行中：`今日已学 X / N，还差 M 词`
  /// - 完成（X ≥ N）：`今日目标完成`
  ///
  /// 抽成方法是为了让测试直接断言三态，不用去拼 UI。
  String statusLine() {
    final done = stats.newLearned;
    final goal = target;
    if (done <= 0) return '今天还没开始 · 目标 $goal 词';
    if (done >= goal) return '今日目标完成';
    return '今日已学 $done / $goal，还差 ${goal - done} 词';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = stats.newLearned;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // T4 次要：400 / 墨 62%（v0.7.9，与「目标 N 词」同一档）。
              Text('今日新词',
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textTertiary)),
              Text('目标 $target 词', style: text.labelSmall),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: ProgressRing(
              value: loading ? 0 : ratio,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 数字从旧值滚到新值（v0.7.6），跟环用同一根弹簧。
                  // 等宽数字在 RollingInt 内部套好，宽度不随数值跳。
                  if (loading)
                    Text('—', style: _numberStyle(text))
                  else
                    RollingInt(
                      key: const ValueKey('ring-count'),
                      value: done,
                      style: _numberStyle(text),
                    ),
                  Text(
                    '/ $target',
                    style: AppTheme.numeric(text.labelMedium).copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 今日状态（v0.7.8）：14pt / 墨 70%，居中对着环。
          // 读库中先占位（全角空格），避免这行忽有忽无把下方三格顶来顶去。
          SizedBox(
            width: double.infinity,
            child: Text(
              loading ? '　' : statusLine(),
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Metric(label: '新词', value: '$done'),
              const SizedBox(width: 28),
              _Metric(label: '待复习', value: '${stats.dueReview}'),
              const SizedBox(width: 28),
              _Metric(label: '答错', value: '${stats.wrongToday}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// 环内大数字的字阶（v0.7.8）：displayLarge 44 → 56，与 176 的环同比例放大。
/// 只改字号，字重 / 行高 / 字距沿用全局 displayLarge，不另造一套。
TextStyle? _numberStyle(TextTheme text) =>
    text.displayLarge?.copyWith(fontSize: TodayCard.numberSize);

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTheme.numeric(text.titleLarge?.copyWith(fontSize: 20))),
        const SizedBox(height: 2),
        Text(label, style: text.labelSmall),
      ],
    );
  }
}
