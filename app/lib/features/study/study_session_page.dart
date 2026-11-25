import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dao/study_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/study_card.dart';
import '../../data/tts/speech.dart';
import '../words/word_detail_page.dart';

/// 学习会话：认词卡 + 三题型轮换 + 当日重测。
///
/// 卡片来源是 [StudyDao.buildSession]：到期复习 + 今日新词，按比例交错。
/// 答错的词当天必再出一次，新词当天也收尾复习一次 —— 这两类都靠
/// 「把卡重新追加到队尾」实现，不重查数据库，所以同一场会话里不会重复刷屏。
class StudySessionPage extends StatefulWidget {
  const StudySessionPage({this.onlyReview = false, super.key});

  /// 只复习，不上新词。
  final bool onlyReview;

  @override
  State<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<StudySessionPage> {
  static const _dao = StudyDao();

  final List<StudyCard> _queue = [];
  final Map<String, int> _requeued = {};

  StudySession? _session;
  String? _error;
  bool _loading = true;

  int _index = 0;
  bool _answered = false;
  int? _selected;
  bool? _selfVerdict;

  int _newDone = 0;
  int _reviewDone = 0;
  int _correctCount = 0;
  int _wrongCount = 0;
  int _answeredCount = 0;

  StudyCard? get _card => _index < _queue.length ? _queue[_index] : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await _dao.buildSession(onlyReview: widget.onlyReview);
      if (!mounted) return;
      setState(() {
        _session = session;
        _queue
          ..clear()
          ..addAll(session.cards);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DatabaseUnavailable ? '词库打不开' : '学习记录读取失败';
        _loading = false;
      });
    }
  }

  Future<void> _answer(bool correct) async {
    final card = _card;
    if (card == null || _answered) return;

    setState(() {
      _answered = true;
      _correctCount += correct ? 1 : 0;
      _wrongCount += correct ? 0 : 1;
      _answeredCount++;
      if (card.isNew) {
        _newDone++;
      } else {
        _reviewDone++;
      }
    });

    try {
      final result = await _dao.answer(card: card, correct: correct);
      if (!mounted) return;
      // 当天还要再考一次的（答错 / 新词收尾），追加到队尾。
      // 同一个词一场会话最多补 2 次，避免一直答错一直循环。
      final times = _requeued[card.wordKey] ?? 0;
      if (result.retest && times < 2) {
        _requeued[card.wordKey] = times + 1;
        _queue.add(_retestCopy(card));
      }
    } catch (_) {
      // 落库失败不打断学习，只是这一次不计入统计。
    }
  }

  /// 重测卡：强制主动回忆，不再给选项提示。
  StudyCard _retestCopy(StudyCard card) {
    return StudyCard(
      wordKey: card.wordKey,
      word: card.word,
      phonetic: card.phonetic,
      meaning: card.meaning,
      meaningEcdict: card.meaningEcdict,
      box: card.box,
      isNew: false,
      isRetest: true,
      type: QuestionType.recall,
      options: const [],
      answerIndex: -1,
    );
  }

  void _next() {
    if (!mounted) return;
    setState(() {
      _index++;
      _answered = false;
      _selected = null;
      _selfVerdict = null;
    });
  }

  void _pick(int i) {
    final card = _card;
    if (card == null || _answered) return;
    setState(() {
      _selected = i;
      _selfVerdict = i == card.answerIndex;
    });
    _answer(i == card.answerIndex);
  }

  void _verdict(bool remembered) {
    if (_answered) return;
    setState(() => _selfVerdict = remembered);
    _answer(remembered);
  }

  Future<void> _speak(String text) async {
    final ok = await Speech.speak(text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这台手机没有可用的英文语音引擎')),
      );
    }
  }

  void _openDetail(String wordKey) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailPage(wordKey: wordKey),
      ),
    );
  }

  void _close() {
    Navigator.of(context).pop(_answeredCount > 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.close_rounded, size: 22),
        ),
        title: Text(_title()),
        actions: [
          if (_card != null)
            IconButton(
              tooltip: '词条详情',
              onPressed: () => _openDetail(_card!.wordKey),
              icon: const Icon(Icons.menu_book_outlined, size: 20),
            ),
        ],
        bottom: _loading || _session == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _queue.isEmpty
                      ? 0
                      : (_answeredCount / _queue.length).clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: AppColors.divider,
                  color: AppColors.accent,
                ),
              ),
      ),
      body: _body(),
    );
  }

  String _title() {
    if (_loading) return '';
    if (_session == null || _session!.isEmpty) return '学习';
    if (_card == null) return '完成';
    return '${_answeredCount + 1} / ${_queue.length}';
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    if (_session == null || _session!.isEmpty) {
      return _emptyState();
    }
    final card = _card;
    if (card == null) return _summary();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: _cardBody(card),
          ),
        ),
        _bottom(card),
      ],
    );
  }

  Widget _emptyState() {
    final text = Theme.of(context).textTheme;
    final gap = _session?.quota.gapDays ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 42, color: AppColors.known),
            const SizedBox(height: 16),
            Text('今天没有要学的词', style: text.titleSmall),
            const SizedBox(height: 8),
            Text(
              gap >= 3
                  ? '断档 $gap 天，今天的复习已经清完。明天继续。'
                  : '复习清完了，新词配额也用完了。明天再来。',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _close,
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardBody(StudyCard card) {
    final text = Theme.of(context).textTheme;

    if (card.isNew) {
      // 第一次见：先认一遍，不考。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _badge('新词', AppColors.accent),
          const SizedBox(height: 20),
          _wordHead(card),
          const SizedBox(height: 26),
          _meaningBlock(card, showEcdict: true),
          const SizedBox(height: 28),
          Text(
            '先记住它，学完今天所有新词后再回来考你一遍。',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      );
    }

    if (card.type == QuestionType.recall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _badge(card.isRetest ? '今日重测' : '主动回忆', AppColors.textSecondary),
          const SizedBox(height: 20),
          _wordHead(card),
          const SizedBox(height: 26),
          if (_answered) _meaningBlock(card, showEcdict: true)
          else
            Text(
              '想一下它的意思，再决定记不记得。',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
        ],
      );
    }

    if (card.type == QuestionType.cnToEn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _badge('中 → 英', AppColors.textSecondary),
          const SizedBox(height: 20),
          Text(
            card.meaning,
            style: text.headlineSmall?.copyWith(
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < card.options.length; i++) ...[
            _optionTile(card, i, card.options[i]),
            const SizedBox(height: 10),
          ],
          if (_answered) ...[
            const SizedBox(height: 16),
            _answerBlock(card),
          ],
        ],
      );
    }

    // enToCn
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge('英 → 中', AppColors.textSecondary),
        const SizedBox(height: 20),
        _wordHead(card),
        const SizedBox(height: 28),
        for (var i = 0; i < card.options.length; i++) ...[
          _optionTile(card, i, card.options[i]),
          const SizedBox(height: 10),
        ],
        if (_answered) ...[
          const SizedBox(height: 16),
          _answerBlock(card),
        ],
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 1.2,
          ),
    );
  }

  Widget _wordHead(StudyCard card) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          card.word,
          style: text.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (card.phonetic.isNotEmpty) ...[
              Text(
                '/${card.phonetic}/',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
            ],
            InkWell(
              onTap: () => _speak(card.word),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        size: 15, color: AppColors.accent),
                    const SizedBox(width: 5),
                    Text(
                      '发音',
                      style: text.labelSmall?.copyWith(color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Text(
              '箱 ${card.box}',
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _meaningBlock(StudyCard card, {bool showEcdict = false}) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('单词本原文', style: text.labelSmall?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          )),
          const SizedBox(height: 6),
          Text(
            card.meaning.isEmpty ? '单词本没有这个词的释义' : card.meaning,
            style: text.bodyMedium?.copyWith(height: 1.7),
          ),
          if (showEcdict && card.meaningEcdict.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('词典补全', style: text.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            )),
            const SizedBox(height: 6),
            Text(
              card.meaningEcdict,
              style: text.bodySmall?.copyWith(
                height: 1.7,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionTile(StudyCard card, int i, String label) {
    final text = Theme.of(context).textTheme;
    final isAnswer = i == card.answerIndex;
    final isPicked = _selected == i;

    var border = AppColors.divider;
    var bg = AppColors.surface;
    var fg = AppColors.textPrimary;
    double width = 0.5;

    if (_answered) {
      if (isAnswer) {
        border = AppColors.known;
        bg = AppColors.known.withValues(alpha: 0.12);
        fg = AppColors.known;
        width = 1;
      } else if (isPicked) {
        border = AppColors.unknown;
        bg = AppColors.unknown.withValues(alpha: 0.12);
        fg = AppColors.unknown;
        width = 1;
      } else {
        fg = AppColors.textTertiary;
      }
    }

    return InkWell(
      onTap: _answered ? null : () => _pick(i),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: width),
        ),
        child: Row(
          children: [
            Text(
              String.fromCharCode(65 + i),
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(color: fg, height: 1.5),
              ),
            ),
            if (_answered && isAnswer)
              const Icon(Icons.check_rounded, size: 17, color: AppColors.known),
            if (_answered && isPicked && !isAnswer)
              const Icon(Icons.close_rounded, size: 17, color: AppColors.unknown),
          ],
        ),
      ),
    );
  }

  Widget _answerBlock(StudyCard card) {
    final text = Theme.of(context).textTheme;
    final right = _selfVerdict ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            right ? '对了' : '不对',
            style: text.titleSmall?.copyWith(
              color: right ? AppColors.known : AppColors.unknown,
            ),
          ),
          const SizedBox(height: 8),
          Text(card.meaning, style: text.bodyMedium?.copyWith(height: 1.7)),
          if (card.meaningEcdict.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              card.meaningEcdict,
              style: text.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _openDetail(card.wordKey),
            child: Text(
              '看词条详情 →',
              style: text.labelSmall?.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottom(StudyCard card) {
    final text = Theme.of(context).textTheme;

    if (_answered) {
      return _bar(
        child: FilledButton(
          onPressed: _next,
          child: const Text('继续'),
        ),
      );
    }

    if (card.isNew) {
      return _bar(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _answer(false),
                child: const Text('不认识'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => _answer(true),
                child: const Text('记住了'),
              ),
            ),
          ],
        ),
      );
    }

    if (card.type == QuestionType.recall) {
      return _bar(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _verdict(false),
                child: const Text('没想起来'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => _verdict(true),
                child: const Text('想起来了'),
              ),
            ),
          ],
        ),
      );
    }

    return _bar(
      child: Text(
        '选一个',
        textAlign: TextAlign.center,
        style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _bar({required Widget child}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: child,
      ),
    );
  }

  Widget _summary() {
    final text = Theme.of(context).textTheme;
    final total = _correctCount + _wrongCount;
    final rate = total == 0 ? 0 : (_correctCount * 100 / total).round();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这一轮结束了', style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            )),
            const SizedBox(height: 20),
            _summaryRow('新词', '$_newDone'),
            _summaryRow('复习', '$_reviewDone'),
            _summaryRow('答对', '$_correctCount'),
            _summaryRow('答错', '$_wrongCount'),
            _summaryRow('正确率', '$rate%'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _close,
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label, style: text.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          )),
          const Spacer(),
          Text(value, style: text.titleSmall),
        ],
      ),
    );
  }
}
