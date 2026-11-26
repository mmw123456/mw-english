import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart' show HapticFeedback, SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

import '../../app/theme/liquid_glass.dart';
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
/// 交互（v0.6.0，v0.6.6 调整去向）：
/// - 点错：该选项左右抖一下再变粉禁用，留在本卡继续选；首次点错即记错
/// - 点对：变绿 + 对勾画出来，500ms 后自动走
/// - **第一次就答对 → 直接下一张**（新词也一样）；只有先点错再选对才进详情
/// - 「不认识」（v0.6.2）：按首次答错记，直接进详情整页；已记过错的卡只跳详情
///
/// 主题（v0.7.0 起）：纸底玻璃已经是全局主题 AppTheme.light，这一页不再
/// 自己套 Theme。v0.6.6 起单词框也是玻璃（中间平坦、只弯边缘），行为不变。
/// 氛围层只留在这一屏 —— 列表页的背景有颜色会干扰阅读。
///
/// 顶栏（v0.6.9）：撤掉 AppBar，换成一根悬浮玻璃胶囊 —— X、进度数字、
/// 书本图标都在里面，下面一根 2px 进度线；状态与箱数各一颗小标签胶囊。
///
/// 动效（v0.6.6）：全部走弹簧 [LiquidGlass.spring]，只改变换与透明度。
class StudySessionPage extends StatelessWidget {
  const StudySessionPage({
    this.onlyReview = false,
    this.debugSessionBuilder,
    super.key,
  });

  /// 只复习，不上新词。
  final bool onlyReview;

  /// 测试注入：绕开数据库直接给一份会话，用来断言「换卡首帧」这类
  /// 和时间点相关的行为。生产环境永远是 null。
  @visibleForTesting
  final StudySession Function()? debugSessionBuilder;

  @override
  Widget build(BuildContext context) {
    // 主题已提到全局（v0.7.0），这一页不再局部覆盖。
    return _StudySessionView(
      onlyReview: onlyReview,
      debugSessionBuilder: debugSessionBuilder,
    );
  }
}

class _StudySessionView extends StatefulWidget {
  const _StudySessionView({this.onlyReview = false, this.debugSessionBuilder});

  /// 只复习，不上新词。
  final bool onlyReview;

  final StudySession Function()? debugSessionBuilder;

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

  /// 入场 stagger 只在这屏第一次出现时播一次。
  ///
  /// v0.7.2：以前每换一张卡，[ValueKey] 变了 → [_SpringIn] 重建 → 从
  /// opacity 0 重新入场。实测换卡后 0–60ms 四个选项全透明、最后一条要到
  /// 500ms 才满不透明，就是用户看到的「下一张卡选项空白闪一下」。
  /// 选项数据本身在会话装配时就算好了（[StudyDao.buildSession] 一次算完
  /// 整条队列），所以这里只需要不重播动画。
  bool _entrance = true;

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
      final injected = widget.debugSessionBuilder;
      final session = injected != null
          ? injected()
          : await _dao.buildSession(onlyReview: widget.onlyReview);
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
      // 触觉：答错比答对重一档。没触觉马达的设备由系统静默忽略。
      unawaited(HapticFeedback.mediumImpact());
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
    unawaited(HapticFeedback.lightImpact());
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
    final exit = exitAfterCorrect(hadWrong: _progress.recordedWrong);
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
      // 换卡不重播入场：下一张的首帧必须四个选项都在、都不透明。
      _entrance = false;
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
    final total = _queue.length;
    final value = total == 0 ? 0.0 : (_index / total).clamp(0.0, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 纸底是浅色，状态栏图标必须是深色。以前靠 AppBar 自动设，
      // v0.6.9 撤掉 AppBar 换成悬浮胶囊，就得自己声明。
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: LiquidGlass.paper,
        // 氛围层必须在内容下面、且铺满整屏：玻璃要有东西可弯，
        // 弯的是这层彩色光，不是纯纸底。
        body: Stack(
          children: [
            const Positioned.fill(child: LiquidGlassBackdrop()),
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // 顶栏是一条浮在纸上的玻璃胶囊：X、进度、书本图标在同一条里，
                    // 不再让字和图标裸摆在纸上。
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: StudyTopCapsule(
                        label: _title(),
                        onClose: _close,
                        // 答完之后这张卡马上就要走了，别再让人从这里进详情页，
                        // 否则会和 500ms 后自动跳转的详情页叠在一起。
                        onDetail: _card != null && !_progress.resolved
                            ? () => _openDetail(_card!.wordKey)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 胶囊下面一根 2px 细线，按当前进度填充。
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: StudyProgressLine(value: value),
                    ),
                    // 顶部留白：胶囊条和题目之间要呼吸，不要把标签顶着进度线。
                    const SizedBox(height: 26),
                    Expanded(child: _body()),
                  ],
                ),
              ),
            ),
          ],
        ),
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
      // 顶部留 8：标签胶囊的投影要落在滚动区里面，否则上边缘会被裁出一条直边。
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
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
        // 状态与箱数各一颗小胶囊，左右对齐；字号层级靠尺寸拉开（13 / 11），
        // 不靠颜色，玻璃语言里没有第二种色。
        Row(
          children: [
            StudyTagPill(label: _badgeLabel(card), emphasized: true),
            const Spacer(),
            if (card.box > 0) StudyTagPill(label: '箱 ${card.box}'),
          ],
        ),
        const SizedBox(height: 18),
        // 入场 stagger：单词 0ms，四个选项依次 50/85/120/155ms，
        // 「不认识」最后。每个都是独立弹簧，不是一条线性时间轴。
        _SpringIn(
          key: ValueKey('word-${card.wordKey}'),
          animate: _entrance,
          child: StudyWordCard(
            card: card,
            onSpeak: () => _speak(card.word),
          ),
        ),
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
            _SpringIn(
              key: ValueKey('unknown-${card.wordKey}'),
              animate: _entrance,
              delayMs: 190,
              child: SizedBox(
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
              Expanded(child: _optionTile(i, card.options[i], card)),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < n
                    ? _optionTile(i + 1, card.options[i + 1], card)
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

  String _badgeLabel(StudyCard card) {
    return card.isNew ? '新词' : (card.isRetest ? '今日重测' : '复习');
  }

  /// 选项：玻璃 + 弹簧按压 + 触点高光 + 答错抖动 + 答对对勾。
  ///
  /// 入场延迟按 index 递增（50 / 85 / 120 / 155ms），由外层 [_SpringIn] 负责；
  /// 这里只管作答反馈。key 里带 wordKey：换卡时组件重建，动画从头来。
  Widget _optionTile(int i, String label, StudyCard card) {
    final state = _progress.stateOf(i);
    return _SpringIn(
      key: ValueKey('opt-${card.wordKey}-$i'),
      animate: _entrance,
      delayMs: 50 + i * 35,
      child: _GlassOption(
        index: i,
        label: label,
        state: state,
        onTap: state == OptionState.neutral ? () => _tap(i) : null,
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

/// 单词卡（v0.6.6）：正文从「不透明深色卡片」换成玻璃。
///
/// 弯只发生在边缘：中间是一整块平的 tint，文字画在它上面，不做任何位移，
/// 所以 36pt 单词和音标都不会被折碎。背后的氛围渐变透过这层玻璃还能看到一点，
/// 玻璃才有东西可弯 —— 不然跟深色卡片没区别。
class StudyWordCard extends StatelessWidget {
  const StudyWordCard({required this.card, this.onSpeak, super.key});

  final StudyCard card;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: GlassSurface(
            radius: LiquidGlass.bevel,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.word, style: text.displaySmall),
                if (card.phonetic.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // 音标是小字，落在中央平坦区：那里不弯，不会被高光切碎。
                  Text('/${card.phonetic}/', style: text.bodyLarge),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 发音仍放在卡片外面：控件压在不透明底上就没有东西可弯。
        GlassSurface(
          onTap: onSpeak,
          radius: LiquidGlass.bevel,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.volume_up_rounded,
                  size: 16, color: LiquidGlass.textPrimary),
              const SizedBox(width: 6),
              Text('发音',
                  style:
                      text.labelLarge?.copyWith(color: LiquidGlass.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部悬浮玻璃胶囊条（v0.6.9）。
///
/// X、进度数字、书本图标都在同一条胶囊里，胶囊浮在纸面上（投影用常态
/// `.20`），不再让字和图标裸摆在纸上。
///
/// 小胶囊不上磨砂：1px 模糊在这个尺寸上看不出来，省一层 BackdropFilter。
/// 数字用小字（13 / 700），不跟下面的单词抢视线。
class StudyTopCapsule extends StatelessWidget {
  const StudyTopCapsule({
    required this.label,
    required this.onClose,
    this.onDetail,
    super.key,
  });

  /// 进度数字，如 `1 / 28`；空态 / 完成时是文字。
  final String label;
  final VoidCallback onClose;

  /// 没有可跳的词条时传 null：那颗图标不显示，位置留白保持对称。
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: LiquidGlass.ink,
        );

    return GlassSurface(
      // 999 = 完整胶囊：高度多少，半圆就是多少。
      radius: 999,
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          _CapsuleButton(
            icon: Icons.close_rounded,
            tooltip: '退出学习',
            onTap: onClose,
          ),
          Expanded(
            child: Center(child: Text(label, style: style)),
          ),
          if (onDetail != null)
            _CapsuleButton(
              icon: Icons.menu_book_outlined,
              tooltip: '词条详情',
              onTap: onDetail!,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      color: LiquidGlass.ink,
      padding: EdgeInsets.zero,
      // 定 40：默认 48 的点击区会把胶囊撑高，40 已经够手指点。
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }
}

/// 胶囊下面那根 2px 细进度线（v0.6.9）。
///
/// 轨道色仍从主题取（墨 12%），填充用墨；两端半圆，才有「细线」而不是
/// 「细条」的感觉。
class StudyProgressLine extends StatelessWidget {
  const StudyProgressLine({required this.value, this.thickness = 2, super.key});

  /// 0–1。
  final double value;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).progressIndicatorTheme.linearTrackColor ??
        const Color(0x1F0B0C10);

    return ClipRRect(
      borderRadius: BorderRadius.circular(thickness / 2),
      child: SizedBox(
        height: thickness,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const ColoredBox(color: LiquidGlass.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 小标签胶囊（v0.6.9）：状态（新词 / 今日重测 / 复习）与箱数各一颗。
///
/// 字号层级拉开：状态 13 / 700，箱数 11 / 600 且用次要字色 —— 同级同色
/// 就变成一排散字，看不出主次。
class StudyTagPill extends StatelessWidget {
  const StudyTagPill({
    required this.label,
    this.emphasized = false,
    super.key,
  });

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = emphasized
        ? text.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: LiquidGlass.ink,
          )
        : text.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: LiquidGlass.textSecondary,
          );

    return GlassSurface(
      radius: 999,
      blur: 0,
      padding: EdgeInsets.symmetric(
        horizontal: emphasized ? 12 : 9,
        vertical: emphasized ? 6 : 4,
      ),
      child: Text(label, style: style),
    );
  }
}

/// 入场：弹簧 + 延迟，只动透明度和位移/缩放。
///
/// 不用 CurvedAnimation：规范要求全部走弹簧，所以直接喂
/// [SpringSimulation]（stiffness 300 / damping 24 / mass 0.8）。
///
/// [animate] 为 false 时完全不介入：直接把 child 原样返回（不是
/// opacity 1 的 Opacity），首帧就是最终位置、最终不透明度。换卡走这条，
/// 只有进会话的第一张卡才播入场。
class _SpringIn extends StatefulWidget {
  const _SpringIn({
    required this.child,
    this.delayMs = 0,
    this.animate = true,
    super.key,
  });

  final Widget child;
  final int delayMs;
  final bool animate;

  @override
  State<_SpringIn> createState() => _SpringInState();
}

class _SpringInState extends State<_SpringIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _c.value = 1;
      return;
    }
    if (widget.delayMs <= 0) {
      _start();
    } else {
      _delay = Timer(Duration(milliseconds: widget.delayMs), _start);
    }
  }

  @override
  void didUpdateWidget(covariant _SpringIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 会话中途关掉入场（第一次换卡）：直接跳到终态，别留半截动画。
    if (!widget.animate && _c.value != 1) {
      _delay?.cancel();
      _delay = null;
      _c.value = 1;
    }
  }

  void _start() {
    if (!mounted) return;
    _c.animateWith(SpringSimulation(LiquidGlass.spring, 0, 1, 0));
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // 弹簧会过冲到 1 以上，透明度必须夹住；位移夹住后视觉上就是「到位」。
        final t = _c.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
          ),
        );
      },
    );
  }
}

/// 玻璃选项：按压缩到 0.96、按点倾斜、触点高光、答错抖动、答对对勾。
///
/// 只改 transform / opacity，不碰宽高和位置，所以 500ms 自动走的节奏不会被拖慢。
class _GlassOption extends StatefulWidget {
  const _GlassOption({
    required this.index,
    required this.label,
    required this.state,
    required this.onTap,
  });

  final int index;
  final String label;
  final OptionState state;
  final VoidCallback? onTap;

  @override
  State<_GlassOption> createState() => _GlassOptionState();
}

class _GlassOptionState extends State<_GlassOption>
    with TickerProviderStateMixin {
  /// 按压缩放（0 = 常态，1 = 完全按下）。
  late final AnimationController _press = AnimationController(vsync: this);

  /// 触点高光：按下 90ms 亮起，松开 200ms 淡出。
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  /// 答错抖动：360ms，3–4 次。
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  /// 答对：缩放 + 对勾 300ms 一起走。
  late final AnimationController _resolve = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  Offset _focal = Offset.zero;
  Size _size = Size.zero;

  /// 抖完才变红：抖动期间保持中性色，抖到位再换粉。
  bool _wrongVisible = false;

  @override
  void initState() {
    super.initState();
    _shake.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _wrongVisible = true);
      }
    });
    _sync(widget.state);
  }

  @override
  void didUpdateWidget(covariant _GlassOption old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _sync(widget.state);
  }

  void _sync(OptionState now) {
    switch (now) {
      case OptionState.wrong:
        _wrongVisible = false;
        _shake.forward(from: 0);
      case OptionState.correct:
        _resolve.forward(from: 0);
      case OptionState.neutral:
        _wrongVisible = false;
        _press.value = 0;
        _glow.value = 0;
        _shake.value = 0;
        _resolve.value = 0;
      case OptionState.dimmed:
        break;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _glow.dispose();
    _shake.dispose();
    _resolve.dispose();
    super.dispose();
  }

  void _down(TapDownDetails d) {
    if (widget.onTap == null) return;
    _size = context.size ?? Size.zero;
    setState(() => _focal = d.localPosition);
    _press.animateTo(
      1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
    _glow.animateTo(
      1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  /// 松开：缩放走弹簧回弹，高光 200ms 内淡出。
  void _release() {
    if (widget.onTap == null) return;
    _press.animateWith(
      SpringSimulation(LiquidGlass.spring, _press.value, 0, 0),
    );
    _glow.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: Listenable.merge([_press, _glow, _shake, _resolve]),
      builder: (context, _) {
        final press = _press.value.clamp(0.0, 1.0);
        final glow = _glow.value.clamp(0.0, 1.0);
        final resolve = _resolve.value.clamp(0.0, 1.0);
        final shake = _shake.value.clamp(0.0, 1.0);
        final showWrong = widget.state == OptionState.wrong && _wrongVisible;
        final state = widget.state;

        // 玻璃没有颜色，状态只调 tint 与亮度。
        var tintColor = Colors.white;
        var tintAlpha = LiquidGlass.tint;
        var highlight = 1.0;
        var shadow = LiquidGlass.shadow;
        var fg = LiquidGlass.textPrimary;
        var letterFg = LiquidGlass.textSecondary;

        if (state == OptionState.correct) {
          tintAlpha = LiquidGlass.tintSelected;
          highlight = 1.6;
          // 选中态投影加深：纸底上光靠 36% 白 tint 不够浮起来。
          shadow = LiquidGlass.shadowSelected;
        } else if (showWrong) {
          tintColor = LiquidGlass.wrongPink;
          tintAlpha = 0.22;
          highlight = 1.2;
        } else if (state == OptionState.dimmed) {
          tintAlpha = 0.03;
          // 已揭晓的其余选项：淡到「不可选」，但不承担待读信息。
          fg = LiquidGlass.textDisabled;
          letterFg = LiquidGlass.textDisabled;
        }

        // 抖动：3.5 个来回，幅度随时间衰减，纯位移。
        final shakeX =
            math.sin(shake * math.pi * 7) * 6 * (1 - shake);

        // 按压倾斜：朝手指那侧微倾，松手回正。
        final tilt = Matrix4.identity();
        if (press > 0 && _size.width > 0 && _size.height > 0) {
          final dx = (_focal.dx / _size.width - 0.5) * 2;
          final dy = (_focal.dy / _size.height - 0.5) * 2;
          tilt.setEntry(3, 2, 0.0015);
          tilt.rotateX(dy * 0.035 * press);
          tilt.rotateY(-dx * 0.035 * press);
        }

        final scale =
            (1 - (1 - LiquidGlass.pressScale) * press) * (1 + 0.03 * resolve);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap == null ? null : _down,
          onTapUp: widget.onTap == null ? null : (_) => _release(),
          onTapCancel: widget.onTap == null ? null : _release,
          onTap: widget.onTap,
          child: Transform.translate(
            offset: Offset(shakeX, 0),
            child: Transform.scale(
              scale: scale,
              child: Transform(
                transform: tilt,
                alignment: Alignment.center,
                child: GlassSurface(
                  minHeight: 76,
                  radius: LiquidGlass.bevel,
                  tintColor: tintColor,
                  tintAlpha: tintAlpha,
                  highlight: highlight,
                  shadow: shadow,
                  overlay: glow > 0.01
                      ? _TouchGlow(focal: _focal, opacity: glow)
                      : null,
                  child: Row(
                    children: [
                      Text(
                        String.fromCharCode(65 + widget.index),
                        style: text.labelLarge?.copyWith(color: letterFg),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: text.titleMedium?.copyWith(color: fg),
                        ),
                      ),
                      if (state == OptionState.correct)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CustomPaint(
                            painter: _CheckPainter(resolve, fg),
                          ),
                        )
                      else if (showWrong)
                        Icon(Icons.close_rounded, color: fg, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 触点高光：以按下的位置为中心的一团白光，透明度由 `_glow` 控制。
class _TouchGlow extends StatelessWidget {
  const _TouchGlow({required this.focal, required this.opacity});

  final Offset focal;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0) return const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                (focal.dx / w) * 2 - 1,
                (focal.dy / h) * 2 - 1,
              ),
              radius: 0.65,
              colors: <Color>[
                Colors.white.withValues(alpha: 0.20 * opacity),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 对勾：按 0→1 的进度把路径画出来（250–350ms）。
class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.15, h * 0.55)
      ..lineTo(w * 0.42, h * 0.80)
      ..lineTo(w * 0.88, h * 0.25);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(
      0,
      metric.length * progress.clamp(0.0, 1.0),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}
