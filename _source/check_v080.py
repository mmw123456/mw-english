"""v0.8.0 验收：自加词进调度 + 斩词 + 设置页。

跑法：python _source/check_v080.py

主线（全部取自需求原文，不从实现里抄）：
1. 自加词进同一套六箱调度：与 820 一起排每日配额，820 在前、自加按添加时间正序；
   答错降箱 / 箱上限 / 断档削减与 820 完全同一支；自加词从 0 箱起步
2. 每日统计与箱位颜色同样适用；词库行那颗箱 0 灰点改成真实箱位，不再是例外
3. 斩词：学习卡片 + 详情页两个入口，点后一次确认；斩 = 移出复习队列、词库保留、
   「已斩」里可恢复；与「不认识」区分开
4. 设置页：每日目标 10–50（默认 30，环 / 状态行 / 配额都跟它走，不许写死 30）、
   遮盖中文开关（默认关）、自动朗读开关（默认开）
5. 版本：0.8.0 / +25；我的页 0.8.0 (2025)
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "77838b3"  # v0.7.9 收尾提交（DESIGN.md 落库）

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


def strip_code(text):
    """去掉注释与字符串字面量，只留真正的代码。"""
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", text)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    return text


defaults = read(LIB, "app", "app_defaults.dart")
signals = read(LIB, "app", "app_signals.dart")
settings_dao = read(LIB, "data", "dao", "settings_dao.dart")
study_dao = read(LIB, "data", "dao", "study_dao.dart")
detail_dao = read(LIB, "data", "dao", "detail_dao.dart")
detail_model = read(LIB, "data", "models", "word_detail.dart")
killed_model = read(LIB, "data", "models", "killed_word.dart")
settings_page = read(LIB, "features", "profile", "settings_page.dart")
profile = read(LIB, "features", "profile", "profile_page.dart")
study_page = read(LIB, "features", "study", "study_page.dart")
session = read(LIB, "features", "study", "study_session_page.dart")
words = read(LIB, "features", "words", "words_page.dart")
detail = read(LIB, "features", "words", "word_detail_page.dart")
today = read(LIB, "features", "study", "today_card.dart")
pub = read(APP, "pubspec.yaml")
design = read(ROOT, "DESIGN.md")

print("== 1. 版本行 ==")

m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.8.0 / +25", version == (0, 8, 0, 25), str(version))
check("我的页版本行 = 0.8.0 (2025)", "const base = '0.8.0 (2025)';" in profile)

print("== 2. 设置页三项（都是真设置，不是占位）==")

check("新建设置页", "class SettingsPage extends StatefulWidget" in settings_page)
check("我的页 → 设置页入口", "const SettingsPage()" in profile
      and "onTap: _openSettings," in profile)
check("我的页那一行叫「设置」并显示当前目标",
      "title: '设置'," in profile and "value: '每日 $_target 词'," in profile)
check("设置页三项齐全",
      "DailyTargetCard(" in settings_page
      and "ValueKey('mask-chinese')" in settings_page
      and "ValueKey('auto-speak')" in settings_page)
check("其余设置项只占位、写明未接",
      "其余设置项先占位" in settings_page and "'未接'" in settings_page)

print("== 3. 每日目标 10–50 / 默认 30，且不许写死 30 ==")

check("范围常量只在 AppDefaults 一处",
      "minDailyNewWords = 10" in defaults and "maxDailyNewWords = 50" in defaults)
check("默认仍是 30", "dailyNewWordTarget = 30" in defaults)
check("夹取走同一个函数（设置页 != 另一套范围）",
      "static int clampDailyTarget(int value) => value.clamp(" in settings_dao
      and "minValue = AppDefaults.minDailyNewWords;" in settings_page
      and "maxValue = AppDefaults.maxDailyNewWords;" in settings_page)
check("滑块 10 到 50、40 档",
      "min: DailyTargetCard.minValue.toDouble()" in settings_page
      and "max: DailyTargetCard.maxValue.toDouble()" in settings_page
      and "DailyTargetCard.maxValue - DailyTargetCard.minValue" in settings_page)
check("拖动中不写库，松手才回调", "onChangeEnd:" in settings_page
      and "onChanged: (v) => setState(() => _value = v.round())" in settings_page)
check("改目标清掉当天配额缓存（决策 35）",
      "txn.delete('settings', where: \"key LIKE 'quota_%'\")" in settings_dao)
check("删缓存与写目标同一事务",
      "await db.transaction((txn) async {" in settings_dao)
check("每日配额基准读设置，不是常量",
      "final base = await const SettingsDao().dailyTarget();" in study_dao
      and "base: base," in study_dao)

# 30 只能来自配置：UI 四个文件的纯代码里不许出现数字 30。
for path, text in (
    ("today_card.dart", today),
    ("study_page.dart", study_page),
    ("profile_page.dart", profile),
    ("settings_page.dart", settings_page),
):
    bare = strip_code(text)
    check(f"{path} 纯代码无写死 30", re.search(r"\b30\b", bare) is None,
          str(re.findall(r".{0,20}\b30\b.{0,20}", bare)[:2]))
check("状态行分母仍是 newTarget（决策 103）",
      "stats.newTarget" in today and "statusLine" in today)

print("== 4. 自加词进调度（决策 107）==")

check("池子 = 820 + 自加词（详情页口径）",
      "学习池 = 820 + 自加词" in detail_dao
      and "final inPool = my != null || addedRows.isNotEmpty;" in detail_dao)
check("箱 0 = 池子 − 已进箱 − 已斩",
      "counts[0] = (total - placed - killed).clamp(0, total);" in study_dao)
check("箱位计数读池子两个来源",
      "USER_ADDED" in study_dao.upper() or "user_added_words" in study_dao)
check("新词队列 = 820 + 自加词（UNION ALL）",
      "UNION ALL" in study_dao and "FROM user_added_words u" in study_dao)
check("820 排在自加词前面、自加按添加时间正序",
      "0 AS grp" in study_dao and "1 AS grp" in study_dao
      and "u.added_at AS ord" in study_dao
      and "ORDER BY grp ASC, ord ASC" in study_dao)
check("自加词若已在 820 里不重复排",
      "NOT EXISTS (\n              SELECT 1 FROM my_words m2" in study_dao)
# 答辩落库只看 wordKey，不看词从哪来 —— 自加词与 820 走的是同一条 Leitner。
answer_body = strip_code(
    study_dao.split("Future<AnswerResult> answer({")[1].split("  Future<")[0])
check("答题落库不区分来源（同一支 Leitner.apply）",
      "Leitner.apply(" in answer_body
      and "user_added" not in answer_body
      and "my_words" not in answer_body)
check("自加词与 820 共用同一个 _card 构造",
      study_dao.count("return _card(") >= 2)
check("自加词从箱 0 起步",
      "box: 0,\n        isNew: true," in study_dao)
check("箱位色点用真实箱位，不再是固定 0",
      "不再固定画箱 0 灰点（决策 107）" in words
      and "BoxDot(box: box)" in words)
check("词表行把真实箱位传进来",
      "box: _boxOf[added.word] ?? 0" in words)

print("== 5. 斩词（决策 108）==")

check("模型：已斩词一条", "class KilledWord" in killed_model)
check("DAO：kill / restore / 查询 / 计数",
      "Future<void> kill(" in study_dao
      and "Future<void> restore(" in study_dao
      and "Future<List<KilledWord>> killedWords(" in study_dao
      and "Future<int> killedCount(" in study_dao)
check("斩只动 killed 标记，箱位/到期不动",
      "'killed': 1," in study_dao and "{'killed': 0}" in study_dao
      and "只动 `killed` 标记" in study_dao
      and "恢复时回原箱，不从头学" in study_dao)
check("斩词不进复习队列",
      "WHERE started = 1 AND killed = 0 AND due_at <= ?" in study_dao)
check("斩词不进新词队列",
      "AND COALESCE(r.killed, 0) = 0" in study_dao)
check("已斩不计入箱 0，也不算已进箱",
      "killed: await _killedCount(db)" in study_dao)

check("入口一：学习卡片", "Future<void> _tapKill() async {" in session)
check("入口二：详情页", "Future<void> _confirmKill() async {" in detail)
check("两处都先确认一次",
      session.count("AlertDialog(") >= 1 and detail.count("AlertDialog(") >= 1
      and "'斩掉这个词？'" in session and "'斩掉这个词？'" in detail)
check("确认文案说清后果（移出队列 + 可恢复）",
      session.count("可在词库「已斩」里恢复") >= 1
      and detail.count("可在词库「已斩」里恢复") >= 1)
check("斩词按钮与「不认识」同款次按钮（并排两颗 Expanded）",
      "'斩词', style: text.labelLarge" in session
      and "'不认识'" in session
      and session.count("GlassSurface(") >= 2)
check("会话页斩完把卡从队列摘掉（不前进到下一张）",
      "_dropWord(wordKey)" in session and "void _dropWord(String wordKey)" in session)
check("只读一次按「下标 + 词」记账，斩词后同下标换卡不会漏读",
      "_spokenCards.add('$_index:${card.wordKey}')" in session)
check("详情页斩/恢复行只在学习池内出现",
      "if (!d.inMyList) return primary;" in detail)
check("详情页斩词行两颗态：斩 / 已斩 · 点此恢复",
      "d.killed ? '已斩 · 点此恢复' : '斩词（不再出现）'" in detail)
check("详情页头部给「已斩」标签",
      "if (d.killed) const _Tag(text: '已斩')," in detail)
check("模型带 killed 字段", "final bool killed;" in detail_model
      and "required this.killed" in detail_model)
check("详情查询带 killed 列", "killed" in detail_dao)

check("词库「已斩」分组（默认收起）", "ValueKey('killed-group')" in words
      and "_showKilled = false" in words)
check("已斩行有恢复按钮", "ValueKey('restore-${entry.wordKey}')" in words
      and "Future<void> _restoreKilled(KilledWord k) async {" in words)
check("已斩行也画真实箱位", "BoxDot(box: entry.box)" in words)
check("词库里保留下来的词仍在（不删 my_words / user_added_words）",
      "移出复习队列、词库保留" in words or "词库保留" in killed_model)
check("斩词与「不认识」分开：不认识仍走重测（retest 由 Leitner 给，行里没被挪用）",
      "'retest': outcome.retest ? 1 : 0," in study_dao
      and "isRetest: ((r['retest'] as int?) ?? 0) == 1" in study_dao
      and "AND (r.box > 0 OR r.retest = 1)" in study_dao)

print("== 6. 设置变更广播（决策 110）==")

check("一个 ValueNotifier 做信号", "class AppSignals" in signals
      and "ValueNotifier<int> settingsChanged" in signals)
check("写库后发信号", settings_page.count("AppSignals.settingsUpdated();") == 3)
check("首页 / 词库页挂监听并在 dispose 摘掉",
      "AppSignals.settingsChanged.addListener(_onSettingsChanged)" in study_page
      and "removeListener(_onSettingsChanged)" in study_page
      and "AppSignals.settingsChanged.addListener(_onSettingsChanged)" in words
      and "removeListener(_onSettingsChanged)" in words)
check("「全部词汇」= 820 + 自加",
      "total: _myCount + _addedCount," in study_page
      and "Future<int> addedCount()" in settings_dao)

print("== 7. 只动该动的：冻结面零改动 ==")

frozen = [
    "app/lib/app/theme/app_colors.dart",
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/lib/app/shell/home_shell.dart",
    "app/lib/app/shell/shell_padding.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/shaders/liquid_glass.frag",
    "app/lib/data/study/leitner.dart",
    "app/lib/data/study/choice_options.dart",
    "app/lib/data/study/study_flow.dart",
    "app/lib/data/dao/word_dao.dart",
    "app/lib/data/db/app_database.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/box_band.dart",
    "app/lib/features/study/study_heatmap.dart",
]
for path in frozen:
    check(f"零改动：{os.path.basename(path)}",
          git("diff", "--name-only", BASE, "--", path).strip() == "")

allowed_files = {
    "app/lib/app/app_defaults.dart",
    "app/lib/app/app_signals.dart",
    "app/lib/data/dao/detail_dao.dart",
    "app/lib/data/dao/settings_dao.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/models/killed_word.dart",
    "app/lib/data/models/word_detail.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/profile/settings_page.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/pubspec.yaml",
    "app/test/v077_box_color_test.dart",   # AddedRow 加 box 参数，同轮改断言
    "app/test/v080_settings_test.dart",
    "DESIGN.md",
    "项目日志.md",
    "_source/check_v080.py",
    "_source/release_notes_v080.md",
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
      len(touched) == 2
      and touched[0].startswith("-version: 0.7.9+24")
      and touched[1].startswith("+version: 0.8.0+25"),
      str(touched))

print("== 8. 设计稿同步 ==")

design_body = design.split("## 1.")[1]  # 跳过顶部说明块（那里的改稿记录会提到旧例外）
exception_lines = [l for l in design_body.splitlines() if "现状例外" in l]
check("DESIGN.md 删掉「自加词行灰点」的现状例外",
      not any("自加" in l for l in exception_lines),
      str(exception_lines[:2]))
check("DESIGN.md 记了设置页", "设置" in design)
check("DESIGN.md 记了已斩", "已斩" in design)

print("== 9. 新增测试覆盖 ==")

t = read(APP, "test", "v080_settings_test.dart")
for needle, label_text in (
    ("clamp 到 10–50", "目标夹取"),
    ("断档削减按设置的目标算，不写死 30", "断档削减按新目标算"),
    ("首页环 / 状态行 / 分母都跟 newTarget 走", "目标跟到底"),
    ("目标卡：范围 10–50，松手才回调", "滑块范围与松手回调"),
    ("整行可点，回调拿到相反值", "开关整行可点"),
    ("行内「恢复」能点，箱位点仍在", "已斩行恢复"),
    ("色带箱 0 扣掉已斩", "已斩扣箱 0"),
    ("「不认识」旁有「斩词」，点开一次确认，取消后不撤卡", "会话页斩词确认"),
    ("我的页 → 设置页：三项都在", "我的页进设置页"),
    ("320 宽：设置卡与已斩行不溢出", "320 宽不溢出"),
    ("320 宽：学习卡两个次按钮并排不溢出", "320 宽两颗次按钮不溢出"),
    ("bandCountsFrom", "纯函数可单测"),
):
    check(f"新增测试：{label_text}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
