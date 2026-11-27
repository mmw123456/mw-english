import 'package:material_ui/material_ui.dart';

import '../../app/app_signals.dart';
import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../app/widgets/press_scale.dart';
import '../../data/dao/settings_dao.dart';
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
  static const _settings = SettingsDao();

  TodayStats _stats = TodayStats.empty;
  int _myCount = 0;

  /// 自加词数（v0.8.0）。「全部词汇」= 820 + 自加词（决策 107）。
  int _addedCount = 0;
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
    AppSignals.settingsChanged.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    AppSignals.settingsChanged.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 设置页改了每日目标 / 遮盖 / 朗读后重读。首页的环、状态行与配额
  /// 都从库里算，重读一次就全部跟上（决策 110）。
  void _onSettingsChanged() => _load();

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
        _settings.addedCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as TodayStats;
        _myCount = results[1] as int;
        _dayNumber = results[2] as int;
        _dayTotals = results[3] as Map<String, DayTotal>;
        _streak = results[4] as int;
        _boxCounts = results[5] as Map<int, int>;
        _addedCount = results[6] as int;
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
                // T4 次要：400 / 墨 62%（v0.7.9）。
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.textTertiary),
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
                // 首页只留一个玻璃控件（v0.7.8）：主操作是 56 高、橙 tint 10%
                // 的玻璃胶囊，18pt 字；「只复习」降为它下面的文字入口。
                _GlassButton(
                  label: '开始学习',
                  tint: 0.10,
                  tintColor: AppColors.ringOrange,
                  fontSize: 18,
                  onTap: _loading ? null : () => _start(onlyReview: false),
                ),
                const SizedBox(height: 12),
                ReviewLink(
                  label: _stats.dueReview == 0
                      ? '没有待复习'
                      : '只复习待复习 ${_stats.dueReview} 词',
                  onTap: _loading || _stats.dueReview == 0
                      ? null
                      : () => _start(onlyReview: true),
                ),
                const SizedBox(height: 20),
                _StatsRow(
                  dayNumber: _dayNumber,
                  mastered: _stats.mastered,
                  total: _myCount + _addedCount,
                ),
                const SizedBox(height: 20),
                // 学习足迹（v0.7.4）：数据区连成一片，规则说明沉底。
                StudyHeatmap(totals: _dayTotals, streak: _streak),
                const SizedBox(height: 32),
                const _SectionLabel('怎么排的'),
                const SizedBox(height: 12),
                // 七箱色带（v0.7.7）：七段按箱位色排，段宽按词数占比。
                // 这条同时是全站图例 —— 词库色点、详情徽章、会话标签都认它。
                // 加载中或读库失败时 counts 为空，整块不出现，免得先闪一排「0 词」。
                if (_boxCounts.isNotEmpty) ...[
                  BoxBand(counts: _boxCounts),
                  const SizedBox(height: 12),
                ],
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

/// 二级区块标题（v0.7.8）：16 / 700 / 墨。
///
/// 首页主角化后，环里的 56 是唯一的视觉重心；区块标题统一到「比正文重、
/// 比 Hero 小得多」这一档，不再用 13 小字 + 字距 1.2 的老写法。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
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
///
/// v0.7.8：首页只剩这一个玻璃控件，字号可传（主操作用 18），高度仍是 56。
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.onTap,
    required this.tint,
    this.tintColor,
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback? onTap;
  final double tint;

  /// null = 白 tint。主操作传 [AppColors.ringOrange]。
  final Color? tintColor;

  /// 文字字号。默认 16（全局 labelLarge），首页主操作传 18。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      // 高度靠 GlassSurface 的 minHeight 56：正常字号下正好 56，系统字体
      // 放大时跟着长高而不是裁字。写死 height 会在 1.3 倍字号下切掉字。
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
                fontSize: fontSize,
                color: enabled ? LiquidGlass.ink : LiquidGlass.textDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 次要入口（v0.7.8）：「只复习」从第二个玻璃胶囊降成一行文字按钮。
///
/// 无玻璃、无底色、无投影，只有墨 70% 的字 —— 首页的玻璃只留给主操作。
/// 文案与点击逻辑与 v0.7.7 完全一致（0 待复习时禁用并显示「没有待复习」）。
///
/// 公开类，理由同 [TodayCard] / `WordRow`：`StudyPage` 依赖 sqflite，
/// widget 测试打不开库，只能单独喂它。
class ReviewLink extends StatelessWidget {
  const ReviewLink({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final text = Theme.of(context).textTheme;

    return Center(
      child: TextButton(
        key: const ValueKey('review-link'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          label,
          // T2 按钮文字：700（v0.7.9）。它仍是次入口 —— 靠 16pt / 墨 70%
          // 跟 18pt 墨色的主按钮拉开，不靠降字重。
          style: text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: enabled ? AppColors.textSecondary : LiquidGlass.textDisabled,
          ),
        ),
      ),
    );
  }
}
