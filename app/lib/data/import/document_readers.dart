import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 读文件失败，或文件格式不对时抛这个。message 是给人看的一句话。
class DocumentReadException implements Exception {
  const DocumentReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 读 `.docx`：docx 就是个 zip，正文在 `word/document.xml`。
///
/// **为什么自己解 zip 而不是用包：** docx 的正文结构简单到不值得引一个解析库 ——
/// 段落 `<w:p>` 里 `<w:t>` 是文字、`<w:tab/>` 是 Tab、`<w:br/>` 是换行；
/// 表格 `<w:tbl>` 的每一行把单元格拼成一行（用 Tab 分隔），正好落进
/// `parseWordLines` 认识的「Tab 分隔」排版。
///
/// 做完这一层就不再碰 XML：返回纯文本行给解析层。
List<String> readDocxLines(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0) {
    // OLE 复合文档 = 老 .doc / .xls / .ppt
    throw const DocumentReadException(
      '这是老版 .doc 文件，读不了。请用 Word 另存为 .docx 再导。',
    );
  }

  // docx 一定是个 zip。先看 PK 头再解 —— `ZipDecoder` 对垃圾字节不一定会抛，
  // 会返回一个空壳 Archive，那样错误提示就变成「找不到正文」，把人指错方向。
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    throw const DocumentReadException('这个文件不是有效的 .docx（不是 zip 包）。');
  }

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const DocumentReadException('这个文件不是有效的 .docx（解不开压缩包）。');
  }

  final entry = archive.findFile('word/document.xml') ??
      archive.files.firstWhere(
        (f) => f.name.endsWith('document.xml'),
        orElse: () => ArchiveFile('', 0, <int>[]),
      );
  if (entry.name.isEmpty) {
    throw const DocumentReadException('这个 .docx 里找不到正文（word/document.xml）。');
  }

  final raw = entry.content;
  if (raw.isEmpty) {
    throw const DocumentReadException('这个 .docx 的正文是空的。');
  }

  XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(raw, allowMalformed: true));
  } catch (_) {
    throw const DocumentReadException('这个 .docx 的正文解不开（XML 格式坏了）。');
  }

  // 找 `<w:body>`。真实 docx 里元素都带 `w:` 前缀，`findAllElements('body')`
  // 比的是 qualifiedName（`w:body`），所以这里按 localName 找 —— 不带前缀的
  // 简化 XML（单测里手写的那种）也照样认。
  final body = doc.descendants
      .whereType<XmlElement>()
      .firstWhere((e) => e.localName == 'body', orElse: () => doc.rootElement);

  final lines = <String>[];
  for (final node in body.descendants.whereType<XmlElement>()) {
    if (node.parent != body) continue; // 只要 body 的直接子节点
    final name = node.localName;
    if (name == 'p') {
      lines.addAll(_splitHardBreaks(_paragraphText(node)));
    } else if (name == 'tbl') {
      lines.addAll(_tableLines(node));
    }
  }
  return lines;
}

/// 段落文本：按文档顺序拼 `<w:t>`，`<w:tab/>` 变 Tab，`<w:br/>` 变换行。
String _paragraphText(XmlElement p) {
  final buf = StringBuffer();
  for (final node in p.descendants) {
    if (node is! XmlElement) continue;
    switch (node.localName) {
      case 't':
        buf.write(node.innerText);
      case 'tab':
        buf.write('\t');
      case 'br':
      case 'cr':
        buf.write('\n');
    }
  }
  return buf.toString();
}

/// 表格：一行一条，单元格之间用 Tab 分隔（解析层认这种排版）。
List<String> _tableLines(XmlElement tbl) {
  final lines = <String>[];
  for (final row in tbl.children.whereType<XmlElement>()) {
    if (row.localName != 'tr') continue;
    final cells = <String>[];
    for (final cell in row.children.whereType<XmlElement>()) {
      if (cell.localName != 'tc') continue;
      final parts = <String>[];
      for (final p in cell.children.whereType<XmlElement>()) {
        if (p.localName == 'p') parts.add(_paragraphText(p).trim());
      }
      cells.add(parts.join(' ').trim());
    }
    if (cells.any((c) => c.isNotEmpty)) lines.add(cells.join('\t'));
  }
  return lines;
}

List<String> _splitHardBreaks(String text) {
  if (!text.contains('\n')) return [text];
  return text.split('\n');
}

/// 读 `.txt` / `.csv`：按 UTF-8 解，认 BOM；不是 UTF-8 就明说，别猜编码。
///
/// 这条是退路（需求：「.txt / .csv 与粘贴单词表只作解析失败时的退路」）。
/// 中文环境里 Windows 记事本存的是 GBK，猜错会整篇乱码 —— 与其猜，不如说清楚。
List<String> readTextLines(Uint8List bytes) {
  if (bytes.isEmpty) throw const DocumentReadException('文件是空的。');

  // UTF-16 LE/BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }

  var start = 0;
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    start = 3;
  }

  String text;
  try {
    text = utf8.decode(bytes.sublist(start), allowMalformed: false);
  } on FormatException {
    throw const DocumentReadException(
      '这个文件不是 UTF-8 编码（中文 Windows 常存成 GBK），'
      '请另存为 UTF-8 再导，或直接把内容粘贴进来。',
    );
  }
  return _splitLines(text);
}

List<String> _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final lo = littleEndian ? bytes[i] : bytes[i + 1];
    final hi = littleEndian ? bytes[i + 1] : bytes[i];
    units.add((hi << 8) | lo);
  }
  return _splitLines(String.fromCharCodes(units));
}

/// 把一整段文本切成行。PDF（pdfium 吐整页文本）、txt、粘贴三条来源共用这一条。
///
/// pdfium 的行分隔是 `\r\n`（老文档只有 `\r`），所以先统一成 `\n` 再切。
/// 少切一次的结果是「整页当一行」，解析层会一行都认不出来 —— 这条不能省。
List<String> splitTextIntoLines(String text) {
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
}

List<String> _splitLines(String text) => splitTextIntoLines(text);
