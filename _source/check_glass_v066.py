"""v0.6.6 验收：单词框玻璃 + 答对直走 + 交互灵动。

四条主线：
1. 视觉：单词框从不透明卡片换成玻璃，参数与选项玻璃同一套
2. 流程：第一次答对直接下一张，只有「先错后对」才进详情
3. 动效：弹簧参数、按压/高光/抖动/对勾/入场 stagger/触觉
4. 影响面：lib/ 只动学习页、主题、答对去向纯函数；其余数据层与页面零改动

跑法：python _source/check_glass_v066.py
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")

# v0.6.4 发布后的提交（含日志）。用它当基线看这次的改动落在哪。
BASE = "79e0858"

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


def version_checks():
    assert_version_at_least("0.6.6")


def assert_version_at_least(want):
    """版本只能往前，不能倒挂回旧版（v0.6.7 起这里不再钉死小版本号）。"""
    pub = read("pubspec.yaml")
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)", pub, re.M)
    check(f"版本号 ≥ {want}", bool(m) and tuple(map(int, m.groups())) >= tuple(
        map(int, want.split("."))), m.group(0) if m else "没找到 version")


def theme_checks():
    src = read("lib/app/theme/liquid_glass_preview_theme.dart")
    check("弹簧 mass 0.8", re.search(r"mass:\s*0\.8", src) is not None)
    check("弹簧 stiffness 300", re.search(r"stiffness:\s*300", src) is not None)
    check("弹簧 damping 24", re.search(r"damping:\s*24", src) is not None)
    check("按压 0.96", re.search(r"pressScale\s*=\s*0\.96", src) is not None)
    check("单词 36pt", re.search(r"displaySmall: TextStyle\([^)]*fontSize: 36", src, re.S) is not None)
    check("玻璃仍只有 tint ≤2% / 26 / 投影",
          re.search(r"tint\s*=\s*0\.0[0-2]", src) is not None and
          "bevel = 26" in src and "blurRadius: 32" in src)
    check("玻璃有 overlay 层（触点高光用）", "this.overlay" in src)


def page_checks():
    src = read("lib/features/study/study_session_page.dart")
    check("单词框抽成 StudyWordCard", "class StudyWordCard" in src)
    check("单词框用玻璃", re.search(r"class StudyWordCard[\s\S]*?GlassSurface\(", src) is not None)
    check("单词框不再用不透明 sheet", "LiquidGlass.sheet" not in src)
    check("音标仍是 bodyLarge 小字", "text.bodyLarge" in src)

    # 动效
    check("入场 stagger 20–50ms 一档", "delayMs: 50 + i * 35" in src)
    check("弹簧入场（SpringSimulation）", "SpringSimulation(LiquidGlass.spring" in src)
    check("选项按压 90ms 内缩", "milliseconds: 90" in src)
    check("高光 200ms 淡出", "milliseconds: 200" in src)
    check("答错抖动 360ms", "milliseconds: 360" in src)
    check("对勾 300ms", "milliseconds: 300" in src)
    check("抖动是 3–4 次往复", "math.sin(shake * math.pi * 7)" in src)
    check("触点高光按位置画", "_TouchGlow" in src and "localPosition" in src)
    check("触觉：轻 + 中", "HapticFeedback.lightImpact" in src and "HapticFeedback.mediumImpact" in src)
    check("触觉失败不打断（unawaited）", "unawaited(HapticFeedback" in src)

    # 行为不变
    check("2×2 未变", "IntrinsicHeight" in src)
    check("500ms 自动走未变", "Duration(milliseconds: 500)" in src)
    check("点错留卡未变", "CardTap.wrong" in src)
    check("「不认识」仍进详情", "_tapUnknown" in src and "revealChinese: true" in src)
    check("去向只看有没有答错", "exitAfterCorrect(hadWrong: _progress.recordedWrong)" in src)


def flow_checks():
    src = read("lib/data/study/study_flow.dart")
    check("答对去向参数只剩 hadWrong", "exitAfterCorrect({required bool hadWrong})" in src)
    check("新词不再强制进详情", "isNew" not in src.split("/// 答对之后该去哪")[1])
    check("只有答错过才进详情", "hadWrong ? CardExit.detail : CardExit.nextCard" in src)


def scope_checks():
    """影响面：lib/ 只允许三处。"""
    allowed_lib = {
        "app/lib/app/theme/liquid_glass_preview_theme.dart",
        "app/lib/features/study/study_session_page.dart",
        # 例外：答对去向这条规则本身就写在这个纯函数里，改的是流程不是数据访问。
        "app/lib/data/study/study_flow.dart",
        # 例外：v0.6.7 补中文查词按设计改了这个 DAO（只改查询，不碰表）。
        "app/lib/data/dao/word_dao.dart",
    }
    allowed_other = {"app/pubspec.yaml", "项目日志.md"}

    diff = subprocess.run(
        ["git", "-c", "core.quotepath=false", "diff", "--name-only", BASE],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    untracked = subprocess.run(
        ["git", "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    changed = sorted(set(diff) | set(untracked))

    bad = []
    for path in changed:
        if path in allowed_lib or path in allowed_other:
            continue
        if path.startswith("app/test/") or path.startswith("_source/"):
            continue
        bad.append(path)

    check("lib/ 只改学习页 + 主题 + 答对去向", not bad, "越界：" + ", ".join(bad))
    check("数据层其余文件零改动",
          not any(p.startswith("app/lib/data/") and p not in allowed_lib for p in changed),
          "改动：" + ", ".join(p for p in changed if p.startswith("app/lib/data/")))
    check("app.dart / 外壳 / 全局主题零改动",
          not any(p in ("app/lib/app/app.dart", "app/lib/app/theme/app_theme.dart",
                        "app/lib/app/theme/app_colors.dart") for p in changed))
    check("词库页 / 详情页零改动",
          not any(p.endswith("words_page.dart") or p.endswith("word_detail_page.dart")
                  for p in changed))
    check("M3 预览主题保留未动",
          not any(p.endswith("study_preview_theme.dart") for p in changed))


def main():
    print("== 版本 ==")
    version_checks()
    print("== 主题 ==")
    theme_checks()
    print("== 学习页 ==")
    page_checks()
    print("== 答对去向 ==")
    flow_checks()
    print("== 影响面 ==")
    scope_checks()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
