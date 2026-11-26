import 'dart:async';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

import '../../features/profile/profile_page.dart';
import '../../features/reading/reading_page.dart';
import '../../features/study/study_page.dart';
import '../../features/words/words_page.dart';
import '../theme/liquid_glass.dart';

/// 选中态过渡时长（v0.7.2）：tint、图标、文字统一 170ms，落在 150–200
/// 的范围内。三处共用一个常量，别让它们各走各的。
const Duration _kTabTransition = Duration(milliseconds: 170);

/// 四个 Tab 的容器。
///
/// 用 IndexedStack 保状态：切 Tab 不重建页面，学习进度不会被打断。
/// 底部栏自定义，不用 NavigationBar —— 后者自带的高亮胶囊块和极简风格冲突。
///
/// v0.7.0：底部栏换成悬浮玻璃条。玻璃最该在的位置就是 Tab 栏 —— 它一直
/// 压在页面内容上，背后有东西可弯。所以 `extendBody: true` 让内容从条子
/// 底下穿过去。
///
/// v0.7.1：底部留白不再写死 96，统一走 `ShellPadding.scroll`（96 + 系统
/// 底部安全区）。v0.7.0 的 96 在全面屏上会让最后一行被条子压住。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec('学习', Icons.school_outlined, Icons.school),
    _TabSpec('词库', Icons.menu_book_outlined, Icons.menu_book),
    _TabSpec('阅读', Icons.article_outlined, Icons.article),
    _TabSpec('我的', Icons.person_outline, Icons.person),
  ];

  /// 切 Tab（v0.7.2）。
  ///
  /// - 点当前页：不震、不 setState —— 什么都没发生，不该有反馈。
  /// - 真切页：lightImpact，和答对同款力度。每次点都震，不节流、不吞，
  ///   连点四个不同页就是四次。
  /// - 失败静默：没有触觉马达的设备由系统忽略，Future 上的错误也吞掉，
  ///   绝不能因为震不动就抛到框架里。
  void _select(int i) {
    if (i == _index) return;
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          StudyPage(),
          WordsPage(),
          ReadingPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        tabs: _tabs,
        onTap: _select,
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 悬浮玻璃条：四周留 16 的边，底下留 10。
///
/// 条子本身是一块玻璃（28 圆角、1px 迎光亮边、`.20` 投影），图标和文字
/// 都用墨；选中项在条子里再压一层 36% 白 tint，不另加颜色。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  final int index;
  final List<_TabSpec> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassSurface(
        radius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        shadow: LiquidGlass.shadow,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _BottomBarItem(
                    key: ValueKey('tab-$i'),
                    spec: tabs[i],
                    selected: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    required this.spec,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 图标和文字都用墨系：选中 = 纯墨 + 更深的 tint，未选中 = 墨 70%。
    final color = selected ? LiquidGlass.ink : LiquidGlass.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        containedInkWell: false,
        highlightShape: BoxShape.rectangle,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: _kTabTransition,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: LiquidGlass.tintSelected)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 图标两态是两个字形，用 AnimatedSwitcher 交叉淡入（默认
              // FadeTransition），旧图标淡出的同时新图标淡入。
              AnimatedSwitcher(
                duration: _kTabTransition,
                child: Icon(
                  selected ? spec.activeIcon : spec.icon,
                  key: ValueKey(selected),
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              // 文字以前是瞬切（颜色、字重都直接换）。走
              // AnimatedDefaultTextStyle：颜色跟着补间，字重不可补间但
              // 和颜色一起在同一时长里完成，看起来是渐变不是跳变。
              AnimatedDefaultTextStyle(
                duration: _kTabTransition,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: color,
                ),
                child: Text(spec.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
