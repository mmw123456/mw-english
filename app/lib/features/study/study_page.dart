import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';

/// 学习页。
///
/// 阶段 2 只做骨架：展示今日进度的空状态 + 主入口按钮。
/// 卡片流、三题型、Leitner 调度在 P0 第 4 步接入。
class StudyPage extends StatelessWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                '第 1 天',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _TodayCard(),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _notReady(context),
            child: const Text('开始学习'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _notReady(context),
            child: const Text('复习待复习'),
          ),
          const SizedBox(height: 32),
          const _StatsRow(),
          const SizedBox(height: 32),
          const _SectionLabel('接下来'),
          const SizedBox(height: 12),
          const _PlanTile(
            index: 1,
            title: '词库接入',
            desc: '820 词 + 43,350 词离线词典导入 SQLite',
          ),
          const _PlanTile(
            index: 2,
            title: '学习卡片',
            desc: '主动回忆 + 三题型轮换',
          ),
          const _PlanTile(
            index: 3,
            title: 'Leitner 调度',
            desc: '六箱分箱，答错降一箱，熟词保护',
          ),
        ],
      ),
    );
  }

  void _notReady(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('学习流程在 P0 第 4 步接入，当前是骨架')),
      );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
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
              Text('今日', style: text.labelMedium),
              Text('目标 20 词', style: text.labelSmall),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '0',
                style: text.displayLarge,
              ),
              const SizedBox(width: 6),
              Text(
                '/ 20',
                style: text.titleLarge?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: const LinearProgressIndicator(
              value: 0,
              minHeight: 3,
              backgroundColor: AppColors.surfaceMuted,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Metric(label: '新词', value: '0'),
              const SizedBox(width: 28),
              _Metric(label: '待复习', value: '0'),
              const SizedBox(width: 28),
              _Metric(label: '答错', value: '0'),
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
        Text(
          value,
          style: text.titleLarge?.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 2),
        Text(label, style: text.labelSmall),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _StatBlock(label: '连续天数', value: '0')),
        SizedBox(width: 12),
        Expanded(child: _StatBlock(label: '已掌握', value: '0')),
        SizedBox(width: 12),
        Expanded(child: _StatBlock(label: '全部词汇', value: '820')),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: text.titleLarge),
          const SizedBox(height: 4),
          Text(label, style: text.labelSmall),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.index,
    required this.title,
    required this.desc,
  });

  final int index;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$index',
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(desc, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
