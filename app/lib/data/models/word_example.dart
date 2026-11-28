import 'dart:convert';

/// 一条真实例句（v0.12.0）。
///
/// 数据来自 `assets/data/examples.json`，源是 Tatoeba 英中句对（CC-BY 2.0 FR），
/// 入库前人工逐条过了一遍。**不是生成的**：App 里没有、也不许有「用模型造例句」
/// 这条路径。
///
/// [hl] 是英文原句的加粗版：目标词两侧带 `**`，与文章正文同一套标记，
/// UI 只按 `**` 切分，不再自己猜哪个词是目标词（猜错过：`pulse` 译成「脉冲」）。
class WordExample {
  const WordExample({
    required this.en,
    required this.hl,
    required this.zh,
    this.tatoebaId,
  });

  /// 英文原句。
  final String en;

  /// 同一句，目标词两侧带 `**`。
  final String hl;

  /// 中文译文（已校订）。
  final String zh;

  /// Tatoeba 句子 id，溯源与署名用。
  final int? tatoebaId;

  /// 按 `**` 切成「普通 / 加粗」交替的片段，奇数位是加粗。
  List<ExampleSpan> get spans {
    final parts = hl.split('**');
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty) ExampleSpan(text: parts[i], bold: i.isOdd),
    ];
  }
}

/// 例句里的一段文字。
class ExampleSpan {
  const ExampleSpan({required this.text, required this.bold});

  final String text;
  final bool bold;
}

/// 例句来源的署名文案（App 内必须显示，CC-BY 2.0 FR 的要求）。
const String kExampleAttribution = '例句来自 Tatoeba · CC-BY 2.0 FR';

/// 解析整个例句资源。纯函数，`flutter test` 直接喂字符串就能测。
///
/// 容错口径：结构不对、单条缺 `en` / `zh` 就跳过那一条，不抛 —— 例句是锦上添花，
/// 不该把详情页整个拖垮。
Map<String, List<WordExample>> parseExamplesAsset(String raw) {
  final out = <String, List<WordExample>>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return out; // 资源坏了当没有，详情页照常显示
  }
  if (decoded is! Map) return out;
  final words = decoded['words'];
  if (words is! Map) return out;

  words.forEach((key, value) {
    if (value is! List) return;
    final list = <WordExample>[];
    for (final item in value) {
      if (item is! Map) continue;
      final en = (item['en'] ?? '').toString().trim();
      final zh = (item['zh'] ?? '').toString().trim();
      if (en.isEmpty || zh.isEmpty) continue;
      final hl = (item['hl'] ?? '').toString().trim();
      final id = item['id'];
      list.add(
        WordExample(
          en: en,
          hl: hl.isEmpty ? en : hl,
          zh: zh,
          tatoebaId: id is int ? id : null,
        ),
      );
    }
    if (list.isNotEmpty) out[key.toString()] = list;
  });
  return out;
}
