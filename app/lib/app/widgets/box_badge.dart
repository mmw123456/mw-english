import 'package:material_ui/material_ui.dart';

import '../theme/box_colors.dart';
import '../theme/liquid_glass.dart';

/// 8px 实心色点（v0.7.7）：全站箱位色的唯一画法。
///
/// 只给两个地方用：词库列表行首、箱位徽章内部。颜色一律走 [boxColor]，
/// 别在页面里另写十六进制。**不加描边**——薄荷在纸上只有约 1.6:1，
/// 靠色相区分不靠明暗；真机实测若发淡，再给它单独加深描边。
class BoxDot extends StatelessWidget {
  const BoxDot({required this.box, this.size = 8, super.key});

  final int box;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: boxColor(box),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 箱位徽章（v0.7.7）：色点 + 墨字「箱 N」（箱 0 写「新词」），底色是箱位色 15%。
///
/// 详情页头部与会话页顶部共用这一个组件，两处样式必须一模一样。
/// **不用白字**：薄荷底上白字对比度不够，所以文字一律用墨。
class BoxBadge extends StatelessWidget {
  const BoxBadge({required this.box, super.key});

  final int box;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: boxTint(box),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoxDot(box: box),
          const SizedBox(width: 5),
          Text(
            boxLabel(box),
            // T4 次要：400（v0.7.9）。颜色仍用墨 —— 徽章压在 15% 箱色底上，
            // 墨 62% 会糊；决策 96 的「徽章文字一律墨色」优先。
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: LiquidGlass.ink,
                ),
          ),
        ],
      ),
    );
  }
}
