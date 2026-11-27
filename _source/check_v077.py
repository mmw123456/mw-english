"""v0.7.7 验收：六箱色彩系统。

跑法：python _source/check_v077.py

主线（全部取自需求原文 + 2026-11-26 修正，不从实现里抄）：
1. 箱位 → 颜色七档定死：0 墨 35% / 1 粉 #FF2E7E / 2 紫 #8B5CFF / 3 蓝 #2E4BFF /
   4 橙 #E8490F（就是环那个橙）/ 5 深橙 #C43A06 / 6 薄荷 #2BD9A0；
   只用现有五色 + 环橙 + 墨，不新增色相
2. 色点一律 8px 实心圆，不加描边（薄荷纸上 1.6:1，靠色相区分不靠明暗）
3. 词库页：序号与单词之间一颗点，颜色跟该词箱位；自加词墨 35% 灰点
4. 详情页：色点 + 墨字「箱 N」（箱 0 写「新词」），底色箱位色 15%；不许白字；
   自加词与纯词典词不显示徽章
5. 首页：七段色带，段宽按词数占比，0 词段只留色标不占宽；箱 0 含未学的 820 词
6. 会话页：「箱 N」小标签换成详情页那套徽章
7. 不动：Leitner 逻辑、每日 30、按天日志写入、shader、玻璃常量、Tab 栏、环、热力图
8. 版本：0.7.7 / versionCode 2022
"""

import os
import re
import sqlite3
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "b657b75"  # v0.7.6 收尾提交

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


# v0.7.8 起只作留档：7 条断言被新版有意超越 —— 进度环（132/12 → 176/14）、
# 任务卡（数字 56 + 状态行）、热力图（标题改 16/700）、改动面白名单、
# 版本号（0.7.8 / +23）、我的页版本行。71 PASS / 7 FAIL 是预期状态，
# 不再当门禁用。
raise SystemExit(0)


boxc = read(LIB, "app", "theme", "box_colors.dart")
badge = read(LIB, "app", "widgets", "box_badge.dart")
band = read(LIB, "features", "study", "box_band.dart")
words = read(LIB, "features", "words", "words_page.dart")
detail = read(LIB, "features", "words", "word_detail_page.dart")
detail_model = read(LIB, "data", "models", "word_detail.dart")
detail_dao = read(LIB, "data", "dao", "detail_dao.dart")
study = read(LIB, "features", "study", "study_page.dart")
session = read(LIB, "features", "study", "study_session_page.dart")
dao = read(LIB, "data", "dao", "study_dao.dart")
colors = read(LIB, "app", "theme", "app_colors.dart")
defaults = read(LIB, "app", "app_defaults.dart")

print("== 1. 箱位 → 颜色（七档定死）==")

check("箱色表独立成一个文件", "class BoxColors" in boxc)
check("boxColor 是顶层纯函数（测试可直接断言）",
      re.search(r"^Color boxColor\(int box\)", boxc, re.M) is not None)
check("boxTint 是顶层纯函数", "Color boxTint(int box)" in boxc)
check("boxLabel 是顶层纯函数", "String boxLabel(int box)" in boxc)

for label, hexv in (
    ("箱 0 墨 35%", "0x590B0C10"),
    ("箱 1 粉", "0xFFFF2E7E"),
    ("箱 2 紫", "0xFF8B5CFF"),
    ("箱 3 蓝", "0xFF2E4BFF"),
    ("箱 4 橙", "0xFFE8490F"),
    ("箱 5 深橙", "0xFFC43A06"),
    ("箱 6 薄荷", "0xFF2BD9A0"),
):
    check(f"{label} = {hexv}", hexv in boxc)

ring = re.search(r"ringOrange = Color\((0x[0-9A-Fa-f]{8})\)", colors)
check("箱 4 的橙与首页环是同一支 #E8490F",
      ring is not None and ring.group(1).lower() == "0xffe8490f")

# 不新增色相：文件里出现的每一个 Color(0x...) 都必须是这七支之一。
used = {h.lower() for h in re.findall(r"Color\((0x[0-9A-Fa-f]{8})\)", boxc)}
allowed = {
    "0x590b0c10", "0xffff2e7e", "0xff8b5cff", "0xff2e4bff",
    "0xffe8490f", "0xffc43a06", "0xff2bd9a0",
}
check("只用现有五色 + 环橙 + 墨，没有新色相", used <= allowed, str(sorted(used - allowed)))

check("最高箱位从 AppDefaults.boxIntervals 推出，不写死 6",
      "AppDefaults.boxIntervals.length - 1" in boxc)
check("箱 6 及以上统一算已掌握", "box >= topBox" in boxc or "box >= BoxColors.topBox" in boxc)
check("箱 0 与未进调度都走同一支灰", "if (box <= 0)" in boxc)
check("越界箱位有兜底", "?? mastered" in boxc)

print("== 2. 色点规格（8px 实心圆，不加描边）==")

check("默认 8px", "this.size = 8" in badge)
check("形状是圆", "shape: BoxShape.circle" in badge)
check("颜色走 boxColor，不在组件里写 hex",
      "color: boxColor(box)" in badge and "Color(0x" not in badge)
check("色点没有描边", "border:" not in badge and "BorderSide" not in badge)

print("== 3. 词库页 ==")

_row = words.split("class WordRow")[1].split("class AddedRow")[0]

check("每行色点按该词箱位取色", "BoxDot(box: box)" in words)
check("调用点把词对到箱位，没学过的按 0",
      "box: _boxOf[entry.wordKey] ?? 0" in words and "box: _boxOf[e.wordKey] ?? 0" in words)
check("箱位读失败不拖垮词库页", "try {" in words and "_studyDao.boxByWord()" in words)
check("自加词固定灰点", "BoxDot(box: 0)" in words)
check("色点排在序号与单词之间（顺序：序号列 → 点 → 8px 缝 → 单词）",
      _row.find("width: 34") >= 0
      and _row.find("width: 34") < _row.find("BoxDot(box: box)")
      < _row.find("SizedBox(width: 8)") < _row.find("Expanded"))
check("行高没动（纵向 11 内边距原样）",
      "padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4)," in words)

print("== 4. 详情页 ==")

check("详情页用同一颗徽章", "BoxBadge(box: box)" in detail)
check("自加词 / 纯词典词不显示徽章（box 为 null 才有守卫）",
      "final box = d.box;" in detail and "if (box != null)" in detail)
check("模型里 box 可空", "final int? box;" in detail_model)
check("只有 820 词表里的词才有箱位",
      "box: my == null ? null :" in detail_dao)
check("星标空壳（started=0）按箱 0", "started ?" in detail_dao)
check("淡底是 15%", "withValues(alpha: 0.15)" in boxc)
check("徽章文字用墨色，不许白字",
      "color: LiquidGlass.ink" in badge and "Colors.white" not in badge)
check("箱 0 写「新词」", "box <= 0 ? '新词' : '箱 $box'" in boxc)

print("== 5. 首页七段色带 ==")

check("色带挂在「怎么排的」下", "BoxBand(counts: _boxCounts)" in study)
check("七段：0 到 topBox", "b <= BoxColors.topBox" in band)
check("有词的段按词数分宽", "flex: counts[b]!" in band)
check("0 词的段固定 6px 色标", "stubWidth = 6" in band)
check("段间留 2px 缝（相邻橙 / 深橙靠明度分）", "gap = 2" in band)
check("段颜色 = 箱位色", "color: boxColor(b)" in band)
check("图例名字走 boxLabel（箱 0 = 新词）", "boxLabel(box)" in band)

print("== 6. 会话页 ==")

check("箱标签换成徽章", "BoxBadge(box: card.box)" in session)
check("旧的玻璃箱标签已撤", "StudyTagPill(label: '箱 " not in session)
check("状态标签仍是玻璃胶囊（没被一起改）",
      "StudyTagPill(label: _badgeLabel(card), emphasized: true)" in session)

print("== 7. 冻结面 ==")

frozen = {
    "app/lib/data/study/leitner.dart": "Leitner 逻辑",
    "app/lib/app/app_defaults.dart": "每日 30 / 六箱间隔",
    "app/lib/data/study/choice_options.dart": "干扰项",
    "app/lib/data/study/study_flow.dart": "作答状态机",
    "app/lib/app/theme/liquid_glass.dart": "玻璃常量",
    "app/shaders/liquid_glass.frag": "shader",
    "app/lib/app/shell/home_shell.dart": "Tab 栏",
    "app/lib/features/study/study_heatmap.dart": "热力图",
    "app/lib/features/study/progress_ring.dart": "进度环",
    "app/lib/features/study/today_card.dart": "任务卡",
    "app/lib/data/db/app_database.dart": "表结构",
}
for path, label in frozen.items():
    check(f"{label}零改动", git("diff", "--name-only", BASE, "--", path).strip() == "")

check("按天日志仍是只插入不覆盖",
      "dayStatConflict" in dao and "ConflictAlgorithm.ignore" in dao)
check("数据层只加了只读查询（boxByWord / boxCounts）",
      "boxByWord()" in dao and "boxCounts()" in dao
      and "INSERT INTO daily_stat" not in dao)

print("== 8. 影响面（基线 %s）==" % BASE)

allowed_files = {
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/lib/features/study/box_band.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/dao/detail_dao.dart",
    "app/lib/data/models/word_detail.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/pubspec.yaml",
    "app/test/v077_box_color_test.dart",
    "项目日志.md",
    "_source/check_theme_v070.py",  # WordRow 改名后跟着读新类名（踩坑 47）
    "_source/check_v076.py",  # 只加「留档」说明
    "_source/check_v077.py",
    "_source/release_notes_v077.md",
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

print("== 9. 版本 ==")

pub = read(APP, "pubspec.yaml")
m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.7.7 / +22", version[:3] == (0, 7, 7), str(version))
check("versionCode 2022（+22，构建时 +2000）", version[3] == 22, str(version))
profile = read(LIB, "features", "profile", "profile_page.dart")
mine = re.search(r"'(\d+\.\d+\.\d+) \((\d+)\)'", profile)
check("我的页版本行 = 0.7.7 (2022)",
      mine is not None and mine.group(1) == "0.7.7"
      and mine.group(2) == "2022",
      f"{mine.group(0) if mine else '缺'}")

print("== 10. 真跑 SQL：箱 0 口径 ==")

# 与 StudyDao.boxCounts 同样的语句，在真 sqlite3 上跑一遍。
con = sqlite3.connect(":memory:")
con.executescript("""
CREATE TABLE my_words (word_key TEXT PRIMARY KEY, no INTEGER);
CREATE TABLE study_record (
  word_key TEXT PRIMARY KEY, box INTEGER NOT NULL DEFAULT 0,
  started INTEGER NOT NULL DEFAULT 0, killed INTEGER NOT NULL DEFAULT 0
);
""")
for i in range(820):
    con.execute("INSERT INTO my_words VALUES (?, ?)", (f"w{i}", i + 1))

rows = []
rows += [("a%d" % i, 1, 1, 0) for i in range(10)]     # 箱 1：10
rows += [("b%d" % i, 3, 1, 0) for i in range(5)]      # 箱 3：5
rows += [("c%d" % i, 6, 1, 0) for i in range(2)]      # 箱 6：2（已掌握）
rows += [("d%d" % i, 0, 1, 0) for i in range(3)]      # 退回箱 0：3
rows += [("e%d" % i, 4, 1, 1) for i in range(1)]      # 已斩：不进任何档
rows += [("f%d" % i, 0, 0, 0) for i in range(2)]      # 星标空壳：没开学
con.executemany("INSERT INTO study_record VALUES (?,?,?,?)", rows)

total = con.execute("SELECT COUNT(*) FROM my_words").fetchone()[0]
got = {}
placed = 0
for box, c in con.execute(
    "SELECT box, COUNT(*) FROM study_record "
    "WHERE started = 1 AND killed = 0 AND box > 0 GROUP BY box"
):
    got[box] = c
    placed += c
got[0] = total - placed

check("箱 0 = 820 − 已进箱（含答错退回 0 箱、不含未开学与已斩）",
      got.get(0) == 803, str(got.get(0)))
check("箱 1 计入 10", got.get(1) == 10, str(got.get(1)))
check("箱 3 计入 5", got.get(3) == 5, str(got.get(3)))
check("箱 4 已斩不计入", got.get(4) is None, str(got.get(4)))
check("箱 6 计入 2（已掌握）", got.get(6) == 2, str(got.get(6)))
check("七档合计 = 820", sum(got.get(b, 0) for b in range(7)) == 820,
      str(sum(got.get(b, 0) for b in range(7))))
con.close()

print("== 11. 测试覆盖 ==")

t = read(APP, "test", "v077_box_color_test.dart")
for needle, label in (
    ("七档逐档对上", "箱位 → 颜色七档"),
    ("箱 4 橙 = 环那个橙", "箱 4 就是环橙"),
    ("七档互不相同", "七档互不相同"),
    ("色点颜色跟箱位走", "词库行色点"),
    ("固定墨 35% 灰点", "自加词灰点"),
    ("15% 淡底 + 色点 + 墨字", "详情徽章"),
    ("薄荷底上不许用白字", "徽章不用白字"),
    ("段宽按词数占比", "色带段宽"),
    ("0 词段只留固定色标", "0 词段只留色标"),
):
    check(f"新增测试：{label}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
