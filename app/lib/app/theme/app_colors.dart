import 'package:material_ui/material_ui.dart';

/// 深色极简调色板。
///
/// 整个 App 只用这一组颜色：近黑底、灰阶面、单一冷白强调色。
/// 不加渐变、不用高饱和色 —— 背单词时视觉刺激越少越专注。
class AppColors {
  const AppColors._();

  /// 页面底色，近黑但不纯黑（纯黑在 OLED 上滚动会有拖影）
  static const Color background = Color(0xFF0B0B0C);

  /// 卡片、弹层
  static const Color surface = Color(0xFF161618);

  /// 次级面：未选中的控件、内嵌块
  static const Color surfaceMuted = Color(0xFF1E1E21);

  /// 主文字
  static const Color textPrimary = Color(0xFFF2F2F4);

  /// 次文字、说明
  static const Color textSecondary = Color(0xFF8E8E96);

  /// 极弱文字、占位、未选中图标
  static const Color textTertiary = Color(0xFF55555C);

  /// 唯一强调色，克制的冷白偏蓝
  static const Color accent = Color(0xFFC9CED8);

  /// 分隔线、描边
  static const Color divider = Color(0xFF242428);

  /// 认识 / 掌握（低饱和，只做状态提示）
  static const Color known = Color(0xFF7FA88C);

  /// 不认识 / 待学
  static const Color unknown = Color(0xFFB08484);

  /// 星标
  static const Color starred = Color(0xFFC8A96E);
}
