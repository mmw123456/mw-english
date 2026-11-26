import 'package:material_ui/material_ui.dart';

import '../../app/app_defaults.dart';
import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/liquid_glass.dart';
import '../../data/dao/study_dao.dart';
import '../../data/dao/word_dao.dart';
import 'study_session_page.dart';

/// 学习页。
///
/// 顶部卡片读本地 SQLite 的真实记录：今天学了多少新词 / 今日配额、
/// 到期待复习、今天答错次数。点「开始学习」进会话页（四选一 + 当日重测）。
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

  Future<void> _start({required bool onlyReview}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StudySessionPage(onlyReview: onlyReview),
      ),
    );
    if (!mounted) return;
    if (changed != false) _load();
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
          // 底部 96 + 安全区：Tab 栏浮在内容上（extendBody），别把最后一行说明挡住。
          padding: ShellPadding.scroll(context),
          children: [
            _TodayCard(stats: _stats, loading: _loading),
            if (_stats.reduced) ...[
              const SizedBox(height: 12),
              _LapseNotice(stats: _stats),
            ],
            const SizedBox(height: 20),
            // 两个主按钮都是玻璃胶囊（v0.7.0）。主操作靠 tint 更深一档区分，
            // 不另加颜色。
            _GlassButton(
              label: '开始学习',
              tint: 0.10,
              onTap: _loading ? null : () => _start(onlyReview: false),
            ),
            const SizedBox(height: 12),
            _GlassButton(
              label: _stats.dueReview == 0
                  ? '没有待复习'
                  : '只复习待复习 ${_stats.dueReview} 词',
              tint: LiquidGlass.tint,
              onTap: _loading || _stats.dueReview == 0
                  ? null
                  : () => _start(onlyReview: true),
            ),
            const SizedBox(height: 32),
            _StatsRow(
              dayNumber: _dayNumber,
              mastered: _stats.mastered,
              total: _myCount,
            ),
            const SizedBox(height: 32),
            const _SectionLabel('怎么排的'),
            const SizedBox(height: 12),
            const _RuleNote(
              '六箱间隔 1 / 2 / 4 / 7 / 15 / 30 天。答对升一箱，答错降一箱'
              '（不归零，已到 4 箱以上的词最低只落到 3 箱）。'
              '新词要连续答对 3 次才会进入 3 箱以上。',
            ),
            const SizedBox(height: 10),
            const _RuleNote(
              '当天答错的词当天再考一次，考过才回到正常间隔；当天新学的词'
              '在学完后也再考一次，不等明天。单日复习上限 150 词，多出来的往后顺延。',
            ),
            const SizedBox(height: 10),
            const _RuleNote(
              '断档 3 天以上：新词减半、复习排前面；7 天以上：新词按断档天数摊薄。',
            ),
          ],
        ),
      ),
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
    final target = stats.newTarget <= 0 ? AppDefaults.dailyNewWordTarget : stats.newTarget;
    final done = stats.newLearned;
    final ratio = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);

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
              Text('今日新词', style: text.labelMedium),
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

class _LapseNotice extends StatelessWidget {
  const _LapseNotice({required this.stats});

  final TodayStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 15, color: AppColors.starred),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '断档 ${stats.gapDays} 天，今天新词降到 ${stats.newTarget} 个，先把复习清掉。',
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 0.5),
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

class _RuleNote extends StatelessWidget {
  const _RuleNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            height: 1.7,
            color: AppColors.textSecondary,
          ),
    );
  }
}

/// 全宽玻璃胶囊按钮（v0.7.0）。
///
/// 玻璃只做控件层：0 磨砂（胶囊上 1px 模糊也看不出来，省一层 saveLayer）、
/// 999 圆角、`.20` 投影。主操作把白 tint 提到 10%，跟次要操作拉开一档，
/// 不引第二个颜色。
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.onTap,
    required this.tint,
  });

  final String label;
  final VoidCallback? onTap;
  final double tint;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      child: GlassSurface(
        onTap: onTap,
        radius: 999,
        blur: 0,
        tintAlpha: tint,
        minHeight: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: enabled ? LiquidGlass.ink : LiquidGlass.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}
