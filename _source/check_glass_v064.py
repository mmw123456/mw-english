"""v0.6.4 预览版验收：功能两点 + 液态玻璃一屏。

三条主线：
1. 功能：学习会话进详情直接显示中文；每张卡自动读一次单词
2. 风格：液态玻璃按 014 的规则落实（tint / 迎光亮边 / 投影 / 状态 / 字号）
3. 影响面：lib/ 下只动学习页、新主题文件、详情页；数据层和其他页零改动

跑法：python _source/check_glass_v064.py
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")

# v0.6.3 发布时的提交。用它当基线，影响面才不会被后续提交搅乱。
BASE = "df61eaa"

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


def block(src, start_marker, end_marker):
    i = src.find(start_marker)
    if i < 0:
        return ""
    j = src.find(end_marker, i)
    return src[i:] if j < 0 else src[i:j]


def version_checks():
    pub = read("pubspec.yaml")
    check("版本号 0.6.4+10", "version: 0.6.4+10" in pub)


def theme_checks():
    src = read("lib/app/theme/liquid_glass_preview_theme.dart")
    check("新主题文件存在", os.path.exists(
        os.path.join(APP, "lib/app/theme/liquid_glass_preview_theme.dart")))
    check("页面底色是墨 #0B0C10", "0xFF0B0C10" in src)
    check("bevel 26", re.search(r"bevel\s*=\s*26", src) is not None)
    check("白 tint 4%–6%（取 0.05）", re.search(r"tint\s*=\s*0\.05", src) is not None)
    check("选中 tint 36%", re.search(r"tintSelected\s*=\s*0\.36", src) is not None)
    check("点错用粉 #FF2E7E", "0xFFFF2E7E" in src)
    check("投影 0 10 32", "blurRadius: 32" in src and "Offset(0, 10)" in src)
    check("投影 18%", "0x2E000000" in src)
    check("五支氛围色齐全",
          all(c in src for c in ("0xFFFF5A1F", "0xFFFF2E7E", "0xFF2BD9A0",
                                 "0xFF8B5CFF", "0xFF2E4BFF")))
    check("玻璃有方向性亮边（不是整圈白描边）", "_BevelPainter" in src and "Alignment(-0.9, -1)" in src)
    check("玻璃背后的模糊 ≤6px", "sigmaX: blur" in src and "this.blur = 6" in src)
    check("中文 16 / 700（选项）",
          re.search(r"titleMedium: TextStyle\([^)]*fontSize: 16", src, re.S) is not None
          and re.search(r"titleMedium: TextStyle\([^)]*FontWeight\.w700", src, re.S) is not None)
    check("中文 16 / 700（按钮）",
          re.search(r"labelLarge: TextStyle\([^)]*fontSize: 16", src, re.S) is not None
          and re.search(r"labelLarge: TextStyle\([^)]*FontWeight\.w700", src, re.S) is not None)
    check("字体 NotoSansSC", "AppTheme.fontFamily" in src)
    check("诚实标注：写明是近似、没做真折射",
          "近似效果" in src and "色散" in src and "边缘位移" in src)


def study_page_checks():
    src = read("lib/features/study/study_session_page.dart")
    check("学习页套液态玻璃主题", "data: LiquidGlassPreviewTheme.theme" in src)
    check("学习页不再引用 M3 预览主题", "StudyPreviewTheme" not in src)
    check("页面不再手写旧色板", "AppColors." not in src)
    check("玻璃只做控件：正文卡片用不透明 sheet",
          "color: LiquidGlass.sheet" in src)
    check("选项格间距保持 10（未按 24 改）",
          "SizedBox(width: 10)" in src and "SizedBox(height: 10)" in src)
    # 行为一行不动
    check("2×2 未变", "_optionGrid" in src and "IntrinsicHeight" in src)
    check("点错留卡（CardTap.wrong 分支未动）", "CardTap.wrong" in src)
    check("500ms 自动走未变", "Duration(milliseconds: 500)" in src)
    check("不认识按钮仍在（且走玻璃）", "_tapUnknown" in src and "GlassSurface(" in src)
    # 自动读词
    check("自动读词：按队列下标只读一次", "_spokenIndexes" in src)
    check("自动读词：首卡也读", "_autoSpeak();" in src)
    check("自动读词：静默失败（不弹提示）",
          "unawaited(Speech.speak(card.word))" in src)
    # 详情页两类入口
    check("学习会话进详情：传 revealChinese: true",
          src.count("revealChinese: true") >= 2,
          f"实际 {src.count('revealChinese: true')} 处")


def detail_page_checks():
    src = read("lib/features/words/word_detail_page.dart")
    check("详情页有 revealChinese 参数且默认 false",
          "this.revealChinese = false" in src)
    check("revealChinese 时强制不遮盖",
          "widget.revealChinese ? false : masked" in src)
    check("revealChinese 时隐藏遮盖开关", "if (!widget.revealChinese)" in src)
    check("词库进详情仍读全局开关（maskChinese 未删）",
          "_settings.maskChinese()" in src)


def scope_checks():
    """影响面：只允许三个 lib 文件 + 测试/脚本/版本号/日志。"""
    allowed_lib = {
        "app/lib/app/theme/liquid_glass_preview_theme.dart",
        "app/lib/features/study/study_session_page.dart",
        "app/lib/features/words/word_detail_page.dart",
    }
    allowed_other = {
        "app/pubspec.yaml",
        "项目日志.md",
    }
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

    check("lib/ 只改学习页 + 新主题 + 详情页", not bad, "越界：" + ", ".join(bad))
    check("数据层零改动", not any(p.startswith("app/lib/data/") for p in bad))
    check("app.dart / 全局主题 / 外壳零改动",
          not any(p in ("app/lib/app/app.dart", "app/lib/app/theme/app_theme.dart",
                        "app/lib/app/theme/app_colors.dart") for p in bad))
    check("M3 预览主题文件保留未动",
          not any(p.endswith("study_preview_theme.dart") for p in bad))
    features_changed = sorted(
        p for p in changed if p.startswith("app/lib/features/")
    )
    check("其余页面零改动",
          features_changed == sorted([
              "app/lib/features/study/study_session_page.dart",
              "app/lib/features/words/word_detail_page.dart",
          ]),
          "实际：" + ", ".join(features_changed))


def main():
    print("== 版本 ==")
    version_checks()
    print("== 液态玻璃主题 ==")
    theme_checks()
    print("== 学习页 ==")
    study_page_checks()
    print("== 详情页 ==")
    detail_page_checks()
    print("== 影响面 ==")
    scope_checks()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
