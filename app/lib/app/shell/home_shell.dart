import 'package:material_ui/material_ui.dart';

import '../../features/profile/profile_page.dart';
import '../../features/reading/reading_page.dart';
import '../../features/study/study_page.dart';
import '../../features/words/words_page.dart';
import '../theme/liquid_glass.dart';

/// 四个 Tab 的容器。
///
/// 用 IndexedStack 保状态：切 Tab 不重建页面，学习进度不会被打断。
/// 底部栏自定义，不用 NavigationBar —— 后者自带的高亮胶囊块和极简风格冲突。
///
/// v0.7.0：底部栏换成悬浮玻璃条。玻璃最该在的位置就是 Tab 栏 —— 它一直
/// 压在页面内容上，背后有东西可弯。所以 `extendBody: true` 让内容从条子
/// 底下穿过去（各页列表底部预留 96 的内边距，别被挡住）。
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
        onTap: (i) => setState(() => _index = i),
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
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: LiquidGlass.tintSelected)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  selected ? spec.activeIcon : spec.icon,
                  key: ValueKey(selected),
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                spec.label,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
