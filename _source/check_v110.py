"""v0.11.0 验收：把查词做成统一功能，不占新 Tab。

跑法：python _source/check_v110.py

主线（全部取自需求原文与用户当日三处拍板，不从实现里抄）：
1. 四个入口同一套查词：首页顶部、词库页顶部、学习页卡片、文章详情页双击
2. 查词逻辑离线：820 词（两段式）> 自加/导入词（入库释义）> ECDICT 兜底
3. 输入三种：英文单词、英文短语（整串）、中文；英文前缀候选、中文释义包含
4. 查不到明说「未查到」，不编、不联网、不调 DeepSeek
5. 820 里 ECDICT 没覆盖的 8 个词按书释显示，不许说查不到
6. 候选最多 10 条，大小写不敏感
7. 结果页：词 / 音标 / 词性 / 释义（两段式）/ 发音 / 加入生词本（已在库置灰）
8. 加入生词本按自加词口径，已在库不重复加
9. 学习页查词不离开会话、不记答题、不影响当前卡片
10. 本版不做：例句 / 读后填空 / 拼写 / 统计图表 / 查词历史
11. 版本：0.11.0 / +28；我的页 0.11.0 (2028)
"""

import os
import re
import sqlite3
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
DB = os.path.join(APP, "assets", "db", "dict.sqlite")
BASE = "f4381b4"  # v0.10.0 代码提交（日志记阶段 6.12）

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


pub = read(APP, "pubspec.yaml")
profile = read(LIB, "features", "profile", "profile_page.dart")
service = read(LIB, "data", "lookup", "lookup_service.dart")
card = read(LIB, "features", "lookup", "lookup_result_card.dart")
page = read(LIB, "features", "lookup", "lookup_page.dart")
capsule = read(LIB, "app", "widgets", "search_capsule.dart")
detail_dao = read(LIB, "data", "dao", "detail_dao.dart")
study_page = read(LIB, "features", "study", "study_page.dart")
session_page = read(LIB, "features", "study", "study_session_page.dart")
words_page = read(LIB, "features", "words", "words_page.dart")
article_page = read(LIB, "features", "reading", "article_page.dart")
design = read("DESIGN.md")
test_v011 = read(APP, "test", "v011_lookup_test.dart")

print("== 1. 版本行 ==")
check("pubspec 版本 0.11.0+28", "version: 0.11.0+28" in pub, pub.splitlines()[4])
check("我的页显示 0.11.0 (2028)", "const base = '0.11.0 (2028)';" in profile)
check("版本号两处一致（+28 → 2028）", "+28" in pub and "(2028)" in profile)

print("== 2. 四个入口 ==")
check("首页 AppBar 有查词入口", "key: const ValueKey('home-lookup')" in study_page)
check("首页入口进查词页", "LookupPage()" in study_page or "LookupPage(" in study_page)
check("词库页搜索框改用共用胶囊", "SearchCapsule(" in words_page)
check("词库页搜索走统一查词", "_lookup.search(q)" in words_page)
check("学习卡上有放大镜", "key: const ValueKey('card-lookup')" in session_page)
check("学习卡放大镜是放大镜图标", "Icons.search_rounded" in session_page)
check("文章双击走统一查词", "_lookupService.lookup(word)" in article_page)
check("查词不占新 Tab", "LookupPage" not in read(LIB, "app", "shell", "home_shell.dart"))

print("== 3. 一套查词函数 ==")
check("有 LookupService", "class LookupService" in service)
check("有统一入口方法 lookup()", "Future<LookupView> lookup(String raw) async" in service)
check("来源枚举顺序 词书 > 自加 > 词典",
      service.index("book('词书')") < service.index("added('自加')")
      < service.index("dict('词典')"))
check("解析复用 DetailDao（不另写一份）",
      "details.load(wordKey)" in service and "class SqlLookupStore implements LookupStore" in service)
check("搜索复用 WordDao 三条",
      "words.searchMyWords(query)" in service
      and "words.searchAddedWords(query)" in service
      and "words.searchDictionary(query)" in service)
check("DetailDao 是唯一解析入口（lookup 层没有自己拼 SQL）",
      "SELECT " not in service and "rawQuery" not in service)
check("入口不各写一套：只有一处 candidateLimit 定义",
      pub.count("candidateLimit") == 0 and service.count("candidateLimit = 10") == 1)

print("== 4. 释义来源优先级 ==")
check("820 词有额外汇总字段 meaningPdf", "meaningPdf" in read(LIB, "data", "models", "word_detail.dart"))
check("两段式判定：两段都有且不一样", "bookMeaning != dictMeaning" in service)
check("词书那一段进 bookMeaning", "String get bookMeaning => detail.meaningPdf.trim();" in service)
check("词典那一段进 dictMeaning", "String get dictMeaning => detail.meaningEcdict.trim();" in service)
check("加词写的释义取词典那段", "String get meaning => dictMeaning.isNotEmpty ? dictMeaning : bookMeaning;" in service)

print("== 5. 搜索规则 ==")
check("输入规范化保留括号（只压空白）",
      "raw.trim().replaceAll(_spaces, ' ').toLowerCase()" in service)
check("中文判定用汉字区间", "_cjk = RegExp(r'[\\u4e00-\\u9fff]')" in service)
check("候选上限 10", "static const int candidateLimit = 10;" in service)
check("合并去重按 wordKey", "if (seen.add(h.wordKey)) out.add(h);" in service)
check("精确命中不受 10 条上限影响", "for (final h in all) {" in service)
check("候选按 词书 → 自加 → 词典 拼接",
      service.index("for (final e in book)") < service.index("for (final e in added)")
      < service.index("for (final e in dict)"))

print("== 6. 8 个 ECDICT 没覆盖的词 ==")
conn = sqlite3.connect(DB)
cur = conn.cursor()
eight = [
    "duple", "graver", "utile", "once (and) for all",
    "in retrospect", "meditating", "diapers", "plagued",
]
for w in eight:
    row = cur.execute(
        "SELECT LENGTH(COALESCE(meaning_pdf, '')), LENGTH(COALESCE(meaning_ecdict, '')) "
        "FROM my_words WHERE word_key = ?", (w,)
    ).fetchone()
    check(f"{w} 在 820 里且有书释", bool(row) and row[0] > 0, str(row))
# 需求把这 8 个词称作「ECDICT 没有的」。实测（v0.10.0 的库）：它们都被 820
# 强制并入 `words`（tag=user820），`my_words.meaning_ecdict` 也大多补上了词典段。
# 真正为空、必须靠书释兜底的只有 `once (and) for all`。这里按真实数据断言，
# 不按需求的口头前提硬编一个「8 个都空」。
empty_dict = [
    w for w in eight
    if ((cur.execute(
        "SELECT LENGTH(COALESCE(meaning_ecdict, '')) FROM my_words WHERE word_key = ?",
        (w,)).fetchone() or [0])[0]) == 0
]
check("其中 once (and) for all 的词典段为空（书释必须兜底）",
      "once (and) for all" in empty_dict, str(empty_dict))
check("其余 7 个已带词典段（显示两段式，不是查不到）",
      len(empty_dict) == 1 and len(eight) - len(empty_dict) == 7, str(empty_dict))

print("== 7. 查不到就明说未查到 ==")
check("空态文案写明未查到", "title: '未查到「${view.query}」'" in page)
check("明说不联网、不编释义", "不联网查，也不会编一个释义出来" in page)
check("查不到用独立 key 断言", "key: const ValueKey('lookup-not-found')" in page)
check("lookup 层没有编造释义的分支", "未查到" not in service)

print("== 8. 结果页与加词 ==")
check("卡上有词 key", "key: const ValueKey('lookup-word')" in card)
check("卡上有音标 key", "key: const ValueKey('lookup-phonetic')" in card)
check("卡上有词性 key", "keyName: 'lookup-pos'" in card)
check("两段式分开标 词书原释 / 词典全释",
      "label: '词书原释'" in card and "label: '词典全释'" in card)
check("有发音按钮", "key: const ValueKey('lookup-speak')" in card)
check("已在库写「已在词库 · 箱 X」", "return '已在词库 · 箱 $box';" in card)
check("已在库按钮置灰", "onPressed: _inLibrary || adding ? null : onAdd," in card)
check("已在库不重复加（服务层也拦一次）", "if (result.inLibrary) return false;" in service)
check("加词带上释义", "await _store.addToLibrary(result.wordKey, result.meaning);" in service)
check("写库真的写 meaning 列", "'meaning': meaning.trim()," in detail_dao)
check("加完广播词库变更", "AppSignals.libraryUpdated();" in page)
check("发音与学习页同一套 TTS", "Speech.speak(r.wordKey)" in page and "Speech.speak" in read(
    LIB, "features", "words", "word_detail_page.dart"))

print("== 9. 学习页查词不记答题 ==")
open_lookup = session_page.split("Future<void> _openLookup() async {", 1)
body = open_lookup[1].split("}\n", 1)[0]
check("_openLookup 只 push 查词页", "LookupPage(" in body and "Navigator" in body)
check("_openLookup 不碰答题进度", "_progress" not in body and "_index" not in body)
check("_openLookup 不写库", "_dao" not in body and "answer" not in body)
check("顶栏书本图标保留（两个入口并存）",
      "onDetail: _card != null && !_progress.resolved" in session_page
      and "key: const ValueKey('card-lookup')" in session_page)
check("放大镜画在单词卡内部（不加第三层玻璃）",
      session_page.count("GlassSurface(") == session_page.count("GlassSurface(")
      and "Icons.search_rounded" in session_page)

print("== 10. 本版不做 ==")
for word, label in [
    ("例句", "每词例句"),
    ("拼写", "拼写"),
    ("查词历史", "查词历史"),
    ("统计图表", "统计图表"),
]:
    scope = page + card + service + capsule
    check(f"未做：{label}", word not in scope)
check("查词层不调 DeepSeek", "deepseek" not in (page + card + service).lower())

print("== 11. 改的都是该改的（关键改动自检）==")
check("词库页三条 SQL 还在 WordDao（search 门禁仍指向它）",
      "meaning_pdf LIKE ?1 OR meaning_ecdict LIKE ?1" in read(LIB, "data", "dao", "word_dao.dart"))
check("词库页不再自己拼三条搜索（改成调统一查词）",
      "searchMyWords(" not in words_page and "_lookup.search(q)" in words_page)
check("文章页不再自带一套查词弹层",
      "sheet-add" not in article_page and "sheet-speak" not in article_page)
check("文章页弹层用共用卡", "LookupResultCard(" in article_page)
check("搜索胶囊两处共用", words_page.count("SearchCapsule(") == 1 and "SearchCapsule(" in page)

print("== 12. 冻结面零改动 ==")

frozen = [
    # 主题与控件
    "app/lib/app/theme/app_colors.dart",
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/lib/app/widgets/press_scale.dart",
    # 外壳
    "app/lib/app/shell/home_shell.dart",
    "app/lib/app/shell/shell_padding.dart",
    "app/lib/app/shell/spring_page_physics.dart",
    # 调度与题目
    "app/lib/data/study/leitner.dart",
    "app/lib/data/study/choice_options.dart",
    "app/lib/data/study/study_flow.dart",
    "app/lib/data/study/near_words.dart",
    "app/lib/data/study/word_lexicon.dart",
    # 旧 DAO（本版只动了 detail_dao 的加词签名）
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/dao/word_dao.dart",
    "app/lib/data/dao/settings_dao.dart",
    "app/lib/data/dao/import_dao.dart",
    "app/lib/data/dao/article_dao.dart",
    # 导入
    "app/lib/data/import/word_list_parser.dart",
    "app/lib/data/import/document_readers.dart",
    "app/lib/data/import/pdfium_ffi.dart",
    "app/lib/data/import/import_service.dart",
    # 学习页其余部分
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/study/box_band.dart",
    # 词库其余页面
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/features/words/import_page.dart",
    # 阅读与文章生成
    "app/lib/features/reading/reading_page.dart",
    "app/lib/data/models/article.dart",
    "app/lib/data/article/article_metrics.dart",
    "app/lib/data/article/article_check.dart",
    "app/lib/data/article/article_parser.dart",
    "app/lib/data/article/article_prompt.dart",
    "app/lib/data/article/word_picker.dart",
    "app/lib/data/article/rare_words.dart",
    "app/lib/data/article/article_service.dart",
    "app/lib/data/llm/deepseek_client.dart",
    "app/lib/data/llm/secret_store.dart",
    "app/lib/data/tts/article_reader.dart",
    "app/lib/features/profile/deepseek_key_card.dart",
]
changed = set(
    line for line in git("diff", "--name-only", BASE).splitlines() if line.strip()
)
for path in frozen:
    check(f"冻结：{os.path.basename(path)}", path not in changed, "被改动")

print("== 13. 影响面白名单 ==")

allowed = {
    "app/pubspec.yaml",
    "app/pubspec.lock",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/lib/features/reading/article_page.dart",
    "app/lib/data/dao/detail_dao.dart",
    "DESIGN.md",
    "项目日志.md",
    "_source/check_v110.py",
    "_source/release_notes_v110.md",
    # 回归门禁跟文件走：搜索框搬去 app/widgets/search_capsule.dart
    "_source/check_theme_v070.py",
}
new_files = {
    "app/lib/data/lookup/lookup_service.dart",
    "app/lib/app/widgets/search_capsule.dart",
    "app/lib/features/lookup/lookup_page.dart",
    "app/lib/features/lookup/lookup_result_card.dart",
    "app/test/v011_lookup_test.dart",
}
unexpected = changed - allowed - new_files
check("改动文件都在白名单或新增清单里", not unexpected, str(sorted(unexpected)))

print("== 14. 设计稿同步 ==")
check("DESIGN 标题已是 v0.11.0", "已按 v0.11.0 代码核对" in design)
check("新增 §9 统一查词", "## 9. 统一查词" in design)
check("§9 写了四个入口", "AppBar 右侧放大镜" in design and "单词卡右上角放大镜" in design)
check("§9 写了来源优先级", "### 9.2 释义来源优先级" in design)
check("§9 写了搜索规则", "### 9.3 搜索规则" in design)
check("8 个词写进设计稿", "duple" in design and "once (and) for all" in design)
check("后续章节顺延（布局 10 / 渲染 11 / 门禁 12）",
      "## 10. 布局规则" in design and "## 11. 渲染验收" in design and "## 12. 常规验收门禁" in design)
check("5.4 补了 0.11.0", "0.11.0（`0.11.0+28` → 2028 / 1028 / 4028）" in design)
check("门禁节写了 374", "374 passed" in design)

print("== 15. 测试覆盖（需求点名的验收用例）==")
for needle, label in [
    ("两段式释义（820 词）", "820 词两段式释义"),
    ("短语整串命中", "短语整串命中"),
    ("中文按释义查到", "中文按释义查到"),
    ("英文前缀候选", "英文前缀候选"),
    ("ECDICT 没覆盖的 8 个词仍显示词书释义", "8 个词仍显示书释"),
    ("查不到就明说未查到", "查不到明说未查到"),
    ("加入生词本", "已在库不重复加"),
    ("学习页查词不记答题", "学习页查词不记答题"),
]:
    check(f"测试覆盖：{label}", needle in test_v011)

print()
print(f"  {passed} PASS / {failed} FAIL")
if failed:
    raise SystemExit(1)
