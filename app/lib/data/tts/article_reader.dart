import 'package:flutter/foundation.dart';

import 'speech.dart';

/// 朗读用的发音后端。抽出来是为了测试：`flutter test` 里没有 TTS 引擎。
abstract class SpeechBackend {
  /// 说一段，说完才返回 true；被打断返回 false。
  Future<bool> speakSegment(String text);

  Future<void> stop();
}

/// 真机实现：走到 `MainActivity` 的 TextToSpeech。
class SystemSpeechBackend implements SpeechBackend {
  const SystemSpeechBackend();

  @override
  Future<bool> speakSegment(String text) => Speech.speakSegment(text);

  @override
  Future<void> stop() => Speech.stop();
}

/// 朗读状态。
enum ReaderState {
  /// 还没开始（或已停止、回到开头）。
  idle,

  /// 正在读。
  playing,

  /// 停在某一句，继续时从那句重播。
  paused,

  /// 读完了全文。
  finished,

  /// 这台设备没有英文语音引擎 —— 界面提示一句，不报错。
  unavailable,
}

/// 全文朗读控制器（v0.10.0）。
///
/// Android 的 TTS **没有 pause**，只有 stop。所以「暂停」实现成：
/// 记住当前读到第几句 → stop；继续时从那句重播（不是从句中接着读，
/// 但用户感知是「停在这句」）。
///
/// 逐句串行播，不排队 —— `QUEUE_ADD` 一次性把 60 句塞进去之后就没法
/// 精确知道读到哪句、也没法在中途停在一个确定的位置。
///
/// 用「代次」而不是「是否在跑」的布尔量来管并发：`play` / `pause` / `stop`
/// 每次都会让代次 +1，旧循环在下一个 await 之后立刻退出，不会有两个循环
/// 同时往 TTS 里塞句子。
class ArticleReader extends ChangeNotifier {
  ArticleReader({SpeechBackend? backend})
    : _backend = backend ?? const SystemSpeechBackend();

  final SpeechBackend _backend;

  List<String> _sentences = const [];
  int _cursor = 0;
  int _generation = 0;
  ReaderState _state = ReaderState.idle;

  List<String> get sentences => List.unmodifiable(_sentences);
  int get cursor => _cursor;
  ReaderState get state => _state;

  /// 当前停在哪一句（给界面做进度显示）。
  String get currentSentence =>
      _cursor >= 0 && _cursor < _sentences.length ? _sentences[_cursor] : '';

  bool get isPlaying => _state == ReaderState.playing;
  bool get isPaused => _state == ReaderState.paused;
  bool get canPlay => _sentences.isNotEmpty && _state != ReaderState.unavailable;

  /// 换一篇文章。会停掉正在读的。
  void load(String body) {
    _generation++;
    _sentences = splitSentences(body);
    _cursor = 0;
    _state = ReaderState.idle;
    notifyListeners();
  }

  /// 开始 / 继续。读完再点从头开始。
  Future<void> play() async {
    if (_sentences.isEmpty) return;
    if (_state == ReaderState.playing) return;

    if (_state == ReaderState.finished) _cursor = 0;
    _state = ReaderState.playing;
    final gen = ++_generation;
    notifyListeners();

    while (_cursor < _sentences.length) {
      final ok = await _backend.speakSegment(_sentences[_cursor]);
      // 这一代已经被 pause / stop / 新的一次 play 接管了，直接退出，
      // 不要动 state，也不要再往 TTS 里塞句子。
      if (gen != _generation) return;
      if (!ok) {
        _state = ReaderState.unavailable;
        notifyListeners();
        return;
      }
      _cursor++;
      notifyListeners();
    }

    if (gen == _generation && _cursor >= _sentences.length) {
      _state = ReaderState.finished;
      notifyListeners();
    }
  }

  /// 暂停：停在第几号句子上，继续时从这句重播。
  Future<void> pause() async {
    if (_state != ReaderState.playing) return;
    _generation++;
    _state = ReaderState.paused;
    notifyListeners();
    await _backend.stop();
  }

  /// 停止：回到开头。
  Future<void> stop() async {
    _generation++;
    _state = ReaderState.idle;
    _cursor = 0;
    notifyListeners();
    await _backend.stop();
  }

  @override
  void dispose() {
    _generation++;
    _state = ReaderState.idle;
    super.dispose();
    // 不 await：dispose 不能异步，stop 是「尽力而为」。
    _backend.stop();
  }
}

/// 把正文切成朗读的句子。
///
/// - 先去掉 `**` 加粗标记（朗读不读星号）；
/// - 段落换行也当分隔；
/// - 以 `Mr.` / `Dr.` / `U.S.` 这类缩写结尾的片段不切开；
/// - 太短的碎片（< 3 个词）并到上一句，避免 TTS 一句一顿地蹦。
List<String> splitSentences(String body) {
  final plain = body.replaceAll('**', '');
  final rough = <String>[];

  for (final paragraph in plain.split(RegExp(r'\n\s*\n'))) {
    final text = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    // 句末标点（可带一个引号）后面跟空白 = 句子边界。
    // 正则用双引号 raw string：模式里同时有单引号与双引号，单引号定界会截断。
    for (final piece in text.split(RegExp(r'''(?<=[.!?])["'”’]?\s+'''))) {
      final s = piece.trim();
      if (s.isNotEmpty) rough.add(s);
    }
  }

  final out = <String>[];
  for (final sentence in rough) {
    if (out.isNotEmpty && (_isAbbreviationEnding(out.last) || _wordCount(sentence) < 3)) {
      out[out.length - 1] = '${out.last} $sentence';
    } else {
      out.add(sentence);
    }
  }
  return out;
}

bool _isAbbreviationEnding(String sentence) {
  final m = RegExp(r'(\b[A-Za-z]{1,3}\.)$').firstMatch(sentence);
  if (m == null) return false;
  final token = m.group(1)!.toLowerCase();
  const abbrev = {
    'mr.', 'mrs.', 'ms.', 'dr.', 'st.', 'jr.', 'sr.', 'vs.', 'etc.',
    'e.g.', 'i.e.', 'no.', 'fig.', 'prof.', 'gov.', 'capt.', 'lt.',
  };
  return abbrev.contains(token) || RegExp(r'^[a-z]\.$').hasMatch(token);
}

int _wordCount(String s) =>
    s.split(RegExp(r'\s+')).where((w) => RegExp('[A-Za-z]').hasMatch(w)).length;
