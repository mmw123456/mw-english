import 'dart:math' as math;

import 'package:flutter/physics.dart'
    show Simulation, SpringSimulation, Tolerance;
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/liquid_glass.dart';

/// 会滚动的整数（v0.7.6）。
///
/// 数字从旧值扫到新值，用的是全 App 唯一那条弹簧（[LiquidGlass.spring]，
/// 300 / 24 / 0.8），不另加曲线。宽度不跳由等宽数字（[AppTheme.tabular]）
/// 保证，不靠给数字留固定宽度。
///
/// 首次出现**不从 0 播**：页面重建（切 Tab 回来、下拉刷新）时数字会从 0
/// 跳一遍，比瞬显更烦人。只有 `value` 真的变了才滚。
///
/// 弹簧会过冲，显示的整数夹在「起点—终点」之间，所以永远不会短暂显示
/// 一个比目标更大的数（比如目标 13 却闪一下 14）。
class RollingInt extends StatefulWidget {
  const RollingInt({
    required this.value,
    this.style,
    this.textAlign,
    super.key,
  });

  final int value;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// 与 [ProgressRing.tolerance] 同一档：尾巴上那点抖动不值得多跑几十帧。
  static const Tolerance tolerance = Tolerance(
    distance: 0.0005,
    velocity: 0.002,
  );

  /// 从 [from] 走到 [to] 的那条模拟。抽成静态方法，测试直接断言参数。
  @visibleForTesting
  static Simulation simulation(double from, double to) => SpringSimulation(
        LiquidGlass.spring,
        from,
        to,
        0,
        tolerance: tolerance,
      );

  @override
  State<RollingInt> createState() => _RollingIntState();
}

class _RollingIntState extends State<RollingInt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 本次滚动的起点与终点。显示值夹在这两个数之间。
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.value.toDouble();
    _controller = AnimationController.unbounded(vsync: this, value: _from);
  }

  @override
  void didUpdateWidget(covariant RollingInt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;

    _from = _controller.value;
    _to = widget.value.toDouble();
    // 差不到半个数就别滚了，直接落位，免得 12→12 也走一遍弹簧。
    if ((_to - _from).abs() < 0.5) {
      _controller.value = _to;
      return;
    }
    _controller.animateWith(RollingInt.simulation(_from, _to));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.numeric(widget.style);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final lo = math.min(_from, _to);
        final hi = math.max(_from, _to);
        final shown = _controller.value.clamp(lo, hi).round();
        return Text('$shown', style: style, textAlign: widget.textAlign);
      },
    );
  }
}
