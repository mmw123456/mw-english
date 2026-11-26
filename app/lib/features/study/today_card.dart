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
/// 「已学 / 目标」）→ 三格数字（新词 / 待复习 / 答错）。
///
/// v0.7.4 撤掉了原来的细进度条和中间那行大数字 —— 那两样讲的是同一件事，
/// 挤在一张卡里谁都不是主角。现在主角是环。
///
/// **分母用 [TodayStats.newTarget]，不是硬编码 30**：断档会削减当日配额，
/// 那时顶部写「目标 6 词」、环里写「/6」，三处一致；写死 30 会自相矛盾。
class TodayCard extends StatelessWidget {
  const TodayCard({required this.stats, required this.loading, super.key});

  final TodayStats stats;
  final bool loading;

  /// 今日目标。配额异常（0）时退回默认值，避免除零。
  int get target =>
      stats.newTarget <= 0 ? AppDefaults.dailyNewWordTarget : stats.newTarget;

  /// 环的填充比例。与环里的数字是同一对 (done, target)。
  double get ratio => (stats.newLearned / target).clamp(0.0, 1.0);

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
              Text('今日新词', style: text.labelMedium),
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
                    Text('—', style: text.displayLarge)
                  else
                    RollingInt(
                      key: const ValueKey('ring-count'),
                      value: done,
                      style: text.displayLarge,
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
