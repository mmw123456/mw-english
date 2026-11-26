"""v0.7.5 验收：首页暖冷分工配色。

跑法：python _source/check_v075.py

主线（全部取自需求原文，不从实现里抄）：
1. 进度环：填充 #E8490F（纸上 ≥3:1），亮橙 #FF5A1F 不达标不许用；
   直径 132 / 线宽 12 / 圆头 / 轨道墨 10% / 弹簧 300-24-0.8 一律不动；
   蓝 #2E4BFF 只从环上退下来，热力图的蓝阶不动
2. 按钮：开始学习 = 橙 10% tint，文字墨色；只复习按钮仍是白 tint，不上色
3. 热力图空态：空格墨 5% 底 + 保留边框；全空时标题下「从今天开始记」，
   有数据即消失；今天那格 1.5px 墨 60% 描边；蓝阶四档与几何不动
4. 12 列：格子尺寸向下取整，总宽严格不超可用宽（超窄容器也不缺列）
5. 影响面：只改首页三个文件 + 调色板 + 版本行；其余全部零改动
6. 版本：0.7.5 / versionCode 2020
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "d53f3c0"  # v0.7.4 收尾提交

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


def luminance(hex_color):
    h = hex_color.lstrip("#")
    channels = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        channels.append(c / 12.92 if c <= 0.03928
                        else ((c + 0.055) / 1.055) ** 2.4)
    return (0.2126 * channels[0] + 0.7152 * channels[1]
            + 0.0722 * channels[2])


def contrast(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


colors = read(LIB, "app", "theme", "app_colors.dart")
ring = read(LIB, "features", "study", "progress_ring.dart")
heat = read(LIB, "features", "study", "study_heatmap.dart")
study = read(LIB, "features", "study", "study_page.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")
glass = read(LIB, "app", "theme", "liquid_glass.dart")

print("== 1. 调色板 ==")

check("进度橙 token = #E8490F",
      "static const Color ringOrange = Color(0xFFE8490F);" in colors)
check("亮橙 #FF5A1F 没有进调色板",
      "0xFFFF5A1F" not in colors)
check("蓝 #2E4BFF 原样保留（给热力图）",
      "static const Color accentBlue = Color(0xFF2E4BFF);" in colors)
check("空格墨 5% token（0x0D 墨）",
      "static const Color heatmapEmpty = Color(0x0D0B0C10);" in colors)
check("今天描边墨 60% token（0x99 墨）",
      "static const Color heatmapTodayBorder = Color(0x990B0C10);" in colors)

paper = "#F3F2EE"
ring_cr = contrast("#E8490F", paper)
check(f"橙在纸上对比 ≥3:1（实测 {ring_cr:.2f}）", ring_cr >= 3.0)
check("亮橙在纸上 <3:1（所以不能用）",
      contrast("#FF5A1F", paper) < 3.0)

print("== 2. 进度环 ==")

check("填充走 token，不写死 hex",
      "AppColors.ringOrange" in ring and "0xFF" not in ring)
check("环上不再有那支蓝", "accentBlue" not in ring)
check("直径 132 未动", "static const double diameter = 132;" in ring)
check("线宽 12 未动", "static const double stroke = 12;" in ring)
check("轨道墨 10% 未动", "static const Color track = Color(0x1A0B0C10);" in ring)
check("圆头端点未动", "StrokeCap.round" in ring)
check("从 12 点起未动", "-math.pi / 2" in ring)
check("弹簧仍是 LiquidGlass.spring",
      re.search(r"SpringSimulation\(\s*LiquidGlass\.spring", ring) is not None)
check("首次 0 → 当前值、变化从旧值接着扫",
      "ProgressRing.simulation(0, target)" in ring
      and "ProgressRing.simulation(from, to)" in ring)

print("== 3. 首页两个按钮 ==")

primary = study.split("label: '开始学习'")[1].split("),")[0]
check("开始学习按钮 tint 橙 10%",
      "tint: 0.10" in primary
      and "tintColor: AppColors.ringOrange" in primary)
secondary = study.split("label: _stats.dueReview == 0")[1].split("),")[0]
check("只复习按钮不上色", "tintColor" not in secondary)
check("只复习按钮 tint 沿用 LiquidGlass.tint",
      "tint: LiquidGlass.tint" in secondary)
check("按钮文字仍是墨色",
      "color: enabled ? LiquidGlass.ink : LiquidGlass.textDisabled" in study)
check("GlassSurface 支持 tintColor（没为这版另造一个组件）",
      "final Color? tintColor;" in glass
      and "tintColor: tintColor" in study)

print("== 4. 热力图空态 ==")

check("空格底色 = 墨 5% token",
      "if (total <= 0) return AppColors.heatmapEmpty;" in heat)
check("空格边框保留 0.5px",
      "Border.all(color: AppColors.divider, width: 0.5)" in heat)
check("今天描边 1.5px",
      "width: 1.5," in heat)
check("今天描边用墨 60% token",
      "color: StudyHeatmap.todayBorder" in heat
      and "static const Color todayBorder = AppColors.heatmapTodayBorder;"
      in heat)
check("今天判断按 dayKey 比",
      "final isToday = key == StudyDao.dayKey(_today);" in heat)
check("描边画在前景（不占布局）",
      "foregroundDecoration: isToday" in heat)
check("全空文案「从今天开始记」", "'从今天开始记'" in heat)
check("文案有 key（测试能钉住）", "heatmap-empty-hint" in heat)
check("全空判断只看窗口内有没有记录",
      "bool get _hasAnyRecord" in heat
      and "_totalOf(_shift(_start, i)).total > 0" in heat)
check("有数据就隐藏（条件渲染）", "if (!_hasAnyRecord) ...[" in heat)

print("== 5. 热力图没动的部分 ==")

check("12 周 / 7 天未动",
      "static const int weeks = 12;" in heat
      and "static const int daysPerWeek = 7;" in heat)
check("间距 4 未动", "static const double gap = 4;" in heat)
check("蓝阶 25 / 50 / 75 / 100 未动",
      all(f"alpha: 0.{a})" in heat for a in ("25", "50", "75"))
      and "return AppColors.accentBlue;" in heat)
check("四档阈值没动（<10 / <20 / <30）",
      "if (total < 10)" in heat and "if (total < 20)" in heat
      and "if (total < 30)" in heat)
check("未来格不画", "if (date.isAfter(_today)) {" in heat
      and "SizedBox.shrink()" in heat)
check("点格出 caption", "onTap: () => setState(() => _selected = date)" in heat
      and "heatmap-caption" in heat)
check("月份小字仍在", "class _MonthRuler" in heat and "_monthLabel" in heat)
check("周一起头", "-(t.weekday - 1)" in heat)
check("区块仍是纸面卡不是玻璃", "GlassSurface" not in heat)
check("cap 上限仍是 30", "30.0," in heat)

print("== 6. 12 列几何 ==")

check("格子尺寸向下取整（不超可用宽）",
      "final raw = (constraints.maxWidth -" in heat
      and "(raw * 10).floorToDouble() / 10" in heat)
check("去掉了 clamp(12, 30) 的硬下限（超窄容器会缺列）",
      ".clamp(12.0, 30.0)" not in heat)

print("== 7. 影响面（基线 %s）==" % BASE)

allowed = {
    "app/lib/app/theme/app_colors.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/pubspec.yaml",
    "app/test/v074_ring_test.dart",
    "app/test/v074_heatmap_test.dart",
    "app/test/v075_home_color_test.dart",
    "项目日志.md",
    "_source/check_v075.py",
    "_source/release_notes_v075.md",
}
changed = set(git("diff", "--name-only", BASE, "--", ".").splitlines())
changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad = changed - allowed
check("改动面都在白名单里", not bad, str(sorted(bad)[:6]))

for frozen, label in (
    ("app/shaders", "shader"),
    ("app/android", "android 配置"),
    ("app/lib/main.dart", "入口 main"),
    ("app/lib/app/app.dart", "入口 app"),
    ("app/lib/app/app_defaults.dart", "默认值"),
    ("app/lib/app/shell", "外壳（PageView / 翻页物理）"),
    ("app/lib/app/theme/app_theme.dart", "全局主题"),
    ("app/lib/app/theme/liquid_glass.dart", "玻璃常量与色洗"),
    ("app/lib/features/study/study_session_page.dart", "学习会话页"),
    ("app/lib/features/study/today_card.dart", "首页任务卡"),
    ("app/lib/features/words", "词库页与详情页"),
    ("app/lib/features/reading", "阅读页"),
    ("app/lib/data/models", "数据模型"),
    ("app/lib/data/study", "Leitner / 选项 / 词典"),
    ("app/lib/data/dao/study_dao.dart", "学习 DAO"),
    ("app/lib/data/db", "数据库结构"),
    ("app/lib/data/dao/word_dao.dart", "词库 DAO"),
    ("app/lib/data/dao/detail_dao.dart", "详情 DAO"),
    ("app/lib/data/dao/settings_dao.dart", "设置 DAO"),
):
    check(f"{label}零改动",
          git("diff", "--name-only", BASE, "--", frozen).strip() == "")

print("== 8. 版本 ==")

pub = read(APP, "pubspec.yaml")
m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.7.5 / +20", version[:3] == (0, 7, 5), str(version))
check("versionCode 2020（+20，构建时 +2000）", version[3] == 20, str(version))
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
check("我的页版本行 = 0.7.5 (2020)",
      mine is not None and mine.group(1) == "0.7.5"
      and mine.group(2) == "2020",
      f"{mine.group(0) if mine else '缺'}")

print("== 9. 测试覆盖 ==")

t = read(APP, "test", "v075_home_color_test.dart")
for needle, label in (
    ("橙 token：纸上 ≥3:1", "橙 token + 对比度"),
    ("环画的是橙，不是蓝", "环填充"),
    ("开始学习按钮 = 橙 10%", "按钮主次"),
    ("空格子：墨 5% 底", "空格底色"),
    ("从今天开始记", "全空空态"),
    ("1.5px 墨 60% 描边", "今天描边"),
    ("蓝阶四档没动", "蓝阶不动"),
    ("12 列完整在卡片内宽里", "12 列不溢出"),
):
    check(f"新增测试：{label}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
