import 'package:material_ui/material_ui.dart';

import 'liquid_glass.dart';

/// 纸底调色板（v0.7.0 起全 App 只用这一套）。
///
/// 底色是设计风格自带的纸 #F3F2EE，正文用墨 #0B0C10，其余全是墨的透明档。
/// 不引第二个色相：背单词时视觉刺激越少越专注，颜色只出现在学习卡片页的
/// 氛围层和点错态那一支粉上。
///
/// v0.7.4 例外：首页有了数据图形（进度环、学习热力图），一支蓝只做图元
/// 填充，不碰文字、不做按钮、不扩散到别的页。
///
/// 对比（WCAG，逐档实测，背景 = 纸 / 纸面卡）：
/// - 墨：17.45 / 18.55
/// - 次要墨 70%：7.08 / 7.29
/// - 三级墨 62%：5.33 / 5.44
/// - 进度蓝：5.26（纸上，做图元够，不做正文小字）
class AppColors {
  const AppColors._();

  /// 页面底色 = 纸。
  static const Color background = LiquidGlass.paper;

  /// 纸面卡：比纸再亮一点点，靠这一点亮度和 0.5px 描边跟底分开。
  /// 正文卡片用它，不用玻璃（玻璃只给控件层）。
  static const Color surface = Color(0xFFFAF9F5);

  /// 次级面：未选中的控件、内嵌块、遮盖占位条。墨 8%。
  static const Color surfaceMuted = Color(0x140B0C10);

  /// 主文字 = 墨。
  static const Color textPrimary = LiquidGlass.ink;

  /// 次文字：墨 70%（纸上 7.08:1）。
  static const Color textSecondary = LiquidGlass.textSecondary;

  /// 三级文字：墨 62%（纸上 5.33:1）。序号、音标、字段名用它。
  /// v0.6.9 在学习页把三级并到了次要字，全量换纸底后重新拉开一档。
  static const Color textTertiary = Color(0x9E0B0C10);

  /// 强调色：纸上不再有冷白，强调靠墨本身（选中 / 激活态就用它）。
  static const Color accent = LiquidGlass.ink;

  /// 分隔线、描边。墨 12%。
  static const Color divider = Color(0x1F0B0C10);

  /// 星标：深琥珀。纸上的 #C8A96E 只有 1.9:1，图标也得看得见，所以压深。
  static const Color starred = Color(0xFF9A6B00);

  /// 进度蓝（v0.7.4）：首页进度环的填充 + 学习热力图的单色阶。
  ///
  /// 纸上 5.26:1。只做图元（环、色块），**不做正文**——这仍是「不引第二个
  /// 色相」那条规则的唯一豁免，扩展到别处要先问。
  static const Color accentBlue = Color(0xFF2E4BFF);
}
