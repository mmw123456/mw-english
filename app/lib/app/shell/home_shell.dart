import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

import '../../features/profile/profile_page.dart';
import '../../features/reading/reading_page.dart';
import '../../features/study/study_page.dart';
import '../../features/words/words_page.dart';
import '../theme/liquid_glass.dart';
import 'spring_page_physics.dart';

/// 选中态过渡时长（v0.7.2）：tint、图标、文字统一 170ms，落在 150–200
/// 的范围内。三处共用一个常量，别让它们各走各的。
const Duration _kTabTransition = Duration(milliseconds: 170);

/// 四个 Tab 的容器（v0.7.3：IndexedStack → PageView）。
///
/// 左右划切页、点 Tab 也能切，两边同步：
/// - 手指划动时，Tab 选中态跟着页码走（过半就换高亮，跟手不滞后）；
/// - 点 Tab 时页面用同一条弹簧滑过去，选中态立刻跟上，不等动画。
///
/// 状态不丢：四个页面各带 `AutomaticKeepAliveClientMixin`，划走只是移出
/// 视口、元素树不销毁，所以滚动位置、学习进度、搜索框内容、已读的库全部
/// 还在，切页不重新读库。**这条替代 v0.7.2 的「切页不重建」验收**。
///
/// 震动：页面**落定**（滑到整页）时一次 `lightImpact`，与答对同款。
/// 按下 Tab 那一刻不震 —— 否则点 Tab 会「按下震一次 + 落定再震一次」。
/// 划动过程中一律不震。点了当前页、或者拖了一点点又弹回原页，也不震
/// （没换页就没有可确认的东西）。
///
/// 冲突：只认横向划。词库列表的上下滑仍归它自己的 ListView；学习会话页与
/// 详情页是 push 出来的整页，不在这个 PageView 里，不参与左右划。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _pages = PageController();

  /// Tab 栏选中态；也是 PageView 的当前页。
  int _index = 0;

  /// 已经播过震动的那一页。只有落定到「另一页」才震。
  int _announced = 0;

  /// 点 Tab 的目标页；非 null 表示正在跑点按引发的动画。
  ///
  /// 这段时间里忽略划动同步：否则动画刚开始还停在第 0 页，
  /// 同步逻辑会把选中态又拽回 0，出现「点了没反应再蹦过去」。
  int? _tapTarget;

  static const _tabs = <_TabSpec>[
    _TabSpec('学习', Icons.school_outlined, Icons.school),
    _TabSpec('词库', Icons.menu_book_outlined, Icons.menu_book),
    _TabSpec('阅读', Icons.article_outlined, Icons.article),
    _TabSpec('我的', Icons.person_outline, Icons.person),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  int _pageOf(ScrollMetrics metrics) {
    if (metrics.viewportDimension <= 0) return _index;
    return SpringPagePhysics.pageOf(metrics)
        .round()
        .clamp(0, _tabs.length - 1);
  }

  /// 点 Tab（v0.7.3）：选中态立刻跟上，页面用弹簧滑过去，落定才震。
  ///
  /// 点当前页直接返回 —— 没有位移、没有落定，不该有反馈。
  void _select(int i) {
    if (i == _index) return;

    // PageView 的 position 是 `_PagePosition extends
    // ScrollPositionWithSingleContext`（只有它才是 ScrollActivityDelegate）。
    final position = _pages.position as ScrollPositionWithSingleContext;
    setState(() {
      _index = i;
      _tapTarget = i;
    });

    // 扫三页也一样用弹簧：起点是当前位置，终点是目标页，初速度 0，
    // 所以不会出现「点第 4 个 Tab 时飞出屏幕」。多页过冲按阻尼比 0.72
    // 算约 2%，肉眼看是到位时轻轻一顿。
    //
    // 为什么不用 `animateToPage`：那个只吃 duration + curve，曲线怎么调都不
    // 是这条弹簧（v0.6.6 定下「动效统一走弹簧，不用线性」）。公开 API 里
    // 没有「用指定 Simulation 起一段滚动」的入口，所以直接挂一个
    // BallisticScrollActivity —— 它和 `goBallistic` 走的是同一条路，
    // 手指随时可以中途接管。
    position.beginActivity(
      BallisticScrollActivity(
        position,
        ScrollSpringSimulation(
          LiquidGlass.spring,
          position.pixels,
          i * position.viewportDimension,
          0,
          tolerance: SpringPagePhysics.pageTolerance,
        ),
        position.context.vsync,
        false,
      ),
    );
  }

  /// 只在「不在布局阶段」才直接 setState。
  ///
  /// `ScrollEndNotification` 有可能在首帧布局里派发，那时候 setState 会
  /// 抛「markNeedsBuild called during build」。挪到帧后再改。
  void _setIndex(int i) {
    if (i == _index) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && i != _index) setState(() => _index = i);
      });
      return;
    }
    setState(() => _index = i);
  }

  bool _onScroll(ScrollNotification n) {
    // depth 0 才是 PageView 自己的滚动，里层列表（词库 / 学习页）的通知不接。
    if (n.depth != 0) return false;

    if (n is ScrollStartNotification && n.dragDetails != null) {
      // 手指接管：点按动画作废，选中态重新跟着划动走。
      _tapTarget = null;
    } else if (n is ScrollUpdateNotification) {
      if (_tapTarget == null) _setIndex(_pageOf(n.metrics));
    } else if (n is ScrollEndNotification) {
      _onSettled(n.metrics);
    }
    return false;
  }

  /// 页面落定：同步选中态 + 换页才震一次。
  void _onSettled(ScrollMetrics metrics) {
    _tapTarget = null;
    final i = _pageOf(metrics);
    final changed = i != _announced;
    _announced = i;
    _setIndex(i);
    if (!changed) return;
    // 失败静默：没有马达的设备由系统忽略，Future 上的错误也吞掉。
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: PageView(
          controller: _pages,
          physics: const SpringPagePhysics(),
          // 四页都是 const 实例；页面自己 keep-alive，划走不销毁。
          children: const [
            StudyPage(),
            WordsPage(),
            ReadingPage(),
            ProfilePage(),
          ],
        ),
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
/// 条子本身是一块玻璃（28 圆角、迎光 rim、`.20` 投影），图标和文字都用墨；
/// 选中项在条子里再压一层 36% 白 tint，不另加颜色。
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
