"""v0.13.0 验收：听音拼写（一轮拼今天的词，判定写死，不动调度）。

跑法：python _source/check_v130.py

主线（全部取自需求原文与用户给的版本号，不从实现里抄）：
1. 入口只有一颗：学习 Tab 首页「拼写练习」，点开进整页，不占新 Tab、不动认词学习流程
2. 今天没词时置灰并明说「今天没词可拼」，不进空页面
3. 一轮 = 今天新词 + 今天到期复习（跟学习会话同一批词），最多 30（跟每日目标一致）
4. 判定写死：大小写不敏感 / 前后空格去掉 / 空格归一 / 短语整串 / once (and) for all 可选 / 空输入算错
5. 判对：显示「对了」+ 正确拼写，1 秒后自动下一题；判错：正确拼写 + 音标 + 释义 + 你拼的是，不自动跳
6. 拼写不记六箱升降、不动 streak、不动每日进度（只读 study_record，不写 study_log / daily_stat）
7. 正确率只记拼写自己的：spelling_round 表 + 顶部一个累计正确率，不做图表、不做统计页
8. 版本：0.13.0 / +30；我的页 0.13.0 (2030)
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "7d2aa1e"  # v0.12.0 代码提交（日志记阶段 6.17）

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
    """去掉整行注释：文档注释里会提到「不写 study_log」这种词，不能当代码断言。"""
    return "\n".join(
        line for line in src.splitlines() if not line.lstrip().startswith("//")
    )


pub = read(APP, "pubspec.yaml")
profile = read(LIB, "features", "profile", "profile_page.dart")
study_page = read(LIB, "features", "study", "study_page.dart")
model = read(LIB, "data", "spelling", "spelling_round.dart")
dao = read(LIB, "data", "dao", "spelling_dao.dart")
page = read(LIB, "features", "spelling", "spelling_page.dart")
app_db = read(LIB, "data", "db", "app_database.dart")
design = read("DESIGN.md")
test_v013 = read(APP, "test", "v013_spelling_test.dart")

print("== 1. 版本行 ==")
check("pubspec 版本 0.13.0+30", "version: 0.13.0+30" in pub, pub.splitlines()[4])
check("我的页显示 0.13.0 (2030)", "const base = '0.13.0 (2030)';" in profile)
check("版本号两处一致（+30 → 2030）", "+30" in pub and "(2030)" in profile)

print("== 2. 入口：首页一颗，整页，不占新 Tab ==")
check("首页有拼写入口组件", "class SpellingLink extends StatelessWidget {" in study_page)
check("入口有固定 key", "key: const ValueKey('spelling-link')," in study_page)
check("首页渲染了入口", "SpellingLink(" in study_page and "count: _loading ? -1 : _spellCount," in study_page)
check("有词报数量", "return count == 0 ? '今天没词可拼' : '拼写练习 · 今天 $count 词';" in study_page)
check("今天没词明说「今天没词可拼」", "'今天没词可拼'" in study_page)
check("没词时不进页面（onTap 置空 + 函数体早退）",
      "onTap: _loading || _spellCount <= 0 ? null : _openSpelling," in study_page
      and "if (_spellCount <= 0) return;" in study_page)
check("点开是整页 SpellingPage",
      "Future<void> _openSpelling() async {" in study_page
      and "builder: (_) => const SpellingPage()" in study_page)
check("入口不是玻璃（首页只留一个玻璃控件）",
      "GlassSurface" not in study_page.split("class SpellingLink")[1])
check("题数读的是同一套口径", "_spelling.countToday()," in study_page)
check("SpellingPage 是整页 Scaffold",
      "class SpellingPage extends StatefulWidget {" in page
      and "Scaffold(" in page and "AppBar(title: const Text('拼写练习'))" in page)
check("一轮最多 = 当日目标（cap 来自 quota.newWords）",
      "final quota = await _study.dailyQuota(now: n);" in dao
      and "cap: quota.newWords," in dao)

print("== 3. 判定规矩（写死）==")
check("判定只有一处：SpellingJudge", "abstract final class SpellingJudge {" in model)
check("归一化：去首尾空白 + 压空格 + 转小写",
      "raw.trim().replaceAll(_spaces, ' ').toLowerCase();" in model)
check("大小写不敏感（归一化里转小写）", ".toLowerCase();" in model)
check("括号注释可有可无（三种写法）",
      "static List<String> acceptedForms(String answer) {" in model
      and "forms.add(_squeeze(base.replaceAll(_openParen, ' ').replaceAll(_closeParen, ' ')));"
      in model
      and "forms.add(_squeeze(base.replaceAll(_parenthetical, ' ')));" in model)
check("短语整串判：不按空格拆",
      "split(" not in model.split("acceptedForms")[1].split("static bool isCorrect")[0])
check("空输入一律算错", "if (given.isEmpty) return false;" in model)
check("页面不自己比字符串（只调 Judge）",
      "SpellingJudge.isCorrect(raw, item.word)" in page
      and "toLowerCase()" not in page)
check("念出来时去掉括号、保留里面的词",
      "String get spoken => SpellingJudge.spokenForm(word);" in model
      and "replaceAll('(', ' ').replaceAll(')', ' ')" in model)

print("== 4. 每题流程 ==")
check("与学习页同一套 TTS（Speech.speak）",
      "widget.speak ?? Speech.speak;" in page)
check("有重听按钮", "key: const ValueKey('spelling-replay')," in page)
check("重听不限次数、不扣分（不记次数、不进成绩）",
      "重听不限次数，不扣分" in page and "replayCount" not in page)
check("输入框可回车提交",
      "key: const ValueKey('spelling-input')," in page
      and "onSubmitted: (_) => _submit()," in page)
check("提交按钮", "key: const ValueKey('spelling-submit')," in page)
check("判对：显示对了 + 正确拼写",
      "'对了'" in page and "key: const ValueKey('spelling-answer')," in page)
check("判对 1 秒后自动下一题", "static const Duration autoAdvance = Duration(seconds: 1);" in page
      and "_advance = Timer(SpellingPage.autoAdvance, _next);" in page)
check("判对也能手动下一题", "key: const ValueKey('spelling-next')," in page
      and "onPressed: onNext," in page)
check("只有判对才起自动跳转的定时器",
      "if (attempt.correct) {" in page
      and page.index("if (attempt.correct) {") < page.index("_advance = Timer("))
check("判错：正确拼写 + 音标 + 释义 + 你拼的是",
      "key: const ValueKey('spelling-phonetic')," in page
      and "key: const ValueKey('spelling-meaning')," in page
      and "key: const ValueKey('spelling-yours')," in page
      and "'你拼的是 ${attempt.input}'" in page)
check("判错不自动跳（不判对就不起 timer）",
      "if (!ok) ...[" in page)

print("== 5. 一轮怎么组 ==")
check("组轮函数在纯函数层", "static List<SpellingItem> compose({" in model)
check("顺序：今天已学的新词 → 队列 → 到期复习",
      "for (final batch in [learnedToday, queued, due]) {" in model)
check("按 wordKey 去重", "if (key.isEmpty || !seen.add(key)) continue;" in model)
check("截到 cap", "if (out.length >= cap) return out;" in model)
check("今天已学的新词也算今天的词",
      "WHERE killed = 0 AND started = 1 AND first_seen_at >= ? AND first_seen_at < ? "
      in dao)
check("到期复习的取词口径与学习会话一致",
      "AND (box > 0 OR retest = 1) " in dao)
check("新词队列 820 在前、自加按 added_at",
      "ORDER BY grp ASC, ord ASC LIMIT ?" in dao)
check("自加词对 words 走 LEFT JOIN", "LEFT JOIN words w ON w.word = u.word_key" in dao)

print("== 6. 不动调度（硬规矩）==")
dao_code = code_only(dao)
page_code = code_only(page)
model_code = code_only(model)
check("拼写层没有写 study_record", "insert('study_record'" not in dao_code
      and "update('study_record'" not in dao_code)
check("拼写层一次都没提 study_log", "study_log" not in dao_code)
check("拼写层一次都没提 daily_stat", "daily_stat" not in dao_code)
check("拼写层不写任何 study 表",
      "INSERT INTO study" not in dao_code and "UPDATE study" not in dao_code
      and "DELETE FROM study" not in dao_code)
check("页面不碰 StudyDao / Leitner / answer",
      "StudyDao" not in page_code and "Leitner" not in page_code
      and ".answer(" not in page_code)
check("模型层不碰 Leitner", "Leitner" not in model_code)
check("唯一写入是拼写自己的表",
      "insert('spelling_round'" in dao_code)
check("只读配额，不改配额口径", "dailyQuota(now: n)" in dao_code)

print("== 7. 正确率统计 ==")
check("schema 8", "static const int _schemaVersion = 8;" in app_db)
check("新建 spelling_round（日期 / 题数 / 对数）",
      "CREATE TABLE IF NOT EXISTS spelling_round(" in app_db
      and "day     TEXT NOT NULL," in app_db
      and "total   INTEGER NOT NULL," in app_db
      and "correct INTEGER NOT NULL," in app_db)
check("累计正确率 = SUM(correct)/SUM(total)",
      "COALESCE(SUM(correct), 0) AS correct FROM spelling_round" in dao)
check("一题都没拼时不算 0%",
      "if (total <= 0) return null;" in model
      and "'累计正确率：还没有拼写记录'" in page)
check("顶部只有一行累计正确率", "key: const ValueKey('spelling-accuracy')," in page
      and "累计正确率 $percent% · ${stats.rounds} 轮 ${stats.total} 题" in page)
check("不做图表（页面里没有图表控件）",
      "Chart" not in page and "CustomPaint" not in page)
check("一轮只记一笔", "if (_saved || _attempts.isEmpty) return;" in page)
check("半途退出不记（只在收尾时存）",
      "setState(() => _finished = true);" in page
      and page.index("void _finish()") < page.index("Future<void> _save()"))

print("== 8. 小结 ==")
check("小结是页内一块（不是弹窗）", "class SpellingSummary extends StatelessWidget {" in page
      and "showDialog" not in page)
check("对了几题 / 共几题", "'对了 $correct 题 / 共 $total 题'," in page)
check("正确率", "'正确率 $percent%'," in page)
check("错词清单", "'错词 ${misses.length} 个'" in page)
check("错词行：错拼 → 正确 + 音标 + 释义",
      "key: ValueKey('spelling-wrong-${item.wordKey}')," in page
      and "attempt.input.isEmpty" in page)
check("点错词进词条详情页",
      "final ValueChanged<SpellingItem> onOpenWord;" in page
      and "builder: (_) => WordDetailPage(" in page)

print("== 9. 本版不做 ==")
scope = page + dao + model + study_page
for word, label in [
    ("语境填空", "语境填空"),
    ("例句朗读", "例句朗读"),
    ("学习统计", "学习统计页"),
    ("deepseek", "接 DeepSeek"),
]:
    check(f"未做：{label}", word not in scope.lower())
check("拼写不写六箱（代码里没有 box 写入）",
      "box =" not in dao_code and "'box'" not in dao_code)

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
    # 调度与题目（拼写不碰）
    "app/lib/data/study/leitner.dart",
    "app/lib/data/study/choice_options.dart",
    "app/lib/data/study/study_flow.dart",
    "app/lib/data/study/near_words.dart",
    "app/lib/data/study/word_lexicon.dart",
    "app/lib/data/dao/study_dao.dart",
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
    "app/lib/data/article/word_picker.dart",
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
    "app/lib/features/study/study_page.dart",
    "app/lib/data/db/app_database.dart",
    "DESIGN.md",
    "项目日志.md",
    "_source/check_v130.py",
    "_source/release_notes_v130.md",
}
new_files = {
    "app/lib/data/spelling/spelling_round.dart",
    "app/lib/data/dao/spelling_dao.dart",
    "app/lib/features/spelling/spelling_page.dart",
    "app/test/v013_spelling_test.dart",
}
removed = set(
    line for line in git("diff", "--name-only", "--diff-filter=D", BASE).splitlines()
    if line.strip()
)
unexpected = changed - allowed - new_files - removed
check("改动文件都在白名单或新增清单里", not unexpected, str(sorted(unexpected)))
check("没有删文件", not removed, str(sorted(removed)))

print("== 12. 设计稿同步 ==")
check("DESIGN 标题已是 v0.13.0", "已按 v0.13.0 代码核对" in design)
check("新增 §11 听音拼写", "## 11. 听音拼写（v0.13.0 已发布，versionCode 2030，arm64）" in design)
check("§11.1 入口与流程", "### 11.1 入口与流程" in design)
check("§11.2 判定规矩", "### 11.2 判定规矩（写死）" in design)
check("§11.3 不动调度", "### 11.3 不动调度（写死）" in design)
check("§11.4 正确率口径", "### 11.4 正确率口径" in design)
check("§11.5 本版不做", "### 11.5 本版不做" in design)
check("判定规矩表格逐条在稿里",
      all(s in design for s in ("大小写不敏感", "多个空格算一个", "短语整串判",
                                "括号注释可选", "空输入算错")))
check("后续章节顺延（布局 12 / 渲染 13 / 门禁 14）",
      "## 12. 布局规则" in design and "## 13. 渲染验收" in design
      and "## 14. 常规验收门禁" in design)
check("5.4 补了 0.13.0", "0.13.0（`0.13.0+30` → 2030 / 1030 / 4030）" in design)
check("门禁节写了 412", "412 passed" in design)
check("门禁节写了 check_v130", "check_v130.py" in design)
check("渲染验收补了 v0.13.0 待验", "v0.13.0 **5 项**" in design)

print("== 13. 测试覆盖（需求点名的验收用例）==")
for needle, label in [
    ("大小写不敏感", "大小写不敏感"),
    ("前后空格不算错，中间多个空格算一个", "前后空格 / 空格归一"),
    ("短语整串判，不拆词", "短语整串判"),
    ("once (and) for all 的 (and) 可有可无", "once (and) for all 两种写法都对"),
    ("判错：正确拼写 + 音标 + 释义 + 你拼的是，且不自动跳", "判错显示拼写/音标/释义"),
    ("页面与数据层没有写学习数据的语句", "拼写不改箱位/streak/每日进度"),
    ("今天没词：置灰且点不动", "今天没词时入口置灰"),
    ("重听不限次数、不扣分，答对照样算对", "重听不扣分"),
]:
    check(f"测试覆盖：{label}", needle in test_v013)

print()
print(f"  {passed} PASS / {failed} FAIL")
if failed:
    raise SystemExit(1)
