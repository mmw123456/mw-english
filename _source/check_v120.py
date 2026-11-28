"""v0.12.0 验收：每词 2–3 条真实例句（只做 Tatoeba 那 188 词）。

跑法：python _source/check_v120.py

主线（全部取自需求原文与用户当日拍板，不从实现里抄）：
1. 只做例句一件事：拼写默写 / 语境填空 / 统计图表 / 例句朗读一律不做
2. 例句必须真实：只收 Tatoeba 英中句对（CC-BY 2.0 FR），禁止模型生成、禁止联网现抓
3. 覆盖数按实测：188/820 有例句（306 句），其余 632 词显「暂无例句」，不硬凑
4. 详情页「例句」一节：1–3 条 + 目标词加粗 + 中文译文 + 底部署名
5. 查词结果卡只显第一条，不展开
6. 短语按整串显例句；多义词只用词书本义
7. 本版顺带修 `my_words` 第 257 条：take + advantage of → take advantage of
8. 版本：0.12.0 / +29；我的页 0.12.0 (2029)
"""

import json
import os
import sqlite3
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
DB = os.path.join(APP, "assets", "db", "dict.sqlite")
ASSET = os.path.join(APP, "assets", "data", "examples.json")
BASE = "22da607"  # v0.11.0 代码提交（日志记阶段 6.13）

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
model = read(LIB, "data", "models", "word_example.dart")
bank = read(LIB, "data", "examples", "example_bank.dart")
detail_model = read(LIB, "data", "models", "word_detail.dart")
detail_dao = read(LIB, "data", "dao", "detail_dao.dart")
app_db = read(LIB, "data", "db", "app_database.dart")
line = read(LIB, "app", "widgets", "example_line.dart")
card = read(LIB, "features", "lookup", "lookup_result_card.dart")
page = read(LIB, "features", "words", "word_detail_page.dart")
design = read("DESIGN.md")
test_v012 = read(APP, "test", "v012_example_test.dart")

print("== 1. 版本行 ==")
check("pubspec 版本 0.12.0+29", "version: 0.12.0+29" in pub, pub.splitlines()[4])
check("我的页显示 0.12.0 (2029)", "const base = '0.12.0 (2029)';" in profile)
check("版本号两处一致（+29 → 2029）", "+29" in pub and "(2029)" in profile)

print("== 2. 例句资源（只 Tatoeba，188 词 / 306 句）==")
asset = json.loads(read(ASSET))
words = asset["words"]
check("资源存在且只有 Tatoeba 一个来源", asset.get("source") == "Tatoeba", asset.get("source"))
check("许可写 CC-BY 2.0 FR", asset.get("license") == "CC-BY 2.0 FR", asset.get("license"))
check("188 个词有例句", len(words) == 188, str(len(words)))
total = sum(len(v) for v in words.values())
check("共 306 句", total == 306, str(total))
check("每词 1–3 条，不超", all(1 <= len(v) <= 3 for v in words.values()))
three = sum(1 for v in words.values() if len(v) == 3)
two = sum(1 for v in words.values() if len(v) == 2)
one = sum(1 for v in words.values() if len(v) == 1)
check("分布 3 条 40 / 2 条 38 / 1 条 110",
      (three, two, one) == (40, 38, 110), f"{three}/{two}/{one}")
checks = []
for key, items in words.items():
    for s in items:
        checks.append(
            bool(s.get("en")) and bool(s.get("zh")) and "**" in s.get("hl", "")
            and isinstance(s.get("id"), int) and s["hl"].replace("**", "") == s["en"]
        )
check("每句都有 en / zh / 加粗标记 / Tatoeba id，且去标记后与原文一致", all(checks))
check("没有 OpenSubtitles / TED 的句子混进来",
      "OpenSubtitles" not in json.dumps(asset, ensure_ascii=False)
      and "TED" not in json.dumps(asset["words"], ensure_ascii=False))
check("pulse 三句都是「脉搏」，没有「脉冲」（多义词只用词书本义）",
      all("脉搏" in s["zh"] and "脉冲" not in s["zh"] for s in words["pulse"]))
check("短语 take advantage of 按整串出例句",
      len(words.get("take advantage of", [])) == 3
      and all("advantage of" in s["en"].lower() for s in words["take advantage of"]))
check("没例句的词确实不在资源里（transmit / prevail / in retrospect）",
      "transmit" not in words and "prevail" not in words and "in retrospect" not in words)
check("不编例句：资源里没有 examples_synthetic 之类字段",
      "synthetic" not in json.dumps(asset, ensure_ascii=False).lower())

print("== 3. 数据层 ==")
check("有 WordExample 模型", "class WordExample {" in model)
check("按 ** 切分加粗段", "final parts = hl.split('**');" in model)
check("解析容错：坏 JSON 返回空表", "on FormatException {" in model and "return out;" in model)
check("缺 en / zh 的条跳过", "if (en.isEmpty || zh.isEmpty) continue;" in model)
check("署名常量写明来源与许可",
      "const String kExampleAttribution = '例句来自 Tatoeba · CC-BY 2.0 FR';" in model)
check("ExampleBank 读的是 assets 资源（不建表）",
      "static const String assetPath = 'assets/data/examples.json';" in bank
      and "SELECT" not in bank)
check("资源只加载一次", "_loading ??= rootBundle.loadString(assetPath)" in bank)
check("取词大小写不敏感", "_bank?[wordKey.trim().toLowerCase()] ?? const [];" in bank)
check("WordDetail 带 examples 字段", "final List<WordExample> examples;" in detail_model)
check("DetailDao 装配例句", "await ExampleBank.ensureLoaded();" in detail_dao
      and "final examples = ExampleBank.forWord(key);" in detail_dao
      and "examples: examples," in detail_dao)

print("== 4. 详情页「例句」一节 ==")
check("页面用 ExampleSection", "ExampleSection(" in page)
check("区块标题是「例句」", "'例句'," in line)
check("没有例句显「暂无例句」", "key: const ValueKey('detail-no-example')" in line
      and "'暂无例句'," in line)
check("有例句时画署名", "key: const ValueKey('detail-example-source')" in line
      and "kExampleAttribution," in line)
check("例句一条一个块，有独立 key", "key: ValueKey('detail-example-$i')," in line)
check("目标词加粗（w700）", "fontWeight: FontWeight.w700" in line)
check("中文跟随遮盖开关", "masked: maskedOf?.call(i) ?? false," in line
      and "'点一下显示中文'" in line)
check("放在「词典补全」之后（顺序：ecdict 块 → 例句 → 单词变形）",
      page.index("label: '词典补全'") < page.index("ExampleSection(")
      < page.index("title: '单词变形'"))

print("== 5. 查词结果卡只显第一条 ==")
check("只取 first", "result.detail.examples.first" in card)
check("没有 for 循环把例句全铺开", "for (final e in result.detail.examples" not in card)
check("有独立 key 断言", "key: const ValueKey('lookup-example')" in card)
check("卡上也署名", "key: const ValueKey('lookup-example-source')" in card
      and "'Tatoeba · CC-BY 2.0 FR'" in card)
check("没例句整块不出现（靠 isNotEmpty 判断）",
      "if (result.detail.examples.isNotEmpty) ...[" in card)

print("== 6. 第 257 条 take → take advantage of ==")
conn = sqlite3.connect(DB)
row = conn.execute(
    "SELECT word, word_key, phonetic, meaning_pdf, meaning_ecdict FROM my_words WHERE no = 257"
).fetchone()
check("word 已是 take advantage of", row[0] == "take advantage of", str(row[0]))
check("word_key 同步", row[1] == "take advantage of", str(row[1]))
check("音标置空（PDF 没有短语音标）", row[2] == "", repr(row[2]))
check("释义以 phr. 开头，不再带 advantage of 前缀",
      row[3].startswith("phr. ") and not row[3].startswith("advantage of"), row[3])
check("meaning_ecdict 置空（原来那条是 take 的释义）", row[4] == "", repr(row[4]))
check("820 总数不变", conn.execute("SELECT COUNT(*) FROM my_words").fetchone()[0] == 820)
check("库里没有残留的 take 行",
      conn.execute("SELECT COUNT(*) FROM my_words WHERE word_key = 'take'").fetchone()[0] == 0)
conn.close()
csv_text = read("data", "words_820.csv")
check("data/words_820.csv 同步", "257,take advantage of," in csv_text, "未同步")
syn = json.loads(read(APP, "assets", "data", "synonyms.json"))
check("近义词键改成短语", "take advantage of" in syn and "take" not in syn)
check("老库迁移：schema 7 + _fixTakeEntry",
      "static const int _schemaVersion = 7;" in app_db
      and "static Future<void> _fixTakeEntry(Database db) async {" in app_db
      and "await _fixTakeEntry(db);" in app_db)
check("迁移只在还是坏的那一条时动手",
      "if (word != broken || !meaning.startsWith('advantage of')) return;" in app_db)
check("迁移把学习记录/自加词/近义词一起搬到新 key",
      "for (final table in ['study_record', 'user_added_words', 'synonyms']) {" in app_db)

print("== 7. 不建表、不把原始语料塞进仓库 ==")
check("例句没建 SQLite 表", "CREATE TABLE IF NOT EXISTS example" not in app_db)
check("例句不进数据库层（DAO 里没有 example 表查询）",
      "FROM example" not in detail_dao and "'example'" not in detail_dao)
tracked = git("ls-files", "_source/opus", "_source/examples_820_opensubtitles.json").strip()
check("OPUS 原始包与 OpenSubtitles 产物不在 git 里", tracked == "", tracked)

print("== 8. 本版不做 ==")
scope = line + card + page + bank + model
for word, label in [
    ("拼写", "拼写默写"),
    ("语境填空", "语境填空"),
    ("统计图表", "统计图表"),
    ("朗读例句", "例句朗读"),
]:
    check(f"未做：{label}", word not in scope)
check("例句层不调 DeepSeek", "deepseek" not in scope.lower())

print("== 9. 冻结面零改动 ==")

frozen = [
    # 主题与控件
    "app/lib/app/theme/app_colors.dart",
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/lib/app/widgets/press_scale.dart",
    "app/lib/app/widgets/search_capsule.dart",
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
    # 其余 DAO
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
    # 查词（本版只在结果卡加一块，服务层一行不动）
    "app/lib/data/lookup/lookup_service.dart",
    "app/lib/features/lookup/lookup_page.dart",
    # 学习页
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/study/box_band.dart",
    # 词库其余页面
    "app/lib/features/words/words_page.dart",
    "app/lib/features/words/import_page.dart",
    # 阅读与文章生成
    "app/lib/features/reading/reading_page.dart",
    "app/lib/features/reading/article_page.dart",
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
    "app/lib/features/profile/settings_page.dart",
]
changed = set(
    line_ for line_ in git("diff", "--name-only", BASE).splitlines() if line_.strip()
)
for path in frozen:
    check(f"冻结：{os.path.basename(path)}", path not in changed, "被改动")

print("== 10. 影响面白名单 ==")

allowed = {
    "app/pubspec.yaml",
    "app/pubspec.lock",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/data/dao/detail_dao.dart",
    "app/lib/data/models/word_detail.dart",
    "app/lib/data/db/app_database.dart",
    "app/lib/features/words/word_detail_page.dart",
    "app/lib/features/lookup/lookup_result_card.dart",
    "app/assets/db/dict.sqlite",
    "app/assets/data/examples.json",
    "app/assets/data/synonyms.json",
    "data/words_820.csv",
    "DESIGN.md",
    "项目日志.md",
    ".gitignore",
    "_source/check_v120.py",
    "_source/curate_examples.py",
    "_source/gen_examples_asset.py",
    "_source/fix_take_entry.py",
    "_source/build_examples_opus.py",
    "_source/build_examples.py",
    "_source/examples_820.json",
    "_source/fetch_opus.py",
    "_source/examples_820_curated.json",
    "_source/release_notes_v120.md",
}
new_files = {
    "app/lib/data/models/word_example.dart",
    "app/lib/data/examples/example_bank.dart",
    "app/lib/app/widgets/example_line.dart",
    "app/test/v012_example_test.dart",
}
removed = set(
    line_ for line_ in git("diff", "--name-only", "--diff-filter=D", BASE).splitlines()
    if line_.strip()
)
unexpected = changed - allowed - new_files - removed
check("改动文件都在白名单或新增清单里", not unexpected, str(sorted(unexpected)))
check("删掉的文件只有 OPUS 产物",
      removed <= {"_source/examples_820_opensubtitles.json",
                  "_source/examples_820_ted2020.json",
                  "_source/examples_820_ted2020_raw.json"}, str(sorted(removed)))

print("== 11. 设计稿同步 ==")
check("DESIGN 标题已是 v0.12.0", "已按 v0.12.0 代码核对" in design)
check("新增 §10 例句", "## 10. 例句（v0.12.0 已发布，versionCode 2029，arm64）" in design)
check("§10 写了来源与覆盖数", "188 / 820 词有例句，共 306 句" in design)
check("§10 写了选句规矩", "### 10.2 选句规矩" in design)
check("§10 写了显示位置与署名", "### 10.3 显示位置" in design and "CC-BY 2.0 FR" in design)
check("§10 写了本版不做", "### 10.4 本版不做" in design)
check("后续章节顺延（布局 11 / 渲染 12 / 门禁 13）",
      "## 11. 布局规则" in design and "## 12. 渲染验收" in design
      and "## 13. 常规验收门禁" in design)
check("5.4 补了 0.12.0", "0.12.0（`0.12.0+29` → 2029 / 1029 / 4029）" in design)
check("门禁节写了 388", "388 passed" in design)

print("== 12. 测试覆盖（需求点名的验收用例）==")
for needle, label in [
    ("188 个词有例句，共 306 句", "820 有例句的词显 1–3 条"),
    ("没例句：一行「暂无例句」", "没例句显暂无例句"),
    ("多义词只用词书本义：pulse", "多义词只用词书本义"),
    ("短语按整串显例句", "短语显短语例句"),
    ("有例句只显第一条，不展开", "查词卡只显第一条"),
    ("每条都有英文、中文、加粗标记", "例句来源/加粗字段有值"),
    ("遮盖中文", "译文跟随遮盖开关"),
]:
    check(f"测试覆盖：{label}", needle in test_v012)

print()
print(f"  {passed} PASS / {failed} FAIL")
if failed:
    raise SystemExit(1)
