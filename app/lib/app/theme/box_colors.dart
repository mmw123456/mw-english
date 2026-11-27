import 'package:material_ui/material_ui.dart';

import '../../app/app_defaults.dart';
import 'liquid_glass.dart';

/// 七箱色彩系统（v0.7.7）。
///
/// 箱位 → 颜色是一张定死的表，纯函数 [boxColor] 直接给测试断言：
///
/// | 箱位 | 间隔 | 颜色 |
/// |---|---|---|
/// | 0 | 新词 / 未进调度 | 墨 35% 灰 |
/// | 1 | 1 天 | 粉 `#FF2E7E` |
/// | 2 | 2 天 | 紫 `#8B5CFF` |
/// | 3 | 4 天 | 蓝 `#2E4BFF` |
/// | 4 | 7 天 | 橙 `#E8490F`（与首页进度环同一支） |
/// | 5 | 15 天 | 深橙 `#C43A06` |
/// | 6 | 30 天 / 已掌握 | 薄荷 `#2BD9A0` |
///
/// 语义是「从生到熟」：冷色是还在练的，暖色是快掌握了，已掌握用绿（打勾、
/// 完成的通用语义）。只用现有五色 + 环橙 + 墨，**不新增色相**。
///
/// 薄荷在纸上只有约 1.6:1，色点靠色相区分、不靠明暗，所以色点一律 8px
/// 实心圆。真机上若薄荷点发淡，只许给它加深描边，不许换色相。
class BoxColors {
  const BoxColors._();

  /// 箱 0 的点色：墨 35%。
  static const Color newWord = Color(0x590B0C10);

  /// 箱 1–5 的点色，键即箱位。
  ///
  /// 箱 5 用深橙而不是另一支色相：它和箱 4 同色系、只压深一档，读起来是
  /// 「暖色还在往上走」；再给一个薄荷会造成「箱 5 已经掌握」的错觉。
  static const Map<int, Color> ladder = <int, Color>{
    1: Color(0xFFFF2E7E), // 粉
    2: Color(0xFF8B5CFF), // 紫
    3: Color(0xFF2E4BFF), // 蓝
    4: Color(0xFFE8490F), // 橙（= AppColors.ringOrange）
    5: Color(0xFFC43A06), // 深橙
  };

  /// 箱 6（已掌握）的点色：薄荷。
  static const Color mastered = Color(0xFF2BD9A0);

  /// 最高箱位。与 `AppDefaults.boxIntervals` 的最后一项对齐（30 天）。
  static int get topBox => AppDefaults.boxIntervals.length - 1;

  /// 不带透明度的底色。徽章的 15% 淡底由它算，所以箱 0 的淡底是墨 15%，
  /// 不是「墨 35% 再乘 15%」。
  static Color solid(int box) {
    if (box <= 0) return LiquidGlass.ink;
    if (box >= topBox) return mastered;
    return ladder[box] ?? mastered;
  }
}

/// 箱位 → 色点颜色（纯函数，测试直接断言）。
///
/// 箱 0 与所有负数（未进调度）都是墨 35%；箱 6 及以上统一算已掌握。
Color boxColor(int box) {
  if (box <= 0) return BoxColors.newWord;
  if (box >= BoxColors.topBox) return BoxColors.mastered;
  return BoxColors.ladder[box] ?? BoxColors.mastered;
}

/// 箱位 → 15% 淡底（徽章底、会话页标签底）。
Color boxTint(int box) => BoxColors.solid(box).withValues(alpha: 0.15);

/// 箱位 → 徽章文字。箱 0 写「新词」，其余写「箱 N」。
String boxLabel(int box) => box <= 0 ? '新词' : '箱 $box';
