import 'dart:typed_data';

import '../dao/import_dao.dart';
import 'document_readers.dart';
import 'pdfium_ffi.dart';
import 'word_list_parser.dart';

/// 导入来源的格式。
enum ImportFormat { pdf, docx, text }

/// 预览页要的一份数据（v0.9.0）。
///
/// 这一步**不写库** —— 需求：没确认不写库。写库发生在 [ImportService.commit]。
class ImportPreview {
  const ImportPreview({
    required this.fileName,
    required this.format,
    required this.candidates,
    required this.duplicateCount,
    required this.inFileDuplicateCount,
    required this.unparsedLines,
  });

  final String fileName;
  final ImportFormat format;

  /// 可导入的词（已去掉库里已有的与文件内重复的）。
  final List<ImportCandidate> candidates;

  /// 库里已有（820 或已在自加词里）被跳过的条数。
  final int duplicateCount;

  /// 文件内部自己重复、被合掉的条数。
  final int inFileDuplicateCount;

  /// 看起来像词条、但没通过校验的行（预览页原样列给用户看）。
  final List<String> unparsedLines;

  /// 从文件里解析出的词条总数（含重复的）。
  int get parsedTotal => candidates.length + duplicateCount;

  bool get isEmpty => candidates.isEmpty;
}

/// PDF / Word / 文本导入的服务层（v0.9.0）。
///
/// 分工：
/// - [pdfium_ffi] 负责 PDF 取文本，[document_readers] 负责 docx / txt 取行；
/// - [parseWordLines] 负责「行 → 词条」，是纯函数，测试主要打这一层；
/// - [ImportDao] 负责去重与写库。
class ImportService {
  const ImportService({this.dao = const ImportDao()});

  /// 去重、补释义、写库都走它。
  ///
  /// 留成构造参数是为了单测能塞个假的进来：`flutter test` 里开不了 sqflite，
  /// 不注入的话「解析 → 去重 → 补释义 → 未查到」这条链只能等真机验。
  final ImportDao dao;

  /// 解析文件，返回预览数据（不写库）。
  ///
  /// [onProgress] 只有 PDF 会用到：大文件逐页回调，界面拿它刷进度条。
  /// 抛 [DocumentReadException]（含 pdfium 不可用）时，UI 直接把 message 显示出来。
  Future<ImportPreview> buildPreview({
    required String fileName,
    required Uint8List bytes,
    void Function(int done, int total)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw const DocumentReadException('文件是空的。');
    }

    final format = _detectFormat(fileName, bytes);

    final List<String> lines;
    switch (format) {
      case ImportFormat.pdf:
        lines = await _readPdf(bytes, onProgress);
      case ImportFormat.docx:
        lines = readDocxLines(bytes);
      case ImportFormat.text:
        lines = readTextLines(bytes);
    }

    return _finish(fileName: fileName, format: format, lines: lines);
  }

  /// 粘贴进来的文本。
  Future<ImportPreview> buildPreviewFromText(String text, {String fileName = '粘贴的单词表'}) async {
    if (text.trim().isEmpty) {
      throw const DocumentReadException('粘贴的内容是空的。');
    }
    return _finish(
      fileName: fileName,
      format: ImportFormat.text,
      lines: splitTextIntoLines(text),
    );
  }

  /// 确认导入（写库）。[candidates] 是用户在预览页勾选后剩下的。
  Future<ImportCommitResult> commit({
    required String fileName,
    required List<ImportCandidate> candidates,
    int skipped = 0,
  }) async {
    if (candidates.isEmpty) {
      throw const DocumentReadException('没有勾选任何词。');
    }
    return dao.commit(
      fileName: fileName,
      candidates: candidates,
      skipped: skipped,
    );
  }

  Future<List<String>> _readPdf(
    Uint8List bytes,
    void Function(int done, int total)? onProgress,
  ) async {
    if (!PdfiumText.isAvailable) {
      throw const DocumentReadException('这台设备上读不了 PDF（pdfium 原生库没加载成功）。');
    }
    final List<String> pages;
    try {
      pages = await PdfiumText.instance.readPages(bytes, onPage: onProgress);
    } on PdfiumUnavailable catch (e) {
      throw DocumentReadException(e.message);
    } on FormatException catch (e) {
      throw DocumentReadException('PDF 打不开：${e.message}');
    }
    // pdfium 一次给一整页文本，行分隔是 `\r\n`。这里必须切行：不切的话
    // 「整页一行」会一个词都解析不出来（第一版就是这么错的）。
    return pages.expand(splitTextIntoLines).toList();
  }

  Future<ImportPreview> _finish({
    required String fileName,
    required ImportFormat format,
    required List<String> lines,
  }) async {
    final parsed = parseWordLines(lines);
    if (parsed.words.isEmpty) {
      throw const DocumentReadException(
        '一个词都没解析出来。可能不是词表，或者排版太乱 —— '
        '可以把内容粘贴进来，或者另存为 .txt 再导。',
      );
    }

    // 库里已有的跳过（820 + 自加词）。大小写不敏感由解析层归一化保证。
    final existing = await dao.existingKeys(
      parsed.words.map((w) => w.word).toList(),
    );
    final freshWords = parsed.words.where((w) => !existing.contains(w.word)).toList();
    final duplicates = parsed.words.length - freshWords.length;

    // 文件里没带释义的，用内置词典补；词典也没有就标「未查到」。
    // 直接把结果写进 `meaning`：预览页看到的释义，就是学习卡以后显示的释义。
    final needDict = freshWords
        .where((w) => w.meaning.isEmpty)
        .map((w) => w.word)
        .toList();
    final dict = await dao.dictionaryMeanings(needDict);

    final fresh = freshWords
        .map((w) => ImportCandidate(
              word: w.word,
              meaning: w.meaning.isNotEmpty ? w.meaning : (dict[w.word] ?? missingMeaning),
            ))
        .toList();

    return ImportPreview(
      fileName: fileName,
      format: format,
      candidates: fresh,
      duplicateCount: duplicates,
      inFileDuplicateCount: parsed.duplicates,
      unparsedLines: parsed.unparsedLines,
    );
  }

  /// 文件里没带、词典也查不到时，释义就写这三个字（需求：不许编释义）。
  static const String missingMeaning = '未查到';

  /// 先看扩展名，扩展名不认识再看文件头。两头都对不上就明说，别瞎猜。
  static ImportFormat _detectFormat(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return ImportFormat.pdf;
    if (lower.endsWith('.docx')) return ImportFormat.docx;
    if (lower.endsWith('.txt') || lower.endsWith('.csv') || lower.endsWith('.tsv')) {
      return ImportFormat.text;
    }
    if (lower.endsWith('.doc')) {
      throw const DocumentReadException(
        '这是老版 .doc 文件，读不了。请用 Word 另存为 .docx 再导。',
      );
    }

    // 扩展名不认识：看文件头
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return ImportFormat.pdf; // %PDF
    }
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return ImportFormat.docx; // PK = zip
    }
    throw const DocumentReadException(
      '认不出这个文件类型。支持 .pdf / .docx，退路是 .txt / .csv 或直接粘贴。',
    );
  }
}
