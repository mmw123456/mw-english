import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme/liquid_glass_preview_theme.dart';
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
/// 主题（v0.6.4 预览）：整页套 [LiquidGlassPreviewTheme.theme]，只有这一屏走
/// 液态玻璃；行为逻辑与 v0.6.2 完全一致。
///
/// 玻璃只做在控件层（发音、不认识、四宫格），正文卡片保持不透明。
/// v0.6.3 的 M3 主题文件保留未动，方便两版对比。
class StudySessionPage extends StatelessWidget {
  const StudySessionPage({this.onlyReview = false, super.key});

  /// 只复习，不上新词。
  final bool onlyReview;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: LiquidGlassPreviewTheme.theme,
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

  /// 已经自动读过词的队列下标。一张卡只自动读一次 —— 从详情页回来、
  /// 页面重建、旋转屏幕都不重读；手动点「发音」不受这个集合限制。
  final Set<int> _spokenIndexes = <int>{};

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
      // 第一张卡也是「新出现的一张」，同样自动读。放 setState 外面，
      // 语音失败不影响首帧。
      _autoSpeak();
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
        builder: (_) => WordDetailPage(
          wordKey: card.wordKey,
          showNext: true,
          // 从学习会话进来：中文直接显示，不遮盖。答错/不认识之后正是需要
          // 立刻看到意思的时候，这时再让人点一下才显示没有意义。
          revealChinese: true,
        ),
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
    _autoSpeak();
  }

  /// 新卡出现就自动读一遍单词（新词 / 复习 / 重测都算）。
  ///
  /// 只读一次：按队列下标记账，同一张卡不重复读。语音失败静默跳过 ——
  /// 自动读是附加动作，没装英文引擎不该弹提示打断学习。
  void _autoSpeak() {
    final card = _card;
    if (card == null) return;
    if (!_spokenIndexes.add(_index)) return;
    unawaited(Speech.speak(card.word));
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
        // 同样是从学习会话进的详情页，中文直接显示。
        builder: (_) => WordDetailPage(wordKey: wordKey, revealChinese: true),
      ),
    );
  }

  void _close() {
    Navigator.of(context).pop(_index > 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LiquidGlass.ink,
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
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _queue.isEmpty
                      ? 0
                      : (_index / _queue.length).clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFF23242A),
                ),
              ),
      ),
      // 氛围层必须在内容下面、且铺满整屏：玻璃要有东西可弯，
      // 弯的是这层彩色光，不是纯墨底。
      body: Stack(
        children: [
          const Positioned.fill(child: LiquidGlassBackdrop()),
          Positioned.fill(child: _body()),
        ],
      ),
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
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: LiquidGlass.textSecondary),
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
    final text = Theme.of(context).textTheme;
    final gap = _session?.quota.gapDays ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 42, color: LiquidGlass.textPrimary),
            const SizedBox(height: 16),
            Text('今天没有要学的词', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              gap >= 3
                  ? '断档 $gap 天，今天的复习已经清完。明天继续。'
                  : '复习清完了，新词配额也用完了。明天再来。',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: LiquidGlass.textSecondary),
            ),
            const SizedBox(height: 24),
            // 控件层 → 玻璃。空态这一屏同样只有墨底和氛围层可弯。
            GlassSurface(
              onTap: _close,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: Text('返回', style: text.labelLarge),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardBody(StudyCard card) {
    final text = Theme.of(context).textTheme;

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
                style: text.labelMedium
                    ?.copyWith(color: LiquidGlass.textTertiary),
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
            style: text.labelMedium?.copyWith(color: LiquidGlass.textSecondary),
          ),
          const SizedBox(height: 8),
          _optionGrid(card),
          // 「不认识」：全宽玻璃按钮，跟四个选项明显不是一类（v0.6.2）。
          // 答对后隐藏；点错后保留，此时点了只跳详情页、不重复记错。
          if (!_progress.resolved) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: GlassSurface(
                onTap: _tapUnknown,
                minHeight: 48,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('不认识', style: text.labelLarge),
                ),
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
    final label = card.isNew ? '新词' : (card.isRetest ? '今日重测' : '复习');
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            // 状态提示不上色：玻璃风格的强调靠亮度，不靠色相。
            color: card.isNew
                ? LiquidGlass.textPrimary
                : LiquidGlass.textSecondary,
          ),
    );
  }

  /// 单词区块：正文卡片，**不做玻璃**（压字的区域要稳，背景变化不能透上来）。
  /// 只有里面那颗「发音」是控件，走玻璃。
  Widget _wordHead(StudyCard card) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LiquidGlass.sheet,
        borderRadius: BorderRadius.circular(12),
      ),
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
                  style: text.bodyLarge,
                ),
                const SizedBox(width: 12),
              ],
              GlassSurface(
                onTap: () => _speak(card.word),
                radius: LiquidGlass.bevel,
                blur: 4,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        size: 16, color: LiquidGlass.textPrimary),
                    const SizedBox(width: 6),
                    // 玻璃上的中文：16 / 700，细字会碎在高光边上。
                    Text('发音',
                        style: text.labelLarge
                            ?.copyWith(color: LiquidGlass.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionTile(int i, String label) {
    final text = Theme.of(context).textTheme;
    final state = _progress.stateOf(i);

    // 玻璃没有颜色，状态只调 tint 和亮度：
    // 未选 = 白 5%，选中 = 白 36% + 高光更亮，点错 = 那支粉的低透明度 tint。
    var tintColor = Colors.white;
    var tintAlpha = LiquidGlass.tint;
    var highlight = 1.0;
    var fg = LiquidGlass.textPrimary;
    var letterFg = LiquidGlass.textSecondary;
    IconData? mark;

    switch (state) {
      case OptionState.correct:
        tintAlpha = LiquidGlass.tintSelected;
        highlight = 1.6;
        mark = Icons.check_rounded;
      case OptionState.wrong:
        tintColor = LiquidGlass.wrongPink;
        tintAlpha = 0.22;
        highlight = 1.2;
        fg = LiquidGlass.textPrimary;
        letterFg = LiquidGlass.textPrimary;
        mark = Icons.close_rounded;
      case OptionState.dimmed:
        tintAlpha = 0.03;
        fg = LiquidGlass.textTertiary;
        letterFg = LiquidGlass.textTertiary;
      case OptionState.neutral:
        break;
    }

    final disabled = state == OptionState.wrong ||
        state == OptionState.correct ||
        state == OptionState.dimmed;

    return GlassSurface(
      onTap: disabled ? null : () => _tap(i),
      minHeight: 76,
      radius: LiquidGlass.bevel,
      tintColor: tintColor,
      tintAlpha: tintAlpha,
      highlight: highlight,
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
    );
  }

  /// 释义缺失时的兜底：不记分、不阻塞，直接跳过。
  Widget _brokenCard() {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '这个词没有可用释义，跳过。',
          style: text.bodyMedium?.copyWith(color: LiquidGlass.textSecondary),
        ),
        const SizedBox(height: 16),
        GlassSurface(
          onTap: _next,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text('跳过', style: text.labelLarge),
        ),
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
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label,
              style: text.bodyMedium
                  ?.copyWith(color: LiquidGlass.textSecondary)),
          const Spacer(),
          Text(value, style: text.titleMedium),
        ],
      ),
    );
  }
}
