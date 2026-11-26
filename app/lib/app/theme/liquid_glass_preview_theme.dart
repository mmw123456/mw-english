import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// **只给学习卡片页**用的液态玻璃主题。
///
/// 风格来源 guanmo-ai/design-style 的 014 液态玻璃。规则按原文落实：
/// - 玻璃本身没有颜色：只有极淡白 tint（4%–6%）、迎光侧 1px 亮边、投影；
/// - 亮边方向固定左上（-37°），不是整圈描边 —— 整圈白边就是 2020 年的毛玻璃；
/// - 背景亮时字用墨（规则 05）：纸底 #F3F2EE 上正文用 #0B0C10。
///
/// v0.6.8：底色从墨换成风格自带的纸 #F3F2EE，字色跟着底走。玻璃参数没变
/// （白 tint 5% 在纸底上几乎看不见，这是正常的，玻璃感靠亮边与投影）。
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

  /// 纸上次要字：对比约 4.5:1。音标、今日重测、选出正确的中文意思都用它。
  static const Color textSecondary = Color(0xFF6B6E78);

  /// 纸底上不再往下掉一档：再灰就跌破 4.5:1。第三级与次要字同值。
  static const Color textTertiary = textSecondary;

  /// 已揭晓、不可再选的那几个选项：可以淡，因为不承载待读信息。
  static const Color textDisabled = Color(0x610B0C10);

  /// 点错态用的那支粉，同时也是背景氛围色之一。
  static const Color wrongPink = Color(0xFFFF2E7E);

  /// 玻璃倒角 / 按钮 bevel。
  static const double bevel = 26;

  /// 玻璃白 tint：4%–6%，取中间值。
  static const double tint = 0.05;

  /// 选中态白 tint：加深到 36%。
  static const double tintSelected = 0.36;

  /// 玻璃层后面的氛围色（低透明度，只做背景，不抢字）。
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

class LiquidGlassPreviewTheme {
  const LiquidGlassPreviewTheme._();

  static final ThemeData theme = _build();

  static ThemeData _build() {
    return ThemeData(
      useMaterial3: true,
      // 纸底是浅色，主题也跟着切到 light —— 否则系统控件（进度条、
      // 涟漪、图标默认色）会按深色算，落到纸上全是白字。
      brightness: Brightness.light,
      fontFamily: AppTheme.fontFamily,
      // 玻璃没有颜色，所以不给配色系统挑种子：直接给墨字 + 纸底，
      // 避免 fromSeed 又生成一支跟风格无关的彩色。
      colorScheme: const ColorScheme.light(
        primary: LiquidGlass.ink,
        onPrimary: LiquidGlass.paper,
        secondary: LiquidGlass.ink,
        onSecondary: LiquidGlass.paper,
        surface: LiquidGlass.paper,
        onSurface: LiquidGlass.ink,
        onSurfaceVariant: LiquidGlass.textSecondary,
        error: LiquidGlass.wrongPink,
        onError: LiquidGlass.paper,
      ),
      scaffoldBackgroundColor: LiquidGlass.paper,
      textTheme: _textTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: LiquidGlass.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 返回 X、书本图标走这里。
        foregroundColor: LiquidGlass.ink,
        // 顶栏「1 / 31」：墨色，16 / 700。
        titleTextStyle: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: LiquidGlass.ink,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: LiquidGlass.ink,
        // 墨 12%：纸上的进度轨道，够看得见又不抢顶栏。
        linearTrackColor: Color(0x1F0B0C10),
      ),
      // 提示条仍走墨底纸字：它浮在纸面上，深色块反而更清楚。
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: LiquidGlass.ink,
        contentTextStyle: TextStyle(
          color: LiquidGlass.paper,
          fontFamily: AppTheme.fontFamily,
          fontSize: 14,
        ),
      ),
    );
  }

  /// 字阶按风格规则：压在玻璃上的中文一律 700、最小 16px。
  /// 细字压在高光边缘会碎，这条比「好看」优先。
  static TextTheme _textTheme() {
    return const TextTheme(
      // 英文单词不是中文，可以放大，但 36 足够；再大就把音标挤下去了。
      // 纸底上压字的颜色是墨，不是白。
      displaySmall: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 36,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: LiquidGlass.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 24,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: LiquidGlass.textPrimary,
      ),
      // 四个选项的释义：16 / 700，正是规则里点名的那条。
      titleMedium: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w700,
        color: LiquidGlass.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: LiquidGlass.textSecondary,
      ),
      bodyMedium: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: LiquidGlass.textPrimary,
      ),
      // 「不认识」等玻璃上的按钮字。
      labelLarge: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: LiquidGlass.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: LiquidGlass.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: LiquidGlass.textSecondary,
      ),
    );
  }
}

/// 页面底的氛围层：纸底 + 五团低透明度彩色光。
///
/// 玻璃要有东西可弯才看得出来，所以这层不是装饰，是玻璃的「底片」。
/// 纸底上用 9%–12%：颜色看得出在流动，墨字仍在 15:1 以上。
class LiquidGlassBackdrop extends StatelessWidget {
  const LiquidGlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: LiquidGlass.paper)),
          _Aura(
            color: LiquidGlass.aura[0],
            alignment: const Alignment(-1.0, -0.85),
            size: 380,
            opacity: 0.12,
          ),
          _Aura(
            color: LiquidGlass.aura[1],
            alignment: const Alignment(0.95, -0.45),
            size: 320,
            opacity: 0.10,
          ),
          _Aura(
            color: LiquidGlass.aura[2],
            alignment: const Alignment(-0.85, 0.55),
            size: 300,
            opacity: 0.09,
          ),
          _Aura(
            color: LiquidGlass.aura[3],
            alignment: const Alignment(0.9, 0.8),
            size: 360,
            opacity: 0.11,
          ),
          _Aura(
            color: LiquidGlass.aura[4],
            alignment: const Alignment(0.1, 0.35),
            size: 420,
            opacity: 0.10,
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
  });

  final Color color;
  final Alignment alignment;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
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
    );
  }
}

/// 一块玻璃。
///
/// 结构：投影 → 圆角裁切 → 背景模糊 → 白 tint 渐变 → 左上亮边 → 内容。
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
    this.blur = 6,
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
  final double tintAlpha;

  /// 高光强度倍率：1 = 常态，选中态用 1.6 让亮边更亮。
  final double highlight;

  /// 磨砂强度（0–6）。压在字上的浮层才需要，正文卡片不用。
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          // CustomPaint 的 painter 画在 child 下面：先铺白 tint，再压亮边，
          // 最后才是可点的内容。宽度由外面传进来的约束决定 —— 全宽按钮
          // 给紧约束就是全宽，Row 里的胶囊给松约束就收缩到文字宽。
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: fill),
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
          ),
        ),
      ),
    );
  }
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
