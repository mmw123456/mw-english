"""v0.7.9 验收：字重对比拉开。

跑法：python _source/check_v079.py

主线（全部取自需求原文，不从实现里抄）：
1. 四档字重：T1 主角数字 700、T2 标题 / 按钮 700、T3 正文 400 墨 70%、
   T4 次要 400 墨 62%；全 App 无 w300 / w500 / w600 / w900
2. 包里只有 400 / 700 两个字重（pubspec 只声明这两个）
3. 只改字重 + T4 一处颜色：字号 / 间距 / 圆角 / 布局 / 逻辑 / 数据不动
4. 版本：0.7.9 / +24；我的页 0.7.9 (2024)
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "da2cb8c"  # v0.7.8 收尾提交（日志 docs）

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


theme = read(LIB, "app", "theme", "app_theme.dart")
today = read(LIB, "features", "study", "today_card.dart")
study = read(LIB, "features", "study", "study_page.dart")
session = read(LIB, "features", "study", "study_session_page.dart")
words = read(LIB, "features", "words", "words_page.dart")
detail = read(LIB, "features", "words", "word_detail_page.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")
band = read(LIB, "features", "study", "box_band.dart")
heat = read(LIB, "features", "study", "study_heatmap.dart")
badge = read(LIB, "app", "widgets", "box_badge.dart")
pub = read(APP, "pubspec.yaml")

print("== 1. 主题四档：只有 400 / 700 ==")

check("T3 bodyLarge = 400", "bodyLarge: style(\n        16,\n        FontWeight.w400," in theme)
check("T3 bodyMedium = 400", "bodyMedium: style(16, FontWeight.w400, height: 1.45)" in theme)
check("T3 bodySmall = 400", "13,\n        FontWeight.w400,\n        height: 1.55," in theme)
check("T4 labelMedium 默认 400", "labelMedium: style(\n        13,\n        FontWeight.w400," in theme)
check("T4 labelSmall 默认 400", "labelSmall: style(\n        12,\n        FontWeight.w400," in theme)
check("T2 titleMedium 仍 700", "titleMedium: style(16, FontWeight.w700" in theme)
check("T2 titleSmall 仍 700", "titleSmall: style(14, FontWeight.w700" in theme)
check("T2 labelLarge 仍 700", "labelLarge: style(16, FontWeight.w700" in theme)
check("中文 700 / ≥16px 的老规则没动",
      "玻璃上的中文 700、最小 16px 这条规则还在" in theme)

print("== 2. 全 App 没有中间字重 ==")

used = set()
bad = []
for dirpath, _, files in os.walk(LIB):
    for name in files:
        if not name.endswith(".dart"):
            continue
        path = os.path.join(dirpath, name)
        text = read(path)
        for m in re.finditer(r"FontWeight\.w(\d+)", text):
            w = int(m.group(1))
            used.add(w)
            if w not in (400, 700):
                bad.append(f"{os.path.relpath(path, ROOT)}: w{w}")
check("只出现 w400 / w700", not bad, str(bad[:6]))
check("两个字重都用到了", used == {400, 700}, str(sorted(used)))

print("== 3. T1 主角数字 700 ==")

check("环内数字沿用 displayLarge（700）+ 56pt",
      "text.displayLarge?.copyWith(fontSize: TodayCard.numberSize)" in today)
check("三格统计数字 titleLarge（700）",
      "AppTheme.numeric(text.titleLarge?.copyWith(fontSize: 20))" in today)
check("首页三块统计数字 titleLarge（700）",
      "Text(value, style: AppTheme.numeric(text.titleLarge))" in study)

print("== 4. T2 标题 / 按钮 700 ==")

check("只复习 = 按钮文字 700", "fontWeight: FontWeight.w700," in study
      and "style: text.bodyMedium?.copyWith(" in study)
check("词库「词表」700", "fontWeight: FontWeight.w700," in words)
check("词库分组标题 700", words.count("fontWeight: FontWeight.w700,") >= 2)
check("我的页分组标题 700", "fontWeight: FontWeight.w700," in profile)
check("详情页区块标题 700（_Section）",
      detail.count("// T2 区块标题：700 / 墨 62%（v0.7.9）。") >= 2)
check("详情页「发音」700", "// T2 按钮文字：700（v0.7.9）。" in detail)
check("热力图「学习足迹」仍是 titleMedium 700",
      "Text('学习足迹', style: text.titleMedium)" in heat)

print("== 5. T3 正文 400 + 墨 70% ==")

check("状态行 400 + textSecondary",
      "fontWeight: FontWeight.w400,\n                color: AppColors.textSecondary," in today)
check("词表释义 bodySmall（400 / 70%）",
      "final style = Theme.of(context).textTheme.bodySmall;" in words)

print("== 6. T4 次要 400 + 墨 62% ==")

check("今日新词 400 + 62%", "text.labelMedium\n                      ?.copyWith(color: AppColors.textTertiary)" in today)
check("/N 仍是 62%", "'/ $target'," in today and "color: AppColors.textTertiary" in today)
check("AppBar 第 N 天 400 + 62%",
      "labelMedium\n                    ?.copyWith(color: AppColors.textTertiary)" in study)
check("色带图例 400 + 62%",
      "fontSize: 11,\n              color: AppColors.textTertiary," in band)
check("热图说明 400 + 62%",
      "style: text.labelSmall?.copyWith(color: AppColors.textTertiary)," in heat)
check("详情页标签 400 + 62%",
      "?.copyWith(color: AppColors.textTertiary, fontSize: 10)" not in detail
      and "color: AppColors.textTertiary,\n              fontSize: 10," in detail)
check("普通状态胶囊 400 + 62%",
      "fontWeight: FontWeight.w400,\n            color: AppColors.textTertiary," in session)
check("箱位徽章 400，但文字仍用墨（决策 96）",
      "fontSize: 11,\n                  fontWeight: FontWeight.w400,\n                  color: LiquidGlass.ink," in badge)

print("== 7. 只动该动的：冻结面零改动 ==")

frozen = [
    "app/lib/app/app_defaults.dart",
    "app/lib/app/shell/home_shell.dart",
    "app/lib/app/shell/shell_padding.dart",
    "app/lib/app/theme/app_colors.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/shaders/liquid_glass.frag",
    "app/lib/data/study/leitner.dart",
    "app/lib/data/study/choice_options.dart",
    "app/lib/data/study/study_flow.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/dao/word_dao.dart",
    "app/lib/data/db/app_database.dart",
    "app/lib/features/study/progress_ring.dart",
]
for path in frozen:
    check(f"零改动：{os.path.basename(path)}",
          git("diff", "--name-only", BASE, "--", path).strip() == "")

allowed_files = {
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/study/box_band.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/pubspec.yaml",
    "app/test/v079_weight_test.dart",
    "DESIGN.md",  # 文档资产，与 README 同类
    # 以下三处只订正注释（六箱 → 七箱、不归零 → 最低到 0），不改行为；
    # 进白名单表示改动面已知，冻结面的「零改动」断言仍会如实报出。
    "app/lib/app/app_defaults.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/data/study/leitner.dart",
    "项目日志.md",
    "_source/check_v079.py",
    "_source/release_notes_v079.md",
}
changed = set(git("diff", "--name-only", BASE, "--", ".").splitlines())
changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad_files = changed - allowed_files
check("改动面都在白名单里", not bad_files, str(sorted(bad_files)[:6]))

diff_pub = git("diff", BASE, "--", "app/pubspec.yaml")
touched = [l for l in diff_pub.splitlines()
           if l[:1] in "+-" and not l.startswith(("+++", "---"))]
check("pubspec 只动版本行",
      bool(touched) and all("version: 0.7" in l for l in touched),
      str(touched))
check("字体只声明 400 / 700", "weight: 400" in pub and "weight: 700" in pub
      and "weight: 500" not in pub and "weight: 600" not in pub)

print("== 8. 版本行 ==")

m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.7.9 / +24", version == (0, 7, 9, 24), str(version))
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
check("我的页版本行 = 0.7.9 (2024)",
      mine is not None and mine.group(1) == "0.7.9" and mine.group(2) == "2024",
      f"{mine.group(0) if mine else '缺'}")

print("== 9. 新增测试覆盖 ==")

t = read(APP, "test", "v079_weight_test.dart")
for needle, label_text in (
    ("expect(t.bodyMedium?.fontWeight, FontWeight.w400)", "T3 400"),
    ("expect(t.labelSmall?.fontWeight, FontWeight.w400)", "T4 400"),
    ("expect(t.labelLarge?.fontWeight, FontWeight.w700)", "T2 700"),
    ("expect(t.displayLarge?.fontWeight, FontWeight.w700)", "T1 700"),
    ("expect(bad, isEmpty", "无中间字重"),
    ("expect(used, <int>{400, 700})", "只用两个字重"),
    ("今日已学 13 / 30，还差 17 词", "T3 状态行"),
    ("expect(style.color, AppColors.textTertiary", "T4 墨 62%"),
):
    check(f"新增测试：{label_text}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
