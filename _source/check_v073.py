"""v0.7.3 验收：左右划切页（PageView）+ 四页 keep-alive + 玻璃加深。

跑法：python _source/check_v073.py

六条主线：
1. 外壳：IndexedStack 撤掉换 PageView + PageController，落位走 SpringPagePhysics
   （过半才翻页、速度不参与选页、用 LiquidGlass.spring）
2. 边同步：划动时 Tab 选中态跟页码走；点 Tab 用弹簧滑过去、选中态立刻跟上
3. 震动：落定一次 lightImpact（与答对同款），划动中不震，点当前页不震
4. 保活：四个 Tab 页都有 AutomaticKeepAliveClientMixin + wantKeepAlive + super.build
5. 玻璃：白 tint 6%、rim 2px、选中 36% 不变；首页有色洗（五色 8–12%），其余页没有
6. 影响面：数据层 / 学习会话页 / 详情页 / shader / 入口 / android 零改动

注意（踩坑 40）：这是**工作区**门禁，发布时以 BASE..工作区 判定；入库后自然全绿。
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "56f9145"  # v0.7.2 收尾提交

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {detail}")


def read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as f:
        return f.read()


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout


shell = read(LIB, "app", "shell", "home_shell.dart")
physics = read(LIB, "app", "shell", "spring_page_physics.dart")
glass = read(LIB, "app", "theme", "liquid_glass.dart")
study = read(LIB, "features", "study", "study_page.dart")
words = read(LIB, "features", "words", "words_page.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")
reading = read(LIB, "features", "reading", "reading_page.dart")

print("== 1. 外壳：PageView 取代 IndexedStack ==")

check("外壳是 PageView", "child: PageView(" in shell)
check("IndexedStack 已撤掉（只剩注释里的历史说明）", "IndexedStack(" not in shell)
check("有 PageController", "PageController" in shell and "_pages" in shell)
check("用 SpringPagePhysics", "physics: const SpringPagePhysics()" in shell)
check("四页都在 children 里", all(
    f"{page}()" in shell
    for page in ("StudyPage", "WordsPage", "ReadingPage", "ProfilePage")))

check("翻页物理是独立文件", "class SpringPagePhysics extends PageScrollPhysics" in physics)
check("落位用全 App 那条弹簧", "LiquidGlass.spring" in physics)
check("过半才翻页（目标取最近整页）", "roundToDouble() * viewport" in physics)
check("选页不看速度（没有 ±0.5 页的速度折算）",
      "velocity < -" not in physics and "velocity > " not in physics
      and "velocity" not in [ln for ln in physics.splitlines() if "final target" in ln][0])
check("落在整页上不再交回父物理（否则速度会多翻一页）",
      "if ((target - position.pixels).abs() < 0.01) return null;" in physics)

print("== 2. 边框同步（划动跟手 / 点 Tab 滑过去）==")

check("划动时同步选中态", "_setIndex(_pageOf(n.metrics))" in shell)
check("点 Tab 用弹簧滑过去（BallisticScrollActivity）",
      "BallisticScrollActivity(" in shell and "ScrollSpringSimulation(" in shell)
check("点 Tab 选中态立刻跟上", "setState(() {\n      _index = i;" in shell)
check("点当前页直接返回", "if (i == _index) return;" in shell)
check("手指接管时作废点按动画", "n is ScrollStartNotification && n.dragDetails != null" in shell)
check("布局期不 setState（帧后再改）",
      "SchedulerPhase.persistentCallbacks" in shell and "addPostFrameCallback" in shell)
check("只认 depth == 0（里层列表的滚动不接）", "if (n.depth != 0) return false;" in shell)
check("选中态过渡仍是 170ms 一个常量",
      "const Duration _kTabTransition = Duration(milliseconds: 170);" in shell)

print("== 3. 震动 ==")

check("落定震 lightImpact（与答对同款）", "HapticFeedback.lightImpact()" in shell)
check("失败静默", "catchError((Object _) {})" in shell)
check("只有换页才震", "final changed = i != _announced;" in shell and "if (!changed) return;" in shell)
check("按下 Tab 不震（震在落定）",
      "HapticFeedback" not in shell.split("void _select(int i) {")[1].split("}")[0])
check("划动过程中不震（只在 ScrollEnd 里震）",
      shell.count("lightImpact()") == 1
      and "HapticFeedback.lightImpact()" in shell.split("void _onSettled")[1])

print("== 4. 四页 keep-alive ==")

for name, src in (("学习", study), ("词库", words), ("阅读", reading), ("我的", profile)):
    check(f"{name}页 AutomaticKeepAliveClientMixin",
          "with AutomaticKeepAliveClientMixin" in src)
    check(f"{name}页 wantKeepAlive", "bool get wantKeepAlive => true;" in src)
    check(f"{name}页 build 里 super.build", "super.build(context);" in src)

check("阅读页已改成 StatefulWidget", "class ReadingPage extends StatefulWidget" in reading)

print("== 5. 玻璃与色洗 ==")

check("白 tint 6%", "static const double tint = 0.06;" in glass)
check("rim 2px", "static const double rim = 2;" in glass)
check("rim 真的用在描边宽度上", "strokeWidth = LiquidGlass.rim" in glass)
check("选中态 36% 不变", "static const double tintSelected = 0.36;" in glass)
check("点错粉不变", "Color(0xFFFF2E7E)" in glass)

check("色洗组件存在", "class LiquidTopWash extends StatelessWidget" in glass)
check("色洗是五色", "static const List<double> washOpacity" in glass
      and "LiquidGlass.aura[i]" in glass)
check("色洗不吃点击", "ShaderMask(" in glass and "IgnorePointer(" in glass.split("class LiquidTopWash")[1])
check("色洗只铺顶部一条（有高度常量）", "static const double washHeight = 420;" in glass)
check("色洗上下渐隐（dstIn 蒙版）", "BlendMode.dstIn" in glass)

check("首页挂上色洗", "LiquidTopWash()" in study)
check("词库页没有色洗", "LiquidTopWash" not in words)
check("我的页没有色洗", "LiquidTopWash" not in profile)
check("阅读页没有色洗", "LiquidTopWash" not in reading)

print("== 6. 测试覆盖 ==")

t = read(APP, "test", "v073_shell_test.dart")
for needle, label in (
    ("左右划到下一页", "左右划到下一页"),
    ("划不到一半松手弹回原页", "划一半松手弹回"),
    ("划动过程中不震", "划动中不震"),
    ("划动时 Tab 选中态跟着走", "划动时选中态同步"),
    ("State 不重建，滚动位置还在", "划走再回来滚动位置还在"),
    ("搜索框内容：划走再划回来还在", "搜索框内容保住"),
    ("点 Tab：页面滑过去", "点 Tab 页面滑过去"),
    ("IndexedStack 已撤", "IndexedStack 已撤"),
    ("Tab 栏 tint 6%", "Tab 栏 tint 6%"),
    ("首页顶部有色洗", "首页有色洗 / 其余页没有"),
    ("落位用的是全 App 那条弹簧", "弹簧参数一致"),
):
    check(f"新增测试：{label}", needle in t)

t_liquid = read(APP, "test", "liquid_glass_test.dart")
check("旧用例改成 tint 6% / rim 2px", "expect(LiquidGlass.tint, 0.06);" in t_liquid)
t_paper = read(APP, "test", "theme_paper_test.dart")
check("主题用例跟着改", "expect(LiquidGlass.rim, 2);" in t_paper)

print("== 7. 影响面 ==")

allowed = {
    "app/lib/app/shell/home_shell.dart",
    "app/lib/app/shell/spring_page_physics.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/reading/reading_page.dart",
    "app/pubspec.yaml",
    "app/test/liquid_glass_test.dart",
    "app/test/theme_paper_test.dart",
    "app/test/v072_shell_test.dart",
    "app/test/v073_shell_test.dart",
    "项目日志.md",
    "_source/check_v073.py",
    "_source/release_notes_v073.md",
}

changed = set(git("diff", "--name-only", BASE, "--", ".").splitlines())
changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad = changed - allowed
check("改动面都在白名单里", not bad, str(sorted(bad)[:6]))

for frozen, label in (
    ("app/lib/data", "数据层"),
    ("app/shaders", "shader"),
    ("app/android", "android 配置"),
    ("app/lib/main.dart", "入口 main"),
    ("app/lib/app/app.dart", "入口 app"),
    ("app/lib/app/app_defaults.dart", "默认值"),
    ("app/lib/app/theme/app_theme.dart", "全局主题"),
    ("app/lib/app/theme/app_colors.dart", "调色板"),
    ("app/lib/features/study/study_session_page.dart", "学习会话页"),
    ("app/lib/features/words/word_detail_page.dart", "详情页"),
):
    check(f"{label}零改动",
          git("diff", "--name-only", BASE, "--", frozen).strip() == "")

print("== 8. 版本 ==")

pub = read(APP, "pubspec.yaml")
m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 ≥ 0.7.3", version[:3] >= (0, 7, 3), str(version))
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
# Flutter 分架构构建会把 versionCode 再 +2000（本工程一直这么对：+17 → 2017）。
check("我的页版本号跟着 pubspec 走",
      mine is not None and m is not None
      and mine.group(1) == ".".join(m.groups()[:3])
      and mine.group(2) == str(int(m.group(4)) + 2000),
      f"{mine.group(0) if mine else '缺版本号'} vs {m.group(0) if m else '缺'}")

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(1 if failed else 0)
