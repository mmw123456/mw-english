import '../dao/article_dao.dart';
import '../llm/deepseek_client.dart';
import '../llm/secret_store.dart';
import '../models/article.dart';
import 'article_check.dart';
import 'article_metrics.dart';
import 'article_parser.dart';
import 'article_prompt.dart';
import 'rare_words.dart';
import 'word_picker.dart';

/// 生成一篇的进度，给阅读页的按钮态用。
enum ArticleStage {
  /// 从词库里挑 25 个目标词。
  picking,

  /// 请求模型。
  calling,

  /// 自检不过，带着原因重试。
  retrying,

  /// 写库。
  saving,
}

/// 按词库生成文章（v0.10.0）。
///
/// 一次生成的完整链路：读 Key → 取词 → 调接口 → 解析 → 度量 → 自检 →
/// 不过就带原因重试一次 → 仍不过报错不存 → 过了单事务写库。
///
/// 所有依赖都可注入：`flutter test` 里不许真打 DeepSeek（按量付费），
/// 也不许开 sqflite（要设备）。测试塞假 LLM / 假存储 / 假词池，走完整条链。
class ArticleService {
  ArticleService({
    WordPool? pool,
    ArticleStore? store,
    RareWordLookup? rareWords,
    SecretStore? secrets,
    ArticleLlm Function(String apiKey)? llmFactory,
  }) : _pool = pool ?? const SqlWordPool(),
       _store = store ?? const ArticleDao(),
       _rare = rareWords ?? const SqlRareWordLookup(),
       _secrets = secrets ?? SecureSecretStore(),
       _llmFactory = llmFactory ?? ((key) => DeepSeekClient(apiKey: key));

  final WordPool _pool;
  final ArticleStore _store;
  final RareWordLookup _rare;
  final SecretStore _secrets;
  final ArticleLlm Function(String apiKey) _llmFactory;

  /// 生成下一篇。只由用户点「生成下一篇」触发，**不自动批量跑**（决策 118）。
  ///
  /// 失败一律抛 [LlmException]：message 是给人看的一句话，UI 直接显示。
  /// 注意「词不够」这种前置条件也用它 —— 对界面来说都是「这次没生成出来」。
  Future<Article> generateNext({
    void Function(ArticleStage stage, String message)? onProgress,
    DateTime? now,
  }) async {
    void report(ArticleStage s, String m) => onProgress?.call(s, m);

    // ① Key
    final key = await _secrets.readKey();
    if (key == null) {
      throw const LlmException('先去「我的 → 设置」填 DeepSeek API Key，再回来生成。');
    }

    // ② 取词
    report(ArticleStage.picking, '正在挑这一篇的 25 个词…');
    final picked = await _pickTargets();
    final targets = picked.map((w) => w.toArticleWord()).toList();

    // ③ 调模型（最多两次：第一次 + 自检不过重试一次）
    final llm = _llmFactory(key);
    var raw = '';
    var attempt = 0;
    List<String> problems = const [];
    RawArticle? parsed;
    ArticleMetrics? metrics;

    while (attempt < 2) {
      attempt++;
      report(
        attempt == 1 ? ArticleStage.calling : ArticleStage.retrying,
        attempt == 1 ? '正在生成（一般 20–60 秒）…' : '上一版没过自检，正在重写…',
      );

      raw = await llm.complete(
        system: articleSystemPrompt,
        user: buildArticleUserPrompt(
          targetWords: targets,
          retryNote: attempt == 1 ? '' : _hint(problems),
        ),
      );

      try {
        parsed = parseArticleResponse(raw);
      } on ArticleFormatException catch (e) {
        problems = [e.message];
        continue;
      }

      // 生词率要先查词典，所以度量放在这里，不在 check 里。
      final isRare = await _rare.prepare(tokenizeBody(parsed.body));
      metrics = measureArticle(
        body: parsed.body,
        targetWords: targets.map((t) => t.word).toSet(),
        isRareWord: isRare,
      );

      final check = checkArticle(
        body: parsed.body,
        targets: targets,
        words: parsed.words,
        metrics: metrics,
      );
      if (check.ok) {
        problems = const [];
        break;
      }
      problems = check.problems;
    }

    if (parsed == null || metrics == null || problems.isNotEmpty) {
      throw LlmException(
        '两次都没通过自检，这次没存。${problems.isEmpty ? '' : '原因：${_hint(problems)}'}',
      );
    }

    // ④ 存库
    report(ArticleStage.saving, '正在保存…');
    final id = await _store.save(
      title: parsed.title,
      body: parsed.body,
      targetWords: parsed.words,
      wordCount: metrics.wordCount,
      rareRatio: metrics.rareRatio,
      model: DeepSeekClient.defaultModel,
      now: now,
    );

    return Article(
      id: id,
      title: parsed.title,
      body: parsed.body,
      targetWords: parsed.words,
      wordCount: metrics.wordCount,
      rareRatio: metrics.rareRatio,
      model: DeepSeekClient.defaultModel,
      createdAt: now ?? DateTime.now(),
    );
  }

  /// 取 25 个；不够就报清楚缺多少。
  Future<List<PoolWord>> _pickTargets() async {
    final used = await _store.usedWordKeys();
    final pool = await _pool.load();
    final picked = pickTargets(pool: pool, used: used);

    if (picked.length >= articleTargetCount) return picked;

    final usable = pool
        .where((w) => !w.killed && !used.contains(w.wordKey) && w.wordKey.isNotEmpty)
        .length;
    if (usable == 0) {
      throw const LlmException(
        '词库里没有可用的词了 —— 820 词都出过文章、也都被斩了。'
        '去词库加些新词，或者把斩掉的词恢复几个。',
      );
    }
    throw LlmException(
      '能用的词只剩 $usable 个，不够 $articleTargetCount 个。'
      '去词库加些新词，或者把斩掉的词恢复几个。',
    );
  }

  Future<List<Article>> list({int limit = 50}) => _store.recent(limit: limit);

  Future<Article?> byId(int id) => _store.byId(id);

  Future<void> markRead(int id, {DateTime? now}) =>
      _store.markRead(id, now: now);

  Future<int> count() => _store.count();

  /// 提示：重试时喂回模型，报错时给人看。超过 3 条就截断，别让提示比正文还长。
  String _hint(List<String> problems) {
    if (problems.isEmpty) return '';
    const max = 3;
    final head = problems.take(max).map((p) => '· $p').join('\n');
    if (problems.length <= max) return head;
    return '$head\n（还有 ${problems.length - max} 条同类问题）';
  }
}
