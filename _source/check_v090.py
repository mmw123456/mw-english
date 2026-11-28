"""v0.9.0 验收：PDF / Word 导入。

跑法：python _source/check_v090.py

主线（全部取自需求原文，不从实现里抄）：
1. 入口只有词库页右上角一颗导入按钮：不占 Tab、不上首页
2. 文件：`.pdf` / `.docx` 为主路，`.txt` / `.csv` / 粘贴是退路，`.doc` 明说另存为 .docx
3. 解析：编号列表 / 一行一词 / 词 + 词性 + 释义 / 逗号分号 / Tab；短语整串保留；
   跳表头页码；续行接上；认不出的行列出来不静默丢
4. 必须先预览确认：总数 / 重复跳过 / 无法解析行；可勾选可删改；按钮写「导入 X 个新词」；
   没确认不写库
5. 去重与入库：小写归一化去重、已在 820 或自加词的跳过并报数、导入词就是自加词
   （同一张 user_added_words、added_at 递增、进同一套六箱）、释义「自带 > 词典 > 未查到」
6. 失败与边界：空文件 / 一个词都没解析出来都给人话，不崩不半导入；进度不卡界面；全程本地
7. 版本：0.9.0 / +26；我的页 0.9.0 (2026)
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "09368d2"  # v0.8.0 收尾提交（日志记阶段 6.10）

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


defaults = read(LIB, "app", "app_defaults.dart")
signals = read(LIB, "app", "app_signals.dart")
app_db = read(LIB, "data", "db", "app_database.dart")
word_dao = read(LIB, "data", "dao", "word_dao.dart")
study_dao = read(LIB, "data", "dao", "study_dao.dart")
detail_dao = read(LIB, "data", "dao", "detail_dao.dart")
import_dao = read(LIB, "data", "dao", "import_dao.dart")
parser = read(LIB, "data", "import", "word_list_parser.dart")
readers = read(LIB, "data", "import", "document_readers.dart")
ffi = read(LIB, "data", "import", "pdfium_ffi.dart")
service = read(LIB, "data", "import", "import_service.dart")
import_page = read(LIB, "features", "words", "import_page.dart")
words = read(LIB, "features", "words", "words_page.dart")
study_page = read(LIB, "features", "study", "study_page.dart")
home_shell = read(LIB, "app", "shell", "home_shell.dart")
pub = read(APP, "pubspec.yaml")
profile = read(LIB, "features", "profile", "profile_page.dart")
design = read(ROOT, "DESIGN.md")
manifest = read(APP, "android", "app", "src", "main", "AndroidManifest.xml")

print("== 1. 版本行 ==")

m = re.search(r"version: (\d+)\.(\d+)\.(\d+)\+(\d+)", pub)
version = tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)
check("版本号 = 0.9.0 / +26", version == (0, 9, 0, 26), str(version))
check("我的页版本行 = 0.9.0 (2026)", "const base = '0.9.0 (2026)';" in profile)

print("== 2. 入口只有一个 ==")

check("词库页右上角一颗导入按钮",
      "key: const ValueKey('import-entry')," in words
      and "tooltip: '导入词表'," in words
      and "icon: const Icon(Icons.file_upload_outlined," in words)
check("点进去是整页 ImportPage",
      "Future<void> _openImport() async {" in words
      and "MaterialPageRoute<int>(builder: (_) => const ImportPage())," in words)
check("导完回词库并提示导入条数",
      "SnackBar(content: Text('已导入 $imported 个词，按添加顺序排进每日新词'))," in words)
# `_TabSpec(` 出现 5 次 = 构造函数 1 次 + 四个 Tab 各 1 次
check("不占 Tab（外壳零改动，仍是四个 Tab）",
      git("diff", "--name-only", BASE, "--", "app/lib/app/shell/home_shell.dart").strip() == ""
      and home_shell.count("_TabSpec(") == 5,
      str(home_shell.count("_TabSpec(")))
check("首页没有任何导入入口", "ImportPage" not in read(
    LIB, "features", "study", "study_page.dart"))

print("== 3. 支持的文件与格式判定 ==")

check("三种来源：pdf / docx / text", "enum ImportFormat { pdf, docx, text }" in service)
check(".pdf 与 .docx 是主路",
      "if (lower.endsWith('.pdf')) return ImportFormat.pdf;" in service
      and "if (lower.endsWith('.docx')) return ImportFormat.docx;" in service)
check(".txt / .csv / .tsv 是退路",
      "if (lower.endsWith('.txt') || lower.endsWith('.csv') || lower.endsWith('.tsv')) {"
      in service)
check(".doc 不做，明说另存为 .docx",
      "if (lower.endsWith('.doc')) {" in service
      and "请用 Word 另存为 .docx 再导" in service)
check("老 .doc 的 OLE 头也拦（改成 .docx 后缀也认得出）",
      "bytes[1] == 0xCF &&" in readers and "bytes[3] == 0xE0) {" in readers)
check("扩展名不认识就看文件头（%PDF / PK）",
      "bytes[3] == 0x46) {" in service and "return ImportFormat.pdf; // %PDF" in service
      and "return ImportFormat.docx; // PK = zip" in service)
check("都认不出就明说支持哪些",
      "认不出这个文件类型。支持 .pdf / .docx，退路是 .txt / .csv 或直接粘贴。" in service)
check("PDF 用 pdfium FFI，不是 pdf.js / pdfrx",
      "FPDF_LoadMemDocument" in ffi and "FPDFText_GetText" in ffi
      and "pdfrx" not in pub and "syncfusion" not in pub.lower()
      and "pdf.js" not in LIB and "mammoth" not in pub)
check("三份 Android 原生库在仓库里",
      all(os.path.exists(os.path.join(
          APP, "android", "app", "src", "main", "jniLibs", abi, "libpdfium.so"))
          for abi in ("arm64-v8a", "armeabi-v7a", "x86_64")))
check("Windows dll 只给测试用、不进 git",
      "app/.pdfium/" in read(ROOT, ".gitignore")
      and subprocess.run(["git", "check-ignore", "-q",
                          "app/.pdfium/win-x64/pdfium.dll"],
                         cwd=ROOT).returncode == 0)
check("docx 解 zip 读 word/document.xml",
      "archive.findFile('word/document.xml')" in readers)
check("docx 的段落 / Tab / 换行 / 表格都读",
      "case 'tab':" in readers and "case 'br':" in readers
      and "if (cell.localName != 'tc') continue;" in readers)
check("body 按 localName 找（真 docx 带 w: 前缀）",
      ".firstWhere((e) => e.localName == 'body', orElse: () => doc.rootElement);"
      in readers)
check("txt 认 UTF-8 / UTF-16 BOM",
      "if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {" in readers
      and "bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF" in readers)
check("非 UTF-8 不猜编码", "这个文件不是 UTF-8 编码（中文 Windows 常存成 GBK），" in readers)

print("== 4. 解析规则 ==")

check("编号列表：1. / (1) / [1] / 1、/ -", "final RegExp _leadingNumbering = RegExp(" in parser)
check("Tab 分隔优先", "final tab = body.indexOf('\\t');" in parser)
check("逗号 / 分号 / 全角", "final sep = body.indexOf(RegExp(r'[,，;；]'));" in parser)
check("词性缩写集合", "const Set<String> _posTokens = {" in parser
      and "'adj', 'adv', 'prep', 'conj', 'pron', 'num'," in parser)
check("词形允许空格与圆括号（短语不拆）",
      '_allowedWordShape = RegExp(r"^[A-Za-z]' in parser)
check("短语最多 6 个 part、括号要配对",
      "if (parts.isEmpty || parts.length > 6) return null;" in parser
      and "if (open != close) return null;" in parser)
check("跳表头 / 标题 / 页码 / 空行",
      "final List<RegExp> _headerLike = [" in parser
      and "final RegExp _pageNumberLike = RegExp(" in parser
      and "skipped++;" in parser)
check("续行接上（词一行、释义另起一行）",
      "final meaningOnly = split.word.isEmpty || _cjk.hasMatch(body);" in parser
      and "String _joinMeaning(String a, String b) {" in parser)
check("带点词性可剥到空，不带点的 art/int/num 不吞",
      "if (tokens.length == 1 && !dotted) break;" in parser
      and "if (!tokens[0].endsWith('.') && !tokens[0].endsWith('．')) break;" in parser)
check("认不出的行原样记下来（不静默丢）",
      "unparsed.add(line);" in parser
      and "final List<String> unparsedLines;" in parser)
check("数字开头的怪行不当词", "if (RegExp(r'\\d').hasMatch(w)) return null;" in parser)

print("== 5. 先预览、确认才写库 ==")

# 写库只有一个出口：`commit()` 里的 `dao.commit`。解析链路（buildPreview）不碰它。
check("预览这一步不写库（全文件只有一处 dao.commit）",
      "class ImportPreview {" in service
      and service.count(".commit(") == 1
      and "Future<ImportPreview> buildPreview({" in service)
check("摘要报总数 / 重复跳过 / 文件内重复 / 没认出来",
      "'解析出 ${preview.parsedTotal} 个词'," in import_page
      and "if (preview.duplicateCount > 0) '重复跳过 ${preview.duplicateCount}'," in import_page
      and "if (preview.inFileDuplicateCount > 0) '文件内重复 ${preview.inFileDuplicateCount}',"
      in import_page
      and "'${preview.unparsedLines.length} 行没认出来'" in import_page)
check("每行可勾选", "Checkbox(" in import_page and "final checked = _selected.contains(idx);" in import_page)
check("每行可删改",
      "Future<void> _edit(int index) async {" in import_page
      and "tooltip: '改这一条'," in import_page
      and "tooltip: '不要这个'," in import_page)
check("确认按钮写明「导入 X 个新词」",
      ": Text('导入 $count 个新词')," in import_page)
check("一个都没选时按钮禁用",
      "onPressed: (_committing || count == 0) ? null : _commit," in import_page)
check("写库只在 _commit 里发生（解析阶段不碰库）",
      import_page.count("_service.commit(") == 1
      and "Future<void> _commit() async {" in import_page)
check("没认出来的行可展开看（前 50 行）",
      "ValueKey('unparsed-toggle')" in import_page
      and "for (final line in preview.unparsedLines.take(50))" in import_page)

print("== 6. 去重与入库口径 ==")

check("小写归一化", "return w.toLowerCase();" in parser)
check("文件内重复合掉并计数", "if (!seen.add(word)) {" in parser and "duplicates++;" in parser)
check("已存在 = 820 + 自加词",
      "'SELECT word_key FROM my_words WHERE word_key IN ($marks) '" in import_dao
      and "'SELECT word_key FROM user_added_words WHERE word_key IN ($marks)'" in import_dao)
check("重复跳过条数写进批次记录",
      "'skipped': skipped + skippedExisting," in import_dao)
check("导入词写进同一张 user_added_words",
      "await txn.insert(\n          'user_added_words'," in import_dao
      and "'meaning': fresh[i].meaning," in import_dao)
check("added_at 按文件顺序严格递增（先加的先学）",
      "'added_at': base + i," in import_dao)
check("记来源：文件名 + 导入时间 + 词数",
      "'file_name': fileName," in import_dao
      and "'imported_at': at.millisecondsSinceEpoch," in import_dao
      and "'word_count': fresh.length," in import_dao)
check("写库在单个事务里（不半导入）",
      "return db.transaction((txn) async {" in import_dao)
check("释义优先级：自带 > 词典 > 未查到",
      "COALESCE(NULLIF(u.meaning, ''), w.translation, '')" in word_dao
      and "COALESCE(NULLIF(u.meaning, ''), w.translation, '') AS meaning_ecdict," in study_dao
      and "static const String missingMeaning = '未查到';" in service
      and "dict[w.word] ?? missingMeaning" in service)
check("自加词全部 LEFT JOIN（不在词典里的短语不会消失）",
      word_dao.count("LEFT JOIN words w ON w.word = u.word_key") >= 3
      and study_dao.count("LEFT JOIN words w ON w.word = u.word_key") >= 2)
check("不进池的只剩纯词典词（导入词与 820 同一张表同一套调度）",
      "user_added_words" in study_dao and "my_words" in study_dao)
check("schema 5：meaning / batch_id / import_batch",
      "static const int _schemaVersion = 5;" in app_db
      and "meaning  TEXT NOT NULL DEFAULT ''," in app_db
      and "CREATE TABLE IF NOT EXISTS import_batch(" in app_db)
check("老库靠 ALTER 补列",
      "ALTER TABLE user_added_words ADD COLUMN meaning TEXT NOT NULL DEFAULT ''" in app_db
      and "'ALTER TABLE user_added_words ADD COLUMN batch_id INTEGER'" in app_db)
check("导入后发词库变更信号",
      "static final ValueNotifier<int> libraryChanged = ValueNotifier<int>(0);" in signals
      and "AppSignals.libraryUpdated();" in import_page)
check("首页 / 词库页把两个信号合成一个监听",
      "late final Listenable _signals = Listenable.merge([" in study_page
      and "late final Listenable _signals = Listenable.merge([" in words
      and "AppSignals.libraryChanged," in study_page and "AppSignals.libraryChanged," in words)

print("== 7. 失败与边界 ==")

check("空文件给人话", "throw const DocumentReadException('文件是空的。');" in service)
check("一个词都没解析出来给出路",
      "一个词都没解析出来。可能不是词表，或者排版太乱 —— " in service)
check("PDF 打不开 / 原生库缺失各有提示",
      "'这台设备上读不了 PDF（pdfium 原生库没加载成功）。'" in service
      and "'PDF 打不开：${e.message}'" in service)
check("大文件逐页回调进度",
      "onProgress: (done, total) {" in import_page
      and "'正在解析 $_done / $_total 页'" in import_page)
check("每页让出事件循环（不卡界面）",
      "await Future<void>.delayed(Duration.zero);" in ffi)
check("pdfium 一张页面切行再解析（不切就整页一行）",
      "return pages.expand(splitTextIntoLines).toList();" in service
      and "List<String> splitTextIntoLines(String text) {" in readers)
check("明说不联网", "'全程在本机解析，不上传文件、不联网'" in import_page)
check("release 清单里没有 INTERNET 权限", "INTERNET" not in manifest)
check("pubspec 没有联网库",
      not re.search(r"^\s+(dio|http|web_socket_channel|graphql):", pub, re.M))

print("== 8. 只动该动的：冻结面零改动 ==")

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
    "app/lib/app/app_defaults.dart",
    "app/lib/data/dao/settings_dao.dart",
    "app/lib/data/models/killed_word.dart",
    "app/lib/data/models/word_detail.dart",
    "app/lib/features/profile/settings_page.dart",
    "app/lib/features/study/study_session_page.dart",
    "app/lib/features/study/today_card.dart",
    "app/lib/features/study/progress_ring.dart",
    "app/lib/features/study/box_band.dart",
    "app/lib/features/study/study_heatmap.dart",
    "app/lib/features/words/word_detail_page.dart",
]
for path in frozen:
    check(f"零改动：{os.path.basename(path)}",
          git("diff", "--name-only", BASE, "--", path).strip() == "")

allowed_files = {
    ".gitattributes",
    ".gitignore",
    "app/lib/app/app_signals.dart",
    "app/lib/data/dao/detail_dao.dart",
    "app/lib/data/dao/import_dao.dart",
    "app/lib/data/dao/study_dao.dart",
    "app/lib/data/dao/word_dao.dart",
    "app/lib/data/db/app_database.dart",
    "app/lib/data/import/document_readers.dart",
    "app/lib/data/import/import_service.dart",
    "app/lib/data/import/pdfium_ffi.dart",
    "app/lib/data/import/word_list_parser.dart",
    "app/lib/features/profile/profile_page.dart",
    "app/lib/features/study/study_page.dart",
    "app/lib/features/words/import_page.dart",
    "app/lib/features/words/words_page.dart",
    "app/pubspec.lock",
    "app/pubspec.yaml",
    "app/test/fixtures/sample_words.pdf",
    "app/test/v090_import_test.dart",
    "app/android/gradle.properties",
    "app/android/app/src/main/jniLibs/PDFIUM.txt",
    "app/android/app/src/main/jniLibs/arm64-v8a/libpdfium.so",
    "app/android/app/src/main/jniLibs/armeabi-v7a/libpdfium.so",
    "app/android/app/src/main/jniLibs/x86_64/libpdfium.so",
    "DESIGN.md",
    "项目日志.md",
    "_source/check_v090.py",
    "_source/fetch_pdfium.py",
    "_source/gen_sample_pdf.py",
    "_source/release_notes_v090.md",
}
changed = set(git("diff", "--name-only", BASE, "--", ".").splitlines())
changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
changed = {c for c in changed if c}
bad_files = changed - allowed_files
check("改动面都在白名单里", not bad_files, str(sorted(bad_files)[:6]))

diff_pub = git("diff", BASE, "--", "app/pubspec.yaml")
touched = [l for l in diff_pub.splitlines()
           if l[:1] in "+-" and not l.startswith(("+++", "---"))]
check("pubspec 只动版本行 + 四个新依赖",
      len(touched) == 6
      and touched[0].startswith("-version: 0.8.0+25")
      and touched[1].startswith("+version: 0.9.0+26")
      and all(l.startswith("+") for l in touched[2:]),
      str(touched))

print("== 9. 设计稿同步 ==")

check("DESIGN.md 有导入一节", "## 7. 导入词表（v0.9.0 已发布，versionCode 2026，arm64）" in design)
check("设计稿写了入口、解析规则、去重、入库口径",
      "### 7.1 入口" in design and "### 7.3 解析规则" in design
      and "### 7.5 去重与入库口径" in design)
check("设计稿记了 pdfium 选型理由", "native_toolchain_c" in design and "BSD-3" in design)
check("设计稿章节顺延（7 导入 / 8 布局 / 9 渲染 / 10 门禁）",
      "## 8. 布局规则" in design and "## 9. 渲染验收（最重要的一条）" in design
      and "## 10. 常规验收门禁" in design)
check("设计稿测试数已更新", "**249 passed**" in design)

print("== 10. 新增测试覆盖 ==")

t = read(APP, "test", "v090_import_test.dart")
for needle, label_text in (
    ("编号列表：1. / 2、/ (3) / [4] / - 都认", "编号列表"),
    ("短语整串保留，不按空格拆", "短语不拆"),
    ("词单独一行、释义从下一行接上", "续行接上"),
    ("中文行开头的续行（括号起头）也接上", "括号起头续行"),
    ("表头 / 页码 / 空行整行跳过，不算没认出来", "跳过表头页码"),
    ("认不出来的行列出来，不静默丢", "认不出来"),
    ("大小写不同算同一个词，计数报出", "文件内去重"),
    ("段落 / Tab / 换行 / 表格都读成行", "docx 四种结构"),
    ("老 .doc（OLE 复合文档头）明说另存为 .docx", "老 doc 提示"),
    ("GBK 字节明说不是 UTF-8，不猜编码", "非 UTF-8 提示"),
    ("样例 PDF：两页、切行、去重都对", "PDF 全链路"),
    ("文件自带的释义优先，没有的查词典，都查不到标「未查到」", "释义优先级"),
    ("确认按钮写明「导入 X 个新词」，取消勾选后跟着变", "确认按钮文案"),
    ("删掉一条，列表少一条、按钮文案跟着减", "删改"),
    ("320 宽不溢出", "320 宽不溢出"),
):
    check(f"新增测试：{label_text}", needle in t)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(0 if failed == 0 else 1)
