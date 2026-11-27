import '../models/article.dart';

/// 组装调用 DeepSeek 的两段提示词。
///
/// v3 规矩（用户 2026-11-27 定，不许在别处改）：25 个目标词 / 350–500 词 /
/// CET-4 水平 / 每词正文只出现一次并加粗 / 多义词只用词书本义 /
/// 只要正文 + 单词表 / 自检不过就重写。
///
/// 提示词里刻意写死「输出三段、用 `**` 加粗」—— 解析器认的就是这个。
/// 模型对大结构的遵从度很高，对符号的遵从度一般，所以符号要反复强调。
const String articleSystemPrompt = '''
You write short English reading passages for Chinese college students whose English level is CET-4 (about 4,000–4,500 words).

Hard rules — break none of them:
1. Use EXACTLY 25 target words, each appearing EXACTLY ONCE in the passage, and mark each one in bold with double asterisks like **abandon**.
2. The passage must be 350–500 words.
3. Use the target words in their BASE FORM exactly as given (no -s, -ed, -ing, no plurals, no comparatives). If a target word is a phrase, keep the whole phrase intact.
4. Every other word must be within CET-4 level. Words above CET-4 (CET-6 / postgraduate / TOEFL / GRE / rare words) must make up 2%–5% of the passage — no more, no less. Everything else should be plain, common English.
5. If a target word has several meanings, use only the meaning given in the word list.
6. Genre is free: news, popular science, a story, a slice of life. Write like a human, not like a textbook exercise.
7. Do NOT add comprehension questions, cloze tests, translations, grammar notes, or any exercises.

Output format — exactly three parts, no extra commentary before or after:

TITLE: <one short English title>
---
<the passage; separate paragraphs with a blank line; target words in **bold**>
---
word|pos|meaning
(25 lines, one per target word, in any order)
''';

/// 用户侧提示词：把这 25 个词交给模型。
///
/// [retryNote] 非空表示这是第二次尝试，把上一版没过自检的原因带回去 ——
/// 比重新生成一篇更省 token，模型也知道该改哪儿。
String buildArticleUserPrompt({
  required List<ArticleWord> targetWords,
  String retryNote = '',
}) {
  final buffer = StringBuffer()
    ..writeln('Write one passage using exactly these 25 target words:')
    ..writeln();
  for (final w in targetWords) {
    buffer.writeln('${w.word}|${w.pos}|${w.meaning}');
  }
  buffer
    ..writeln()
    ..writeln('Remember: each word appears exactly once, in base form, marked in **bold**.')
    ..writeln('Passage length 350–500 words. All non-target words stay within CET-4.');

  if (retryNote.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Your previous attempt failed these checks:')
      ..writeln(retryNote.trim())
      ..writeln()
      ..writeln('Write a fresh passage that fixes every one of them.');
  }
  return buffer.toString();
}
