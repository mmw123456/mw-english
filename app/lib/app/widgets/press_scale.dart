import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:material_ui/material_ui.dart';

import '../theme/liquid_glass.dart';

/// 按压缩放（v0.7.6）。
///
/// 跟学习卡上的选项同款：按下 90ms 收到 [pressed]，松开用同一根弹簧
/// （[LiquidGlass.spring]，300 / 24 / 0.8）弹回 1。只改 transform，不碰
/// 宽高和位置，所以按钮的点击热区、投影、玻璃尺寸都不变。
///
/// 用 [Listener] 而不是手势识别器：它不参与 gesture arena，不抢里层
/// `InkWell` 的点击，按下就先缩、抬起由 InkWell 照常走 `onTap`。
class PressScale extends StatefulWidget {
  const PressScale({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// 禁用态（比如「没有待复习」）按下不缩，跟灰字一致。
  final bool enabled;

  /// 按下后的缩放。
  static const double pressed = 0.96;

  /// 按下到位的时间。松开不走时长，走弹簧。
  static const Duration duration = Duration(milliseconds: 90);

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  /// 0 = 常态，1 = 完全按下。
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 按钮从可点变灰时手指可能还按着，别停在按下态。
    if (!widget.enabled && _controller.value != 0) _controller.value = 0;
  }

  void _down(PointerDownEvent _) {
    if (!widget.enabled) return;
    _controller.animateTo(
      1,
      duration: PressScale.duration,
      curve: Curves.easeOut,
    );
  }

  void _release() {
    if (_controller.value == 0) return;
    _controller.animateWith(
      SpringSimulation(LiquidGlass.spring, _controller.value, 0, 0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value.clamp(0.0, 1.0);
          return Transform.scale(
            scale: 1 - (1 - PressScale.pressed) * t,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
