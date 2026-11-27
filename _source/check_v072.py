"""v0.7.2 验收：换卡首帧不空白 + Tab 触觉/选中态 + 版本行 shader 状态。

跑法：python _source/check_v072.py

五条主线：
1. 换卡首帧：入场 stagger 只在进会话第一张卡播一次，换卡不重播；
   `_next()` 不读库、不算选项（选项在会话装配时就整条算好）
2. Tab 触觉：lightImpact、点当前页不震、不节流、失败静默
3. 切页不重建：四个 Tab 仍走 IndexedStack，children 是 const
4. 选中态：tint / 图标 / 文字都走 150–200ms 的隐式动画
5. 版本行：读 isShaderFilterSupported + FragmentProgram 加载结果，
   显示「真折射开 / 玻璃回落」

影响面：只允许学习会话页、外壳、我的页、pubspec 版本、测试和门禁脚本。
数据层、主题、android、shader、其余页面零改动。
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "960d547"  # v0.7.1 收尾提交

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


session = read(LIB, "features", "study", "study_session_page.dart")
shell = read(LIB, "app", "shell", "home_shell.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")
dao = read(LIB, "data", "dao", "study_dao.dart")

print("== 1. 换卡首帧 ==")

check("入场开关 _entrance 存在", "bool _entrance = true;" in session)
next_body = re.search(r"void _next\(\) \{(.*?)\n  \}", session, re.S)
check("_next 里关掉入场", next_body is not None and "_entrance = false;" in next_body.group(1))
check("_next 不读库（函数体里没有 await）",
      next_body is not None and "await" not in next_body.group(1))
check("换卡不重算选项（_next 里没有 options / ChoiceOptions）",
      next_body is not None and "options" not in next_body.group(1)
      and "ChoiceOptions" not in next_body.group(1))

check("_SpringIn 有 animate 开关", re.search(r"this\.animate = true", session) is not None)
check("animate=false 直接返回 child（不是 opacity 0 的壳）",
      "if (!widget.animate) return widget.child;" in session)
check("三处入场都接了开关（单词 / 选项 / 不认识）",
      session.count("animate: _entrance") == 3)

check("选项在装配时就整条算好（不是换卡现算）",
      "options: choice?.options ?? const []" in dao
      and "Future<StudySession> buildSession(" in dao)
check("重测补卡也是先算好再进队列",
      "rebuildCard" in dao and "options:" in dao)

print("== 2. Tab 触觉 ==")

check("切页用 lightImpact（和答对同款）", "HapticFeedback.lightImpact()" in shell)
check("点当前页直接返回（不震不切）", "if (i == _index) return;" in shell)
check("触觉失败静默", "catchError((Object _) {})" in shell)
check("没有节流 / 时间戳拦截",
      not re.search(r"(throttle|_lastHaptic|DateTime\.now|Timer\()", shell))
check("只有真的换页才 setState", "setState(() => _index = i);" in shell)

print("== 3. 切页不重建 ==")

check("仍是 IndexedStack", "body: IndexedStack(" in shell)
check("四个页面都在、children 是 const",
      "children: const [" in shell and all(
          f"{page}()" in shell
          for page in ("StudyPage", "WordsPage", "ReadingPage", "ProfilePage")))
check("切页只改 index", shell.count("_index = i") == 1)

print("== 4. 选中态过渡 ==")

m = re.search(r"const Duration _kTabTransition = Duration\(milliseconds: (\d+)\);", shell)
ms = int(m.group(1)) if m else 0
check("过渡时长 150–200ms", 150 <= ms <= 200, f"{ms}ms")
for widget in ("AnimatedContainer", "AnimatedSwitcher", "AnimatedDefaultTextStyle"):
    check(f"{widget} 走同一个时长", f"{widget}(" in shell and "duration: _kTabTransition" in shell)
check("文字不再是裸 Text 瞬切", "AnimatedDefaultTextStyle(" in shell)
check("tint 仍是 36% 白（没顺手改视觉）", "LiquidGlass.tintSelected" in shell)

print("== 5. 版本行 shader 状态 ==")

check("有 versionLabel()", "String versionLabel(bool? shaderOn)" in profile)
check("真折射开文案", "· 真折射开" in profile)
check("玻璃回落文案", "· 玻璃回落" in profile)
check("读 isShaderFilterSupported（经 GlassRefraction.supported）",
      "GlassRefraction.supported" in profile)
check("读 FragmentProgram 加载结果", "GlassRefraction.ensureLoaded()" in profile)
check("只加这一处显示（版本行）", profile.count("versionLabel(_shaderOn)") == 1)
check("探测中不猜状态", "if (shaderOn == null) return base;" in profile)

pub = read(APP, "pubspec.yaml")
check("pubspec 版本 0.7.2+17", "version: 0.7.2+17" in pub)
check("我的页版本号 0.7.2 (2017)", "0.7.2 (2017)" in profile)

print("== 6. 测试覆盖 ==")

t_next = read(APP, "test", "v072_next_card_test.dart")
t_shell = read(APP, "test", "v072_shell_test.dart")
for needle, label in (
    ("换卡首帧：四个选项都在", "下一张首帧四个选项"),
    ("连点 10 次下一个", "连续 10 次下一个"),
    ("整条队列的选项就已经算好", "选项预取（会话装配时算完）"),
):
    check(f"新增测试：{label}", needle in t_next)
for needle, label in (
    ("切 Tab 震一次 lightImpact", "切页触发 lightImpact"),
    ("点当前页不该震", "点当前页不触发"),
    ("state 不重建", "切换后目标页未重建"),
    ("选中态是 150–200ms 的隐式动画", "选中态是隐式动画"),
    ("我的页版本行显示 shader 状态", "版本行显示 shader 状态"),
):
    check(f"新增测试：{label}", needle in t_shell)

print("== 7. 影响面 ==")

allowed = {
    "app/lib/app/shell/home_shell.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/pubspec.yaml",
    "app/test/theme_paper_test.dart",
    "app/test/v072_next_card_test.dart",
    "app/test/v072_shell_test.dart",
    "项目日志.md",
    "_source/check_v072.py",
    "_source/check_glass_v071.py",
    "_source/check_theme_v070.py",
}

changed = set(
    git("diff", "--name-only", BASE, "--", ".").splitlines()
) | set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad = changed - allowed
check("改动面都在白名单里", not bad, str(sorted(bad)[:5]))

for frozen, label in (
    ("app/lib/data", "数据层"),
    ("app/lib/app/theme", "主题"),
    ("app/shaders", "shader"),
    ("app/android", "android 配置"),
    ("app/lib/main.dart", "入口 main"),
    ("app/lib/app/app.dart", "入口 app"),
    ("app/lib/features/study/study_page.dart", "学习首页"),
    ("app/lib/features/words/words_page.dart", "词库页"),
    ("app/lib/features/words/word_detail_page.dart", "详情页"),
    ("app/lib/features/reading/reading_page.dart", "阅读页"),
):
    check(f"{label}零改动",
          git("diff", "--name-only", BASE, "--", frozen).strip() == "")

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(1 if failed else 0)
