import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/dao/import_dao.dart';
import 'package:mw_english/data/import/document_readers.dart';
import 'package:mw_english/data/import/import_service.dart';
import 'package:mw_english/data/import/pdfium_ffi.dart';
import 'package:mw_english/data/import/word_list_parser.dart';
import 'package:mw_english/features/words/import_page.dart';

/// v0.9.0：PDF / Word 导入。
///
/// 三层分开测：
/// 1. 纯函数 [parseWordLines]：排版规则、续行、去重、认不出来的行 —— 全部可测。
/// 2. 取文本 [readDocxLines] / [readTextLines] / [PdfiumText.readPages]：
///    docx 用内存里现搭的 zip，PDF 用 `test/fixtures/sample_words.pdf`。
/// 3. 预览页 [ImportPage]：勾选 / 删改 / 确认按钮文案 / 320 宽不溢出。
///
/// 数据库那一步用 [_FakeDao] 顶掉：`flutter test` 里没有 sqflite 的 platform
/// channel（踩坑 21），不注入的话「解析 → 去重 → 补释义」这条链只能等真机。
class _FakeDao extends ImportDao {
  _FakeDao({Set<String>? existing, Map<String, String>? dict})
      : existing = existing ?? <String>{},
        dict = dict ?? <String, String>{};

  /// 假装库里已经有的词（820 + 自加词）。
  final Set<String> existing;

  /// 假装内置词典查得到的释义。查不到的不放进来。
  final Map<String, String> dict;

  int commitCalls = 0;
  List<ImportCandidate> lastCandidates = const <ImportCandidate>[];

  @override
  Future<Set<String>> existingKeys(List<String> keys) async =>
      keys.where(existing.contains).toSet();

  @override
  Future<Map<String, String>> dictionaryMeanings(List<String> keys) async => {
        for (final k in keys)
          if ((dict[k] ?? '').isNotEmpty) k: dict[k]!,
      };

  @override
  Future<ImportCommitResult> commit({
    required String fileName,
    required List<ImportCandidate> candidates,
    int skipped = 0,
    DateTime? now,
  }) async {
    commitCalls++;
    lastCandidates = candidates;
    return ImportCommitResult(
      inserted: candidates.length,
      skippedExisting: 0,
      batchId: 1,
    );
  }
}

/// 手搭一个最小 docx（就是个 zip，正文在 `word/document.xml`）。
Uint8List _docx(String bodyXml) {
  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>';
  const tail = '</w:body></w:document>';
  final xml = utf8.encode('$head$bodyXml$tail');
  final archive = Archive()
    ..addFile(ArchiveFile('[Content_Types].xml', 2, <int>[0x20, 0x20]))
    ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

List<String> _wordsOf(Iterable<String> lines) =>
    parseWordLines(lines).words.map((w) => w.word).toList();

List<String> _meaningsOf(Iterable<String> lines) =>
    parseWordLines(lines).words.map((w) => w.meaning).toList();

ParsedWord _one(String line) {
  final out = parseWordLines(<String>[line]);
  expect(out.words, hasLength(1), reason: '「$line」应当解析出一个词');
  return out.words.single;
}

ImportPreview _preview({
  List<ImportCandidate>? candidates,
  int duplicateCount = 0,
  int inFileDuplicateCount = 0,
  List<String> unparsed = const <String>[],
  String fileName = 'sample_words.pdf',
}) {
  return ImportPreview(
    fileName: fileName,
    format: ImportFormat.pdf,
    candidates: candidates ??
        const <ImportCandidate>[
          ImportCandidate(word: 'abandon', meaning: 'v. 放弃'),
          ImportCandidate(word: 'prompt', meaning: 'v. 提示'),
          ImportCandidate(word: 'immune', meaning: 'adj. 免疫的'),
          ImportCandidate(word: 'violate', meaning: 'v. 违反'),
        ],
    duplicateCount: duplicateCount,
    inFileDuplicateCount: inFileDuplicateCount,
    unparsedLines: unparsed,
  );
}

/// pdfium 的 Windows dll 由 `_source/fetch_pdfium.py` 下载、不进 git。
/// 换台机器没这个文件时，PDF 那几条自动 skip，不让整包测试变红。
final bool _pdfReady = PdfiumText.isAvailable;
final String? _pdfSkip = _pdfReady
    ? null
    : '没有 pdfium.dll —— 先跑 python _source/fetch_pdfium.py';

void main() {
  // ---------- 1. 解析规则：排版 ----------
  group('解析排版', () {
    test('编号列表：1. / 2、/ (3) / [4] / - 都认', () {
      expect(
        _wordsOf(<String>[
          '1. abandon',
          '2、prompt',
          '(3) immune',
          '[4] violate',
          '- deliberate',
        ]),
        <String>['abandon', 'prompt', 'immune', 'violate', 'deliberate'],
      );
    });

    test('一行一词：没有释义，等词典补', () {
      final w = _one('abandon');
      expect(w.word, 'abandon');
      expect(w.meaning, '');
      expect(w.meaningFromFile, isFalse);
    });

    test('词 + 词性 + 中文释义：词性留在释义里', () {
      final w = _one('transmit v. 传播；播送；广播');
      expect(w.word, 'transmit');
      expect(w.meaning, 'v. 传播；播送；广播');
      expect(w.meaningFromFile, isTrue);
    });

    test('词 + 形容词词性 + 中文释义', () {
      final w = _one('2 conscious adj. 意识到的');
      expect(w.word, 'conscious');
      expect(w.meaning, 'adj. 意识到的');
    });

    test('逗号 / 分号 / 全角逗号 / Tab 分隔', () {
      expect(_one('abandon, 放弃').meaning, '放弃');
      expect(_one('prompt; 提示').meaning, '提示');
      expect(_one('immune，免疫的').meaning, '免疫的');
      expect(_one('violate\t违反').meaning, '违反');
    });

    test('短语整串保留，不按空格拆', () {
      expect(_one('take advantage of v. 利用').word, 'take advantage of');
      expect(_one('once (and) for all, 一劳永逸地').word, 'once (and) for all');
      expect(_one('as a matter of fact').word, 'as a matter of fact');
    });

    test('没有中文时按词性 token 切英文释义', () {
      final w = _one('abandon v. give up completely');
      expect(w.word, 'abandon');
      expect(w.meaning, 'v. give up completely');
    });

    test('词形归一化：小写、压空格、去首尾标点', () {
      expect(_one('  ABANDON  ').word, 'abandon');
      expect(_one('take   advantage   of').word, 'take advantage of');
      expect(_one('abandon,').word, 'abandon');
    });
  });

  // ---------- 2. 续行与断行（种子 PDF 的真实排版） ----------
  group('续行与断行', () {
    test('词单独一行、释义从下一行接上', () {
      // 这三行抄自 `_source/单词本-820词.pdf` 的实际抽取结果。
      final out = parseWordLines(<String>[
        '3 prompt',
        'v. 导致，敦促；鼓励…说下',
        '去； adj. 迅速的，及时…',
      ]);
      expect(out.words, hasLength(1));
      expect(out.words.single.word, 'prompt');
      expect(out.words.single.meaning, 'v. 导致，敦促；鼓励…说下去； adj. 迅速的，及时…');
      expect(out.unparsedLines, isEmpty);
    });

    test('纯中文续行接到上一条', () {
      expect(_meaningsOf(<String>['content n. 内容；', '满足']), <String>['n. 内容；满足']);
    });

    test('中文行开头的续行（括号起头）也接上', () {
      expect(
        _meaningsOf(<String>['4 eliminate', 'v. 消除，消灭；排除； vt.', '（在比赛中）淘汰']),
        <String>['v. 消除，消灭；排除； vt. （在比赛中）淘汰'],
      );
    });

    test('词性残片不会变成一个词', () {
      // `v. 导致…` 归给上一条；不会出现叫 `v.` 或 `adj.` 的词。
      final words = _wordsOf(<String>['12 harsh', 'adj. 恶劣的，艰苦的', '的；严厉的']);
      expect(words, <String>['harsh']);
    });

    test('接不上的孤立中文行算「没认出来」', () {
      final out = parseWordLines(<String>['满足']);
      expect(out.words, isEmpty);
      expect(out.unparsedLines, <String>['满足']);
    });
  });

  // ---------- 3. 跳过与认不出来 ----------
  group('跳过与认不出来', () {
    test('表头 / 页码 / 空行整行跳过，不算没认出来', () {
      final out = parseWordLines(<String>[
        'Classic Vocabulary List',
        'Title: 收藏的单词 Date: / /',
        'No. Word Meaning',
        '- 1',
        '3/20',
        '第 5 页',
        '',
        '1. abandon',
      ]);
      expect(out.words, hasLength(1));
      expect(out.skippedLines, 7);
      expect(out.unparsedLines, isEmpty);
    });

    test('认不出来的行列出来，不静默丢', () {
      final out = parseWordLines(<String>['abc123', 'take advantage (']);
      expect(out.words, isEmpty);
      expect(out.unparsedLines, <String>['abc123', 'take advantage (']);
    });

    test('数字开头的怪行不当词', () {
      expect(_wordsOf(<String>['2020']), isEmpty);
      expect(_wordsOf(<String>['3D model']), isEmpty);
    });
  });

  // ---------- 4. 词表内去重 ----------
  group('词表内去重', () {
    test('大小写不同算同一个词，计数报出', () {
      final out = parseWordLines(<String>['Abandon v. 放弃', 'abandon', 'ABANDON']);
      expect(out.words, hasLength(1));
      expect(out.words.single.word, 'abandon');
      expect(out.duplicates, 2);
    });

    test('重复时把后出现的释义补上', () {
      final out = parseWordLines(<String>['abandon', 'abandon, 放弃']);
      expect(out.words.single.meaning, '放弃');
      expect(out.duplicates, 1);
    });
  });

  // ---------- 5. docx ----------
  group('读 docx', () {
    test('段落 / Tab / 换行 / 表格都读成行', () {
      final bytes = _docx(
        '<w:p><w:r><w:t>abandon v. 放弃</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>prompt</w:t><w:tab/><w:t>提示</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>one</w:t><w:br/><w:t>two</w:t></w:r></w:p>'
        '<w:tbl><w:tr>'
        '<w:tc><w:p><w:r><w:t>immune</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>免疫的</w:t></w:r></w:p></w:tc>'
        '</w:tr></w:tbl>',
      );
      expect(readDocxLines(bytes), <String>[
        'abandon v. 放弃',
        'prompt\t提示',
        'one',
        'two',
        'immune\t免疫的',
      ]);
    });

    test('docx 读出来的行能直接喂给解析器', () {
      final bytes = _docx(
        '<w:p><w:r><w:t>1. abandon v. 放弃</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>take advantage of</w:t><w:tab/><w:t>利用</w:t></w:r></w:p>',
      );
      final out = parseWordLines(readDocxLines(bytes));
      expect(out.words.map((w) => w.word).toList(),
          <String>['abandon', 'take advantage of']);
      expect(out.words.last.meaning, '利用');
    });

    test('老 .doc（OLE 复合文档头）明说另存为 .docx', () {
      final ole = Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1]);
      expect(
        () => readDocxLines(ole),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('另存为 .docx'))),
      );
    });

    test('不是 zip 明说不是有效 docx', () {
      final junk = Uint8List.fromList(utf8.encode('这不是一个 docx'));
      expect(
        () => readDocxLines(junk),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('不是有效的 .docx'))),
      );
    });

    test('zip 里没有 document.xml 明说找不到正文', () {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 3, utf8.encode('abc')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(
        () => readDocxLines(bytes),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('找不到正文'))),
      );
    });
  });

  // ---------- 6. 读 txt ----------
  group('读 txt', () {
    test('UTF-8 BOM 去掉', () {
      final bytes = Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('abandon\r\nprompt')]);
      expect(readTextLines(bytes), <String>['abandon', 'prompt']);
    });

    test('UTF-16 LE BOM 认得', () {
      const text = 'abandon\nprompt';
      final units = text.codeUnits;
      final bytes = <int>[0xFF, 0xFE];
      for (final u in units) {
        bytes.add(u & 0xFF);
        bytes.add(u >> 8);
      }
      expect(readTextLines(Uint8List.fromList(bytes)), <String>['abandon', 'prompt']);
    });

    test('GBK 字节明说不是 UTF-8，不猜编码', () {
      // 「放弃」的 GBK 编码
      final gbk = Uint8List.fromList(<int>[0xB7, 0xC5, 0xC6, 0xFA]);
      expect(
        () => readTextLines(gbk),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('不是 UTF-8'))),
      );
    });

    test('空文件明说文件是空的', () {
      expect(
        () => readTextLines(Uint8List(0)),
        throwsA(isA<DocumentReadException>()),
      );
    });
  });

  // ---------- 7. 预览：PDF 全链路 ----------
  group('PDF 预览', () {
    final bytes = File('test/fixtures/sample_words.pdf').readAsBytesSync();

    test('样例 PDF：两页、切行、去重都对', () async {
      final progress = <String>[];
      final service = ImportService(dao: _FakeDao());
      final preview = await service.buildPreview(
        fileName: 'sample_words.pdf',
        bytes: bytes,
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      expect(progress, <String>['1/2', '2/2'], reason: '大文件要能刷进度');
      expect(preview.format, ImportFormat.pdf);
      expect(preview.candidates.map((c) => c.word).toList(), <String>[
        'abandon',
        'take advantage of',
        'competent',
        'deliberate',
        'immune',
        'violate',
      ]);
      // 第七行那个重复的 `abandon` 与第二页页码行都不该出现在预览里
      expect(preview.inFileDuplicateCount, 1);
      expect(preview.unparsedLines, isEmpty);
    }, skip: _pdfSkip);

    test('库里已有的跳过并报出条数', () async {
      final preview = await ImportService(
        dao: _FakeDao(existing: <String>{'abandon', 'immune'}),
      ).buildPreview(fileName: 'sample_words.pdf', bytes: bytes);

      expect(preview.candidates.map((c) => c.word).toList(), <String>[
        'take advantage of',
        'competent',
        'deliberate',
        'violate',
      ]);
      expect(preview.duplicateCount, 2);
      expect(preview.parsedTotal, 6);
    }, skip: _pdfSkip);

    test('pdfium 没加载时给人话，不是崩溃', () async {
      // 真机上库在，这条只保证「不可用」这条分支的话术不跑偏。
      if (PdfiumText.isAvailable) return;
      await expectLater(
        ImportService(dao: _FakeDao())
            .buildPreview(fileName: 'x.pdf', bytes: bytes),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('读不了 PDF'))),
      );
    }, skip: _pdfSkip);
  });

  // ---------- 8. 预览：补释义 ----------
  group('补释义', () {
    test('文件自带的释义优先，没有的查词典，都查不到标「未查到」', () async {
      final preview = await ImportService(
        dao: _FakeDao(dict: <String, String>{'prompt': '提示', 'eliminate': ''}),
      ).buildPreviewFromText(
        'abandon v. 放弃\nprompt\neliminate\nzzzzunknown',
      );

      final byWord = <String, String>{
        for (final c in preview.candidates) c.word: c.meaning,
      };
      expect(byWord['abandon'], 'v. 放弃');
      expect(byWord['prompt'], '提示');
      // 词典里查到空串 = 等于没查到，不许拿空串当释义
      expect(byWord['eliminate'], ImportService.missingMeaning);
      expect(byWord['zzzzunknown'], ImportService.missingMeaning);
    });
  });

  // ---------- 9. 失败与边界 ----------
  group('失败与边界', () {
    test('.doc 直接说明另存为 .docx', () async {
      await expectLater(
        ImportService(dao: _FakeDao()).buildPreview(
          fileName: 'old.doc',
          bytes: Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0]),
        ),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('另存为 .docx'))),
      );
    });

    test('认不出的扩展名 + 认不出的文件头', () async {
      await expectLater(
        ImportService(dao: _FakeDao()).buildPreview(
          fileName: 'wordlist.bin',
          bytes: Uint8List.fromList(<int>[0x01, 0x02, 0x03, 0x04]),
        ),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('认不出这个文件类型'))),
      );
    });

    test('空文件', () async {
      await expectLater(
        ImportService(dao: _FakeDao())
            .buildPreview(fileName: 'empty.pdf', bytes: Uint8List(0)),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('文件是空的'))),
      );
    });

    test('一个词都没解析出来：给退路，不半导入', () async {
      await expectLater(
        ImportService(dao: _FakeDao()).buildPreviewFromText('!!! ###\n???'),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('一个词都没解析出来'))),
      );
    });

    test('粘贴内容为空', () async {
      await expectLater(
        ImportService(dao: _FakeDao()).buildPreviewFromText('   \n  '),
        throwsA(isA<DocumentReadException>().having(
          (e) => e.message, 'message', contains('粘贴的内容是空的'))),
      );
    });

    test('没勾选任何词就不写库', () async {
      final dao = _FakeDao();
      await expectLater(
        ImportService(dao: dao).commit(fileName: 'x.pdf', candidates: const []),
        throwsA(isA<DocumentReadException>()),
      );
      expect(dao.commitCalls, 0);
    });

    test('确认导入只带用户勾选后的那几条', () async {
      final dao = _FakeDao();
      await ImportService(dao: dao).commit(
        fileName: 'sample_words.pdf',
        candidates: const <ImportCandidate>[
          ImportCandidate(word: 'abandon', meaning: '放弃'),
          ImportCandidate(word: 'prompt', meaning: '提示'),
        ],
        skipped: 3,
      );
      expect(dao.commitCalls, 1);
      expect(dao.lastCandidates.map((c) => c.word).toList(),
          <String>['abandon', 'prompt']);
    });
  });

  // ---------- 10. 预览页 ----------
  group('预览页', () {
    testWidgets('摘要行报总数 / 重复 / 文件内重复 / 没认出来', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ImportPage(
          initialPreview: _preview(
            duplicateCount: 2,
            inFileDuplicateCount: 1,
            unparsed: const <String>['abc123', 'take advantage ('],
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('sample_words.pdf'), findsOneWidget);
      expect(
        find.text('解析出 6 个词 · 重复跳过 2 · 文件内重复 1 · 2 行没认出来'),
        findsOneWidget,
      );
    });

    testWidgets('确认按钮写明「导入 X 个新词」，取消勾选后跟着变', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ImportPage(initialPreview: _preview()),
      ));
      await tester.pump();

      expect(find.text('导入 4 个新词'), findsOneWidget);

      // 全不选：按钮文案归零、按钮禁用
      await tester.tap(find.byKey(const ValueKey('toggle-all')));
      await tester.pump();
      expect(find.text('导入 0 个新词'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-import')))
            .onPressed,
        isNull,
        reason: '一个都没选时不能点确认',
      );

      // 再全选回来，然后单独取消一条
      await tester.tap(find.byKey(const ValueKey('toggle-all')));
      await tester.pump();
      expect(find.text('导入 4 个新词'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('导入 3 个新词'), findsOneWidget);
    });

    testWidgets('全选 / 全不选 两个文案来回切', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ImportPage(initialPreview: _preview()),
      ));
      await tester.pump();

      expect(find.text('全不选'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-all')));
      await tester.pump();
      expect(find.text('全选'), findsOneWidget);
    });

    testWidgets('删掉一条，列表少一条、按钮文案跟着减', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ImportPage(initialPreview: _preview()),
      ));
      await tester.pump();

      expect(find.text('prompt'), findsOneWidget);
      await tester.tap(find.byTooltip('不要这个').at(1));
      await tester.pump();

      expect(find.text('prompt'), findsNothing);
      expect(find.text('导入 3 个新词'), findsOneWidget);
    });

    testWidgets('没认出来的行默认收起，点开才显示', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ImportPage(initialPreview: _preview(unparsed: const <String>['abc123'])),
      ));
      await tester.pump();

      expect(find.text('abc123'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('unparsed-toggle')));
      await tester.pump();
      expect(find.text('abc123'), findsOneWidget);
    });

    testWidgets('320 宽不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ImportPage(
          initialPreview: _preview(
            candidates: const <ImportCandidate>[
              ImportCandidate(word: 'once (and) for all', meaning: '一劳永逸地；一次性彻底解决'),
              ImportCandidate(
                word: 'take advantage of',
                meaning: 'v. 利用，占……的便宜；充分利用（机会、条件等）',
              ),
              ImportCandidate(word: 'zzzzunknown', meaning: ImportService.missingMeaning),
            ],
            duplicateCount: 12,
            inFileDuplicateCount: 3,
            unparsed: const <String>['abc123'],
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('没选文件时给两个来源 + 明说 .doc 要另存', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const ImportPage(),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('pick-file')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-paste')), findsOneWidget);
      expect(find.textContaining('另存为 .docx'), findsOneWidget);
      expect(find.textContaining('不上传'), findsNothing);
    });
  });
}
