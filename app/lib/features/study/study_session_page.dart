import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme/study_preview_theme.dart';
import '../../data/dao/study_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/study_card.dart';
import '../../data/study/study_flow.dart';
import '../../data/tts/speech.dart';
import '../words/word_detail_page.dart';

/// 学习会话：单词 + 四个中文意思，只有这一种题。
///
/// 卡片来源是 [StudyDao.buildSession]：到期复习 + 今日新词，按比例交错。
/// 答错的词当天必再出一次，新词当天也收尾复习一次 —— 这两类都靠
/// 「把卡重新追加到队尾」实现，重测卡的选项会重新洗牌。
///
/// 交互（v0.6.0）：
/// - 点错：该选项变红禁用，留在本卡继续选，不揭示正确答案；首次点错即记错
/// - 点对：变绿，500ms 后自动走
/// - 新词答对、或答错后才答对 → 先进详情整页，出来再下一张
/// - 「不认识」（v0.6.2）：按首次答错记，直接进详情整页；已记过错的卡只跳详情
///
/// 主题（v0.6.3 预览）：整页套 [StudyPreviewTheme.m3]，只有这一屏走 Material 3；
/// 行为逻辑与 v0.6.2 完全一致，改的只有颜色、圆角、字阶和按压反馈。
class StudySessionPage extends StatelessWidget {
  const StudySessionPage({this.onlyReview = false, super.key});

  /// 只复习，不上新词。
  final bool onlyReview;

  @override
  Widget build(BuildContext context) {
    // Theme 放在 State 外面，页面内所有组件（含 Card / Button 的默认形状）
    // 才会真正读到 M3 这一套。
    return Theme(
      data: StudyPreviewTheme.m3,
      child: _StudySessionView(onlyReview: onlyReview),
    );
  }
}

class _StudySessionView extends StatefulWidget {
  const _StudySessionView({this.onlyReview = false});

  /// 只复习，不上新词。
  final bool onlyReview;

  @override
  State<_StudySessionView> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<_StudySessionView> {
  static const _dao = StudyDao();

  final List<StudyCard> _queue = [];

  /// 同一个词一场会话最多补几张重测卡，避免一直错一直循环。
  final Map<String, int> _requeued = {};

  StudySession? _session;
  String? _error;
  bool _loading = true;

  int _index = 0;
  CardProgress _progress = CardProgress();
  bool _busy = false;
  Timer? _advanceTimer;

  int _newDone = 0;
  int _reviewDone = 0;
  int _firstRight = 0;
  int _firstWrong = 0;

  StudyCard? get _card => _index < _queue.length ? _queue[_index] : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
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

  Future<void> _tap(int i) async {
    final card = _card;
    if (card == null || _busy) return;

    final tap = _progress.tap(i, card.answerIndex);
    if (tap == CardTap.ignored) return;

    if (tap == CardTap.wrong) {
      // 首次点错就按 Leitner 记错：降一箱、进当日重测。
      setState(() => _firstWrong++);
      _busy = true;
      try {
        final result = await _dao.answer(card: card, correct: false);
        if (result.retest) await _requeue(card);
      } catch (_) {
        // 落库失败不打断学习，只是这一次没记进调度。
      } finally {
        _busy = false;
      }
      return;
    }

    // 答对：先点亮，500ms 后走。
    setState(() {
      if (card.isNew) {
        _newDone++;
      } else {
        _reviewDone++;
      }
      if (tap == CardTap.correctFirstTry) _firstRight++;
    });

    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _afterCorrect(card);
    });

    // 已经按答错记过的卡，后来选对不改判、也不再记一次。
    if (tap == CardTap.correctFirstTry) {
      unawaited(_recordCorrect(card));
    }
  }

  /// 「不认识」（v0.6.2）：按首次答错记 —— 降一箱 + 进当日重测 + 小结里算一次
  /// 首次答错 —— 然后直接进这个词的详情整页，出来再下一张。
  ///
  /// 已经点错过选项的卡再点它：不重复记错、不再落库，只跳详情页。
  Future<void> _tapUnknown() async {
    final card = _card;
    if (card == null || _busy) return;

    // markUnknown 返回 false = 这张卡已经记过错（点错或已答完），不再记。
    if (_progress.markUnknown()) {
      setState(() => _firstWrong++);
      _busy = true;
      try {
        final result = await _dao.answer(card: card, correct: false);
        if (result.retest) await _requeue(card);
      } catch (_) {
        // 落库失败不打断学习，和点错一致。
      } finally {
        _busy = false;
      }
      if (!mounted) return;
    }
    await _openDetailThenNext(card);
  }

  Future<void> _recordCorrect(StudyCard card) async {
    try {
      final result = await _dao.answer(card: card, correct: true);
      // 新词当天收尾复习：库里的 retest 被点亮，补一张到队尾。
      if (result.retest) await _requeue(card);
    } catch (_) {
      // 同上，不打断。
    }
  }

  Future<void> _requeue(StudyCard card) async {
    final times = _requeued[card.wordKey] ?? 0;
    if (times >= 2) return;
    _requeued[card.wordKey] = times + 1;
    try {
      final fresh = await _dao.rebuildCard(card.wordKey);
      if (fresh == null || !mounted) return;
      setState(() => _queue.add(fresh));
    } catch (_) {
      // 补卡失败就算了，明天还会到期。
    }
  }

  void _afterCorrect(StudyCard card) {
    final exit = exitAfterCorrect(
      isNew: card.isNew,
      hadWrong: _progress.recordedWrong,
    );
    if (exit == CardExit.detail) {
      _openDetailThenNext(card);
    } else {
      _next();
    }
  }

  /// 进详情整页，出来就下一张 —— 「下一个」按钮和系统返回键都只是关掉
  /// 详情页，由这里统一推进，所以按返回键退出详情也不会卡在同一张卡上。
  /// v0.6.1 去掉了上滑触发（详情页内容照常滚动）。
  Future<void> _openDetailThenNext(StudyCard card) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailPage(wordKey: card.wordKey, showNext: true),
      ),
    );
    if (!mounted) return;
    _next();
  }

  void _next() {
    if (!mounted) return;
    _advanceTimer?.cancel();
    setState(() {
      _index++;
      _progress = CardProgress();
      _busy = false;
    });
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
    Navigator.of(context).pop(_index > 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(_title()),
        actions: [
          // 答完之后这张卡马上就要走了，别再让人从这里进详情页，
          // 否则会和 500ms 后自动跳转的详情页叠在一起。
          if (_card != null && !_progress.resolved)
            IconButton(
              tooltip: '词条详情',
              onPressed: () => _openDetail(_card!.wordKey),
              icon: const Icon(Icons.menu_book_outlined),
            ),
        ],
        bottom: _loading || _session == null
            ? null
            : PreferredSize(
                // 4 = M3 进度条默认轨道高度。
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _queue.isEmpty
                      ? 0
                      : (_index / _queue.length).clamp(0.0, 1.0),
                  backgroundColor: scheme.surfaceContainerHighest,
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
    return '${_index + 1} / ${_queue.length}';
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    if (_session == null || _session!.isEmpty) {
      return _emptyState();
    }
    final card = _card;
    if (card == null) return _summary();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: _cardBody(card),
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final gap = _session?.quota.gapDays ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 42, color: scheme.primary),
            const SizedBox(height: 16),
            Text('今天没有要学的词', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              gap >= 3
                  ? '断档 $gap 天，今天的复习已经清完。明天继续。'
                  : '复习清完了，新词配额也用完了。明天再来。',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _badge(card),
            const Spacer(),
            if (card.box > 0)
              Text(
                '箱 ${card.box}',
                style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _wordHead(card),
        const SizedBox(height: 20),
        if (card.options.isEmpty)
          _brokenCard()
        else ...[
          Text(
            '选出正确的中文意思',
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _optionGrid(card),
          // 「不认识」：全宽、次要描边样式，跟四个选项明显不是一类（v0.6.2）。
          // 答对后隐藏；点错后保留，此时点了只跳详情页、不重复记错。
          if (!_progress.resolved) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _tapUnknown,
                child: const Text('不认识'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// 2×2 四宫格（v0.6.1）。顺序仍是 A/B/C/D 从左到右、从上到下，
  /// 每行用 IntrinsicHeight 让同行两格等高，长释义换行时不留半截边框。
  Widget _optionGrid(StudyCard card) {
    final n = card.options.length;
    final rows = <Widget>[];
    for (var i = 0; i < n; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _optionTile(i, card.options[i])),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < n
                    ? _optionTile(i + 1, card.options[i + 1])
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < n) rows.add(const SizedBox(height: 10));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _badge(StudyCard card) {
    final scheme = Theme.of(context).colorScheme;
    final label = card.isNew ? '新词' : (card.isRetest ? '今日重测' : '复习');
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: card.isNew ? scheme.primary : scheme.onSurfaceVariant,
          ),
    );
  }

  /// 单词区块：三级深浅里的中间一档（surfaceContainer），整块是一张 M3 卡。
  Widget _wordHead(StudyCard card) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;

    return Card.filled(
      color: scheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.word, style: text.displaySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                if (card.phonetic.isNotEmpty) ...[
                  Text(
                    '/${card.phonetic}/',
                    style: text.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton.tonalIcon(
                  onPressed: () => _speak(card.word),
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('发音'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(int i, String label) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final state = _progress.stateOf(i);

    // 三级深浅 + 容器角色（v0.6.3 预览）：未选 = surfaceContainerHigh，
    // 选对 = primaryContainer，点错 = errorContainer，答完后剩下的保持
    // surfaceContainerHigh 但文字降到 onSurfaceVariant。
    var bg = scheme.surfaceContainerHigh;
    var fg = scheme.onSurface;
    var letterFg = scheme.onSurfaceVariant;
    IconData? mark;

    switch (state) {
      case OptionState.correct:
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        letterFg = scheme.onPrimaryContainer;
        mark = Icons.check_rounded;
      case OptionState.wrong:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        letterFg = scheme.onErrorContainer;
        mark = Icons.close_rounded;
      case OptionState.dimmed:
        fg = scheme.onSurfaceVariant;
      case OptionState.neutral:
        break;
    }

    final disabled = state == OptionState.wrong ||
        state == OptionState.correct ||
        state == OptionState.dimmed;

    return Card.filled(
      color: bg,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : () => _tap(i),
        child: ConstrainedBox(
          // 76 沿用 v0.6.1 的最小高度：保证长释义与短释义同高、手指好点。
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  String.fromCharCode(65 + i),
                  style: text.labelLarge?.copyWith(color: letterFg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: text.titleMedium?.copyWith(color: fg),
                  ),
                ),
                if (mark != null) Icon(mark, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 释义缺失时的兜底：不记分、不阻塞，直接跳过。
  Widget _brokenCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '这个词没有可用释义，跳过。',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _next, child: const Text('跳过')),
      ],
    );
  }

  Widget _summary() {
    final text = Theme.of(context).textTheme;
    final total = _firstRight + _firstWrong;
    final rate = total == 0 ? 0 : (_firstRight * 100 / total).round();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这一轮结束了', style: text.headlineSmall),
            const SizedBox(height: 20),
            _summaryRow('新词', '$_newDone'),
            _summaryRow('复习', '$_reviewDone'),
            _summaryRow('首次答对', '$_firstRight'),
            _summaryRow('首次答错', '$_firstWrong'),
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
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label,
              style: text.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          Text(value, style: text.titleMedium),
        ],
      ),
    );
  }
}
