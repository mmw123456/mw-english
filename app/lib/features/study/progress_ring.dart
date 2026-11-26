import 'dart:math' as math;

import 'package:flutter/physics.dart' show Simulation, SpringSimulation, Tolerance;
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/liquid_glass.dart';

/// 首页任务卡的进度环（v0.7.4）。
///
/// 直径 132、线宽 12、圆头端点；轨道是墨 10%，填充是 [AppColors.ringOrange]
/// （纸上 3.48:1，图元线 ≥3:1）。填充比例 = 今日新词已学 / 今日目标，与环里
/// 那组数字同源，所以不会出现「数字 13、环却按别的分母画」这种事。
///
/// v0.7.5：填充由冷色蓝换暖橙 —— 首页按「暖 = 今天 / 进行中」分工，蓝退到
/// 热力图。尺寸、线宽、轨道、弹簧一律没动。
///
/// 动效只有一条：**用全 App 那条弹簧**（[LiquidGlass.spring]，300 / 24 / 0.8）
/// 从旧值扫到新值，**不从 0 重播**。首次出现时旧值天然是 0，看起来就是
/// 「从 12 点扫出当前进度」；从会话页回来数值变了，就从旧值接着扫。
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    required this.value,
    this.size = ProgressRing.diameter,
    this.strokeWidth = ProgressRing.stroke,
    this.child,
    super.key,
  });

  /// 0–1。弹簧会轻微过冲，画的时候夹一次就够。
  final double value;

  final double size;
  final double strokeWidth;

  /// 环中间的内容。首页放今日新词的大数字。
  final Widget? child;

  static const double diameter = 132;
  static const double stroke = 12;

  /// 轨道：墨 10%。比纸深一档，看得见但不抢。
  static const Color track = Color(0x1A0B0C10);

  /// 收敛判据。比默认宽容一点：弹簧尾巴上那点肉眼看不出的抖动不值得
  /// 多跑几十帧，`pumpAndSettle` 也会跟着变慢。
  static const Tolerance tolerance = Tolerance(
    distance: 0.0005,
    velocity: 0.002,
  );

  /// 从 [from] 走到 [to] 的那条模拟。
  ///
  /// 抽成静态方法是为了让测试能直接断言「用的是弹簧、参数就是
  /// LiquidGlass.spring」，而不是去猜动画时序。
  @visibleForTesting
  static Simulation simulation(double from, double to) => SpringSimulation(
        LiquidGlass.spring,
        from,
        to,
        0,
        tolerance: tolerance,
      );

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static double _clamp(double v) => v.clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    // unbounded：弹簧会过冲，超出 1 之后还得能落回来。
    _controller = AnimationController.unbounded(vsync: this, value: 0);
    final target = _clamp(widget.value);
    if (target > 0) {
      _controller.animateWith(ProgressRing.simulation(0, target));
    }
  }

  @override
  void didUpdateWidget(covariant ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;

    final from = _clamp(_controller.value);
    final to = _clamp(widget.value);
    if ((to - from).abs() < 0.0001) {
      _controller.value = to;
      return;
    }
    _controller.animateWith(ProgressRing.simulation(from, to));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: ProgressRingPainter(
              progress: _clamp(_controller.value),
              strokeWidth: widget.strokeWidth,
            ),
            child: child,
          );
        },
        child: Center(child: widget.child),
      ),
    );
  }
}

/// 只画两段圆弧，不掺别的。
@visibleForTesting
class ProgressRingPainter extends CustomPainter {
  const ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    this.color = AppColors.ringOrange,
  });

  final double progress;
  final double strokeWidth;

  /// 填充色。默认就是首页那支暖橙（v0.7.5），调用点不用传。
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = ProgressRing.track,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2, // 12 点起
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(ProgressRingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.color != color;
}
