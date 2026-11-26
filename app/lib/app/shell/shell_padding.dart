import 'package:material_ui/material_ui.dart';

/// Tab 外壳给页面内容留的边距（v0.7.1）。
///
/// v0.7.0 把 Tab 栏改成悬浮玻璃条（`extendBody: true`），各页底部写死 96。
/// 但条子总高是 54 + 上下 12 + 离底 10 = 76，再叠系统底部安全区（全面屏
/// 常见 34）—— 96 只剩 20 余量，安全区一深，最后一行就被压住
/// （v0.7.0 截图里首页「怎么排的」和我的页底部文字就是这么被挡的）。
///
/// 统一口径：96 + `MediaQuery.viewPadding.bottom`，四个 Tab 页共用。
/// 详情页 / 学习会话页是整页 push 进来的，没有 Tab 栏，不适用。
class ShellPadding {
  const ShellPadding._();

  /// 不含系统安全区的基准值：条子总高 76 + 20 的呼吸。
  static const double bottomBase = 96;

  /// 页面内容的统一边距。
  static EdgeInsets scroll(BuildContext context, {double top = 8}) {
    return EdgeInsets.fromLTRB(
      20,
      top,
      20,
      bottomBase + MediaQuery.viewPaddingOf(context).bottom,
    );
  }
}
