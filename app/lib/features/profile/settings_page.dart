import 'package:material_ui/material_ui.dart';

import '../../app/app_defaults.dart';
import '../../app/app_signals.dart';
import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../data/dao/settings_dao.dart';
import 'deepseek_key_card.dart';

/// 纸面卡：与详情页 `_paperCard` 同一套（比纸亮一点 + 0.5px 描边）。
const BoxDecoration _paperCard = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(AppTheme.cardRadius)),
  border: Border.fromBorderSide(
    BorderSide(color: AppColors.divider, width: 0.5),
  ),
);

/// 设置页第一版（v0.8.0）。
///
/// 从「我的」页进。只做三项真实设置：
/// - 每日新词目标 10–50（默认 30）：首页的环、状态行、每日配额都跟着它走；
/// - 遮盖中文（默认关）：与词库页、详情页共用 `settings.mask_chinese`；
/// - 自动朗读（默认开）：每张新卡出现时读一遍单词。
///
/// 其余设置项先占位，不做。改完写库后发 [AppSignals.settingsUpdated]，
/// 三个 keep-alive 的 Tab 页收到通知自己重读，不靠重建。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _settings = SettingsDao();

  bool _loading = true;
  int _target = AppDefaults.dailyNewWordTarget;
  bool _masked = false;
  bool _autoSpeak = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _settings.dailyTarget(),
        _settings.maskChinese(),
        _settings.autoSpeak(),
      ]);
      if (!mounted) return;
      setState(() {
        _target = values[0] as int;
        _masked = values[1] as bool;
        _autoSpeak = values[2] as bool;
        _loading = false;
      });
    } catch (_) {
      // 读不到就用默认值把页面画出来，不让设置页变成错误页。
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveTarget(int value) async {
    // 拖回原值就不写库：写了会白清一次当天配额缓存。
    if (value == _target) return;
    final previous = _target;
    setState(() => _target = value);
    try {
      await _settings.setDailyTarget(value);
      AppSignals.settingsUpdated();
    } catch (_) {
      // 写库失败就退回旧值：下次进来还是旧目标，不假装保存成功。
      if (mounted) setState(() => _target = previous);
    }
  }

  Future<void> _saveMask(bool value) async {
    setState(() => _masked = value);
    try {
      await _settings.setMaskChinese(value);
      AppSignals.settingsUpdated();
    } catch (_) {
      if (mounted) setState(() => _masked = !value);
    }
  }

  Future<void> _saveAutoSpeak(bool value) async {
    setState(() => _autoSpeak = value);
    try {
      await _settings.setAutoSpeak(value);
      AppSignals.settingsUpdated();
    } catch (_) {
      if (mounted) setState(() => _autoSpeak = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              padding: ShellPadding.scroll(context),
              children: [
                const _GroupLabel('学习'),
                DailyTargetCard(target: _target, onChanged: _saveTarget),
                const SizedBox(height: 20),
                const _GroupLabel('显示'),
                _SettingsCard(
                  child: SettingSwitchRow(
                    key: const ValueKey('mask-chinese'),
                    title: '遮盖中文',
                    subtitle: '词库与详情页默认盖住中文释义，点一下显示',
                    value: _masked,
                    onChanged: _saveMask,
                  ),
                ),
                const SizedBox(height: 20),
                const _GroupLabel('朗读'),
                _SettingsCard(
                  child: SettingSwitchRow(
                    key: const ValueKey('auto-speak'),
                    title: '自动朗读',
                    subtitle: '每张新卡出现时读一遍单词',
                    value: _autoSpeak,
                    onChanged: _saveAutoSpeak,
                  ),
                ),
                const SizedBox(height: 20),
                const _GroupLabel('阅读'),
                const _SettingsCard(child: DeepSeekKeyCard()),
                const SizedBox(height: 20),
                const _GroupLabel('其他'),
                const _SettingsCard(
                  child: Column(
                    children: [
                      _PlaceholderRow(
                        icon: Icons.record_voice_over_outlined,
                        title: '发音口音',
                        value: '未接',
                      ),
                      Divider(height: 1, color: AppColors.divider),
                      _PlaceholderRow(
                        icon: Icons.notifications_none_rounded,
                        title: '学习提醒',
                        value: '未接',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '其余设置项先占位，后续版本再做。',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
    );
  }
}

/// 每日新词目标卡（v0.8.0）。
///
/// 公开是为了 widget 测试能直接喂一个目标、断言范围与回调 ——
/// [SettingsPage] 依赖 sqflite，`flutter test` 里打不开库（踩坑 21）。
class DailyTargetCard extends StatefulWidget {
  const DailyTargetCard({
    required this.target,
    required this.onChanged,
    super.key,
  });

  final int target;

  /// 松手时回调（拖动过程中只改本地显示，不写库）。
  final ValueChanged<int> onChanged;

  static const int minValue = AppDefaults.minDailyNewWords;
  static const int maxValue = AppDefaults.maxDailyNewWords;

  @override
  State<DailyTargetCard> createState() => _DailyTargetCardState();
}

class _DailyTargetCardState extends State<DailyTargetCard> {
  late int _value = SettingsDao.clampDailyTarget(widget.target);

  @override
  void didUpdateWidget(covariant DailyTargetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _value = SettingsDao.clampDailyTarget(widget.target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: _paperCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('每日新词目标', style: text.bodyMedium),
              const Spacer(),
              Text(
                '$_value 词',
                style: AppTheme.numeric(text.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: LiquidGlass.ink,
              inactiveTrackColor: AppColors.surfaceMuted,
              thumbColor: LiquidGlass.ink,
              overlayColor: LiquidGlass.ink.withValues(alpha: 0.08),
              valueIndicatorColor: LiquidGlass.ink,
              valueIndicatorTextStyle:
                  text.labelSmall?.copyWith(color: LiquidGlass.paper),
            ),
            child: Slider(
              key: const ValueKey('daily-target-slider'),
              value: _value.toDouble(),
              min: DailyTargetCard.minValue.toDouble(),
              max: DailyTargetCard.maxValue.toDouble(),
              divisions:
                  DailyTargetCard.maxValue - DailyTargetCard.minValue,
              label: '$_value 词',
              onChanged: (v) => setState(() => _value = v.round()),
              onChangeEnd: (v) => widget.onChanged(v.round()),
            ),
          ),
          Text(
            '范围 10–50 词，默认 30。改完当天配额按新目标重算。',
            style: text.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行开关设置（v0.8.0）：标题 + 说明 + 右侧 Switch，整行可点。
class SettingSwitchRow extends StatelessWidget {
  const SettingSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.bodyMedium),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: _paperCard,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: child,
      ),
    );
  }
}

/// 占位行（v0.8.0）：灰掉、不可点，明说「未接」。
class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          Text(
            value,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textTertiary,
            ),
      ),
    );
  }
}
