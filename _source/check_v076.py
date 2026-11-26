"""v0.7.6 验收：细节打磨（字体、间距、动效）+ 热力图今天格修复。

跑法：python _source/check_v076.py

主线（全部取自需求原文，不从实现里抄）：
1. 今天格不许实心黑：底色 = 空格底色（墨 5%），今天只有一圈 1.5px 墨 60%
   描边；根因是 v0.7.5 用实心墨 boxShadow 压在**半透明**底色上
2. 等宽数字：AppTheme.tabular（tnum），不换字体、不加字体文件、不加依赖；
   环内数字 / 目标 / 三格 / 首页三卡 / 词库两卡 / 词表序号都套上
3. 环内数字：RollingInt 从旧值滚到新值，用的还是那条弹簧 300-24-0.8；
   首次出现不从 0 播
4. 按压缩放：PressScale 90ms → 0.96，松开走同一根弹簧；只包首页两个按钮
5. 圆角与间距：内容卡统一 cardRadius = 18（已有值）；两玻璃按钮同为 999；
   页面左右边距 20；纵向间距归到 12 / 20 / 32 三档
6. 影响面：首页、词库页、详情页、我的页、阅读页、主题；颜色 token、
   Leitner、按天日志、shader、Tab 栏、学习会话页全部零改动
7. 版本：0.7.6 / versionCode 2021
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "04e81d3"  # v0.7.5 收尾提交

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


# v0.7.7 起只作留档：6 条断言被新版有意超越 —— 学习会话页（箱标签换徽章）、
# 数据层（新增两个只读查询 + 详情模型的 box 字段）、改动面白名单（箱色三件）、
# 版本号（0.7.7 / +22）。61 PASS / 6 FAIL 是预期状态，不再当门禁用。
raise SystemExit(0)

theme = read(LIB, "app", "theme", "app_theme.dart")
colors = read(LIB, "app", "theme", "app_colors.dart")
heat = read(LIB, "features", "study", "study_heatmap.dart")
ring = read(LIB, "features", "study", "progress_ring.dart")
today = read(LIB, "features", "study", "today_card.dart")
study = read(LIB, "features", "study", "study_page.dart")
words = read(LIB, "features", "words", "words_page.dart")
detail = read(LIB, "features", "words", "word_detail_page.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")
reading = read(LIB, "features", "reading", "reading_page.dart")
rolling = read(LIB, "app", "widgets", "rolling_int.dart")
press = read(LIB, "app", "widgets", "press_scale.dart")

print("== 1. 热力图今天格：不许实心黑 ==")

check("格子填充仍走 colorFor（0 = 墨 5%）",
      "color: StudyHeatmap.colorFor(total)," in heat
      and "if (total <= 0) return AppColors.heatmapEmpty;" in heat)
check("不再用 boxShadow 画描边（实心墨会从半透明底透上来）",
      "boxShadow:" not in heat)
check("今天 / 选中都改成前景描边环",
      "foregroundDecoration: ringColor == null" in heat
      and "final Color? ringColor = isToday" in heat)
check("今天描边 1.5px、颜色走墨 60% token",
      "width: ringWidth)" in heat
      and "final double ringWidth = isToday ? 1.5 : 1.0;" in heat
      and "color: ringColor" in heat
      and "static const Color todayBorder = AppColors.heatmapTodayBorder;"
      in heat)
check("前景环只画边、不铺填充",
      "decoration: BoxDecoration(\n            color: StudyHeatmap.colorFor(total),"
      in heat)
check("坑写在注释里（半透明底 + 实心投影）",
      "半透明" in heat and "实心墨投影" in heat)
check("caption 文案没动",
      "'$label · 没学'" in heat and "'$label · 学了 $total 词'" in heat)

print("== 2. 等宽数字 ==")

check("AppTheme.tabular 只放 tabularFigures",
      "static const List<FontFeature> tabular = <FontFeature>[\n"
      "    FontFeature.tabularFigures(),\n  ];" in theme)
check("numeric() 只加特性、不动其余属性",
      "static TextStyle numeric(TextStyle? base) =>" in theme
      and "copyWith(fontFeatures: tabular)" in theme)
check("环内数字带等宽（RollingInt 内部套 AppTheme.numeric）",
      "final style = AppTheme.numeric(widget.style);" in rolling)
check("「/ 目标」带等宽",
      "AppTheme.numeric(text.labelMedium)" in today)
check("三格数字带等宽",
      "AppTheme.numeric(text.titleLarge?.copyWith(fontSize: 20))" in today)
check("首页三张卡带等宽",
      "AppTheme.numeric(text.titleLarge)" in study)
check("词库两张卡带等宽",
      "AppTheme.numeric(text.headlineSmall)" in words)
check("词表序号带等宽",
      "AppTheme.numeric(\n                  text.labelSmall?.copyWith("
      "color: AppColors.textTertiary)," in words)
check("没换字体：仍只有 NotoSansSC 一个字族",
      read(APP, "pubspec.yaml").count("- family:") == 1
      and "NotoSansSC" in read(APP, "pubspec.yaml"))
check("没加字体文件（assets 目录零改动）",
      git("diff", "--name-only", BASE, "--", "app/assets").strip() == "")

print("== 3. 环内数字滚动 ==")

check("用全 App 那条弹簧，不另加曲线",
      "SpringSimulation(" in rolling and "LiquidGlass.spring" in rolling
      and "Curves." not in rolling)
check("滚动是 unbounded 控制器 + 旧值起点",
      "AnimationController.unbounded" in rolling
      and "_from = _to = widget.value.toDouble();" in rolling)
check("首次出现不从 0 播（只 value 变了才动画）",
      "if (oldWidget.value == widget.value) return;" in rolling)
check("显示值夹在起点与终点之间（过冲不会闪出更大的数）",
      "final shown = _controller.value.clamp(lo, hi).round();" in rolling)
check("今天卡用的是 RollingInt，不是裸 Text",
      "RollingInt(" in today
      and "key: const ValueKey('ring-count')" in today)
check("环本身没动（弹簧参数仍在 progress_ring）",
      "SpringSimulation(\n        LiquidGlass.spring" in ring)

print("== 4. 按压缩放 ==")

check("按下 90ms、缩放 0.96",
      "static const double pressed = 0.96;" in press
      and "static const Duration duration = Duration(milliseconds: 90);"
      in press)
check("松开走同一根弹簧",
      "SpringSimulation(LiquidGlass.spring, _controller.value, 0, 0)"
      in press)
check("用 Listener 不抢 InkWell 的点击",
      "Listener(" in press and "GestureDetector" not in press)
check("只包首页两个玻璃按钮",
      "child: PressScale(" in study and "enabled: enabled," in study
      and press.count("class ") >= 2)
check("学习会话页的选项没被顺手改（零改动，见第 6 节）", True)

print("== 5. 圆角与间距 ==")

check("内容卡圆角只有一个来源：cardRadius = 18",
      "static const double cardRadius = 18;" in theme)
check("主题卡也用它",
      "borderRadius: BorderRadius.circular(cardRadius)," in theme)
for text, label in (
    (today, "任务卡"),
    (heat, "热力图卡"),
    (study, "首页数字卡"),
    (words, "词库两张卡"),
    (detail, "详情页纸面卡"),
    (profile, "我的页卡片与 tile"),
    (reading, "阅读页说明条"),
):
    check(f"{label}用 AppTheme.cardRadius", "AppTheme.cardRadius" in text)
check("卡片里不再留 16 / 18 / 20 的散值",
      all("circular(16)" not in t and "circular(20)" not in t
          and "circular(18)" not in t
          for t in (today, heat, study, words, detail, profile, reading)))
check("两玻璃按钮圆角同为 999（同一个 _GlassButton）",
      study.count("radius: 999,") == 1
      and study.count("_GlassButton(") >= 3)  # 1 定义 + 2 调用
check("详情页左右边距 20（原先 24）",
      "fromLTRB(20, 10, 20, 8)" in detail
      and "fromLTRB(20, 4, 20, 40)" in detail
      and "fromLTRB(24" not in detail)
check("纵向间距归到 12 / 20 / 32：详情页不再有 26",
      "height: 26" not in detail)
check("我的页不再有 28", "height: 28" not in profile)
check("词库页不再有 24", "height: 24" not in words)
check("首页「按钮 → 数据」从 32 收到 20",
      "const SizedBox(height: 20),\n                _StatsRow(" in study)

print("== 6. 没动的部分 ==")

for frozen, label in (
    ("app/lib/app/theme/app_colors.dart", "颜色 token（环橙 / 蓝阶 / 墨档）"),
    ("app/lib/features/study/progress_ring.dart", "进度环尺寸与弹簧"),
    ("app/lib/app/theme/liquid_glass.dart", "玻璃常量与色洗"),
    ("app/lib/app/shell", "外壳（PageView / Tab 栏 / 翻页物理）"),
    ("app/lib/features/study/study_session_page.dart", "学习会话页"),
    ("app/lib/data", "数据层（Leitner / 按天日志 / DAO / 模型）"),
    ("app/lib/main.dart", "入口 main"),
    ("app/lib/app/app.dart", "入口 app"),
    ("app/shaders", "shader"),
    ("app/android", "android 配置"),
):
    check(f"{label}零改动",
          git("diff", "--name-only", BASE, "--", frozen).strip() == "")

print("== 7. 影响面（基线 %s）==" % BASE)

allowed = {
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/widgets/press_scale.dart",
    "app/lib/app/widgets/rolling_int.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/words/words_page.dart",
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/reading/reading_page.dart",
    "app/pubspec.yaml",
    "app/test/v076_polish_test.dart",
    "项目日志.md",
    "_source/check_v075.py",  # 只加了「留档」说明
    "_source/check_v076.py",
    "_source/release_notes_v076.md",
}
changed = set(git("diff", "--name-only", BASE, "--", ".").splitlines())
changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad = changed - allowed
check("改动面都在白名单里", not bad, str(sorted(bad)[:6]))

diff_pub = git("diff", BASE, "--", "app/pubspec.yaml")
touched = [l for l in diff_pub.splitlines()
           if l[:1] in "+-" and not l.startswith(("+++", "---"))]
check("依赖零新增（pubspec 只动版本行）",
      bool(touched) and all("version: 0.7" in l for l in touched),
      str(touched))
check("没有引新依赖（动画不借第三方）",
      "lottie" not in read(APP, "pubspec.yaml").lower()
      and "flutter_animate" not in read(APP, "pubspec.yaml"))

print("== 8. 版本 ==")

pub = read(APP, "pubspec.yaml")
m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.7.6 / +21", version[:3] == (0, 7, 6), str(version))
check("versionCode 2021（+21，构建时 +2000）", version[3] == 21, str(version))
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
check("我的页版本行 = 0.7.6 (2021)",
      mine is not None and mine.group(1) == "0.7.6"
      and mine.group(2) == "2021",
      f"{mine.group(0) if mine else '缺'}")

print("== 9. 测试覆盖 ==")

t = read(APP, "test", "v076_polish_test.dart")
for needle, label in (
    ("底色跟空格一样", "今天格底色 = 空格底色"),
    ("实心墨投影会把今天画成", "今天格没有实心投影"),
    ("tabular figures", "等宽数字"),
    ("环内数字是滚动递增", "数字滚动不是瞬跳"),
    ("那条弹簧", "滚动用同一根弹簧"),
    ("按压缩放 0.96", "按压缩放"),
    ("圆角只有一个值", "圆角统一"),
):
    check(f"新增测试：{label}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
