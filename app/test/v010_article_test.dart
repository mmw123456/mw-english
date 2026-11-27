import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/data/article/article_check.dart';
import 'package:mw_english/data/article/article_metrics.dart';
import 'package:mw_english/data/article/article_parser.dart';
import 'package:mw_english/data/article/article_service.dart';
import 'package:mw_english/data/article/rare_words.dart';
import 'package:mw_english/data/article/word_picker.dart';
import 'package:mw_english/data/dao/article_dao.dart';
import 'package:mw_english/data/llm/deepseek_client.dart';
import 'package:mw_english/data/llm/secret_store.dart';
import 'package:mw_english/data/models/article.dart';
import 'package:mw_english/data/tts/article_reader.dart';
import 'package:mw_english/features/profile/deepseek_key_card.dart';
import 'package:mw_english/features/reading/article_page.dart';
import 'package:mw_english/features/reading/reading_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 固定数据：25 个真词 + 一段能过自检的正文
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _targets = [
  'abandon', 'ability', 'absorb', 'abstract', 'academic',
  'accept', 'access', 'accident', 'account', 'achieve',
  'acquire', 'adapt', 'adjust', 'admire', 'admit',
  'adopt', 'advance', 'affect', 'afford', 'agency',
  'agenda', 'agree', 'allow', 'alter', 'amaze',
];

/// 填充词：都是简单词，且一个都不在 [_targets] 里。
const List<String> _filler = [
  'the', 'a', 'an', 'and', 'or', 'but', 'so', 'if', 'then', 'when',
  'while', 'after', 'before', 'at', 'in', 'on', 'for', 'with', 'of', 'to',
  'from', 'by', 'we', 'they', 'it', 'he', 'she', 'people', 'day', 'time',
  'year', 'place', 'work', 'life', 'hand', 'way', 'part', 'world', 'home',
  'room', 'water', 'food', 'book', 'word', 'name', 'number', 'line', 'end',
  'side', 'kind', 'group', 'team', 'city', 'town', 'road', 'car', 'tree',
  'house', 'school', 'office', 'market', 'street', 'morning', 'evening',
  'night', 'week', 'month', 'spring', 'summer', 'autumn', 'winter', 'light',
  'dark', 'warm', 'cold', 'long', 'short', 'small', 'large', 'good', 'bad',
  'new', 'old', 'young', 'happy', 'sad', 'quiet', 'loud', 'soft', 'hard',
  'fast', 'slow', 'easy', 'busy', 'free', 'open', 'close', 'full', 'empty',
  'clean', 'dirty', 'rich', 'poor', 'strong', 'weak', 'early', 'late',
  'near', 'far', 'once', 'again', 'still', 'much', 'many', 'few', 'very',
];

/// 12 个自造「生词」：→ 400 词里 12 个 = 3.0%，正好在 2–5% 中间。
const List<String> _rareWords = [
  'zorblat', 'quibblex', 'flumox', 'gribnash', 'plenthor', 'vandric',
  'morvex', 'skallow', 'trembic', 'yulmark', 'draneth', 'obscurix',
];

/// 造一篇能过全部自检的正文：25 个目标词各一次且加粗、总词数可调、3.0% 生词率。
String _goodBody({int totalWords = 400}) {
  final tokens = <String>[];
  for (final t in _targets) {
    tokens.addAll(['then', 'we', '**$t**', 'in', 'the', 'town', 'and']);
  }
  tokens.addAll(_rareWords);
  var i = 0;
  while (tokens.length < totalWords) {
    tokens.add(_filler[i++ % _filler.length]);
  }
  return tokens.take(totalWords).join(' ');
}

String _goodResponse({List<String>? targets, String? body}) {
  final t = targets ?? _targets;
  final b = body ?? _goodBody();
  final buffer = StringBuffer()
    ..writeln('TITLE: A Small Town Story')
    ..writeln('---')
    ..writeln(b)
    ..writeln('---');
  for (final w in t) {
    buffer.writeln('$w|v.|释义 $w');
  }
  return buffer.toString();
}

List<ArticleWord> _targetWords([List<String>? list]) {
  final t = list ?? _targets;
  return [for (final w in t) ArticleWord(word: w, pos: 'v.', meaning: '释义 $w')];
}

// ─────────────────────────────────────────────────────────────────────────────
// 假实现
// ─────────────────────────────────────────────────────────────────────────────

class _FakeLlm implements ArticleLlm {
  _FakeLlm(this.responses);

  /// 元素是 String（正常返回）或 Exception（抛出来）。
  final List<Object> responses;
  int calls = 0;
  String lastUserPrompt = '';

  @override
  Future<String> complete({required String system, required String user}) async {
    lastUserPrompt = user;
    final r = responses[calls.clamp(0, responses.length - 1)];
    calls++;
    if (r is Exception) throw r;
    return r as String;
  }
}

class _FakeStore implements ArticleStore {
  final List<Article> items = [];
  final Map<int, Set<String>> links = {};
  int _nextId = 1;
  int saveCount = 0;

  @override
  Future<Set<String>> usedWordKeys() async =>
      links.values.expand((e) => e).toSet();

  @override
  Future<List<Article>> recent({int limit = 50}) async {
    final sorted = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<Article?> byId(int id) async {
    for (final a in items) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<int> count() async => items.length;

  @override
  Future<int> save({
    required String title,
    required String body,
    required List<ArticleWord> targetWords,
    required int wordCount,
    required double rareRatio,
    required String model,
    DateTime? now,
  }) async {
    saveCount++;
    final id = _nextId++;
    items.add(
      Article(
        id: id,
        title: title,
        body: body,
        targetWords: targetWords,
        wordCount: wordCount,
        rareRatio: rareRatio,
        model: model,
        createdAt: now ?? DateTime(2026, 11, 27, 10).add(Duration(seconds: id)),
      ),
    );
    links[id] = targetWords.map((w) => w.word).toSet();
    return id;
  }

  @override
  Future<void> markRead(int id, {DateTime? now}) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].id == id && items[i].readAt == null) {
        items[i] = items[i].copyWith(readAt: now ?? DateTime(2026, 11, 27, 12));
      }
    }
  }
}

class _FakePool implements WordPool {
  _FakePool(this.words);
  final List<PoolWord> words;

  @override
  Future<List<PoolWord>> load() async => words;
}

class _FakeRare implements RareWordLookup {
  _FakeRare([Set<String>? rare]) : rare = rare ?? _rareWords.toSet();
  final Set<String> rare;

  @override
  Future<IsRareWord> prepare(Iterable<String> tokens) async =>
      (String w) => rare.contains(w);
}

/// 可控的后端：每段都要测试手动放行，才能测「暂停停在半路」。
class _GatedSpeech implements SpeechBackend {
  final List<String> spoken = [];
  final List<Completer<bool>> gates = [];
  int stopCalls = 0;

  @override
  Future<bool> speakSegment(String text) {
    spoken.add(text);
    final c = Completer<bool>();
    gates.add(c);
    return c.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    for (final c in gates) {
      if (!c.isCompleted) c.complete(false);
    }
  }

  void finish(int index) {
    if (!gates[index].isCompleted) gates[index].complete(true);
  }
}

class _InstantSpeech implements SpeechBackend {
  final List<String> spoken = [];
  int stopCalls = 0;

  @override
  Future<bool> speakSegment(String text) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async => stopCalls++;
}

ArticleService _service({
  required _FakeLlm llm,
  _FakeStore? store,
  List<PoolWord>? pool,
  String? key = 'sk-test-key',
}) {
  return ArticleService(
    pool: _FakePool(pool ?? _bookPool(30)),
    store: store ?? _FakeStore(),
    rareWords: _FakeRare(),
    secrets: MemorySecretStore(key),
    llmFactory: (_) => llm,
  );
}

List<PoolWord> _bookPool(int count) {
  return [
    for (var i = 0; i < count; i++)
      PoolWord(
        wordKey: _targets[i % _targets.length] + (i < _targets.length ? '' : '$i'),
        order: i + 1,
        fromBook: true,
        killed: false,
        box: 0,
        streak: 0,
        meaning: 'v. 释义',
      ),
  ];
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  group('解析模型返回', () {
    test('标准三段格式', () {
      final r = parseArticleResponse('''
TITLE: A Small Town Story
---
Then we **abandon** the plan.
---
abandon|v.|放弃
prompt|v.|促使
''');
      expect(r.title, 'A Small Town Story');
      expect(r.body, contains('**abandon**'));
      expect(r.words.length, 2);
      expect(r.words.first.word, 'abandon');
      expect(r.words.first.pos, 'v.');
      expect(r.words.first.meaning, '放弃');
    });

    test('代码围栏会剥掉', () {
      final r = parseArticleResponse('''
```markdown
TITLE: Fenced
---
Body with **word**.
---
word|n.|词
```
''');
      expect(r.title, 'Fenced');
      expect(r.body, 'Body with **word**.');
    });

    test('单词表用破折号 / Tab / 全角竖线都认', () {
      for (final sep in ['word|n.|词', 'word\tn.\t词', 'word｜n.｜词', 'word - 词']) {
        final r = parseArticleResponse('TITLE: X\n---\nA **word** here.\n---\n$sep\nother|v.|另一个');
        expect(r.words, isNotEmpty, reason: '分隔符：$sep');
        expect(r.words.first.word, 'word', reason: '分隔符：$sep');
      }
    });

    test('带表头的单词表', () {
      final r = parseArticleResponse('''
TITLE: X
---
A **word** here.
---
word|pos|meaning
word|n.|词
other|v.|另一个
''');
      expect(r.words.map((w) => w.word).toList(), ['word', 'other']);
    });

    test('缺标题时用正文首句兜底', () {
      final r = parseArticleResponse('''
---
Today is a bright day. We **walk** home.
---
walk|v.|走
other|v.|别的
''');
      expect(r.title, isNotEmpty);
      expect(r.title, contains('Today'));
    });

    test('正文没有加粗 → 抛格式错', () {
      expect(
        () => parseArticleResponse('TITLE: X\n---\nNo bold here.\n---\na|v.|一\nb|v.|二'),
        throwsA(isA<ArticleFormatException>()),
      );
    });

    test('没有单词表 → 抛格式错', () {
      expect(
        () => parseArticleResponse('TITLE: X\n---\nA **word** here.'),
        throwsA(isA<ArticleFormatException>()),
      );
    });

    test('正文空 → 抛格式错', () {
      expect(
        () => parseArticleResponse('TITLE: X\n---\n---\na|v.|一\nb|v.|二'),
        throwsA(isA<ArticleFormatException>()),
      );
    });

    test('词形不合法的行不算词条', () {
      final r = parseArticleResponse('''
TITLE: X
---
A **word** here.
---
word|v.|词
123||
other|v.|另一个
''');
      expect(r.words.map((w) => w.word).toList(), ['word', 'other']);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('度量：词数与生词率', () {
    test('目标词不计入生词率，短语拆开的每个词也不算', () {
      final metrics = measureArticle(
        body: 'We **take advantage of** the **abandon** here and there.',
        targetWords: {'take advantage of', 'abandon'},
        isRareWord: (w) => true, // 全都算生词
      );
      // 剩下的：we the here and there —— 5 个
      expect(metrics.rareCount, 5);
      expect(metrics.wordCount, 9);
    });

    test('加粗词按出现顺序收集并小写', () {
      final m = measureArticle(
        body: 'A **Word** and **Another** and **word**.',
        targetWords: {'word', 'another'},
        isRareWord: (_) => false,
      );
      expect(m.boldWords, ['word', 'another', 'word']);
    });

    test('生词率是词次比，不是不同词数比', () {
      final m = measureArticle(
        body: 'zorblat zorblat zorblat the the the the',
        targetWords: const {},
        isRareWord: (w) => w == 'zorblat',
      );
      expect(m.wordCount, 7);
      expect(m.rareCount, 3);
      expect(m.rareRatio, closeTo(3 / 7, 1e-9));
    });

    test('countOccurrences 按词边界，art 不命中 article', () {
      expect(countOccurrences('an article about art', 'art'), 1);
      expect(countOccurrences('**art** and art', 'art'), 2);
      expect(countOccurrences('take  advantage   of it', 'take advantage of'), 1);
    });

    test('tokenizeBody 去掉标记与标点', () {
      expect(tokenizeBody('We **abandon** it, now!'), ['we', 'abandon', 'it', 'now']);
    });

    test('生词率百分比四舍五入', () {
      const m = ArticleMetrics(wordCount: 400, rareCount: 12, boldWords: []);
      expect(m.rarePercent, 3);
      expect(m.rareRatio, 0.03);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('自检四项', () {
    ArticleCheck run(String body, {List<ArticleWord>? targets, List<ArticleWord>? words}) {
      final m = measureArticle(
        body: body,
        targetWords: (targets ?? _targetWords()).map((w) => w.word).toSet(),
        isRareWord: (w) => _rareWords.contains(w),
      );
      return checkArticle(
        body: body,
        targets: targets ?? _targetWords(),
        words: words ?? _targetWords(),
        metrics: m,
      );
    }

    test('全对 → 过', () {
      final c = run(_goodBody());
      expect(c.ok, isTrue, reason: c.problems.join(' / '));
      expect(c.problems, isEmpty);
    });

    test('目标词少一个 → 报出来', () {
      final c = run(_goodBody(), targets: _targetWords(_targets.take(24).toList()));
      expect(c.ok, isFalse);
      expect(c.problems.any((p) => p.contains('24 个目标词')), isTrue);
    });

    test('正文里少一个词 → 报「没有出现」', () {
      final body = _goodBody().replaceFirst('**abandon**', 'the');
      final c = run(body);
      expect(c.problems.any((p) => p.contains('abandon') && p.contains('没有出现')), isTrue);
    });

    test('同一个词出现两次 → 报次数', () {
      final body = '${_goodBody()} abandon';
      final c = run(body);
      expect(c.problems.any((p) => p.contains('出现了 2 次')), isTrue);
    });

    test('漏加粗 → 报没加粗', () {
      final body = _goodBody().replaceFirst('**abandon**', 'abandon');
      final c = run(body);
      expect(c.problems.any((p) => p.contains('没有加粗')), isTrue);
    });

    test('单词表少一个 → 报少了', () {
      final words = _targetWords().sublist(0, 24);
      final c = run(_goodBody(), words: words);
      expect(c.problems.any((p) => p.contains('少了')), isTrue);
    });

    test('单词表多一个 → 报多了', () {
      final words = [..._targetWords(), const ArticleWord(word: 'extra', pos: 'n.', meaning: '多的')];
      final c = run(_goodBody(), words: words);
      expect(c.problems.any((p) => p.contains('多了')), isTrue);
    });

    test('篇幅超了 → 报词数', () {
      final c = run(_goodBody(totalWords: 520));
      expect(c.problems.any((p) => p.contains('520 词')), isTrue);
    });

    test('篇幅短了 → 报词数', () {
      final c = run(_goodBody(totalWords: 300));
      expect(c.problems.any((p) => p.contains('300 词')), isTrue);
    });

    test('生词率过低 → 报区间', () {
      final m = measureArticle(
        body: _goodBody(),
        targetWords: _targets.toSet(),
        isRareWord: (_) => false, // 一个生词都没有 → 0%
      );
      final c = checkArticle(
        body: _goodBody(),
        targets: _targetWords(),
        words: _targetWords(),
        metrics: m,
      );
      expect(c.problems.any((p) => p.contains('生词率') && p.contains('2–5%')), isTrue);
    });

    test('加粗了不在目标词里的词 → 报出来', () {
      final body = _goodBody().replaceFirst('**abandon**', '**abandon** **stranger**');
      final c = run(body);
      expect(c.problems.any((p) => p.contains('stranger')), isTrue);
    });

    test('retryHint 最多给五条', () {
      final c = run('nothing here', targets: _targetWords());
      expect(c.retryHint.split('\n').length, lessThanOrEqualTo(5));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('取词器', () {
    PoolWord w(
      String key, {
      int order = 1,
      bool book = true,
      bool killed = false,
      int box = 0,
      int streak = 0,
    }) => PoolWord(
      wordKey: key,
      order: order,
      fromBook: book,
      killed: killed,
      box: box,
      streak: streak,
      meaning: 'v. 释义',
    );

    test('按 no 顺序取前 25 个', () {
      final pool = [for (var i = 1; i <= 40; i++) w('w$i', order: i)];
      final picked = pickTargets(pool: pool, used: const {});
      expect(picked.length, 25);
      expect(picked.first.wordKey, 'w1');
      expect(picked.last.wordKey, 'w25');
    });

    test('已斩的跳过', () {
      final pool = [w('a', order: 1), w('b', order: 2, killed: true), w('c', order: 3)];
      final picked = pickTargets(pool: pool, used: const {}, count: 3);
      expect(picked.map((e) => e.wordKey).toList(), ['a', 'c']);
    });

    test('已掌握的跳过（box ≥5 或 streak ≥3）', () {
      final pool = [
        w('a', order: 1, box: 5),
        w('b', order: 2, streak: 3),
        w('c', order: 3, box: 4, streak: 2),
      ];
      // count: 1 —— 只取一个，验证已掌握的被排在后面（回填在别的用例里验）
      final picked = pickTargets(pool: pool, used: const {}, count: 1);
      expect(picked.map((e) => e.wordKey).toList(), ['c']);
    });

    test('已经当过目标词的跳过', () {
      final pool = [w('a', order: 1), w('b', order: 2)];
      final picked = pickTargets(pool: pool, used: {'a'}, count: 2);
      expect(picked.map((e) => e.wordKey).toList(), ['b']);
    });

    test('新词不够时用已掌握的 820 回填', () {
      final pool = [
        for (var i = 1; i <= 30; i++) w('w$i', order: i, box: i <= 20 ? 5 : 0),
      ];
      final picked = pickTargets(pool: pool, used: const {});
      expect(picked.length, 25);
      // 前 10 个是没掌握的（w21–w30），再回填 w1–w15
      expect(picked.take(10).map((e) => e.wordKey).toList(), [for (var i = 21; i <= 30; i++) 'w$i']);
      expect(picked[10].wordKey, 'w1');
    });

    test('820 都出完了就接自加词，自加词先未掌握', () {
      final pool = [
        w('b1', order: 1),
        w('a1', order: 100, book: false),
        w('a2', order: 200, book: false, box: 6),
      ];
      final picked = pickTargets(pool: pool, used: {'b1'}, count: 3);
      expect(picked.map((e) => e.wordKey).toList(), ['a1', 'a2']);
    });

    test('可用的词不够就返回短的', () {
      final pool = [w('a'), w('b', killed: true)];
      expect(pickTargets(pool: pool, used: const {}, count: 25).length, 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('词形候选', () {
    test('复数 / 三单', () {
      expect(lemmaCandidates('studies'), contains('study'));
      expect(lemmaCandidates('books'), contains('book'));
      expect(lemmaCandidates('boxes'), contains('box'));
    });

    test('过去式 / 分词', () {
      expect(lemmaCandidates('decided'), contains('decide'));
      expect(lemmaCandidates('running'), contains('run'));
      expect(lemmaCandidates('walked'), contains('walk'));
    });

    test('副词 / 比较级', () {
      expect(lemmaCandidates('quickly'), contains('quick'));
      expect(lemmaCandidates('happily'), contains('happy'));
      expect(lemmaCandidates('bigger'), contains('big'));
    });

    test('原词永远排第一', () {
      expect(lemmaCandidates('was').first, 'was');
      expect(lemmaCandidates('the').first, 'the');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('DeepSeek 客户端', () {
    DeepSeekClient client(
      Future<http.Response> Function(http.Request) handler, {
      Duration timeout = const Duration(seconds: 5),
    }) {
      return DeepSeekClient(
        apiKey: 'sk-secret-do-not-leak',
        httpClient: MockClient(handler),
        timeout: timeout,
      );
    }

    test('200 正常返回正文', () async {
      final c = client((req) async {
        expect(req.headers['Authorization'], 'Bearer sk-secret-do-not-leak');
        return http.Response(
          '{"choices":[{"message":{"content":"TITLE: X"}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      expect(await c.complete(system: 's', user: 'u'), 'TITLE: X');
    });

    test('401 → 说 Key 不对', () async {
      final c = client((_) async => http.Response('{"error":{"message":"bad key"}}', 401));
      await expectLater(
        c.complete(system: 's', user: 'u'),
        throwsA(
          isA<LlmException>().having((e) => e.message, 'message', contains('Key 不对')),
        ),
      );
    });

    test('402 → 说余额不足', () async {
      final c = client((_) async => http.Response('{}', 402));
      await expectLater(
        c.complete(system: 's', user: 'u'),
        throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('余额不足'))),
      );
    });

    test('429 → 说太频繁', () async {
      final c = client((_) async => http.Response('{}', 429));
      await expectLater(
        c.complete(system: 's', user: 'u'),
        throwsA(
          isA<LlmException>()
              .having((e) => e.message, 'message', contains('太频繁'))
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('500 → 说服务不可用', () async {
      final c = client((_) async => http.Response('{}', 500));
      await expectLater(
        c.complete(system: 's', user: 'u'),
        throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('暂时不可用'))),
      );
    });

    test('超时 → 说超时并可重试', () async {
      final c = client(
        (_) => Future<http.Response>.delayed(
          const Duration(seconds: 2),
          () => http.Response('{}', 200),
        ),
        timeout: const Duration(milliseconds: 80),
      );
      await expectLater(
        c.complete(system: 's', user: 'u'),
        throwsA(
          isA<LlmException>()
              .having((e) => e.message, 'message', contains('超时'))
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('错误信息里绝不出现 Key', () async {
      for (final status in [400, 401, 402, 403, 429, 500]) {
        final c = client(
          (_) async => http.Response('{"error":{"message":"sk-secret-do-not-leak is bad"}}', status),
        );
        try {
          await c.complete(system: 's', user: 'u');
        } on LlmException catch (e) {
          expect(e.message, isNot(contains('sk-secret-do-not-leak')), reason: 'HTTP $status');
        }
      }
    });

    test('返回空内容 → 报错', () async {
      final c = client((_) async => http.Response('{"choices":[]}', 200));
      await expectLater(
        c.complete(system: 's', user: 'u'),
        throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('空内容'))),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('ArticleService 生成链路', () {
    test('没填 Key → 明说先去设置', () async {
      final s = _service(llm: _FakeLlm([_goodResponse()]), key: null);
      await expectLater(
        s.generateNext(),
        throwsA(
          isA<LlmException>().having((e) => e.message, 'message', contains('设置')),
        ),
      );
    });

    test('词不够 25 个 → 报清楚缺多少', () async {
      final s = ArticleService(
        pool: _FakePool(_bookPool(3)),
        store: _FakeStore(),
        rareWords: _FakeRare(),
        secrets: MemorySecretStore('sk-test'),
        llmFactory: (_) => _FakeLlm([_goodResponse()]),
      );
      await expectLater(
        s.generateNext(),
        throwsA(
          isA<LlmException>().having((e) => e.message, 'message', contains('不够 25 个')),
        ),
      );
    });

    test('一次过 → 存库并返回文章', () async {
      final store = _FakeStore();
      final llm = _FakeLlm([_goodResponse()]);
      final s = _service(llm: llm, store: store);

      final article = await s.generateNext();
      expect(llm.calls, 1);
      expect(store.saveCount, 1);
      expect(article.title, 'A Small Town Story');
      expect(article.targetWords.length, 25);
      expect(article.wordCount, 400);
      expect(article.rarePercent, 3);
      expect((await store.usedWordKeys()).length, 25);
    });

    test('第一次格式错、第二次好 → 成功且只重试一次', () async {
      final store = _FakeStore();
      final llm = _FakeLlm(['这不是我想要的格式', _goodResponse()]);
      final s = _service(llm: llm, store: store);

      final article = await s.generateNext();
      expect(llm.calls, 2);
      expect(store.saveCount, 1);
      expect(article.title, 'A Small Town Story');
      expect(llm.lastUserPrompt, contains('failed these checks'));
    });

    test('两次都不过 → 抛错且不存库', () async {
      final store = _FakeStore();
      final llm = _FakeLlm(['坏格式', '还是坏格式']);
      final s = _service(llm: llm, store: store);

      await expectLater(
        s.generateNext(),
        throwsA(
          isA<LlmException>().having((e) => e.message, 'message', contains('没存')),
        ),
      );
      expect(store.saveCount, 0);
      expect(store.items, isEmpty);
    });

    test('接口报错直接抛，不重试', () async {
      final llm = _FakeLlm([const LlmException('Key 不对')]);
      final s = _service(llm: llm);
      await expectLater(s.generateNext(), throwsA(isA<LlmException>()));
      expect(llm.calls, 1);
    });

    test('进度回调按阶段走', () async {
      final stages = <ArticleStage>[];
      final s = _service(llm: _FakeLlm([_goodResponse()]));
      await s.generateNext(onProgress: (stage, _) => stages.add(stage));
      expect(stages.first, ArticleStage.picking);
      expect(stages, contains(ArticleStage.calling));
      expect(stages.last, ArticleStage.saving);
    });

    test('第二次生成会跳过第一次用过的词', () async {
      final store = _FakeStore();
      final pool = _bookPool(60);
      final s = _service(
        llm: _FakeLlm([_goodResponse(), _goodResponse()]),
        store: store,
        pool: pool,
      );

      await s.generateNext();
      final firstUsed = await store.usedWordKeys();
      expect(firstUsed.length, 25);

      // 第二次的取词必须排除已用的 —— 这里只要确认 usedWordKeys 在增长即可
      final picked2 = pickTargets(pool: pool, used: firstUsed);
      expect(picked2.length, 25);
      expect(picked2.any((w) => firstUsed.contains(w.wordKey)), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('朗读控制器', () {
    test('切句：去标记、按句号切、缩写不断开', () {
      final s = splitSentences('Dr. Smith went home. He saw a **cat**. Was it his?');
      expect(s.length, 3);
      expect(s.first, startsWith('Dr. Smith'));
      expect(s[1], contains('cat'));
      expect(s[1], isNot(contains('**')));
    });

    test('太短的碎片并到上一句', () {
      final s = splitSentences('This is a full sentence. Yes. And another one here.');
      expect(s.any((e) => e == 'Yes.'), isFalse);
    });

    test('逐句播完到 finished', () async {
      final backend = _InstantSpeech();
      final reader = ArticleReader(backend: backend);
      reader.load('One two three. Four five six.');

      await reader.play();
      expect(backend.spoken.length, 2);
      expect(reader.state, ReaderState.finished);
    });

    test('暂停停住当前句，继续从这句重播', () async {
      final backend = _GatedSpeech();
      final reader = ArticleReader(backend: backend);
      reader.load('One two three. Four five six. Seven eight nine.');

      final playing = reader.play();
      await Future<void>.delayed(Duration.zero);
      expect(reader.state, ReaderState.playing);
      expect(reader.cursor, 0);

      // 第一句读完
      backend.finish(0);
      await Future<void>.delayed(Duration.zero);
      expect(reader.cursor, 1);

      // 第二句读到一半暂停
      await reader.pause();
      expect(reader.state, ReaderState.paused);
      expect(reader.cursor, 1);
      expect(backend.stopCalls, 1);

      await playing.timeout(const Duration(seconds: 1), onTimeout: () {});

      // 继续：从第 2 句重播
      backend.gates.clear();
      unawaited(reader.play());
      await Future<void>.delayed(Duration.zero);
      expect(reader.state, ReaderState.playing);
    });

    test('停止回到开头', () async {
      final backend = _InstantSpeech();
      final reader = ArticleReader(backend: backend);
      reader.load('One two three. Four five six.');
      await reader.play();
      await reader.stop();
      expect(reader.cursor, 0);
      expect(reader.state, ReaderState.idle);
    });

    test('设备没语音引擎 → unavailable，不崩', () async {
      final backend = _GatedSpeech();
      final reader = ArticleReader(backend: backend);
      reader.load('One two three.');
      unawaited(reader.play());
      await Future<void>.delayed(Duration.zero);
      backend.gates.first.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(reader.state, ReaderState.unavailable);
    });

    test('空正文 → play 什么都不做', () async {
      final backend = _InstantSpeech();
      final reader = ArticleReader(backend: backend);
      reader.load('   ');
      await reader.play();
      expect(backend.spoken, isEmpty);
      expect(reader.canPlay, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Key 掩码', () {
    test('只露头尾', () {
      expect(maskKey('sk-abcdefghijklmn'), 'sk-••••••klmn');
    });
    test('太短的整串盖掉', () {
      expect(maskKey('abc'), '••••••••');
    });
    test('空串返回空', () {
      expect(maskKey(''), '');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('页面', () {
    Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

    testWidgets('没有文章 → 空态 + 生成按钮', (tester) async {
      final s = _service(llm: _FakeLlm([_goodResponse()]));
      await tester.pumpWidget(wrap(ReadingPage(service: s)));
      await tester.pumpAndSettle();

      expect(find.text('还没有文章'), findsOneWidget);
      expect(find.byKey(const ValueKey('generate-next')), findsOneWidget);
      expect(find.text('生成下一篇'), findsOneWidget);
    });

    testWidgets('生成成功 → 出现今日推荐', (tester) async {
      final s = _service(llm: _FakeLlm([_goodResponse()]));
      await tester.pumpWidget(wrap(ReadingPage(service: s)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('generate-next')));
      await tester.pumpAndSettle();

      // 生成成功后自动进详情页。这里断言视口内的元素 —— 「本篇单词」在
      // 正文下方，ListView 懒构建，不代表页面没进去。
      expect(find.text('双击正文里的词可以查意思与音标'), findsOneWidget);
      expect(find.textContaining('400 词'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('今日推荐'), findsOneWidget);
      expect(find.textContaining('生词率 3%'), findsOneWidget);
    });

    testWidgets('生成失败 → 页内错误条，可关闭', (tester) async {
      final s = ArticleService(
        pool: _FakePool(_bookPool(30)),
        store: _FakeStore(),
        rareWords: _FakeRare(),
        secrets: MemorySecretStore(null),
        llmFactory: (_) => _FakeLlm([_goodResponse()]),
      );
      await tester.pumpWidget(wrap(ReadingPage(service: s)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('generate-next')));
      await tester.pumpAndSettle();

      expect(find.textContaining('设置'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('generate-error-close')));
      await tester.pumpAndSettle();
      expect(find.textContaining('设置'), findsNothing);
    });

    testWidgets('详情页：正文渲染、目标词加粗、单词表、朗读条', (tester) async {
      final article = Article(
        id: 1,
        title: 'A Small Town Story',
        body: 'We **abandon** the plan. Then we rest.',
        targetWords: const [
          ArticleWord(word: 'abandon', pos: 'v.', meaning: '放弃'),
        ],
        wordCount: 8,
        rareRatio: 0.03,
        model: 'deepseek-chat',
        createdAt: DateTime(2026, 11, 27),
      );

      await tester.pumpWidget(
        wrap(ArticlePage(article: article, reader: ArticleReader(backend: _InstantSpeech()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('本篇单词'), findsOneWidget);
      expect(find.textContaining('放弃', findRichText: true), findsWidgets);
      expect(find.byKey(const ValueKey('reader-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-stop')), findsOneWidget);
      expect(find.textContaining('共 2 句'), findsOneWidget);
    });

    testWidgets('详情页 320 宽不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final article = Article(
        id: 1,
        title: 'A Very Long Title That Should Be Truncated Somewhere',
        body: 'We **abandon** the plan with a very long sentence that keeps going and going.',
        targetWords: const [
          ArticleWord(word: 'abandon', pos: 'v.', meaning: '放弃；抛弃；遗弃'),
        ],
        wordCount: 16,
        rareRatio: 0.03,
        model: 'deepseek-chat',
        createdAt: DateTime(2026, 11, 27),
      );

      await tester.pumpWidget(
        wrap(ArticlePage(article: article, reader: ArticleReader(backend: _InstantSpeech()))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('列表 320 宽不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final s = _service(llm: _FakeLlm([_goodResponse()]));
      await tester.pumpWidget(wrap(ReadingPage(service: s)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generate-next')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Key 卡：输入框 → 保存 → 显示掩码', (tester) async {
      final store = MemorySecretStore();
      await tester.pumpWidget(
        wrap(Scaffold(body: SingleChildScrollView(child: DeepSeekKeyCard(store: store)))),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('deepseek-key-input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('deepseek-key-input')),
        'sk-abcdefghijklmn',
      );
      await tester.tap(find.byKey(const ValueKey('deepseek-key-save')));
      await tester.pumpAndSettle();

      expect(await store.readKey(), 'sk-abcdefghijklmn');
      expect(find.byKey(const ValueKey('deepseek-key-mask')), findsOneWidget);
      expect(find.text('sk-••••••klmn'), findsOneWidget);
      // 完整 Key 不许出现在界面上
      expect(find.text('sk-abcdefghijklmn'), findsNothing);
    });

    testWidgets('Key 卡：清除后回到输入态', (tester) async {
      final store = MemorySecretStore('sk-abcdefghijklmn');
      await tester.pumpWidget(
        wrap(Scaffold(body: SingleChildScrollView(child: DeepSeekKeyCard(store: store)))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('deepseek-key-clear')));
      await tester.pumpAndSettle();

      expect(await store.readKey(), isNull);
      expect(find.byKey(const ValueKey('deepseek-key-input')), findsOneWidget);
    });
  });
}
