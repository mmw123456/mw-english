"""v0.7.8 验收：首页主角化。

跑法：python _source/check_v078.py

主线（全部取自需求原文，不从实现里抄）：
1. Hero 环：132 → 176、stroke 12 → 14；环内数字 44 → 56pt，`/N` 保持小字；
   弹簧参数仍是 LiquidGlass.spring（300 / 24 / 0.8）
2. 环下一行今日状态（14pt / 墨 70%）：未开始 / 进行中 / 完成三态，
   分母跟 newTarget 走，断档削减时不许写死 30
3. CTA 主角化：「开始学习」= 全宽 56 高、橙 tint 10%、18pt w700；
   「只复习」= 无玻璃文字按钮（墨 70% / 16pt）；首页只剩一个玻璃控件
4. 层级：二级区块标题（学习足迹 / 怎么排的）统一 16pt w700 墨
5. 不动：不新增颜色、不新增玻璃、氛围洗 / 热力图 / 色带 / 圆角 / 间距 /
   Leitner / 每日 30 / 按天日志 / shader / 玻璃常量 / Tab 栏 / 其余页面
6. 版本：0.7.8 / versionCode 2023
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "be7fb38"  # v0.7.7 收尾提交（日志 docs）

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


ring = read(LIB, "features", "study", "progress_ring.dart")
today = read(LIB, "features", "study", "today_card.dart")
study = read(LIB, "features", "study", "study_page.dart")
heat = read(LIB, "features", "study", "study_heatmap.dart")
glass = read(LIB, "app", "theme", "liquid_glass.dart")

print("== 1. Hero 环：176 / 14，数字 56 ==")

check("直径 176", "static const double diameter = 176;" in ring)
check("线宽 14", "static const double stroke = 14;" in ring)
check("环默认用这两个常量（不是在调用点传死值）",
      "this.size = ProgressRing.diameter" in ring
      and "this.strokeWidth = ProgressRing.stroke" in ring)
check("轨道色没动（墨 10%）", "Color(0x1A0B0C10)" in ring)
check("环内数字字号 = 56 常量",
      "static const double numberSize = 56;" in today)
check("数字沿用 displayLarge，只改字号（不另造字阶）",
      "text.displayLarge?.copyWith(fontSize: TodayCard.numberSize)" in today)
check("`/N` 仍是小字（labelMedium）",
      "'/ $target'," in today and "text.labelMedium" in today)
check("三格统计没动：新词 / 待复习 / 答错",
      "_Metric(label: '新词'" in today
      and "_Metric(label: '待复习'" in today
      and "_Metric(label: '答错'" in today)

print("== 2. 今日状态行（14pt / 墨 70%）==")

check("状态文案抽成 statusLine()（三态可直接断言）",
      re.search(r"String statusLine\(\)", today) is not None)
check("未开始：今天还没开始 · 目标 N 词",
      "'今天还没开始 · 目标 $goal 词'" in today)
check("进行中：今日已学 X / N，还差 M 词",
      "'今日已学 $done / $goal，还差 ${goal - done} 词'" in today)
check("完成：今日目标完成", "'今日目标完成'" in today)
check("完成态先判，超额不会算出负数",
      today.find("done >= goal") < today.find("goal - done"))
check("分母跟 newTarget 走（target getter）",
      "stats.newTarget <= 0 ? AppDefaults.dailyNewWordTarget : stats.newTarget"
      in today and "final goal = target;" in today)
check("字号 14（titleSmall 的 14 + 字重降到 400）",
      "text.titleSmall?.copyWith(" in today
      and "fontWeight: FontWeight.w400" in today)
check("颜色墨 70%", "color: AppColors.textSecondary" in today)
check("状态行居中", "textAlign: TextAlign.center" in today)
check("读库中不先喊「今天还没开始」",
      "loading ? '　' : statusLine()" in today)
check("状态行在环之后、三格之前",
      today.find("statusLine()") < today.find("_Metric(label: '新词'"))

print("== 3. CTA：一个玻璃主按钮 + 一个文字入口 ==")

check("主按钮字号 18", "fontSize: 18," in study)
check("主按钮仍橙 tint 10%",
      "tint: 0.10," in study and "tintColor: AppColors.ringOrange," in study)
check("主按钮高 56（GlassSurface minHeight）", "minHeight: 56," in study)
check("全宽", "width: double.infinity," in study)
check("只复习是 TextButton", "return Center(\n      child: TextButton(" in study)
check("只复习不上玻璃（组件里没有 GlassSurface）",
      "class ReviewLink" in study
      and "GlassSurface" not in study.split("class ReviewLink")[1])
check("只复习 16pt", "text.bodyMedium?.copyWith(" in study)
check("只复习墨 70% / 禁用墨 38%",
      "enabled ? AppColors.textSecondary : LiquidGlass.textDisabled" in study)
check("首页只剩一个 GlassSurface 调用点",
      study.count("child: GlassSurface(") == 1)
check("主按钮只被 PressScale 包一层（没有第二个胶囊）",
      study.count("PressScale(") == 1)
check("主按钮行为与文案没动",
      "label: '开始学习'," in study
      and "() => _start(onlyReview: false)" in study)
check("只复习文案没动",
      "? '没有待复习'" in study and "'只复习待复习 ${_stats.dueReview} 词'" in study)
check("只复习跳转没动", "() => _start(onlyReview: true)" in study)

print("== 4. 层级：区块标题 16pt w700 墨 ==")

label = study.split("class _SectionLabel")[1].split("class ")[0]
check("「怎么排的」走 titleMedium（16 / 700 / 墨）",
      "Theme.of(context).textTheme.titleMedium" in label)
check("旧的 13 小字 + 字距 1.2 已撤",
      "letterSpacing: 1.2" not in label)
check("「学习足迹」同一档",
      "Text('学习足迹', style: text.titleMedium)" in heat)
check("没有为此新增字号 token（主题零改动）",
      git("diff", "--name-only", BASE, "--", "app/lib/app/theme/app_theme.dart").strip() == "")

print("== 5. 冻结面 ==")

frozen = {
    "app/lib/data/study/leitner.dart": "Leitner 逻辑",
    "app/lib/app/app_defaults.dart": "每日 30 / 六箱间隔",
    "app/lib/data/study/choice_options.dart": "干扰项",
    "app/lib/data/study/study_flow.dart": "作答状态机",
    "app/lib/app/theme/liquid_glass.dart": "玻璃常量 + 弹簧",
    "app/shaders/liquid_glass.frag": "shader",
    "app/lib/app/shell/home_shell.dart": "Tab 栏",
    "app/lib/app/theme/app_colors.dart": "调色板（不新增颜色）",
    "app/lib/features/study/box_band.dart": "六箱色带",
    "app/lib/app/theme/box_colors.dart": "箱色表",
    "app/lib/app/widgets/box_badge.dart": "箱位徽章",
    "app/lib/features/study/study_session_page.dart": "学习会话页",
    "app/lib/features/words/words_page.dart": "词库页",
    "app/lib/features/words/word_detail_page.dart": "详情页",
    "app/lib/data/dao/study_dao.dart": "数据层",
    "app/lib/data/dao/word_dao.dart": "词库数据层",
    "app/lib/data/db/app_database.dart": "表结构",
}
for path, label_text in frozen.items():
    check(f"{label_text}零改动",
          git("diff", "--name-only", BASE, "--", path).strip() == "")

# 热力图只允许改标题那一行：格子颜色、今天描边、几何都不许动。
heat_diff = [l for l in git("diff", BASE, "--",
                            "app/lib/features/study/study_heatmap.dart").splitlines()
             if l[:1] in "+-" and not l.startswith(("+++", "---"))]
check("热力图只改了标题一行（格子 / 今天描边 / 几何零改动）",
      len(heat_diff) == 2 and all("学习足迹" in l for l in heat_diff),
      str(heat_diff))
check("空格墨 5% / 今天 1.5px 墨 60% 仍在",
      "heatmapEmpty" in heat and "heatmapTodayBorder" in heat)
check("蓝阶四档没动", "colorFor" in heat and "accentBlue" in heat)

check("弹簧还是 300 / 24 / 0.8（文件零改动 + 常量在）",
      "stiffness: 300" in glass and "damping: 24" in glass and "mass: 0.8" in glass)
check("首页不新增颜色：study_page / today_card 里没有 hex",
      "Color(0x" not in study and "Color(0x" not in today)
check("LiquidTopWash 仍在、没动", "LiquidTopWash()" in study)
check("页面左右边距 20（ShellPadding 未改）",
      git("diff", "--name-only", BASE, "--",
          "app/lib/app/shell/shell_padding.dart").strip() == "")
check("圆角仍是 18（cardRadius 未改）", "cardRadius = 18" in read(
    LIB, "app", "theme", "app_theme.dart"))

print("== 6. 影响面（基线 %s）==" % BASE)

allowed_files = {
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_heatmap.dart",  # 只改标题一行
    "app/lib/features/profile/profile_page.dart",  # 版本行
    "app/pubspec.yaml",
    "app/test/v074_ring_test.dart",  # 132/12 → 176/14（本版超越）
    "app/test/v075_home_color_test.dart",  # 同上 + 只复习不再上玻璃
    "app/test/v076_polish_test.dart",  # 首页玻璃按钮 2 → 1
    "app/test/v078_hero_test.dart",
    "项目日志.md",
    "_source/check_v077.py",  # 标留档
    "_source/check_v078.py",
    "_source/release_notes_v078.md",
}
changed = set(git("diff", "--name-only", BASE, "--", ".").splitlines())
changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad = changed - allowed_files
check("改动面都在白名单里", not bad, str(sorted(bad)[:6]))

diff_pub = git("diff", BASE, "--", "app/pubspec.yaml")
touched = [l for l in diff_pub.splitlines()
           if l[:1] in "+-" and not l.startswith(("+++", "---"))]
check("依赖零新增（pubspec 只动版本行）",
      bool(touched) and all("version: 0.7" in l for l in touched),
      str(touched))

print("== 7. 版本 ==")

pub = read(APP, "pubspec.yaml")
m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.7.8 / +23", version[:3] == (0, 7, 8), str(version))
check("versionCode 2023（+23，构建时 +2000）", version[3] == 23, str(version))
profile = read(LIB, "features", "profile", "profile_page.dart")
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
check("我的页版本行 = 0.7.8 (2023)",
      mine is not None and mine.group(1) == "0.7.8"
      and mine.group(2) == "2023",
      f"{mine.group(0) if mine else '缺'}")

print("== 8. 新增测试覆盖 ==")

t = read(APP, "test", "v078_hero_test.dart")
for needle, label_text in (
    ("expect(ProgressRing.diameter, 176)", "环 176"),
    ("expect(ProgressRing.stroke, 14)", "线宽 14"),
    ("expect(number.style?.fontSize, 56", "数字 56pt"),
    ("'今天还没开始 · 目标 30 词'", "未开始态"),
    ("'今日已学 13 / 30，还差 17 词'", "进行中态"),
    ("'今日目标完成'", "完成态"),
    ("'今日已学 3 / 6，还差 3 词'", "断档配额跟 newTarget"),
    ("expect(size.height, closeTo(56, 0.01)", "主按钮 56 高"),
    ("closeTo(0.10, 1e-9)", "橙 tint 10%"),
    ("expect(text.style?.fontSize, 18)", "主按钮 18pt"),
    ("ReviewLink", "只复习是文字入口"),
    ("findsOneWidget);\n    });\n\n    testWidgets('主按钮在只复习上面", "只有一个玻璃控件"),
    ("expect(style.fontSize, 16", "标题 16pt"),
):
    check(f"新增测试：{label_text}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
