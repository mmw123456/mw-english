import 'package:material_ui/material_ui.dart';

import '../../app/app_defaults.dart';
import '../../app/theme/app_colors.dart';
import '../../data/dao/study_dao.dart';
import '../../data/dao/word_dao.dart';

/// 学习页。
///
/// 顶部卡片读本地 SQLite 的今日统计：今日已学新词 / 每日目标 30、
/// 待复习、今日答错。卡片流与 Leitner 调度在 P0 第 4 步接入。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  static const _studyDao = StudyDao();
  static const _wordDao = WordDao();

  TodayStats _stats = TodayStats.empty;
  int _myCount = 0;
  int _dayNumber = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _studyDao.todayStats(),
        _wordDao.countMyWords(),
        _studyDao.studyDayNumber(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as TodayStats;
        _myCount = results[1] as int;
        _dayNumber = results[2] as int;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

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
                _loading
                    ? '　'
                    : (_dayNumber == 0 ? '未开始' : '第 $_dayNumber 天'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _TodayCard(stats: _stats, loading: _loading),
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
            _StatsRow(
              dayNumber: _dayNumber,
              mastered: _stats.mastered,
              total: _myCount,
            ),
            const SizedBox(height: 32),
            const _SectionLabel('接下来'),
            const SizedBox(height: 12),
            const _PlanTile(
              index: 1,
              title: '学习卡片',
              desc: '主动回忆 + 三题型轮换',
            ),
            const _PlanTile(
              index: 2,
              title: 'Leitner 调度',
              desc: '六箱分箱，答错降一箱，熟词保护',
            ),
          ],
        ),
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
  const _TodayCard({required this.stats, required this.loading});

  final TodayStats stats;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const target = AppDefaults.dailyNewWordTarget;
    final done = stats.newLearned;
    final ratio = (done / target).clamp(0.0, 1.0);

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
              Text('目标 $target 词', style: text.labelSmall),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(loading ? '—' : '$done', style: text.displayLarge),
              const SizedBox(width: 6),
              Text(
                '/ $target',
                style: text.titleLarge?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: AppColors.surfaceMuted,
            ),
          ),
          const SizedBox(height: 18),
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
        Text(value, style: text.titleLarge?.copyWith(fontSize: 20)),
        const SizedBox(height: 2),
        Text(label, style: text.labelSmall),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.dayNumber,
    required this.mastered,
    required this.total,
  });

  final int dayNumber;
  final int mastered;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatBlock(
            label: '学习天数',
            value: dayNumber == 0 ? '0' : '$dayNumber',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _StatBlock(label: '已掌握', value: '$mastered')),
        const SizedBox(width: 12),
        Expanded(child: _StatBlock(label: '全部词汇', value: '$total')),
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
