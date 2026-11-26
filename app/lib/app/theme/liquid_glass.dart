import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 全 App 共用的液态玻璃语言（v0.7.0 起，不再是「预览」）。
///
/// 风格来源 guanmo-ai/design-style 的 014 液态玻璃。规则按原文落实：
/// - 玻璃本身没有颜色：只有极淡白 tint（0–2%）、迎光侧 1px 亮边、投影；
/// - 亮边方向固定左上（-37°），不是整圈描边 —— 整圈白边就是 2020 年的毛玻璃；
/// - 背景亮时字用墨（规则 05）：纸底 #F3F2EE 上正文用 #0B0C10。
///
/// 版本轨迹：
/// - v0.6.8 底色从墨换成风格自带的纸 #F3F2EE，字色跟着底走；
/// - v0.6.9 按 Apple Clear 玻璃的做法把玻璃「洗干净」：磨砂 6 → 1.5px、
///   白 tint 5% → 2%，存在感交给亮边 + 投影 + 背后的氛围色；
/// - v0.7.0 这套语言从「只给学习卡片页」提成全局：玻璃只用在控件层
///   （按钮、胶囊、Tab 栏、单词框），正文卡片仍是纸面色块。
///
/// **诚实标注：这是近似效果，不是真折射。**
/// 半透明 + 背景模糊 + 方向性高光 + 投影 + 少量磨砂，能让人看出「玻璃压在
/// 彩色背景上」，但没有做折射最核心的两件事：边缘位移（背景在玻璃边缘被
/// 推开、放大）和 6% 色散（边缘出现细微彩边）。这两样要 shader 才能做，
/// 不在这版里，等这屏看过再说。
class LiquidGlass {
  const LiquidGlass._();

  /// 纸底。014 风格自带的页面底色（v0.6.8 起）。
  static const Color paper = Color(0xFFF3F2EE);

  /// 墨。纸上的正文色，纸上对比约 17.5:1。
  static const Color ink = Color(0xFF0B0C10);

  static const Color textPrimary = ink;

  /// 纸上次要字：墨 70%。
  ///
  /// v0.6.9 从 #6B6E78 改过来。氛围透明度提到 18%–25% 以后，原来的灰压在
  /// 蓝色光斑上实测只有 3.11:1（< 4.5），而墨 70% 最差一处 4.84:1。
  /// 用 alpha 而不是定值，是为了让它跟着底一起变：纸上是 #515153（7.4:1），
  /// 越往彩色斑上越自动往深里落。
  static const Color textSecondary = Color(0xB30B0C10);

  /// 纸底上不再往下掉一档：第三级与次要字同值。
  static const Color textTertiary = textSecondary;

  /// 已揭晓、不可再选的那几个选项：可以淡，因为不承载待读信息。
  static const Color textDisabled = Color(0x610B0C10);

  /// 点错态用的那支粉，同时也是背景氛围色之一。
  static const Color wrongPink = Color(0xFFFF2E7E);

  /// 玻璃倒角 / 按钮 bevel。
  static const double bevel = 26;

  /// 玻璃白 tint：v0.6.9 起 2%（0–2%）。
  ///
  /// 「不要整块底色」——2% 只在最亮的那一角留一点水膜的感觉，几乎看不出
  /// 有一层板；玻璃的存在感交给亮边、投影和背后的颜色。
  static const double tint = 0.02;

  /// 玻璃磨砂：v0.6.9 起 1.5px（0–2px）。v0.6.8 是 6px。
  ///
  /// 0.05 以下 GlassSurface 不会开 BackdropFilter —— 没有模糊就别付
  /// saveLayer 的代价，一层一屏十个玻璃也不会掉帧。
  static const double blur = 1.5;

  /// 选中态白 tint：36%（v0.6.8 起不变）。
  static const double tintSelected = 0.36;

  /// 氛围五色的漂移周期：24s 一次来回（20–30s 区间内）。
  ///
  /// 一个控制器带五个色块，各自相位不同，慢到看不出在动、只觉得活着。
  /// 系统开「移除动画」（无障碍）时整层静止。
  static const Duration auraDrift = Duration(seconds: 24);

  /// 玻璃层后面的氛围色（v0.6.9 起 18%–25%，只做背景，不抢字）。
  static const List<Color> aura = <Color>[
    Color(0xFFFF5A1F),
    Color(0xFFFF2E7E),
    Color(0xFF2BD9A0),
    Color(0xFF8B5CFF),
    Color(0xFF2E4BFF),
  ];

  /// 常态投影 0 10px 32px rgb(0 0 0 / .20)。
  ///
  /// v0.6.8 由 .18 略加深：纸底比墨底更容易看出投影，太浅会显得脏。
  static const List<BoxShadow> shadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x33000000),
      offset: Offset(0, 10),
      blurRadius: 32,
    ),
  ];

  /// 选中态投影：再深一档，配合放大与白 tint 让选中项浮起来。
  static const List<BoxShadow> shadowSelected = <BoxShadow>[
    BoxShadow(
      color: Color(0x47000000),
      offset: Offset(0, 12),
      blurRadius: 34,
    ),
  ];

  /// 全场唯一一条动效曲线：弹簧，不用线性。
  ///
  /// mass 0.8 / stiffness 300 / damping 24 → 阻尼比约 0.72，
  /// 停得稳、带一点点过冲回弹。按压、选中、卡片切入都用它。
  static const SpringDescription spring = SpringDescription(
    mass: 0.8,
    stiffness: 300,
    damping: 24,
  );

  /// 按压时缩到的比例（规范 0.95–0.97）。
  static const double pressScale = 0.96;
}

/// 页面底的氛围层：纸底 + 五团彩色光，缓慢漂移。
///
/// 玻璃要有东西可弯才看得出来，所以这层不是装饰，是玻璃的「底片」。
/// v0.6.9 把透明度从 9%–12% 提到 18%–25%：玻璃洗干净之后（2% tint、
/// 1.5px 磨砂），背后没有颜色就等于没有玻璃。
///
/// 漂移：一个 [AnimationController] 带五团光，24s 一个来回、easeInOutSine，
/// 每团的相位和幅度都不同，所以看起来是各漂各的，不是一个整体在晃。
/// 幅度 20–28px，慢到不该抢注意力。
///
/// 系统开「移除动画」时整层静止（低电量下的省事做法）。
class LiquidGlassBackdrop extends StatefulWidget {
  const LiquidGlassBackdrop({this.drift = true, super.key});

  /// 关掉漂移（测试里用，避免无限动画卡住 pumpAndSettle）。
  final bool drift;

  @override
  State<LiquidGlassBackdrop> createState() => _LiquidGlassBackdropState();
}

class _LiquidGlassBackdropState extends State<LiquidGlassBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: LiquidGlass.auraDrift,
  );

  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 「移除动画」开着就别动：静止的画面不影响读字，还能省电。
    final still = !widget.drift || MediaQuery.of(context).disableAnimations;
    if (still) {
      if (_running) {
        _c.stop();
        _running = false;
      }
      _c.value = 0;
    } else if (!_running) {
      _c.repeat(reverse: true);
      _running = true;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: LiquidGlass.paper),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = Curves.easeInOutSine.transform(_c.value);
              return Stack(
                fit: StackFit.expand,
                children: [
                  _Aura(
                    color: LiquidGlass.aura[0],
                    alignment: const Alignment(-1.0, -0.85),
                    size: 380,
                    opacity: 0.24,
                    drift: const Offset(26, 18),
                    phase: 0,
                    t: v,
                  ),
                  _Aura(
                    color: LiquidGlass.aura[1],
                    alignment: const Alignment(0.95, -0.45),
                    size: 320,
                    opacity: 0.22,
                    drift: const Offset(22, -16),
                    phase: 0.22,
                    t: v,
                  ),
                  _Aura(
                    color: LiquidGlass.aura[2],
                    alignment: const Alignment(-0.85, 0.55),
                    size: 300,
                    opacity: 0.20,
                    drift: const Offset(-20, 24),
                    phase: 0.41,
                    t: v,
                  ),
                  _Aura(
                    color: LiquidGlass.aura[3],
                    alignment: const Alignment(0.9, 0.8),
                    size: 360,
                    opacity: 0.25,
                    drift: const Offset(24, -20),
                    phase: 0.63,
                    t: v,
                  ),
                  _Aura(
                    color: LiquidGlass.aura[4],
                    alignment: const Alignment(0.1, 0.35),
                    size: 420,
                    opacity: 0.18,
                    drift: const Offset(-26, 14),
                    phase: 0.82,
                    t: v,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Aura extends StatelessWidget {
  const _Aura({
    required this.color,
    required this.alignment,
    required this.size,
    required this.opacity,
    required this.drift,
    required this.phase,
    required this.t,
  });

  final Color color;
  final Alignment alignment;
  final double size;

  /// 光圈中心的透明度峰值（18%–25%）。
  final double opacity;

  /// 漂移的最大位移（px）。两个方向相位不同，轨迹是一个压扁的椭圆。
  final Offset drift;

  /// 各自的相位，让五团光不同步。
  final double phase;

  /// 0→1 的漂移进度（已过 easeInOutSine）。
  final double t;

  @override
  Widget build(BuildContext context) {
    // sin 的周期是 1，所以 t=0 与 t=1 位置相同：来回一趟不会有跳帧。
    const tau = 2 * math.pi;
    final offset = Offset(
      math.sin((t + phase) * tau) * drift.dx,
      math.sin((t + phase + 0.37) * tau) * drift.dy,
    );

    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: offset,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  color.withValues(alpha: opacity),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一块玻璃。
///
/// 结构：投影 → 圆角裁切 →（磨砂，> 0 才有）→ 2% 白 tint → 左上亮边 → 内容。
/// 玻璃本身不上色；[tintColor] 只在点错态用（那支粉），其余走白。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = LiquidGlass.bevel,
    this.tintColor,
    this.tintAlpha = LiquidGlass.tint,
    this.highlight = 1,
    this.blur = LiquidGlass.blur,
    this.minHeight,
    this.overlay,
    this.shadow = LiquidGlass.shadow,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// null = 白 tint。点错态传 [LiquidGlass.wrongPink]。
  final Color? tintColor;

  /// 默认 2%：几乎不上底色，玻璃靠亮边和投影立住。
  final double tintAlpha;

  /// 高光强度倍率：1 = 常态，选中态用 1.6 让亮边更亮。
  final double highlight;

  /// 磨砂（0–2）。传 0 不会开 BackdropFilter —— 小胶囊上 1px 模糊本来也
  /// 看不出来，省一层 saveLayer。
  final double blur;

  final double? minHeight;

  /// 画在 tint 之上、内容之下的一层（触点高光用）。不吃点击。
  final Widget? overlay;

  /// 选中态传 [LiquidGlass.shadowSelected] 让投影加深。
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) {
    final base = tintColor ?? Colors.white;
    // 高光方向固定左上 -37°：从左上方射进来的光，右下角必须收干净，
    // 否则四条边一样亮，就是旧式毛玻璃的白描边。
    final fill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        base.withValues(alpha: tintAlpha * 1.15),
        base.withValues(alpha: tintAlpha * 0.7),
      ],
    );

    Widget glass = DecoratedBox(
      decoration: BoxDecoration(gradient: fill),
      // CustomPaint 的 painter 画在 child 下面：先铺白 tint，再压亮边，
      // 最后才是可点的内容。宽度由外面传进来的约束决定 —— 全宽按钮
      // 给紧约束就是全宽，Row 里的胶囊给松约束就收缩到文字宽。
      child: CustomPaint(
        painter: _BevelPainter(radius: radius, strength: highlight),
        child: Stack(
          children: [
            if (overlay != null)
              Positioned.fill(
                child: IgnorePointer(child: overlay!),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: Colors.white.withValues(alpha: 0.08),
                highlightColor: Colors.white.withValues(alpha: 0.04),
                child: Container(
                  constraints: minHeight == null
                      ? null
                      : BoxConstraints(minHeight: minHeight!),
                  padding: padding,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // 磨砂为 0 就别开 BackdropFilter：没有模糊需求时它只是一次
    // saveLayer，一屏十块玻璃白付十次代价。
    if (blur > 0.05) {
      glass = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: glass,
      );
    }

    // 投影必须只画在形状**外面**。
    //
    // v0.6.9 发现：BoxDecoration 的 boxShadow 连形状内部一起涂了一层 20%
    // 黑，以前 5% tint 挡住了看不出，降到 2% 之后整块玻璃变成灰板
    // （实测纸 243 → 195）。所以自己画：先把画布裁成「外框减去圆角矩形」，
    // 再画带 maskFilter 的模糊圆角矩形 —— 内部一个像素都不碰。
    return CustomPaint(
      painter: _GlassShadowPainter(radius: radius, shadows: shadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: glass,
      ),
    );
  }
}

/// 形状外部的投影（等价于 BoxShadow，但内部挖空）。
class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter({required this.radius, required this.shadows});

  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // 外框减圆角矩形：evenOdd 让内部成为「洞」。
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(400))
      ..addRRect(rrect);

    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      canvas.drawRRect(
        rrect.shift(s.offset),
        Paint()
          ..color = s.color
          // 与 BoxShadow.toPaint() 同一个换算：blurRadius → sigma。
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            s.blurRadius * 0.57735 + 0.5,
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassShadowPainter old) =>
      old.radius != radius || old.shadows != shadows;
}

/// 迎光侧 1px 亮边。
///
/// 用整圈 stroke + 方向渐变 shader 实现：左上最亮（0.55），过中线衰减，
/// 右下几乎透明。这样只看得到「被光照到的那一条」，不是一圈白线。
class _BevelPainter extends CustomPainter {
  const _BevelPainter({required this.radius, required this.strength});

  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final shader = LinearGradient(
      begin: const Alignment(-0.9, -1),
      end: const Alignment(0.7, 0.9),
      colors: <Color>[
        Colors.white.withValues(alpha: (0.55 * strength).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: (0.14 * strength).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: 0.02),
      ],
      stops: const <double>[0.0, 0.45, 1.0],
    ).createShader(rect);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_BevelPainter old) =>
      old.radius != radius || old.strength != strength;
}
