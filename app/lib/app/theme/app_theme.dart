import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// 全局主题。只有深色一套 —— 这个 App 不做浅色模式。
class AppTheme {
  const AppTheme._();

  /// 英文单词用同一个字族，靠字形区分；不额外引入衬线体，避免包体和字形不一致。
  static const String fontFamily = 'NotoSansSC';

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: AppColors.background,
      secondary: AppColors.known,
      onSecondary: AppColors.background,
      error: AppColors.unknown,
      onError: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceMuted,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.divider,
      outlineVariant: AppColors.divider,
    );

    final base = ThemeData(brightness: Brightness.dark, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textTertiary,
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
          foregroundColor: AppColors.textPrimary,
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceMuted,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceMuted,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    TextStyle style(double size, FontWeight weight, {double? height, Color? color, double? spacing}) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? AppColors.textPrimary,
        letterSpacing: spacing,
      );
    }

    return base.copyWith(
      displayLarge: style(48, FontWeight.w700, height: 1.1, spacing: -0.5),
      displayMedium: style(38, FontWeight.w700, height: 1.15, spacing: -0.4),
      headlineLarge: style(30, FontWeight.w700, height: 1.2, spacing: -0.3),
      headlineMedium: style(24, FontWeight.w700, height: 1.25),
      headlineSmall: style(20, FontWeight.w700, height: 1.3),
      titleLarge: style(18, FontWeight.w700, height: 1.35),
      titleMedium: style(16, FontWeight.w700, height: 1.4),
      titleSmall: style(14, FontWeight.w700, height: 1.4),
      bodyLarge: style(16, FontWeight.w400, height: 1.6),
      bodyMedium: style(14, FontWeight.w400, height: 1.6),
      bodySmall: style(12, FontWeight.w400, height: 1.5, color: AppColors.textSecondary),
      labelLarge: style(14, FontWeight.w700, height: 1.2),
      labelMedium: style(12, FontWeight.w400, height: 1.2, color: AppColors.textSecondary),
      labelSmall: style(11, FontWeight.w400, height: 1.2, color: AppColors.textTertiary),
    );
  }
}
