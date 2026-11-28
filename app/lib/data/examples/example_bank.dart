import 'package:flutter/services.dart' show rootBundle;

import '../models/word_example.dart';

/// 例句池（v0.12.0）。
///
/// 数据只有一个来源：`assets/data/examples.json`（188 词 / 306 句，Tatoeba
/// CC-BY 2.0 FR，人工校订过）。**不建表、不进 SQLite** —— 例句是只读常量，
/// 建表只会多一次迁移和一份冗余；换数据只要换 json。
///
/// 只在内存里留一份解析结果，第一次问的时候读资源，之后都是 O(1)。
/// 资源缺失（比如测试环境）就当「一条例句都没有」，不抛、不白屏。
class ExampleBank {
  ExampleBank._();

  static const String assetPath = 'assets/data/examples.json';

  static Map<String, List<WordExample>>? _bank;
  static Future<void>? _loading;

  /// 保证资源已解析。重复调用只读一次。
  static Future<void> ensureLoaded() {
    if (_bank != null) return Future.value();
    return _loading ??= rootBundle.loadString(assetPath).then((raw) {
      _bank = parseExamplesAsset(raw);
      _loading = null;
    }).catchError((Object _) {
      // 资源缺失不算错：详情页显示「暂无例句」。
      _bank = const <String, List<WordExample>>{};
      _loading = null;
    });
  }

  /// 取某个词的例句。没加载过就先返回空，等 [ensureLoaded] 完成后再取。
  static List<WordExample> forWord(String wordKey) =>
      _bank?[wordKey.trim().toLowerCase()] ?? const [];

  /// 测试注入。
  static void hydrate(String raw) {
    _bank = parseExamplesAsset(raw);
    _loading = null;
  }

  /// 测试复位。
  static void reset() {
    _bank = null;
    _loading = null;
  }

  /// 直接注入已解析好的数据（UI 用例更省事）。
  static void hydrateMap(Map<String, List<WordExample>> data) {
    _bank = data;
    _loading = null;
  }
}
