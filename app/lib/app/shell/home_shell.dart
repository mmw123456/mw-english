import 'package:material_ui/material_ui.dart';

import '../../features/profile/profile_page.dart';
import '../../features/reading/reading_page.dart';
import '../../features/study/study_page.dart';
import '../../features/words/words_page.dart';
import '../theme/app_colors.dart';

/// 四个 Tab 的容器。
///
/// 用 IndexedStack 保状态：切 Tab 不重建页面，学习进度不会被打断。
/// 底部栏自定义，不用 NavigationBar —— 后者自带的高亮胶囊块和极简风格冲突。
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
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
    final color = selected ? AppColors.textPrimary : AppColors.textTertiary;

    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        containedInkWell: false,
        highlightShape: BoxShape.rectangle,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
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
    );
  }
}
