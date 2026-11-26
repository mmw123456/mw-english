"""v0.6.3 预览版验收：只改学习卡片页，换成 Material 3。

【历史留档】v0.6.4 起学习页改走液态玻璃，页面级断言已不成立，
再跑会失败 —— 这是预期行为，不是回归。当前版验收看
check_glass_v068.py（纸底玻璃）与 check_search_v067.py（中文查词）。

三条主线：
1. 主题：M3 + 深色 + 种子用现有冷白强调色（且不许被拉成艳色）
2. 影响面：只有学习卡片页走 M3，其他页一个字没动
3. 行为：四选一 2×2、500ms 自动走、点错留卡、不认识、Leitner 全照 v0.6.2

跑法：python _source/check_m3_v063.py
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")

PASS = 0
FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}" + (f"  -> {detail}" if detail else ""))


def read(rel):
    with open(os.path.join(APP, rel), encoding="utf-8") as f:
        return f.read()


def theme_checks():
    src = read("lib/app/theme/study_preview_theme.dart")
    check("主题是 Material 3", "useMaterial3: true" in src)
    check("配色由 ColorScheme.fromSeed 生成", "ColorScheme.fromSeed(" in src)
    check("种子是现有冷白强调色", "seedColor: AppColors.accent" in src)
    check("深色", "brightness: Brightness.dark" in src)
    check(
        "用 fidelity 变体（默认 tonalSpot 会把冷白拉成天蓝）",
        "DynamicSchemeVariant.fidelity" in src,
    )
    # 圆角/高度不许在主题里手写
    check("主题里没有自写圆角", "borderRadius" not in src and "RoundedRectangleBorder" not in src)


def page_checks():
    src = read("lib/features/study/study_session_page.dart")
    theme = read("lib/app/theme/study_preview_theme.dart")
    for token in ("surfaceContainer", "surfaceContainerHigh", "primaryContainer"):
        check(f"卡片用到 {token}", token in src)
    # 最浅一档是页面底色，定在主题的 scaffoldBackgroundColor 上。
    check(
        "页面底色用 surfaceContainerLow",
        "surfaceContainerLow" in theme or "surfaceContainerLow" in src,
    )
    check("页面不再手写色值（无 AppColors）", "AppColors" not in src)
    check("页面不自写圆角", "BorderRadius.circular(" not in src)
    check("按钮不再手写高度/描边", "OutlinedButton.styleFrom" not in src)
    check("整页套了 Theme(data: StudyPreviewTheme.m3)", "data: StudyPreviewTheme.m3" in src)


def scope_checks():
    """其他页一个字不动：用 git 看这次的改动落在哪些文件。"""
    out = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    changed = []
    for line in out.splitlines():
        path = line[3:].strip().strip('"')
        if " -> " in path:
            path = path.split(" -> ")[-1]
        changed.append(path.replace("\\", "/"))

    lib_changed = [p for p in changed if p.startswith("app/lib/")]
    allowed = {
        "app/lib/features/study/study_session_page.dart",
        "app/lib/app/theme/study_preview_theme.dart",
    }
    extra = [p for p in lib_changed if p not in allowed]
    check("lib 下只动了学习页 + 新主题文件", not extra, f"另外还动了 {extra}")

    # 数据层一行没动（Leitner / DAO / 状态机）
    check(
        "数据层与状态机没动",
        not any(p.startswith("app/lib/data/") for p in changed),
        "改了：" + str([p for p in changed if p.startswith("app/lib/data/")]),
    )

    # 全局主题与外壳没动
    check("app.dart 全局主题没动", "app/lib/app/app.dart" not in changed)
    check("外壳 Tab 没动", not any(p.startswith("app/lib/app/shell/") for p in changed))

    # 只有学习页 import 预览主题（--untracked 让还没 commit 的新文件也参与搜索）
    hits = subprocess.run(
        ["git", "grep", "-l", "--untracked", "StudyPreviewTheme", "--", "app/lib"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    hits = [h.replace("\\", "/") for h in hits]
    check(
        "只有学习页引用预览主题",
        sorted(hits) == sorted(
            [
                "app/lib/app/theme/study_preview_theme.dart",
                "app/lib/features/study/study_session_page.dart",
            ]
        ),
        str(hits),
    )


def behavior_checks():
    src = read("lib/features/study/study_session_page.dart")
    flow = read("lib/data/study/study_flow.dart")
    check("2×2 网格还在", "_optionGrid(" in src and "IntrinsicHeight(" in src)
    check("选项顺序仍 A/B/C/D", "String.fromCharCode(65 + i)" in src)
    check("点对 500ms 后走", "Timer(const Duration(milliseconds: 500)" in src)
    check("点错留卡继续选", "if (tap == CardTap.wrong) {" in src and "case OptionState.wrong:" in src)
    check("不认识按钮还在", "不认识" in src and "_tapUnknown" in src)
    check(
        "不认识仍按首次答错落库",
        "_dao.answer(card: card, correct: false)" in src,
    )
    check("MarkUnknown 状态机没动", "bool markUnknown()" in flow)
    check("答对去向规则没动", "exitAfterCorrect" in src)


def version_checks():
    with open(os.path.join(APP, "pubspec.yaml"), encoding="utf-8") as f:
        pub = f.read()
    m = re.search(r"^version:\s*([\d.]+)\+(\d+)", pub, re.M)
    check("版本号 0.6.3+9", bool(m) and m.group(1) == "0.6.3" and m.group(2) == "9", str(m.groups()))


def main():
    print("主题")
    theme_checks()
    print("页面")
    page_checks()
    print("影响面（其他页一个字不动）")
    scope_checks()
    print("行为（全照 v0.6.2）")
    behavior_checks()
    print("版本")
    version_checks()

    print(f"\n{PASS} PASS / {FAIL} FAIL")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
