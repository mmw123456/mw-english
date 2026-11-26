import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/box_colors.dart';
import '../../app/widgets/box_badge.dart';

/// 六箱色带（v0.7.7）：首页「怎么排的」下面的那条分布图，同时是全站图例。
///
/// 七段按箱位颜色排列（箱 0 新词 + 箱 1–6），段宽按词数占比；0 词的段
/// 只留一个固定宽的色标、不按比例占宽 —— 否则某个箱空着时会在色带上
/// 留一道和「有词」分不清的空隙。
///
/// 文字不塞进段里：390 宽的屏上七段平均只有 50px，「箱 1 · 120 词」放
/// 不下，硬塞会被裁字。改成色带下面一行 Wrap 图例，读得全也读得清。
class BoxBand extends StatelessWidget {
  const BoxBand({required this.counts, super.key});

  /// 箱位 → 词数，0–[BoxColors.topBox] 七档。缺的键按 0 处理。
  final Map<int, int> counts;

  /// 段与段之间的缝。相邻的箱 4 橙 / 箱 5 深橙只靠明度分，留 2px 更清楚。
  static const double gap = 2;

  /// 色带高度。
  static const double bandHeight = 10;

  /// 0 词段的色标宽度。
  static const double stubWidth = 6;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: bandHeight,
            // 必须 stretch：ColoredBox 没有固有高度，Row 默认 center 对齐时
            // 每段会被压成 0 高 —— 宽度全对、色带整个看不见（v0.7.7 撞过）。
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var b = 0; b <= BoxColors.topBox; b++) ...[
                  if (b > 0) const SizedBox(width: gap),
                  if ((counts[b] ?? 0) > 0)
                    Expanded(
                      flex: counts[b]!,
                      child: ColoredBox(
                        key: ValueKey('band-seg-$b'),
                        color: boxColor(b),
                      ),
                    )
                  else
                    SizedBox(
                      width: stubWidth,
                      child: ColoredBox(
                        key: ValueKey('band-seg-$b'),
                        color: boxColor(b),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (var b = 0; b <= BoxColors.topBox; b++)
              _LegendItem(box: b, count: counts[b] ?? 0),
          ],
        ),
      ],
    );
  }
}

/// 图例的一项：8px 色点 + 「箱 N · M 词」（箱 0 写「新词」）。
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.box, required this.count});

  final int box;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BoxDot(box: box),
        const SizedBox(width: 4),
        Text(
          '${boxLabel(box)} · $count 词',
          style: AppTheme.numeric(
            text.labelSmall?.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
