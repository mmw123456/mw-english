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
/// v0.7.5：首页按「暖 = 今天 / 进行中」分工 —— 进度环与主操作按钮走橙，
/// 蓝只留在热力图上。橙不能直接用那支亮橙 #FF5A1F（纸上 2.78:1，图元线
/// 3:1 都不到），压深一档到 #E8490F（纸上 3.48:1）。
///
/// 对比（WCAG，逐档实测，背景 = 纸 / 纸面卡）：
/// - 墨：17.45 / 18.55
/// - 次要墨 70%：7.08 / 7.29
/// - 三级墨 62%：5.33 / 5.44
/// - 进度蓝：5.26 / 5.59（图元够，不做正文小字）
/// - 进度橙：3.48 / 3.70（图元线 ≥3:1 达标，同样不做正文小字）
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

  /// 进度蓝（v0.7.4）：学习热力图的单色阶。
  ///
  /// 纸上 5.26:1。只做图元（色块），**不做正文**——这仍是「不引第二个
  /// 色相」那条规则的唯一豁免，扩展到别处要先问。
  ///
  /// v0.7.5 起从进度环上退下来：环改暖橙。蓝只给热力图，色阶本身不动。
  static const Color accentBlue = Color(0xFF2E4BFF);

  /// 进度橙（v0.7.5）：首页进度环填充 +「开始学习」按钮的 tint。
  ///
  /// 暖色代表「今天 / 进行中」，与热力图的蓝阶分工。纸上 3.48:1 —— 做
  /// 12px 的环线达标（WCAG 非文本 3:1），但**不做正文小字**。
  /// 不用亮橙 #FF5A1F：纸上只有 2.78:1，环线会糊在纸里。
  static const Color ringOrange = Color(0xFFE8490F);

  /// 热力图空格底色（v0.7.5）：墨 5%。
  ///
  /// 原来空格用纸面卡底，边框只有 0.5px 墨 12%，整片颜色和卡片一样，
  /// 远看像没加载出来。压一层 5% 墨，网格先立住；边框仍保留。
  static const Color heatmapEmpty = Color(0x0D0B0C10);

  /// 热力图「今天」那格的描边（v0.7.5）：墨 60%，1.5px。
  ///
  /// 与 0.5px 墨 12% 的普通格线拉开一档，一眼能看出「今天」。用前景描边，
  /// 不吃布局、不缩填充。
  static const Color heatmapTodayBorder = Color(0x990B0C10);
}
