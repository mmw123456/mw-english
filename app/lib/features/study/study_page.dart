import 'package:material_ui/material_ui.dart';

import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../app/widgets/press_scale.dart';
import '../../data/dao/study_dao.dart';
import '../../data/dao/word_dao.dart';
import 'box_band.dart';
import 'study_heatmap.dart';
import 'study_session_page.dart';
import 'today_card.dart';

/// 学习页。
///
/// 顶部卡片读本地 SQLite 的真实记录：今天学了多少新词 / 今日配额、
/// 到期待复习、今天答错次数。点「开始学习」进会话页（四选一 + 当日重测）。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage>
    with AutomaticKeepAliveClientMixin {
  static const _studyDao = StudyDao();
  static const _wordDao = WordDao();

  TodayStats _stats = TodayStats.empty;
  int _myCount = 0;
  int _dayNumber = 0;

  /// 按天完成量（热力图用）。key 是 `yyyy-MM-dd`，只含 v0.7.4 之后的天。
  Map<String, DayTotal> _dayTotals = const {};
  int _streak = 0;

  /// 每个箱位的词数（v0.7.7 色带用）。箱 0 含还没进箱的 820 词。
  Map<int, int> _boxCounts = const {};

  bool _loading = true;

  /// 划走再划回来不重建（v0.7.3）：进度、滚动位置、上一次读到的数字都在。
  /// 进会话页回来仍会 `_load()` 刷新，那是主动刷新，不是重建。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 热力图 12 周最多回到「本周周一 - 11 周」，即今天 - 83 天；
      // 取 90 天窗口兜住跨月跨年的边角。
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day - 90);

      final results = await Future.wait([
        _studyDao.todayStats(),
        _wordDao.countMyWords(),
        _studyDao.studyDayNumber(),
        _studyDao.dailyTotals(from: from, to: now),
        _studyDao.studyStreak(),
        _studyDao.boxCounts(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as TodayStats;
        _myCount = results[1] as int;
        _dayNumber = results[2] as int;
        _dayTotals = results[3] as Map<String, DayTotal>;
        _streak = results[4] as int;
        _boxCounts = results[5] as Map<int, int>;
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
    super.build(context); // AutomaticKeepAliveClientMixin 要求先调 super.build
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
      // v0.7.3：顶部一层柔和色洗（五色 8–12%，只铺任务卡与两个按钮这一带），
      // 让首页的玻璃背后有东西可弯。它不吃点击、不参与布局，也不随列表滚动。
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: LiquidTopWash()),
          RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            child: ListView(
              // 底部 96 + 安全区：Tab 栏浮在内容上（extendBody），别把最后一行说明挡住。
              padding: ShellPadding.scroll(context),
              children: [
                TodayCard(stats: _stats, loading: _loading),
                if (_stats.reduced) ...[
                  const SizedBox(height: 12),
                  _LapseNotice(stats: _stats),
                ],
                const SizedBox(height: 20),
                // 两个主按钮都是玻璃胶囊（v0.7.0）。v0.7.5 起主操作改用橙 tint
                // 10%（跟进度环同一支暖色），次操作保持无色白 tint —— 主次既靠
                // 深浅、也靠色温分开。
                _GlassButton(
                  label: '开始学习',
                  tint: 0.10,
                  tintColor: AppColors.ringOrange,
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
                const SizedBox(height: 20),
                _StatsRow(
                  dayNumber: _dayNumber,
                  mastered: _stats.mastered,
                  total: _myCount,
                ),
                const SizedBox(height: 20),
                // 学习足迹（v0.7.4）：数据区连成一片，规则说明沉底。
                StudyHeatmap(totals: _dayTotals, streak: _streak),
                const SizedBox(height: 32),
                const _SectionLabel('怎么排的'),
                const SizedBox(height: 12),
                // 六箱色带（v0.7.7）：七段按箱位色排，段宽按词数占比。
                // 这条同时是全站图例 —— 词库色点、详情徽章、会话标签都认它。
                BoxBand(counts: _boxCounts),
                const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTheme.numeric(text.titleLarge)),
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
/// 999 圆角、`.20` 投影。主操作把 tint 提到 10% 并染橙（v0.7.5），跟次要
/// 操作的无色 6% 拉开两档；文字保持墨色。
///
/// v0.7.6 补按压缩放：外层 [PressScale] 按下 90ms 收到 0.96，松开走同一根
/// 弹簧回 1 —— 与学习卡上的选项一致。禁用态不缩。
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.onTap,
    required this.tint,
    this.tintColor,
  });

  final String label;
  final VoidCallback? onTap;
  final double tint;

  /// null = 白 tint。主操作传 [AppColors.ringOrange]。
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      child: PressScale(
        enabled: enabled,
        child: GlassSurface(
          onTap: onTap,
          radius: 999,
          blur: 0,
          tintColor: tintColor,
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
      ),
    );
  }
}
