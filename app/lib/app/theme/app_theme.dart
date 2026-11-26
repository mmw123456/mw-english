import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'liquid_glass.dart';

/// 全局主题：浅色纸底 + 液态玻璃（v0.7.0 起全 App 一套）。
///
/// 合并自两处：老的深色主题和只在学习卡片页用的液态玻璃预览主题。
/// v0.7.0 把预览定稿 —— 深色作废，不留切换入口（本来也没有）。
///
/// 分工不变：玻璃只做控件层（按钮、胶囊、Tab 栏、单词框），正文卡片是
/// [AppColors.surface] 纸面色块。列表行压纸、不上玻璃，颜色会干扰阅读。
class AppTheme {
  const AppTheme._();

  /// 英文单词用同一个字族，靠字形区分；不额外引入衬线体，避免包体和字形不一致。
  static const String fontFamily = 'NotoSansSC';

  /// 内容卡圆角（v0.7.6）：全站纸面卡一个值。
  ///
  /// 审计前这里散着 20 / 18 / 16 / 14 四个值（任务卡与热力图 20、数字卡与
  /// 词库卡 16、详情页与我的页 18、tile 与阅读页说明条 14）。取 18 —— 它
  /// 已经是 [cardTheme] 和详情页 `_paperCard` 在用的值，也就是主题里唯一
  /// 被硬编码过的卡片圆角，不发明新值。列表行 / 胶囊是另一层，不套这个。
  static const double cardRadius = 18;

  /// 等宽数字（v0.7.6）：数字变化时宽度不跳。
  ///
  /// 只用已打包的思源黑体的 `tnum` 特性，**不换字体、不加字体文件**。
  /// 字体不支持时系统会忽略，画面无变化，不做兜底渲染。
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// 给数字文本套等宽。语义上「这个 Text 是数字」的地方都用它，别手抄
  /// `fontFeatures`。
  static TextStyle numeric(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontFeatures: tabular);

  /// 全局唯一主题。[brightness] 必须跟纸底走 light，否则系统控件
  /// （进度条、涟漪、图标默认色）会按深色算，落到纸上全是白字。
  static final ThemeData light = _build();

  static ThemeData _build() {
    const scheme = ColorScheme.light(
      primary: LiquidGlass.ink,
      onPrimary: LiquidGlass.paper,
      secondary: LiquidGlass.ink,
      onSecondary: LiquidGlass.paper,
      // 错误色就是点错态那支粉，全 App 只有一个红。
      error: LiquidGlass.wrongPink,
      onError: LiquidGlass.paper,
      surface: LiquidGlass.paper,
      onSurface: LiquidGlass.ink,
      onSurfaceVariant: LiquidGlass.textSecondary,
      outline: AppColors.divider,
      outlineVariant: AppColors.divider,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(base.textTheme),
      iconTheme: const IconThemeData(color: LiquidGlass.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: LiquidGlass.ink,
        // 浅底 + 深字，状态栏图标也得跟着变深，否则白到看不见。
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: LiquidGlass.ink,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      // 主按钮：墨底纸字。纸上唯一能撑起「主操作」的还是实心墨块。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LiquidGlass.ink,
          foregroundColor: LiquidGlass.paper,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: LiquidGlass.textDisabled,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LiquidGlass.ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.divider),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      // 提示条仍走墨底纸字：它浮在纸上，深色块反而最清楚。
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LiquidGlass.ink,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: LiquidGlass.paper,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: LiquidGlass.ink,
        // 墨 12%：纸上的轨道，够看得见又不抢内容。
        linearTrackColor: Color(0x1F0B0C10),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 0.5,
      ),
    );
  }

  /// 全 App 一套字阶。
  ///
  /// 玻璃上的中文 700、最小 16px 这条规则还在（学习页选项、按钮），
  /// 其余页面按信息层级给：正文墨、说明墨 70%、序号墨 62%。
  static TextTheme _textTheme(TextTheme base) {
    TextStyle style(
      double size,
      FontWeight weight, {
      double? height,
      Color? color,
      double? spacing,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? LiquidGlass.ink,
        letterSpacing: spacing,
      );
    }

    return base.copyWith(
      displayLarge: style(44, FontWeight.w700, height: 1.1, spacing: -0.5),
      displayMedium: style(36, FontWeight.w700, height: 1.15, spacing: -0.4),
      // 学习页单词：36 够大，再大就把音标挤下去了。
      displaySmall: style(36, FontWeight.w700, height: 1.15, spacing: -0.5),
      headlineLarge: style(30, FontWeight.w700, height: 1.2, spacing: -0.3),
      headlineMedium: style(26, FontWeight.w700, height: 1.25),
      headlineSmall: style(24, FontWeight.w700, height: 1.3),
      titleLarge: style(20, FontWeight.w700, height: 1.35),
      // 四个选项的释义：16 / 700，正是风格规则点名的那条。
      titleMedium: style(16, FontWeight.w700, height: 1.45),
      titleSmall: style(14, FontWeight.w700, height: 1.4),
      bodyLarge: style(
        16,
        FontWeight.w500,
        height: 1.4,
        color: LiquidGlass.textSecondary,
      ),
      bodyMedium: style(16, FontWeight.w500, height: 1.45),
      // 列表里的释义、说明文字：13 起步，压在纸上是 7.08:1。
      bodySmall: style(
        13,
        FontWeight.w400,
        height: 1.55,
        color: LiquidGlass.textSecondary,
      ),
      // 玻璃上的按钮字 / 胶囊标签。
      labelLarge: style(16, FontWeight.w700, height: 1.25),
      labelMedium: style(
        13,
        FontWeight.w600,
        height: 1.3,
        color: LiquidGlass.textSecondary,
      ),
      labelSmall: style(
        12,
        FontWeight.w600,
        height: 1.3,
        color: AppColors.textTertiary,
      ),
    );
  }
}
