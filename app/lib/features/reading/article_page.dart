import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/app_signals.dart';
import '../../app/theme/app_colors.dart';
import '../../data/dao/article_dao.dart';
import '../../data/dao/detail_dao.dart';
import '../../data/dao/import_dao.dart';
import '../../data/models/article.dart';
import '../../data/models/word_detail.dart';
import '../../data/tts/article_reader.dart';
import '../../data/tts/speech.dart';

/// 文章详情页（v0.10.0）。
///
/// - 全文显示，目标词加粗；
/// - **双击单词**查意思与音标（查内置 ECDICT，不联网）；
/// - 查到的词可一键进生词本（按自加词口径：同一套六箱、0 箱起步）；
/// - 底部朗读条：播放 / 暂停 / 停止，逐句读，**不自动连播下一篇**。
class ArticlePage extends StatefulWidget {
  const ArticlePage({super.key, required this.article, this.reader});

  final Article article;

  /// 测试注入。生产为 null，用默认的 [ArticleReader]（真 TTS）。
  final ArticleReader? reader;

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  static const _dao = ArticleDao();
  static const _detailDao = DetailDao();

  late final ArticleReader _reader = widget.reader ?? ArticleReader();

  /// 去掉 `**` 的纯文本，双击时按它取词。
  late final String _plain = widget.article.body.replaceAll('**', '');

  /// 正文的富文本。缓存在 initState，重建时不用重新扫一遍正则。
  late final TextSpan _span = _buildSpan();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reader.load(widget.article.body);
    // 进页面就算读过。不 await，也不让写库失败挡住阅读：
    // widget 测试里没有 sqflite 通道，这条会抛 MissingPluginException，
    // 吞掉它是让页面能在纯 widget 环境里渲染（已读标记由列表页刷新兜底）。
    unawaited(_dao.markRead(widget.article.id).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _reader.dispose();
    super.dispose();
  }

  TextSpan _buildSpan() {
    final style = (Theme.of(context).textTheme.bodyLarge ??
            const TextStyle(fontSize: 16))
        .copyWith(color: AppColors.textPrimary, height: 1.95, fontSize: 16.5);
    final bold = style.copyWith(fontWeight: FontWeight.w700);

    final body = widget.article.body;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*', dotAll: true).allMatches(body)) {
      if (m.start > last) {
        spans.add(TextSpan(text: body.substring(last, m.start)));
      }
      spans.add(TextSpan(text: m.group(1), style: bold));
      last = m.end;
    }
    if (last < body.length) spans.add(TextSpan(text: body.substring(last)));

    return TextSpan(style: style, children: spans);
  }

  /// 双击：把点击坐标映射到字符，再取词。
  ///
  /// 用 `TextPainter` 复算一次版面（同样的样式、同样的宽度、同样的 textScaler），
  /// 才能把触点落到具体的词上。任何一处与真实 `RichText` 不一致，取出来的词
  /// 就会偏一个词 —— 所以这里的 style 与 `_buildSpan` 必须同源。
  void _handleDoubleTap(Offset local, double maxWidth) {
    final painter = TextPainter(
      text: _span,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    final position = painter.getPositionForOffset(local);
    final range = painter.getWordBoundary(position);
    if (range.start >= _plain.length) return;

    final raw = _plain.substring(
      range.start,
      range.end.clamp(0, _plain.length),
    );
    final word = raw.replaceAll(RegExp(r"[^A-Za-z'\-]"), '').toLowerCase();
    if (word.length < 2) return;
    unawaited(_lookup(word));
  }

  Future<void> _lookup(String word) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final detail = await _detailDao.load(word);
      if (!mounted) return;
      if (detail == null) {
        _snack('离线词典里查不到「$word」。');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (_) => _WordSheet(detail: detail),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = widget.article;

    return Scaffold(
      appBar: AppBar(
        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                children: [
                  Text(
                    '${a.targetWords.length} 个目标词 · ${a.wordCount} 词 · '
                    '生词率 ${a.rarePercent}%',
                    style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '双击正文里的词可以查意思与音标',
                    style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (ctx, constraints) {
                      return GestureDetector(
                        key: const ValueKey('article-body'),
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: (d) =>
                            _handleDoubleTap(d.localPosition, constraints.maxWidth),
                        onDoubleTap: () {},
                        child: RichText(
                          textScaler: MediaQuery.textScalerOf(context),
                          textDirection: Directionality.of(context),
                          text: _span,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 18),
                  Text(
                    '本篇单词',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final w in a.targetWords)
                    _TargetWordRow(
                      key: ValueKey('target-${w.word}'),
                      word: w,
                      onTap: () => _lookup(w.word),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '文章由 DeepSeek 按你的词库生成，只存在本机。',
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            _ReaderBar(reader: _reader),
          ],
        ),
      ),
    );
  }
}

/// 单词表一行：词 + 词性 + 释义，右侧一颗小喇叭直接发音。
class _TargetWordRow extends StatelessWidget {
  const _TargetWordRow({super.key, required this.word, required this.onTap});

  final ArticleWord word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: word.word,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (word.pos.isNotEmpty)
                        TextSpan(
                          text: '  ${word.pos}',
                          style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                        ),
                      TextSpan(
                        text: word.meaning.isEmpty ? '' : '  ${word.meaning}',
                        style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('speak-${word.word}'),
                onPressed: () => Speech.speak(word.word),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                tooltip: '发音',
                icon: const Icon(Icons.volume_up_outlined, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部朗读条。
class _ReaderBar extends StatelessWidget {
  const _ReaderBar({required this.reader});

  final ArticleReader reader;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: reader,
      builder: (context, _) {
        final state = reader.state;
        final total = reader.sentences.length;
        final playing = state == ReaderState.playing;

        IconData icon;
        String tooltip;
        VoidCallback? onPressed;

        switch (state) {
          case ReaderState.unavailable:
            icon = Icons.volume_off_outlined;
            tooltip = '这台设备没有英文语音引擎';
            onPressed = null;
          case ReaderState.finished:
            icon = Icons.replay;
            tooltip = '从头再读一遍';
            onPressed = () => unawaited(reader.play());
          case ReaderState.playing:
            icon = Icons.pause;
            tooltip = '暂停';
            onPressed = () => unawaited(reader.pause());
          case ReaderState.idle:
          case ReaderState.paused:
            icon = Icons.play_arrow;
            tooltip = state == ReaderState.paused ? '继续' : '朗读全文';
            onPressed = total == 0 ? null : () => unawaited(reader.play());
        }

        final String progress;
        if (total == 0) {
          progress = '没有可读的内容';
        } else if (state == ReaderState.finished) {
          progress = '已读完（共 $total 句）';
        } else if (state == ReaderState.paused) {
          progress = '已暂停 · 第 ${(reader.cursor + 1).clamp(1, total)} / $total 句';
        } else if (playing) {
          progress = '第 ${(reader.cursor + 1).clamp(1, total)} / $total 句';
        } else {
          progress = '共 $total 句';
        }

        return Container(
          padding: EdgeInsets.only(
            left: 8,
            right: 12,
            top: 4,
            bottom: 4 + MediaQuery.paddingOf(context).bottom * 0.2,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('reader-play'),
                onPressed: onPressed,
                tooltip: tooltip,
                iconSize: 22,
                icon: Icon(icon, color: onPressed == null
                    ? AppColors.textTertiary
                    : AppColors.textPrimary),
              ),
              IconButton(
                key: const ValueKey('reader-stop'),
                onPressed: () => unawaited(reader.stop()),
                tooltip: '停止',
                iconSize: 18,
                icon: const Icon(Icons.stop, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  progress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 双击查词的底部弹层：词 / 音标 / 释义 / 发音 / 加入生词本。
class _WordSheet extends StatefulWidget {
  const _WordSheet({required this.detail});

  final WordDetail detail;

  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  static const _importDao = ImportDao();

  bool _adding = false;
  bool _added = false;

  String get _meaning {
    final pdf = widget.detail.meaningPdf.trim();
    if (pdf.isNotEmpty) return pdf;
    return widget.detail.meaningEcdict.trim();
  }

  Future<void> _add() async {
    if (_adding || _added) return;
    setState(() => _adding = true);
    try {
      await _importDao.commit(
        fileName: '阅读页查词',
        candidates: [
          ImportCandidate(word: widget.detail.wordKey, meaning: _meaning),
        ],
      );
      if (!mounted) return;
      AppSignals.libraryUpdated();
      setState(() => _added = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${widget.detail.wordKey}」已进生词本，从 0 箱开始。')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加入失败，再试一次。')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final d = widget.detail;
    final inList = d.inMyList || _added;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    d.word.isEmpty ? d.wordKey : d.word,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                if (d.phonetic.trim().isNotEmpty)
                  Text(
                    '/${d.phonetic.trim()}/',
                    style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('sheet-speak'),
                  onPressed: () => Speech.speak(d.wordKey),
                  tooltip: '发音',
                  iconSize: 20,
                  icon: const Icon(Icons.volume_up_outlined, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_meaning.isEmpty)
              Text(
                '离线词典里没有释义。',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              )
            else
              Text(
                _meaning,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.8,
                ),
              ),
            if (d.killed) ...[
              const SizedBox(height: 8),
              Text(
                '这个词已斩（不在学习队列里）。',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('sheet-add'),
                onPressed: inList || _adding ? null : _add,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(
                  inList
                      ? '已在词表里'
                      : (_adding ? '加入中…' : '加入生词本'),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
