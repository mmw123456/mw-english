"""v0.14.0 验收：学习统计（五块、每个数追得到查询、缺数据不补数、已掌握口径统一）。

跑法：python _source/check_v140.py

主线（取自需求原文与用户给的两条拍板，不从实现里抄）：
1. 入口在我的 Tab：一行「学习统计」→ 整页 StatsPage，不占新 Tab、不动学习/词库/阅读
2. 先核查再动手：库里能支撑统计的表 = daily_stat（v0.7.4）/ spelling_round（v0.13.0）/
   study_record；**不新建表**（按日学习量本来就有表），schema 仍 8
3. 页面只做五块：今日 / 累计 / 箱 0–6 分布 / 最近 7·30 天趋势 / 拼写
4. 每个数字都能追到一条查询；页面里不许出现 SQL
5. 缺数据一律「暂无数据」/「—」，不补 0、不编历史、没记录的日子不画柱
6. 已掌握口径统一到 `Mastery`（box ≥5 或 streak ≥3，且未斩），四处同一个数
7. 箱 0–6 只算未斩：七段之和 = 未斩词数，另起一行显「已斩 N」
8. 本版不做：语境填空 / 外刊 / 改六箱 / 改拼写 / 改每日目标 / 新图表依赖
9. 版本：0.14.0 / +31；我的页 0.14.0 (2031)
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "a91fe05"  # v0.13.0 代码提交（日志记阶段 6.18，收尾修正在内）

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


def code_only(src):
    """去掉注释行：文档里会说「不写 study_record」「box >= 5」这类词，不能当代码断言。"""
    return "\n".join(
        line for line in src.splitlines()
        if not line.lstrip().startswith("//")
    )


pub = read(APP, "pubspec.yaml")
profile = read(LIB, "features", "profile", "profile_page.dart")
page = read(LIB, "features", "stats", "stats_page.dart")
dao = read(LIB, "data", "dao", "stats_dao.dart")
snap = read(LIB, "data", "stats", "stats_snapshot.dart")
mastery = read(LIB, "data", "study", "mastery.dart")
study_dao = read(LIB, "data", "dao", "study_dao.dart")
picker = read(LIB, "data", "article", "word_picker.dart")
app_db = read(LIB, "data", "db", "app_database.dart")
design = read("DESIGN.md")
test_v014 = read(APP, "test", "v014_stats_test.dart")

print("== 1. 版本行 ==")
check("pubspec 版本 0.14.0+31", "version: 0.14.0+31" in pub, pub.splitlines()[4])
check("我的页显示 0.14.0 (2031)", "const base = '0.14.0 (2031)';" in profile)
check("版本号两处一致（+31 → 2031）", "+31" in pub and "(2031)" in profile)

print("== 2. 入口：我的 Tab 一行，整页，不占新 Tab ==")
check("我的页有「学习统计」", "title: '学习统计'," in profile)
check("我的页 import 了统计页", "import '../stats/stats_page.dart';" in profile)
check("入口点了进整页", "_Tile(" in profile and "onTap: _openStats," in profile)
check("跳转写的是 StatsPage()",
      "Future<void> _openStats() async {" in profile
      and "builder: (_) => const StatsPage()" in profile)
check("StatsPage 是整页 Scaffold",
      "class StatsPage extends StatefulWidget {" in page
      and "Scaffold(" in page
      and "AppBar(title: const Text('学习统计'))" in page)
check("不是弹窗", "showDialog" not in page and "showModalBottomSheet" not in page)

print("== 3. 页面只做五块 ==")
check("今日块", "title: '今日'" in page)
check("累计块", "title: '累计'" in page)
check("箱 0–6 分布块（不写「六箱分布」）",
      "title: '箱 0–6 分布'" in page and "六箱分布" not in page)
check("分布下方注明箱 0 是新词",
      "箱 0 = 新词（还没进调度）" in page and "箱 1–6 = 调度箱" in page)
check("趋势两档可切", "Key('stats-range-$days')" in page
      and "days: 7," in page and "days: 30," in page)
check("趋势标题跟档位走", "title: '最近 $range 天'" in page)
check("拼写块", "title: '拼写'" in page and "'累计正确率（共 ${snap.spellAllTotal} 题）'" in page)
check("拼写最近 7 天", "'最近 7 天（共 ${snap.spell7Total} 题）'" in page)
check("四个数用 2×2 网格", "class _Grid extends StatelessWidget {" in page)

print("== 4. 每个数字追得到一条查询，页面不查库 ==")
check("页面里没有 SQL", "SELECT" not in code_only(page) and "rawQuery" not in page)
check("学习量读 daily_stat", "FROM daily_stat" in dao)
check("拼写读 spelling_round", "FROM spelling_round" in dao)
check("已掌握 / 箱位读 study_record", "study_record" in dao)
check("学习天数 = COUNT(DISTINCT day)", "SELECT COUNT(DISTINCT day) FROM daily_stat" in dao)
check("今日与趋势复用 StudyDao.dailyTotals", "_study.dailyTotals(" in dao)
check("连续打卡复用 StudyDao.studyStreak", "_study.studyStreak(now: n)" in dao)
check("来源表写在快照文档里（好追）",
      all(f"`{t}`" in snap for t in ("daily_stat", "spelling_round", "study_record")))
check("没有新建表（schema 仍 8）", "static const int _schemaVersion = 8;" in app_db)
check("没有为统计加新表语句", "CREATE TABLE IF NOT EXISTS stats" not in app_db)

print("== 5. 已掌握口径统一（决策 117 + 128）==")
check("门槛只在 mastery.dart", "static const int boxCut = 5;" in mastery
      and "static const int streakCut = 3;" in mastery)
check("Dart 判定 Mastery.of", "static bool of(int box, int streak) => box >= boxCut || streak >= streakCut;"
      in mastery)
check("SQL 片段带未斩与已开学",
      "started = 1 AND killed = 0 AND" in mastery and "box >= $boxCut OR streak >= $streakCut" in mastery)
check("学习页 / 我的页用同一段 SQL", "${Mastery.sqlWhere}" in study_dao)
check("统计页用同一段 SQL", "${Mastery.sqlWhere}" in dao)
check("文章取词用同一个函数", "Mastery.of(box, streak)" in picker)
check("旧的单独门槛已删（study_dao 里没有 box >= ?）",
      "AND box >= ?" not in code_only(study_dao))

offenders = []
for dirpath, _dirs, files in os.walk(LIB):
    for name in files:
        if not name.endswith(".dart"):
            continue
        path = os.path.join(dirpath, name)
        if os.path.normpath(path).endswith(os.path.join("data", "study", "mastery.dart")):
            continue
        body = code_only(open(path, encoding="utf-8").read())
        if "box >= 5" in body or "streak >= 3" in body:
            offenders.append(os.path.relpath(path, ROOT))
check("全库只有 mastery.dart 写字面门槛", not offenders, str(offenders))

print("== 6. 缺数据不补数 ==")
check("快照能判「一条历史都没有」", "bool get noHistory" in snap)
check("无历史写「从今天起开始记录」", "'从今天起开始记录'" in page)
check("有历史但空档另写一句", "'最近 $range 天没有学习记录'" in page)
check("没记录的天不画柱（只留 1px 底）",
      "if (data == null || maxCount <= 0)" in page and "height: 1," in page)
check("拼写没记录写「暂无数据」", "'暂无数据'" in page)
check("正确率 0 题显「—」而不是 0%",
      "percent == null ? '—' : '$percent%'" in page)
check("快照里 0 题返回 null（与拼写页同一函数）",
      "SpellingStats.percentOf(" in snap)

print("== 7. 箱 0–6 只算未斩，合计对得上 ==")
check("七段从学习池 LEFT JOIN 出来", "LEFT JOIN study_record r ON r.word_key = p.word_key" in dao)
check("已斩不进任何一段", "COALESCE(r.killed, 0) = 0" in dao)
check("学习池 = 820 ∪ 自加词（UNION 去重）",
      "SELECT word_key FROM my_words UNION SELECT word_key FROM user_added_words" in dao)
check("七行按箱位循环渲染", "for (var box = 0; box < snap.boxes.length; box++)" in page)
check("合计行写「未斩」与「已斩」",
      "'合计 ${snap.boxSum} 词（未斩）· 已斩 ${snap.killed} · '" in page)
check("快照给出不变量说明", "boxSum + killed == poolTotal" in snap)
check("已斩数只算池里的词", "JOIN study_record r ON r.word_key = p.word_key" in dao
      and "WHERE r.killed = 1" in dao)

print("== 8. 不动调度、不加依赖 ==")
dao_code = code_only(dao)
check("统计层只有读", "INSERT" not in dao_code.upper()
      and "UPDATE " not in dao_code.upper() and "DELETE" not in dao_code.upper())
check("没有写学习表", "insert(" not in dao_code and "rawInsert" not in dao_code)
check("没有写拼写表", "spelling_round'" not in dao_code.replace("FROM spelling_round", ""))
for pkg in ("fl_chart", "syncfusion", "charts_flutter", "graphic", "fl_heatmap"):
    check(f"没引图表包 {pkg}", pkg not in pub)

print("== 9. 本版不做 ==")
scope = page + dao + snap + mastery
for word, label in [
    ("语境填空", "语境填空"),
    ("外刊", "外刊"),
]:
    check(f"未做：{label}", word not in scope)
check("没改每日目标（AppDefaults 不在改动面）", True)

print("== 10. 冻结面零改动 ==")

frozen = [
    # 主题与公共控件
    "app/lib/app/theme/app_colors.dart",
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/lib/app/widgets/example_line.dart",
    "app/lib/app/widgets/press_scale.dart",
    "app/lib/app/widgets/rolling_int.dart",
    "app/lib/app/widgets/search_capsule.dart",
    # 外壳
    "app/lib/app/app.dart",
    "app/lib/app/app_defaults.dart",
    "app/lib/app/app_signals.dart",
    "app/lib/app/shell/home_shell.dart",
    "app/lib/app/shell/shell_padding.dart",
    "app/lib/app/shell/spring_page_physics.dart",
    "app/lib/main.dart",
    # 调度与题目（统计只读，不改）
    "app/lib/data/study/leitner.dart",
    "app/lib/data/study/choice_options.dart",
    "app/lib/data/study/study_flow.dart",
    "app/lib/data/study/near_words.dart",
    "app/lib/data/study/word_lexicon.dart",
    "app/lib/data/dao/word_dao.dart",
    "app/lib/data/dao/settings_dao.dart",
    "app/lib/data/dao/detail_dao.dart",
    "app/lib/data/dao/import_dao.dart",
    "app/lib/data/dao/article_dao.dart",
    "app/lib/data/models/study_card.dart",
    "app/lib/data/models/word_detail.dart",
    "app/lib/data/models/word_entry.dart",
    "app/lib/data/models/word_example.dart",
    "app/lib/data/models/article.dart",
    "app/lib/data/models/killed_word.dart",
    # 学习会话与首页其余块
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/study/box_band.dart",
    "app/lib/features/study/study_page.dart",
    # 词库 / 详情 / 查词
    "app/lib/features/words/words_page.dart",
    "app/lib/features/words/import_page.dart",
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/features/lookup/lookup_page.dart",
    "app/lib/features/lookup/lookup_result_card.dart",
    "app/lib/data/lookup/lookup_service.dart",
    "app/lib/data/examples/example_bank.dart",
    # 阅读 / 文章 / 设置
    "app/lib/features/reading/reading_page.dart",
    "app/lib/features/reading/article_page.dart",
    "app/lib/features/profile/settings_page.dart",
    "app/lib/features/profile/deepseek_key_card.dart",
    "app/lib/data/article/article_check.dart",
    "app/lib/data/article/article_metrics.dart",
    "app/lib/data/article/article_parser.dart",
    "app/lib/data/article/article_prompt.dart",
    "app/lib/data/article/article_service.dart",
    "app/lib/data/article/rare_words.dart",
    "app/lib/data/llm/deepseek_client.dart",
    "app/lib/data/llm/secret_store.dart",
    "app/lib/data/tts/article_reader.dart",
    "app/lib/data/tts/speech.dart",
    "app/lib/data/morphology/root_whitelist.dart",
    # 导入
    "app/lib/data/import/document_readers.dart",
    "app/lib/data/import/import_service.dart",
    "app/lib/data/import/pdfium_ffi.dart",
    "app/lib/data/import/word_list_parser.dart",
    # v0.13.0 新增（v0.14.0 起冻结：本版不许改拼写）
    "app/lib/data/spelling/spelling_round.dart",
    "app/lib/data/dao/spelling_dao.dart",
    "app/lib/features/spelling/spelling_page.dart",
]
changed = set(
    line for line in git("diff", "--name-only", BASE).splitlines() if line.strip()
)
for path in frozen:
    check(f"冻结：{os.path.basename(path)}", path not in changed, "被改动")

print("== 11. 影响面白名单 ==")

allowed = {
    "app/pubspec.yaml",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/article/word_picker.dart",
    "DESIGN.md",
    "项目日志.md",
    "_source/check_v140.py",
    "_source/release_notes_v140.md",
    "app/test/v072_shell_test.dart",  # 我的页多一行，版本行被推到折叠线以下
}
new_files = {
    "app/lib/data/study/mastery.dart",
    "app/lib/data/stats/stats_snapshot.dart",
    "app/lib/data/dao/stats_dao.dart",
    "app/lib/features/stats/stats_page.dart",
    "app/test/v014_stats_test.dart",
}
removed = set(
    line for line in git("diff", "--name-only", "--diff-filter=D", BASE).splitlines()
    if line.strip()
)
unexpected = changed - allowed - new_files - removed
check("改动文件都在白名单或新增清单里", not unexpected, str(sorted(unexpected)))
check("没有删文件", not removed, str(sorted(removed)))

print("== 12. 设计稿同步 ==")
check("DESIGN 标题已是 v0.14.0", "已按 v0.14.0 代码核对" in design)
check("新增 §12 学习统计", "## 12. 学习统计（v0.14.0 已发布，versionCode 2031，arm64）" in design)
check("§12.1 入口与五块", "### 12.1 入口与五块" in design)
check("§12.2 每个数的来源", "### 12.2 每个数的来源（写死，页面不自己算）" in design)
check("§12.3 缺数据怎么显示", "### 12.3 缺数据怎么显示（不许补数）" in design)
check("§12.4 已掌握口径统一", "### 12.4 已掌握口径统一（决策 128）" in design)
check("§12.5 本版不做", "### 12.5 本版不做" in design)
check("五块都在稿里",
      all(s in design for s in ("**今日**", "**累计**", "**箱 0–6 分布**",
                                "**最近 7 天 / 30 天趋势**", "**拼写**")))
check("来源表逐张在稿里",
      all(f"`{t}`" in design for t in ("daily_stat", "spelling_round", "study_record")))
check("后续章节顺延（布局 13 / 渲染 14 / 门禁 15）",
      "## 13. 布局规则" in design and "## 14. 渲染验收" in design
      and "## 15. 常规验收门禁" in design)
check("5.4 补了 0.14.0", "0.14.0（`0.14.0+31` → 2031 / 1031 / 4031）" in design)
check("门禁节写了 check_v140", "check_v140.py" in design)
check("门禁节写了 438", "438 passed" in design)
check("渲染验收补了 v0.14.0 待验", "v0.14.0 **6 项**" in design)
check("稿里写明不新建表", "本版**没有新建表**" in design)

print("== 13. 测试覆盖（需求点名的验收用例）==")
for needle, label in [
    ("SQL 片段与 Dart 判定用同一组门槛", "已掌握口径与现有定义一致"),
    ("四处都走同一处口径，没人再写一遍 box >= 5", "四个地方同一个数"),
    ("七段之和 + 已斩 = 学习池（验收口径）", "七段和 = 未斩词数"),
    ("没记录的日子 total 为 null，不补 0", "没记录的日子不补数"),
    ("一条历史都没有：写「从今天起开始记录」", "无历史显「从今天起开始记录」"),
    ("拼写：没记录写「暂无数据」，有记录给累计与最近 7 天", "拼写正确率读拼写记录表"),
    ("今日四个数来自 store", "今日块数字"),
    ("箱 0–6 七行都显数字，含合计与已斩", "箱 0–6 七个数"),
    ("320 宽 + 真实字体：七行分布与 30 天档都不溢出", "320 宽版式"),
]:
    check(f"测试覆盖：{label}", needle in test_v014)

print()
print(f"  {passed} PASS / {failed} FAIL")
if failed:
    raise SystemExit(1)
