import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../data/dao/spelling_dao.dart';
import '../../data/spelling/spelling_round.dart';
import '../../data/tts/speech.dart';
import '../words/word_detail_page.dart';

/// 纸面卡：与详情页 / 设置页同一套（比纸亮一点 + 0.5px 描边）。
const BoxDecoration _paperCard = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(AppTheme.cardRadius)),
  border: Border.fromBorderSide(
    BorderSide(color: AppColors.divider, width: 0.5),
  ),
);

/// 听音拼写整页（v0.13.0）。
///
/// 从学习 Tab 的「拼写练习」进来。一轮 = 今天的词（今天新词 + 今天到期复习，
/// 与学习会话同一套词表，截到每日目标）。每题：系统 TTS 读一遍 → 输入框拼写
/// → 提交 / 回车判对错。
///
/// **拼写只是独立练习**：不升箱、不降箱、不动 streak、不写每日进度。唯一写库
/// 的地方是 [SpellingStore.saveRound]（`spelling_round` 一行成绩）。
///
/// 判对：一行「对了」+ 正确拼写，1 秒后自动进下一题（也能手动点）。
/// 判错：正确拼写 + 音标 + 释义 + 「你拼的是 xxx」，**不自动跳**，点下一题再走。
class SpellingPage extends StatefulWidget {
  const SpellingPage({this.store, this.speak, super.key});

  /// 测试注入：假题源 / 假成绩单。生产环境为 null，走 SQLite。
  final SpellingStore? store;

  /// 测试注入：假 TTS。生产环境为 null，走系统 TTS（与学习页同一套）。
  final Future<bool> Function(String text)? speak;

  /// 判对之后自动进下一题的时间（需求写死 1 秒）。
  static const Duration autoAdvance = Duration(seconds: 1);

  @override
  State<SpellingPage> createState() => _SpellingPageState();
}

class _SpellingPageState extends State<SpellingPage> {
  late final SpellingStore _store = widget.store ?? const SqlSpellingStore();
  late final Future<bool> Function(String) _speak =
      widget.speak ?? Speech.speak;

  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<SpellingItem> _items = const [];
  final List<SpellingAttempt> _attempts = [];

  SpellingStats _stats = SpellingStats.empty;
  int _index = 0;
  bool _checked = false;
  bool _loading = true;
  String? _error;

  /// 小结已出现（= 这一轮拼完）。
  bool _finished = false;
  bool _saved = false;

  Timer? _advance;

  SpellingItem? get _current =>
      _index >= 0 && _index < _items.length ? _items[_index] : null;

  SpellingAttempt? get _last =>
      _attempts.isEmpty ? null : _attempts.last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _advance?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _store.loadItems();
      final stats = await _store.stats();
      if (!mounted) return;
      setState(() {
        _items = items;
        _stats = stats;
        _index = 0;
        _attempts.clear();
        _checked = false;
        _finished = false;
        _saved = false;
        _loading = false;
      });
      if (_items.isNotEmpty) {
        _focus.requestFocus();
        _speakCurrent();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '拼写练习打不开（读不到本地词库）';
      });
    }
  }

  /// 读当前的词。自动播一次，重听不限次数、不扣分。
  void _speakCurrent() {
    final item = _current;
    if (item == null) return;
    unawaited(_say(item.spoken));
  }

  /// 语音引擎不可用只提示一次：每题都弹会把整轮盖住。
  bool _ttsWarned = false;

  Future<void> _say(String text) async {
    final ok = await _speak(text);
    if (ok || !mounted || _ttsWarned) return;
    _ttsWarned = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这台手机没有可用的英文语音引擎')),
    );
  }

  void _submit() {
    final item = _current;
    if (item == null || _checked) return;
    final raw = _input.text;
    final attempt = SpellingAttempt(
      item: item,
      input: raw.trim(),
      correct: SpellingJudge.isCorrect(raw, item.word),
    );
    // 判完就收起键盘：结果块在输入框下面，键盘不收会被挡住一半。
    _focus.unfocus();
    setState(() {
      _attempts.add(attempt);
      _checked = true;
    });
    if (attempt.correct) {
      // 判对才自动走；判错留在本页，让人看清正确拼写与释义。
      _advance?.cancel();
      _advance = Timer(SpellingPage.autoAdvance, _next);
    }
  }

  void _next() {
    if (!mounted || !_checked) return;
    _advance?.cancel();
    if (_index + 1 >= _items.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _checked = false;
      _input.clear();
    });
    _focus.requestFocus();
    _speakCurrent();
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    unawaited(_save());
  }

  /// 一轮拼完记一笔。只写 `spelling_round`，不碰任何学习数据。
  Future<void> _save() async {
    if (_saved || _attempts.isEmpty) return;
    _saved = true;
    final total = _attempts.length;
    final correct = _attempts.where((a) => a.correct).length;
    try {
      await _store.saveRound(total: total, correct: correct);
      final stats = await _store.stats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // 记成绩失败不影响这一轮的结果展示：小结已经在屏幕上。
    }
  }

  Future<void> _openWord(SpellingItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailPage(
          wordKey: item.wordKey,
          displayWord: item.word,
          revealChinese: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拼写练习')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? const _EmptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: [
                          _AccuracyLine(stats: _stats),
                          const SizedBox(height: 16),
                          if (_finished)
                            SpellingSummary(
                              attempts: _attempts,
                              onOpenWord: _openWord,
                              onRetry: _load,
                              onDone: () => Navigator.of(context).maybePop(),
                            )
                          else ...[
                            _progressLine(),
                            const SizedBox(height: 12),
                            _DrillCard(onReplay: _speakCurrent),
                            const SizedBox(height: 20),
                            _inputField(),
                            const SizedBox(height: 12),
                            if (!_checked)
                              FilledButton(
                                key: const ValueKey('spelling-submit'),
                                onPressed: _submit,
                                child: const Text('提交'),
                              )
                            else
                              _Feedback(
                                attempt: _last!,
                                onNext: _next,
                                isLast: _index + 1 >= _items.length,
                              ),
                          ],
                        ],
                      ),
      ),
    );
  }

  Widget _progressLine() {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          '第 ${_index + 1} / ${_items.length} 题',
          // T4 次要：400 / 墨 62%（字重与颜色两个维度，v0.7.9）。
          style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(width: 12),
        // 用 Expanded + 右对齐而不是 Spacer + Text：系统字号放大时右半边
        // 会先省略，不会把这一行挤成 RenderFlex 溢出。
        Expanded(
          child: Text(
            '拼错不影响六箱与进度',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _inputField() {
    final text = Theme.of(context).textTheme;
    return TextField(
      key: const ValueKey('spelling-input'),
      controller: _input,
      focusNode: _focus,
      enabled: !_checked,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      style: text.titleLarge,
      decoration: InputDecoration(
        hintText: '把听到的词拼在这里',
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: LiquidGlass.ink, width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
    );
  }
}

/// 顶部唯一的统计：累计正确率（不做图表，那是下一版的事）。
class _AccuracyLine extends StatelessWidget {
  const _AccuracyLine({required this.stats});

  final SpellingStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = stats.accuracyPercent;
    return Text(
      percent == null
          ? '累计正确率：还没有拼写记录'
          : '累计正确率 $percent% · ${stats.rounds} 轮 ${stats.total} 题',
      key: const ValueKey('spelling-accuracy'),
      style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}

/// 题面：一个喇叭 + 重听。可无限重听，不扣分。
class _DrillCard extends StatelessWidget {
  const _DrillCard({required this.onReplay});

  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: _paperCard,
      child: Column(
        children: [
          Text(
            '听音拼写',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: '重听',
            child: InkWell(
              key: const ValueKey('spelling-replay'),
              onTap: onReplay,
              customBorder: const CircleBorder(),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volume_up_rounded,
                  size: 28,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '重听不限次数，不扣分',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 判对 / 判错的那一块。
///
/// 判对：一秒后自动走（[SpellingPage.autoAdvance]），另给一颗按钮可以提前走。
/// 判错：**不自动跳**，必须点「下一题」，好让人把正确拼写、音标、释义看清。
class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.attempt,
    required this.onNext,
    required this.isLast,
  });

  final SpellingAttempt attempt;
  final VoidCallback onNext;

  /// 这是最后一题（按钮改成「看小结」）。
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = attempt.item;
    final ok = attempt.correct;

    return Container(
      key: const ValueKey('spelling-feedback'),
      padding: const EdgeInsets.all(18),
      decoration: _paperCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ok ? '对了' : '错了',
            style: text.titleMedium?.copyWith(
              color: ok ? AppColors.textPrimary : LiquidGlass.wrongPink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.word,
            key: const ValueKey('spelling-answer'),
            style: text.displaySmall,
          ),
          if (!ok) ...[
            if (item.phonetic.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.phonetic,
                key: const ValueKey('spelling-phonetic'),
                style: text.bodyLarge,
              ),
            ],
            if (item.meaning.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.meaning,
                key: const ValueKey('spelling-meaning'),
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              attempt.input.isEmpty ? '你拼的是（空）' : '你拼的是 ${attempt.input}',
              key: const ValueKey('spelling-yours'),
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('spelling-next'),
              onPressed: onNext,
              child: Text(
                isLast
                    ? '看小结'
                    : (ok ? '下一题（1 秒后自动）' : '下一题'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一轮小结：对了几题 / 共几题 / 正确率 / 错词清单。
///
/// 错词清单每行「错拼 → 正确拼写 + 音标 + 释义」，点一条进词条详情页。
class SpellingSummary extends StatelessWidget {
  const SpellingSummary({
    required this.attempts,
    required this.onOpenWord,
    required this.onRetry,
    required this.onDone,
    super.key,
  });

  final List<SpellingAttempt> attempts;
  final ValueChanged<SpellingItem> onOpenWord;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  int get total => attempts.length;

  int get correct => attempts.where((a) => a.correct).length;

  List<SpellingAttempt> get wrong =>
      attempts.where((a) => !a.correct).toList();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = SpellingStats.percentOf(correct, total) ?? 0;
    final misses = wrong;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('spelling-summary'),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _paperCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('这一轮拼完了', style: text.titleLarge),
              const SizedBox(height: 12),
              Text(
                '对了 $correct 题 / 共 $total 题',
                key: const ValueKey('spelling-summary-count'),
                style: text.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '正确率 $percent%',
                key: const ValueKey('spelling-summary-percent'),
                style: AppTheme.numeric(text.headlineSmall),
              ),
              const SizedBox(height: 16),
              Text(
                misses.isEmpty ? '没有错词' : '错词 ${misses.length} 个',
                key: const ValueKey('spelling-summary-wrong'),
                style: text.titleMedium,
              ),
            ],
          ),
        ),
        for (final miss in misses) ...[
          const SizedBox(height: 10),
          _WrongRow(attempt: miss, onTap: () => onOpenWord(miss.item)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('spelling-retry'),
            onPressed: onRetry,
            child: const Text('再拼一轮'),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            key: const ValueKey('spelling-done'),
            onPressed: onDone,
            child: const Text('返回学习'),
          ),
        ),
      ],
    );
  }
}

/// 一条错词：错拼留作对照 → 正确拼写 + 音标 + 释义。点进词条详情页。
class _WrongRow extends StatelessWidget {
  const _WrongRow({required this.attempt, required this.onTap});

  final SpellingAttempt attempt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = attempt.item;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('spelling-wrong-${item.wordKey}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attempt.input.isEmpty
                          ? '你拼的是（空）'
                          : '你拼的是 ${attempt.input}',
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 4),
                    Text(item.word, style: text.titleMedium),
                    if (item.phonetic.isNotEmpty || item.meaning.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (item.phonetic.isNotEmpty) item.phonetic,
                          if (item.meaning.isNotEmpty) item.meaning,
                        ].join('  '),
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '今天没词可拼',
              key: const ValueKey('spelling-empty'),
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '先去学今天的词，回来再拼。',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
