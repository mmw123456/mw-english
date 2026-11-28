import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../data/models/word_example.dart';

/// 一条例句：英文原句（目标词加粗）+ 中文译文。
///
/// 详情页与查词结果卡共用这一个控件，只是 [dense] 不同：
/// - 详情页：完整两行 + 段落间距
/// - 查词卡：只显示第一条、行距收紧
///
/// 加粗不在这里判断「哪个词是目标词」—— 数据里 `hl` 已经用 `**` 标好，
/// 控件只负责切分。这样同一个词条在任何地方加粗的位置都一致。
class ExampleLine extends StatelessWidget {
  const ExampleLine({
    required this.example,
    this.dense = false,
    this.masked = false,
    this.onReveal,
    super.key,
  });

  final WordExample example;

  /// 查词卡用：字号与间距收一档。
  final bool dense;

  /// 中文被遮盖时只显示提示，点一下才出译文。
  final bool masked;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enStyle = (dense ? text.bodySmall : text.bodyMedium)?.copyWith(
      color: AppColors.textPrimary,
      height: dense ? 1.5 : 1.65,
    );
    final zhStyle = (dense ? text.labelSmall : text.bodySmall)?.copyWith(
      color: AppColors.textSecondary,
      height: dense ? 1.45 : 1.55,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              for (final span in example.spans)
                TextSpan(
                  text: span.text,
                  style: span.bold
                      ? enStyle?.copyWith(fontWeight: FontWeight.w700)
                      : enStyle,
                ),
            ],
          ),
        ),
        SizedBox(height: dense ? 2 : 4),
        if (masked)
          GestureDetector(
            onTap: onReveal,
            behavior: HitTestBehavior.opaque,
            child: Text(
              '点一下显示中文',
              style: zhStyle?.copyWith(color: AppColors.textTertiary),
            ),
          )
        else
          Text(example.zh, style: zhStyle),
      ],
    );
  }
}

/// 详情页的「例句」区块（v0.12.0）。
///
/// 有例句就列出来（1–3 条）+ 底部一句署名；没有就一行「暂无例句」。
/// 抽成独立控件是为了能在 `flutter test` 里直接喂数据渲染 —— 详情页本身
/// 要开 SQLite，测试环境开不了。
class ExampleSection extends StatelessWidget {
  const ExampleSection({
    required this.examples,
    this.maskedOf,
    this.onReveal,
    super.key,
  });

  final List<WordExample> examples;

  /// 第 i 条的中文是否被遮盖（跟随详情页的全局「遮盖中文」开关）。
  final bool Function(int index)? maskedOf;
  final void Function(int index)? onReveal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('detail-examples'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(AppTheme.cardRadius)),
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '例句',
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          if (examples.isEmpty)
            Text(
              '暂无例句',
              key: const ValueKey('detail-no-example'),
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            )
          else ...[
            for (var i = 0; i < examples.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              ExampleLine(
                key: ValueKey('detail-example-$i'),
                example: examples[i],
                masked: maskedOf?.call(i) ?? false,
                onReveal: onReveal == null ? null : () => onReveal!(i),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              kExampleAttribution,
              key: const ValueKey('detail-example-source'),
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
