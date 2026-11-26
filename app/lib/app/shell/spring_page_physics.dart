import 'package:material_ui/material_ui.dart';

import '../theme/liquid_glass.dart';

/// 左右划翻页的物理（v0.7.3）。
///
/// 两件事和默认 `PageScrollPhysics` 不同：
///
/// 1. **落位用全 App 那条弹簧**（[LiquidGlass.spring]，mass 0.8 / stiffness 300 /
///    damping 24），不是 `ScrollPhysics.spring`（mass 0.5 / stiffness 100），
///    更不是线性动画。松手后的收尾跟按压回弹、卡片切入是同一种手感。
/// 2. **过半才翻页，速度不参与选页**。默认物理会把松手速度折算成 ±0.5 页，
///    于是「快速划一点点」也会翻页，手感与「划过一半松手就到下一页，
///    不到一半弹回」对不上。这里目标一律取**最近的整页**：
///    `page.round()` —— 0.49 弹回原页，0.51 去下一页。
///
/// 松手速度仍作为弹簧的初速度传进去（不改变落点，只影响轨迹）：手指甩得
/// 快，页面就冲过一点再回来；这也是弹簧该有的样子。
///
/// 前提：配合默认 `viewportFraction = 1.0` 的 `PageView`。页宽等于视口宽，
/// `pixels / viewportDimension` 就是页码。
class SpringPagePhysics extends PageScrollPhysics {
  const SpringPagePhysics({super.parent});

  /// 弹簧模拟的收敛判据：0.05px / 0.5px·s⁻¹。
  ///
  /// 与 `PageScrollPhysics` 的内部判据同量级 —— 判得太严会让弹簧在
  /// 肉眼看不见的位移上多跑几十帧（`pumpAndSettle` 也会跟着变慢）。
  static const Tolerance pageTolerance = Tolerance(
    velocity: 0.5,
    distance: 0.05,
  );

  @override
  SpringPagePhysics applyTo(ScrollPhysics? ancestor) {
    return SpringPagePhysics(parent: buildParent(ancestor));
  }

  /// 当前停在「第几页」的小数形式（0.37 = 停在 0 与 1 之间）。
  static double pageOf(ScrollMetrics position) {
    final viewport = position.viewportDimension;
    if (viewport <= 0) return 0;
    return position.pixels / viewport;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // 还没有内容尺寸（首帧）时不要自己算：min / max 都还是 0，
    // 会把目标夹成第 0 页，页面被硬拽回去。
    if (!position.hasContentDimensions) return null;

    final viewport = position.viewportDimension;
    if (viewport <= 0) return super.createBallisticSimulation(position, velocity);

    // 越界（iOS 橡皮筋回弹途中）交给父物理收边，别自己算。
    if (position.pixels < position.minScrollExtent ||
        position.pixels > position.maxScrollExtent) {
      return super.createBallisticSimulation(position, velocity);
    }

    final target = (pageOf(position).roundToDouble() * viewport)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    // 已经落在整页上：什么都不做。
    //
    // 这里**不能**交回父物理 —— `PageScrollPhysics` 会把松手速度折算成
    // ±0.5 页，正好把「速度不参与选页」这条推翻（拖满一页后一甩就多翻一页）。
    if ((target - position.pixels).abs() < 0.01) return null;

    return ScrollSpringSimulation(
      LiquidGlass.spring,
      position.pixels,
      target,
      velocity,
      tolerance: pageTolerance,
    );
  }
}
