"""v0.7.4 验收：首页进度环 + 学习热力图 + 按天完成日志。

跑法：python _source/check_v074.py

七条主线：
1. 进度环：直径 132 / 线宽 12 / 圆头 / 轨道墨 10% / 填充 #2E4BFF；
   比例 = 今日新词已学 ÷ 今日目标（不是写死 30）；三格数字不动
2. 环的动效：LiquidGlass.spring 从旧值扫到新值（首次即 0 → 当前），非线性
3. 热力图：12 周 × 7 天、单色阶四档、空天 = 纸面卡底 + 0.5px 描边、
   点格出 caption、右上角连续 N 天、区块是纸面卡不是玻璃
4. 按天日志：daily_stat 表 +(day, word_key) 主键 + insert OR IGNORE（只增不改）
   + 只答对才记 + 新词/复习按 first_seen_at 判 + 不回填历史
5. 首页顺序：任务卡 → 两个按钮 → 三张数字卡 → 学习足迹 → 怎么排的
6. 影响面：只改首页 / 按天日志 / 调色板 / 版本行；外壳、玻璃常量、会话页、
   详情页、词库页、阅读页、主题、shader、入口、android 零改动
7. 版本：0.7.4，我的页版本行跟着走

真跑 SQL 的部分在最后（Python 自带 sqlite3）：主键去重与「旧数据不被改写」
在这里验证，不靠读代码猜。
"""

import os
import re
import sqlite3
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "88366bc"  # v0.7.3 收尾提交

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
card = read(LIB, "features", "study", "today_card.dart")
heat = read(LIB, "features", "study", "study_heatmap.dart")
study = read(LIB, "features", "study", "study_page.dart")
dao = read(LIB, "data", "dao", "study_dao.dart")
db = read(LIB, "data", "db", "app_database.dart")
colors = read(LIB, "app", "theme", "app_colors.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")

print("== 1. 进度环 ==")

check("直径 132", "static const double diameter = 132;" in ring)
check("线宽 12", "static const double stroke = 12;" in ring)
check("轨道墨 10%", "static const Color track = Color(0x1A0B0C10);" in ring)
check("填充是那支蓝 #2E4BFF", "static const Color accentBlue = Color(0xFF2E4BFF);" in colors
      and "AppColors.accentBlue" in ring)
check("圆头端点", "StrokeCap.round" in ring)
check("从 12 点起顺时针", "-math.pi / 2" in ring)
check("画的是整圈轨道 + 按比例一段填充",
      ring.count("drawArc(") == 2)

check("卡片里细进度条撤掉", "LinearProgressIndicator" not in card)
check("卡片里没有第二行大数字（数字移进环里）",
      "text.displayLarge" in card
      and card.count("displayLarge") == 1)
check("环在卡中部居中", "Center(" in card and "ProgressRing(" in card)
check("比例与数字同源（同一个 target）",
      "double get ratio => (stats.newLearned / target)" in card)
check("分母是 newTarget，不是写死 30",
      "stats.newTarget <= 0 ? AppDefaults.dailyNewWordTarget" in card
      and "/ target" in card)
check("三格数字还在（新词 / 待复习 / 答错）",
      all(f"_Metric(label: '{x}'" in card for x in ("新词", "待复习", "答错")))

print("== 2. 环的动效 ==")

check("用全 App 那条弹簧", "SpringSimulation(\n        LiquidGlass.spring," in ring
      or "SpringSimulation(LiquidGlass.spring" in ring.replace("        ", ""))
check("首次从 0 扫到当前值",
      "_controller = AnimationController.unbounded(vsync: this, value: 0);" in ring
      and "ProgressRing.simulation(0, target)" in ring)
check("数值变化从当前值接着扫（不重播）",
      "final from = _clamp(_controller.value);" in ring
      and "ProgressRing.simulation(from, to)" in ring)
check("过冲能落回来（unbounded 控制器）", "AnimationController.unbounded" in ring)
check("没有用 CurvedAnimation / 固定 duration 糊",
      "CurvedAnimation" not in ring and "Duration(" not in ring)

print("== 3. 热力图 ==")

check("12 周", "static const int weeks = 12;" in heat)
check("7 天", "static const int daysPerWeek = 7;" in heat)
check("四档色阶 25 / 50 / 75 / 100",
      all(f"alpha: 0.{a})" in heat for a in ("25", "50", "75"))
      and "AppColors.accentBlue;" in heat)
check("没学 = 纸面卡底", "if (total <= 0) return AppColors.surface;" in heat)
check("没学格加 0.5px 描边", "Border.all(color: AppColors.divider, width: 0.5)" in heat)
check("未来那天不画（不是涂成没学）",
      "if (date.isAfter(_today)) {" in heat and "SizedBox.shrink()" in heat)
check("点格出 caption", "onTap: () => setState(() => _selected = date)" in heat
      and "heatmap-caption" in heat)
check("caption 形如「11月25日 · 学了 28 词」",
      "'${d.month}月${d.day}日'" in heat and "学了 $total 词" in heat)
check("月份小字标在上方", "class _MonthRuler" in heat and "_monthLabel" in heat)
check("右上角连续 N 天", "连续 ${widget.streak} 天" in heat)
check("区块是纸面卡不是玻璃",
      "GlassSurface" not in heat and "Border.all(color: AppColors.divider, width: 0.5)" in heat)
check("标题是「学习足迹」", "'学习足迹'" in heat)

print("== 4. 按天日志 ==")

check("daily_stat 表存在", "CREATE TABLE IF NOT EXISTS daily_stat(" in db)
check("主键 (day, word_key)：一天一个词只算一次",
      "PRIMARY KEY(day, word_key)" in db)
check("schemaVersion 升到 4", "static const int _schemaVersion = 4;" in db)
check("写入策略是 insert + ignore", "static const ConflictAlgorithm dayStatConflict = ConflictAlgorithm.ignore;" in dao
      and "conflictAlgorithm: dayStatConflict" in dao)
check("只答对才计入", re.search(r"if \(correct\) \{[^}]*daily_stat", dao, re.S) is not None)
check("新词 / 复习按 first_seen_at 判", "isNewToday" in dao and "firstSeen >= range.from" in dao)
check("不回填历史（dailyTotals 只查 daily_stat，不扫 study_log）",
      "FROM daily_stat" in dao
      and "study_log" not in dao.split("Future<Map<String, DayTotal>> dailyTotals")[1].split("Future<int> studyStreak")[0])
check("按天聚合只读不信手改", "GROUP BY day, kind" in dao)
check("连续天数：今天没学就从昨天往回数",
      "if (!days.contains(dayKey(cursor))) {" in dao)
check("连续天数跨月跨年靠日期构造，不靠 Duration",
      "DateTime(cursor.year, cursor.month, cursor.day - 1)" in dao)

print("== 5. 首页顺序 ==")

order = [
    study.index("TodayCard(stats: _stats"),
    study.index("'开始学习'"),
    study.index("_StatsRow("),
    study.index("StudyHeatmap("),
    study.index("const _SectionLabel('怎么排的')"),
]
check("任务卡 → 按钮 → 数字卡 → 热力图 → 说明", order == sorted(order), str(order))
check("热力图读的是 _load 取的按天数据",
      "_dayTotals = results[3] as Map<String, DayTotal>" in study
      and "StudyHeatmap(totals: _dayTotals, streak: _streak)" in study)

print("== 6. 影响面（基线 %s）==" % BASE)

allowed = {
    "app/lib/app/theme/app_colors.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/db/app_database.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/pubspec.yaml",
    "app/test/v074_ring_test.dart",
    "app/test/v074_heatmap_test.dart",
    "app/test/v074_daily_stat_test.dart",
    # 版本行断言改成从 pubspec 读，省得每版手改测试里的版本号。
    "app/test/v072_shell_test.dart",
    "项目日志.md",
    "_source/check_v074.py",
    # 任务卡拆到 today_card.dart 后，v0.7.0 那条「纸面卡不上玻璃」的断言
    # 跟着文件走；顺手把它的影响面比对改成 BASE..REF（踩坑 40）。
    "_source/check_theme_v070.py",
    "_source/release_notes_v074.md",
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
    ("app/lib/features/words", "词库页与详情页"),
    ("app/lib/features/reading", "阅读页"),
    ("app/lib/data/models", "数据模型"),
    ("app/lib/data/study", "Leitner / 选项 / 词典"),
    ("app/lib/data/dao/word_dao.dart", "词库 DAO"),
    ("app/lib/data/dao/detail_dao.dart", "详情 DAO"),
    ("app/lib/data/dao/settings_dao.dart", "设置 DAO"),
):
    check(f"{label}零改动",
          git("diff", "--name-only", BASE, "--", frozen).strip() == "")

print("== 7. 测试覆盖 ==")

t_ring = read(APP, "test", "v074_ring_test.dart")
for needle, label in (
    ("环的比例就是「已学 / 目标」", "环比例与数字一致"),
    ("断档削减配额时分母跟着变", "分母不写死 30"),
    ("超过目标时比例夹到 1", "比例夹取"),
    ("尺寸与线宽", "132 / 12 / 轨道 / 蓝"),
    ("落位走的是全 App 那条弹簧", "弹簧参数"),
    ("轨迹是曲线不是直线", "非线性"),
    ("首次出现从 0 扫到当前值", "首次 0 → 值"),
    ("数值变化从旧值扫起", "变化从旧值"),
    ("细进度条已经撤掉", "细进度条撤掉"),
):
    check(f"新增测试：{label}", needle in t_ring)

t_heat = read(APP, "test", "v074_heatmap_test.dart")
for needle, label in (
    ("84 个格子，未来那几天不画", "12×7 与未来格"),
    ("纸面卡底 + 0.5px 描边", "空天样式"),
    ("按四档上色", "四档色阶"),
    ("色阶四档的边界", "色阶边界"),
    ("点一格，下方小字换成那天的数据", "点格出 caption"),
    ("连续 N 天", "连续天数显示"),
    ("不是玻璃", "纸面卡不是玻璃"),
):
    check(f"新增测试：{label}", needle in t_heat)

t_day = read(APP, "test", "v074_daily_stat_test.dart")
for needle, label in (
    ("连续天数（纯函数）", "连续天数算对"),
    ("insert + ignore", "写入策略"),
    ("主键是 (day, word_key)", "主键去重"),
    ("只答对才计入完成量", "只答对计入"),
):
    check(f"新增测试：{label}", needle in t_day)

print("== 8. 真跑 SQL：去重与「旧数据不改写」 ==")

con = sqlite3.connect(":memory:")
con.execute("""
CREATE TABLE daily_stat(
  day      TEXT NOT NULL,
  word_key TEXT NOT NULL,
  kind     INTEGER NOT NULL DEFAULT 1,
  at       INTEGER NOT NULL,
  PRIMARY KEY(day, word_key)
)
""")
# 第一天：新词 apple，先答对一次；随后当日重测再答对两次，其中一次被误标成复习。
for kind, at in ((0, 1000), (0, 2000), (1, 3000)):
    con.execute(
        "INSERT OR IGNORE INTO daily_stat(day, word_key, kind, at) VALUES(?,?,?,?)",
        ("2026-11-26", "apple", kind, at),
    )
rows = con.execute("SELECT day, word_key, kind, at FROM daily_stat").fetchall()
check("同一天同一个词只留一行", len(rows) == 1, str(rows))
check("旧记录的时间戳没被后来的作答改写", rows and rows[0][3] == 1000, str(rows))
check("类别保留第一次的判定（新词）", rows and rows[0][2] == 0, str(rows))

# 第二天同一个词再答对：算复习，是新的一行。
con.execute(
    "INSERT OR IGNORE INTO daily_stat(day, word_key, kind, at) VALUES(?,?,?,?)",
    ("2026-11-27", "apple", 1, 5000),
)
# 第二天再学一个词。
con.execute(
    "INSERT OR IGNORE INTO daily_stat(day, word_key, kind, at) VALUES(?,?,?,?)",
    ("2026-11-27", "banana", 0, 5100),
)
agg = dict(
    ((day, kind), n)
    for day, kind, n in con.execute(
        "SELECT day, kind, COUNT(*) FROM daily_stat GROUP BY day, kind"
    )
)
check("次日同词记成复习", agg.get(("2026-11-27", 1)) == 1, str(agg))
check("次日新词单独一行", agg.get(("2026-11-27", 0)) == 1, str(agg))
check("第一天不受影响", agg.get(("2026-11-26", 0)) == 1, str(agg))

total_1126 = sum(n for (day, _), n in agg.items() if day == "2026-11-26")
total_1127 = sum(n for (day, _), n in agg.items() if day == "2026-11-27")
check("当日完成量 = 新词 + 复习", total_1126 == 1 and total_1127 == 2,
      f"{total_1126} / {total_1127}")
con.close()

print("== 9. 版本 ==")

pub = read(APP, "pubspec.yaml")
m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 ≥ 0.7.4", version[:3] >= (0, 7, 4), str(version))
if version[:3] == (0, 7, 4):
    check("versionCode 2019（+19，构建时 +2000）", version[3] == 19, str(version))
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
check("我的页版本行跟着 pubspec 走",
      mine is not None and m is not None
      and mine.group(1) == ".".join(m.groups()[:3])
      and mine.group(2) == str(int(m.group(4)) + 2000),
      f"{mine.group(0) if mine else '缺版本号'} vs {m.group(0) if m else '缺'}")

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
