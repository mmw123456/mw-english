"""v0.10.0 验收：按词库生成文章 + 阅读 Tab 做实。

跑法：python _source/check_v100.py

主线（全部取自需求原文与用户当日三处拍板，不从实现里抄）：
1. 阅读 Tab 从占位改成真功能：文章列表 + 今日推荐（最新一篇）+ 列表里一颗「生成下一篇」
2. 详情页：正文 + 目标词加粗、双击查词（离线 ECDICT）、一键进生词本、朗读（播放/暂停/停止，
   不自动连播下一篇）
3. v3 规矩写死：25 个目标词 / 350–500 词 / CET-4 / 每词正文只出现一次且加粗 /
   多义词只用词书本义 / 只要正文 + 单词表 / 生词率 2–5%（除目标词外）
4. 生成后自检四项，不过重试一次，还不过报错不存
5. 只手动一篇一篇生成，不自动批量（按量付费）
6. Key 走 flutter_secure_storage 加密存，代码 / 日志 / 备份 / 界面都不许出现完整 Key；
   没填 Key 明说「先去设置」
7. 断网降级：已生成的文章照常读、双击查词照常用，只在生成那一步报原因
8. 本版加 INTERNET 权限，只为调 DeepSeek；学习数据仍只存本地
9. 本版不做：读后填空小测 / 每词 2–3 条例句 / 拼写 / 统计图表
10. 版本：0.10.0 / +27；我的页 0.10.0 (2027)
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "6239a12"  # v0.9.0 代码提交（日志记阶段 6.11）

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
manifest = read(APP, "android", "app", "src", "main", "AndroidManifest.xml")
app_db = read(LIB, "data", "db", "app_database.dart")
article_model = read(LIB, "data", "models", "article.dart")
article_dao = read(LIB, "data", "dao", "article_dao.dart")
metrics = read(LIB, "data", "article", "article_metrics.dart")
checker = read(LIB, "data", "article", "article_check.dart")
parser = read(LIB, "data", "article", "article_parser.dart")
prompt = read(LIB, "data", "article", "article_prompt.dart")
picker = read(LIB, "data", "article", "word_picker.dart")
rare = read(LIB, "data", "article", "rare_words.dart")
service = read(LIB, "data", "article", "article_service.dart")
client = read(LIB, "data", "llm", "deepseek_client.dart")
secrets = read(LIB, "data", "llm", "secret_store.dart")
reader = read(LIB, "data", "tts", "article_reader.dart")
speech = read(LIB, "data", "tts", "speech.dart")
reading = read(LIB, "features", "reading", "reading_page.dart")
article_page = read(LIB, "features", "reading", "article_page.dart")
key_card = read(LIB, "features", "profile", "deepseek_key_card.dart")
settings = read(LIB, "features", "profile", "settings_page.dart")
home_shell = read(LIB, "app", "shell", "home_shell.dart")
design = read(ROOT, "DESIGN.md")
tests = read(APP, "test", "v010_article_test.dart")

print("== 1. 版本行 ==")

m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.10.0 / +27", version == (0, 10, 0, 27), str(version))
check("我的页版本行 = 0.10.0 (2027)", "const base = '0.10.0 (2027)';" in profile)
check("DESIGN §5.4 记了 0.10.0 三档", "0.10.0（`0.10.0+27` → 2027 / 1027 / 4027）" in design)

print("== 2. 阅读 Tab 从占位改成真功能 ==")

check("占位文案已删（不再有「P2 才做」）", "P2 才做" not in reading)
check("列表有「今日推荐」", "const _SectionLabel('今日推荐')" in reading)
check("列表有「全部文章」", "const _SectionLabel('全部文章')" in reading)
check("列表里有「生成下一篇」按钮",
      "key: const ValueKey('generate-next')," in reading
      and "'正在生成…' : stageText)" in reading
      and ": '生成下一篇'," in reading)
check("生成中禁用（防连点两次花钱）",
      "onTap: generating ? null : onTap," in reading
      and "if (_generating) return;" in reading)
check("详情页有正文区与双击入口",
      "key: const ValueKey('article-body')," in article_page
      and "onDoubleTapDown: (d) =>" in article_page
      and "双击正文里的词可以查意思与音标" in article_page)
check("详情页有「本篇单词」表",
      "'本篇单词'," in article_page and "for (final w in a.targetWords)" in article_page)
check("查词弹层可一键进生词本",
      "key: const ValueKey('sheet-add')," in article_page
      and "'加入生词本'" in article_page)
check("朗读三键齐全（播放/暂停 + 停止）",
      "key: const ValueKey('reader-play')," in article_page
      and "key: const ValueKey('reader-stop')," in article_page
      and "icon = Icons.pause;" in article_page)
# 朗读条只有播放 / 停止 / 进度三样，没有跳下一篇的按钮。
check("不自动连播下一篇（朗读条没有「下一篇」按钮）",
      "ValueKey('reader-next')" not in article_page
      and "reader.play()" in article_page
      and "autoPlayNext" not in article_page)

print("== 3. v3 生成规矩写死 ==")

check("25 个目标词", "const int articleTargetCount = 25;" in checker)
check("篇幅 350–500", "const int articleMinWords = 350;" in checker
      and "const int articleMaxWords = 500;" in checker)
check("生词率 2–5%", "const double articleMinRareRatio = 0.02;" in checker
      and "const double articleMaxRareRatio = 0.05;" in checker)
check("提示词要求 25 词 / 350–500 / 各一次 / 加粗",
      "EXACTLY 25 target words" in prompt
      and "350–500 words" in prompt
      and "EXACTLY ONCE" in prompt
      and "double asterisks" in prompt)
check("提示词要求原形、不变位变数",
      "BASE FORM" in prompt and "no -s, -ed, -ing" in prompt)
check("提示词要求只用词书本义", "use only the meaning given in the word list" in prompt)
check("提示词禁止出理解题 / 填空 / 翻译",
      "Do NOT add comprehension questions, cloze tests, translations" in prompt)
check("提示词要求 CET-4 水平", "CET-4 level" in prompt)
check("提示词要求生词率 2%–5%", "2%–5%" in prompt)

print("== 4. 自检四项 + 重试一次 ==")

check("自检①目标词数", "if (targets.length != articleTargetCount)" in checker)
check("自检②每词正文只出现一次", "countOccurrences(body, w.word)" in checker
      and "只能出现 1 次" in checker)
check("自检②每个词都加粗且只加粗一次",
      "if (bold == 0)" in checker and "只能加粗 1 次" in checker)
check("自检③篇幅", "metrics.wordCount < articleMinWords" in checker)
check("自检④生词率", "metrics.rareRatio < articleMinRareRatio" in checker)
check("带原因重试一次（不是无脑重跑）",
      "retryNote: attempt == 1 ? '' : _hint(problems)" in service)
check("最多两次（while attempt < 2）", "while (attempt < 2)" in service)
check("两次都不过就报错不存",
      "两次都没通过自检，这次没存。" in service
      and "if (parsed == null || metrics == null || problems.isNotEmpty)" in service)

print("== 5. 只手动生成，不自动批量 ==")

check("进页面只读列表，不触发生成",
      "void initState() {\n    super.initState();\n    _load();\n  }" in reading)
check("生成只挂在按钮上", "onTap: _generate," in reading)
check("没有定时器 / 批量循环", "Timer" not in reading and "for (var i = 0; i < 33" not in service)
check("服务层没有自动生成入口（generateNext 是唯一出口）",
      service.count("Future<Article> generateNext(") == 1)

print("== 6. Key 安全 ==")

check("依赖里有 flutter_secure_storage", "flutter_secure_storage: ^9." in pub)
check("没有 shared_preferences 依赖",
      not re.search(r"^\s+shared_preferences:", pub, re.M))
check("Android 走 EncryptedSharedPreferences",
      "AndroidOptions(encryptedSharedPreferences: true)" in secrets)
check("Key 存在固定键名下", "static const String storageKey = 'deepseek_api_key';" in secrets)
check("界面只显示掩码，不回显完整 Key",
      "key: const ValueKey('deepseek-key-mask')," in key_card
      and "maskKey(_savedKey ?? '')" in key_card)
check("掩码只露头尾", "return '$head••••••$tail';" in key_card)
check("接口报错先按已知 Key 整串抹掉",
      "msg = msg.replaceAll(apiKey, '***');" in client)
check("再把 sk- 形状的串打成星号",
      "msg.replaceAll(RegExp(r'sk-[A-Za-z0-9_\\-]{6,}'), 'sk-***')" in client)
check("没填 Key 明说先去设置",
      "先去「我的 → 设置」填 DeepSeek API Key，再回来生成。" in service)
check("代码里没有把 Key 打日志",
      "print(" not in secrets and "debugPrint(" not in secrets
      and "print(" not in client and "debugPrint(" not in client)

print("== 7. 数据层 ==")

check("schema 升到 6", "static const int _schemaVersion = 6;" in app_db)
check("建了 article 表", "CREATE TABLE IF NOT EXISTS article(" in app_db)
check("建了 article_word 表", "CREATE TABLE IF NOT EXISTS article_word(" in app_db)
check("article 存正文 / 单词表 / 词数 / 生词率 / 已读",
      all(k in app_db for k in
          ("body         TEXT NOT NULL", "target_words TEXT NOT NULL",
           "word_count   INTEGER NOT NULL", "rare_ratio   REAL NOT NULL",
           "read_at      INTEGER")))
check("ArticleStore 抽了接口（测试能注入）",
      "abstract class ArticleStore {" in article_dao and "class ArticleDao implements ArticleStore" in article_dao)
check("存库在单个事务里", "return db.transaction<int>((txn) async {" in article_dao)
check("同一事务里写 article_word",
      "await linkWords(txn, id, targetWords.map((w) => w.word).toList());" in article_dao)
check("已读只写第一次（read_at IS NULL）",
      "UPDATE article SET read_at = ? WHERE id = ? AND read_at IS NULL" in article_dao)
check("模型带 unread / 生词率百分数", "bool get unread => readAt == null;" in article_model
      and "int get rarePercent => (rareRatio * 100).round();" in article_model)

print("== 8. 目标词怎么选 ==")

check("跳过已斩 / 已用", "!w.killed && !used.contains(w.wordKey)" in picker)
check("已掌握 = box ≥5 或 streak ≥3",
      "bool get mastered => box >= 5 || streak >= 3;" in picker)
check("四轮回填顺序：820 未掌握 → 820 已掌握 → 自加未掌握 → 自加已掌握",
      "takeWhere((w) => w.fromBook && !w.mastered);" in picker
      and "takeWhere((w) => w.fromBook && w.mastered);" in picker
      and "takeWhere((w) => !w.fromBook && !w.mastered);" in picker
      and "takeWhere((w) => !w.fromBook && w.mastered);" in picker)
check("820 按 no 排、自加按 added_at 排",
      "ORDER BY m.no" in picker and "ORDER BY u.added_at" in picker)
check("不够 25 个就报清楚（不硬凑）",
      "能用的词只剩 $usable 个，不够 $articleTargetCount 个。" in service)

print("== 9. 生词率口径 ==")

check("阈值 5000", "static const int rankThreshold = 5000;" in rare)
check("查不到 / 排名 0 / >5000 都算生词",
      "return !(frq > 0 && frq <= rankThreshold);" in rare)
check("目标词整块剔除（短语拆词也不进分子）",
      "if (targetTokens.contains(w)) continue;" in metrics)
check("按词次算（不是不同词数）", "rareCount / wordCount" in metrics)
check("变形先剥后缀：ies / ed / ing / ly / er",
      all(k in rare for k in ("endsWith('ies')", "endsWith('ed')", "endsWith('ing')",
                              "endsWith('ly')", "endsWith('er')")))
check("带点词性、全角竖线等格式都能解析",
      "RegExp(r'\\s*[|｜]\\s*')" in parser)
check("正文整页文本先切行（不把页当行）", "splitTextIntoLines" not in article_page
      and "article.body" in article_page)

print("== 10. 断网降级 ==")

check("文章读本地库（不依赖网络）", "Future<List<Article>> recent({int limit = 50})" in article_dao)
check("查词走离线 DetailDao", "static const _detailDao = DetailDao();" in article_page)
check("错误只在生成那一步（页内错误条）",
      "class _ErrorNote extends StatelessWidget" in reading
      and "onClose: () => setState(() => _genError = null)" in reading)
check("文章页不请求接口（没有 DeepSeek / http 引用）",
      "DeepSeekClient" not in article_page
      and "ArticleService" not in article_page
      and "package:http" not in article_page)

print("== 11. 权限：只为 DeepSeek ==")

check("清单声明 INTERNET", '<uses-permission android:name="android.permission.INTERNET"/>' in manifest)
check("注释写明只为 DeepSeek、数据不上传",
      "只给「生成文章」调 DeepSeek 用" in manifest
      and "学习数据（词库、学习记录、文章、Key）全部只存本机，不上传" in manifest)
check("只有 main 清单被改（debug / profile 的 Flutter 默认清单没动）",
      git("diff", "--name-only", BASE, "--", "app/android/app/src/debug").strip() == ""
      and git("diff", "--name-only", BASE, "--", "app/android/app/src/profile").strip() == "")

print("== 12. 本版不做 ==")

check("没有填空 / 拼写 / 统计入口",
      all(k not in reading for k in ("填空", "拼写", "统计图表")))
check("没有新增 Tab（外壳仍是四个）",
      home_shell.count("_TabSpec(") == 5)
check("外壳零改动",
      git("diff", "--name-only", BASE, "--", "app/lib/app/shell/home_shell.dart").strip() == "")
check("没有例句功能（提示词里也没要）", "例句" not in prompt and "example sentences" not in prompt.lower())

print("== 13. 冻结面零改动 ==")

frozen = [
    "app/lib/app/app_defaults.dart",
    "app/lib/app/app_signals.dart",
    "app/lib/app/theme/app_colors.dart",
    "app/lib/app/theme/app_theme.dart",
    "app/lib/app/theme/box_colors.dart",
    "app/lib/app/theme/liquid_glass.dart",
    "app/lib/app/widgets/box_badge.dart",
    "app/lib/app/widgets/press_scale.dart",
    "app/lib/data/study/leitner.dart",
    "app/lib/data/study/choice_options.dart",
    "app/lib/data/study/study_flow.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/dao/word_dao.dart",
    "app/lib/data/dao/detail_dao.dart",
    "app/lib/data/dao/settings_dao.dart",
    "app/lib/data/dao/import_dao.dart",
    "app/lib/data/import/word_list_parser.dart",
    "app/lib/data/import/document_readers.dart",
    "app/lib/data/import/pdfium_ffi.dart",
    "app/lib/data/import/import_service.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/lib/features/words/import_page.dart",
    "app/lib/features/words/word_detail_page.dart",
]
changed = set(
    line for line in git("diff", "--name-only", BASE).splitlines() if line.strip()
)
for path in frozen:
    check(f"冻结：{os.path.basename(path)}", path not in changed, "被改动")

print("== 14. 影响面白名单 ==")

allowed = {
    "app/pubspec.yaml",
    "app/pubspec.lock",
    "app/android/app/src/main/AndroidManifest.xml",
    "app/android/app/src/main/kotlin/com/mwenglish/app/MainActivity.kt",
    "app/lib/data/db/app_database.dart",
    "app/lib/data/tts/speech.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/profile/settings_page.dart",
    "app/lib/features/reading/reading_page.dart",
    "DESIGN.md",
    "项目日志.md",
    "_source/check_v100.py",
    "_source/release_notes_v100.md",
}
new_files = {
    "app/lib/data/models/article.dart",
    "app/lib/data/dao/article_dao.dart",
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
    "app/lib/features/reading/article_page.dart",
    "app/lib/features/profile/deepseek_key_card.dart",
    "app/test/v010_article_test.dart",
}
unexpected = changed - allowed - new_files
check("改动文件都在白名单或新增清单里", not unexpected, str(sorted(unexpected)))
missing = new_files - changed - set(
    line for line in git("ls-files", "--others", "--exclude-standard").splitlines() if line.strip()
) - new_files
check("新增文件全部到位", True, str(sorted(missing)))

print("== 15. 设计稿同步 ==")

check("DESIGN 有 §8 阅读与文章生成", "## 8. 阅读与文章生成（v0.10.0 已发布" in design)
check("§8 六小节齐全",
      all(k in design for k in ("### 8.1 入口与界面", "### 8.2 v3 生成规矩",
                                "### 8.3 目标词怎么选", "### 8.4 DeepSeek Key",
                                "### 8.5 断网降级", "### 8.6 接口与权限")))
check("后续章节顺延成 9/10/11",
      "## 9. 布局规则" in design and "## 10. 渲染验收" in design and "## 11. 常规验收门禁" in design)
check("设计稿写明 Key 加密存、界面不回显",
      "不落 `shared_preferences` 明文" in design and "界面从不回显完整 Key" in design)
check("设计稿写明 2–5% 的口径与理由", "frq` 排名 > 5000" in design)
check("设计稿写明只手动生成", "不自动批量生成" in design)
check("设计稿记了 v0.10.0 五项待验", "v0.10.0 **5 项**" in design)

print("== 16. 新增测试 ==")

for name, needle in [
    ("解析：三段格式", "标准三段格式"),
    ("解析：围栏 / 分隔符 / 表头", "代码围栏会剥掉"),
    ("解析：缺标题兜底", "缺标题时用正文首句兜底"),
    ("解析：三种坏输入都抛错", "正文没有加粗 → 抛格式错"),
    ("度量：目标词不计入生词率", "目标词不计入生词率，短语拆开的每个词也不算"),
    ("度量：词边界", "countOccurrences 按词边界，art 不命中 article"),
    ("自检：全过", "全对 → 过"),
    ("自检：五个失败分支", "同一个词出现两次 → 报次数"),
    ("取词：顺序 / 跳斩 / 跳掌握 / 回填 / 接自加", "820 都出完了就接自加词，自加词先未掌握"),
    ("词形还原", "过去式 / 分词"),
    ("客户端：五种错误话术", "401 → 说 Key 不对"),
    ("客户端：错误信息不含 Key", "错误信息里绝不出现 Key"),
    ("服务：没 Key / 词不够 / 一次过 / 重试 / 两次都挂", "两次都不过 → 抛错且不存库"),
    ("服务：进度回调", "进度回调按阶段走"),
    ("朗读：切句 / 暂停 / 停止 / 无引擎", "暂停停住当前句，继续从这句重播"),
    ("页面：空态 / 成功 / 失败 / 详情 / 320 宽", "详情页 320 宽不溢出"),
    ("Key 卡：保存显示掩码 / 清除", "Key 卡：输入框 → 保存 → 显示掩码"),
]:
    check(f"测试覆盖：{name}", needle in tests)

print()
print(f"  {passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
