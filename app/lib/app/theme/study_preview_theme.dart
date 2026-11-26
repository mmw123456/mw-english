import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'app_theme.dart';

/// v0.6.3 预览：**只给学习卡片页**用的 Material 3 主题。
///
/// 全局 [AppTheme.dark] 一行没动，其他页面仍走旧配色。这里靠 `Theme(data:)`
/// 局部覆盖，所以换 M3 的影响面就是一屏 —— 小美看完再决定要不要全量换。
///
/// 只定颜色和字体：字号、圆角、按钮高度、按压反馈全部吃 M3 默认，
/// 不手写数值（预览版的意义是看「原生 M3 长什么样」，掺自定义就看不准了）。
class StudyPreviewTheme {
  const StudyPreviewTheme._();

  /// 种子取现有那支冷白强调色（[AppColors.accent]），M3 会按它生成整套
  /// 深色 tonal palette，不另挑艳色。
  static final ThemeData m3 = _build();

  static ThemeData _build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      // 必须用 fidelity：默认的 tonalSpot 会把这支低饱和冷白拉到饱和天蓝
      // （primary #A0CAFD、primaryContainer #194975），就是「另挑艳色」。
      // fidelity 保留种子本身色相，primary 反而是近白的 #E5EAF4，
      // 选中态 primaryContainer 正好落在现有强调色 #C9CED8 上。
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppTheme.fontFamily,
      // 页面底 = 三级深浅里最浅的一档，卡片/选项逐级抬起。
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // M3 在 Android 上的默认水波就是 InkSparkle，写出来是为了不依赖平台兜底。
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
