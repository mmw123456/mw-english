import '../models/article.dart';
import 'article_metrics.dart';

/// 生成规矩里的硬数字（v3，用户 2026-11-27 定，不许在别处另写一套）。
const int articleTargetCount = 25;
const int articleMinWords = 350;
const int articleMaxWords = 500;
const double articleMinRareRatio = 0.02;
const double articleMaxRareRatio = 0.05;

/// 自检结果。
class ArticleCheck {
  const ArticleCheck({required this.problems});

  /// 空 = 过了。每条都是中文人话：既显示给用户，也喂回模型让它知道错在哪。
  final List<String> problems;

  bool get ok => problems.isEmpty;

  /// 喂回模型时只带前几条，免得整段报错比正文还长。
  String get retryHint => problems.take(5).map((p) => '- $p').join('\n');
}

/// 生成后自检四项：目标词 25 个、每词正文只出现一次且加粗、篇幅 350–500、
/// 生词率 2–5%。不过就重试一次，还不过报错不存（决策 115）。
///
/// [targets] 是我们要求它用的 25 个目标词（小写），[words] 是模型自己交的单词表。
/// 两者都要查：模型可能只写 22 个词，也可能偷换成同义词。
ArticleCheck checkArticle({
  required String body,
  required List<ArticleWord> targets,
  required List<ArticleWord> words,
  required ArticleMetrics metrics,
}) {
  final problems = <String>[];

  // ① 目标词数
  if (targets.length != articleTargetCount) {
    problems.add('这次只凑到 ${targets.length} 个目标词，要 $articleTargetCount 个。');
  }

  // ② 单词表覆盖
  final got = {for (final w in words) w.word};
  final missing = targets.map((w) => w.word).where((w) => !got.contains(w)).toList();
  final extra = got.where((w) => !targets.any((r) => r.word == w)).toList();
  if (missing.isNotEmpty) {
    problems.add('单词表里少了这 ${missing.length} 个词：${_join(missing)}。');
  }
  if (extra.isNotEmpty) {
    problems.add('单词表里多了不该有的词：${_join(extra)}。');
  }

  // ③ 每个词：正文只出现一次，且这一次是加粗的
  final boldCount = <String, int>{};
  for (final b in metrics.boldWords) {
    boldCount[b] = (boldCount[b] ?? 0) + 1;
  }
  for (final w in targets) {
    final hits = countOccurrences(body, w.word);
    if (hits == 0) {
      problems.add('「${w.word}」没有出现在正文里（要原形，不要变位变数）。');
      continue;
    }
    if (hits > 1) {
      problems.add('「${w.word}」在正文里出现了 $hits 次，只能出现 1 次。');
    }
    final bold = boldCount[w.word] ?? 0;
    if (bold == 0) {
      problems.add('「${w.word}」没有加粗（要用 **${w.word}** 标）。');
    } else if (bold > 1) {
      problems.add('「${w.word}」被加粗了 $bold 次，只能加粗 1 次。');
    }
  }
  for (final b in boldCount.keys) {
    if (!targets.any((r) => r.word == b)) {
      problems.add('「$b」被加粗了，但它不在这次的 25 个目标词里。');
    }
  }

  // ④ 篇幅
  if (metrics.wordCount < articleMinWords || metrics.wordCount > articleMaxWords) {
    problems.add(
      '正文 ${metrics.wordCount} 词，要在 $articleMinWords–$articleMaxWords 之间。',
    );
  }

  // ⑤ 生词率（除目标词外）
  if (metrics.rareRatio < articleMinRareRatio ||
      metrics.rareRatio > articleMaxRareRatio) {
    problems.add(
      '生词率 ${(metrics.rareRatio * 100).toStringAsFixed(1)}%，'
      '要在 2–5% 之间 —— 除这 25 个目标词外，别的词请用 CET-4 以内的常见词。',
    );
  }

  return ArticleCheck(problems: problems);
}

String _join(List<String> items) {
  const max = 6;
  if (items.length <= max) return items.join('、');
  return '${items.take(max).join('、')} 等';
}
