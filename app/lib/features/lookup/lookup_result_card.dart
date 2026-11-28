import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/example_line.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models/word_example.dart';

/// 查词结果卡（v0.11.0）。
///
/// 四个入口共用这一张：查词页内联显示、文章双击的底部弹层也用它。
/// 只画结果，不查库、不发音、不加词 —— 那三件事由调用方给回调，
/// 这样 `flutter test` 能直接喂一个 [LookupResult] 断言文案与按钮状态。
///
/// 释义分两段的条件是「两段都有且不一样」（820 词的两段式）：
/// 词书原释一行、词典全释一行，各带小标；只有一段时不加标，直接显示。
class LookupResultCard extends StatelessWidget {
  const LookupResultCard({
    required this.result,
    required this.onSpeak,
    this.onAdd,
    this.adding = false,
    this.justAdded = false,
    this.onOpenDetail,
    super.key,
  });

  final LookupResult result;

  /// 发音。null 表示不提供（比如没有 TTS 的场景）。
  final VoidCallback? onSpeak;

  /// 加入生词本。null 或已在本里都会让按钮置灰。
  final VoidCallback? onAdd;

  final bool adding;

  /// 刚刚在本页加进去的：还没重新读库，先按「已在词库 · 箱 0」画。
  final bool justAdded;

  /// 查看完整词条（变形 / 词根 / 近义词 / 星标 / 斩词都在那边）。
  final VoidCallback? onOpenDetail;

  bool get _inLibrary => result.inLibrary || justAdded;

  /// 例句只显第一条（v0.12.0）：卡片是「快速看一眼释义」的地方，
  /// 想看全部去完整词条。没有例句的 628 个词这里整块不出现，不占位置。
  Widget _exampleBlock(BuildContext context, WordExample example) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('lookup-example'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExampleLine(example: example, dense: true),
          const SizedBox(height: 5),
          Text(
            'Tatoeba · CC-BY 2.0 FR',
            key: const ValueKey('lookup-example-source'),
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 已在库里时按钮上的那句话。
  String get inLibraryLabel {
    // 刚在本页加进去的：还没重新读库，按自加词口径就是 0 箱起步。
    if (justAdded && !result.inLibrary) return '已在词库 · 箱 0';
    final box = result.box;
    if (box == null) return '已在词库';
    return '已在词库 · 箱 $box';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  result.word,
                  key: const ValueKey('lookup-word'),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (result.phonetic.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  '/${result.phonetic}/',
                  key: const ValueKey('lookup-phonetic'),
                  style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
              const Spacer(),
              IconButton(
                key: const ValueKey('lookup-speak'),
                onPressed: onSpeak,
                tooltip: '发音',
                iconSize: 20,
                icon: const Icon(
                  Icons.volume_up_outlined,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (result.pos.isNotEmpty)
                _Tag(
                  label: result.pos,
                  keyName: 'lookup-pos',
                ),
              _Tag(
                label: result.source.label,
                keyName: 'lookup-source',
                muted: true,
              ),
              if (result.killed)
                _Tag(label: '已斩', keyName: 'lookup-killed', muted: true),
            ],
          ),
          const SizedBox(height: 12),
          if (!result.hasMeaning)
            Text(
              '这个词在离线词典里没有释义。',
              key: const ValueKey('lookup-no-meaning'),
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            )
          else if (result.twoParts) ...[
            _MeaningBlock(
              label: '词书原释',
              value: result.bookMeaning,
              keyName: 'lookup-meaning-book',
            ),
            const SizedBox(height: 12),
            _MeaningBlock(
              label: '词典全释',
              value: result.dictMeaning,
              keyName: 'lookup-meaning-dict',
            ),
          ] else
            Text(
              result.bookMeaning.isNotEmpty
                  ? result.bookMeaning
                  : result.dictMeaning,
              key: const ValueKey('lookup-meaning'),
              style: text.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.8,
              ),
            ),
          const SizedBox(height: 16),
          if (result.detail.examples.isNotEmpty) ...[
            _exampleBlock(context, result.detail.examples.first),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: ValueKey(_inLibrary ? 'lookup-in-lib' : 'lookup-add'),
              onPressed: _inLibrary || adding ? null : onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(
                _inLibrary
                    ? inLibraryLabel
                    : (adding ? '加入中…' : '加入生词本'),
              ),
            ),
          ),
          if (onOpenDetail != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                key: const ValueKey('lookup-detail'),
                onPressed: onOpenDetail,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(0, 44),
                ),
                child: Text(
                  '查看完整词条',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeaningBlock extends StatelessWidget {
  const _MeaningBlock({
    required this.label,
    required this.value,
    required this.keyName,
  });

  final String label;
  final String value;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          key: ValueKey(keyName),
          style: text.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.8,
          ),
        ),
      ],
    );
  }
}

/// 小标签：词性 / 来源 / 已斩。
class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.keyName,
    this.muted = false,
  });

  final String label;
  final String keyName;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: ValueKey(keyName),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: muted ? AppColors.textTertiary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
