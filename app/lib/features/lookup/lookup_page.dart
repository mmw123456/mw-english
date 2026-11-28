import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/app_signals.dart';
import '../../app/theme/app_colors.dart';
import '../../app/widgets/search_capsule.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/tts/speech.dart';
import '../words/word_detail_page.dart';
import 'lookup_result_card.dart';

/// 查词页（v0.11.0）。四个入口共用这一页：
/// 首页 AppBar 放大镜、学习会话卡上的放大镜、词库页（走同一套搜索逻辑）、
/// 文章详情页双击（走同一张结果卡，弹层形式）。
///
/// 一屏内完成「输入 → 候选 → 结果」：输入恰好是某个词条时直接出结果卡，
/// 否则先给最多 10 条候选，点一条再出卡。全程本地 SQLite，不联网。
class LookupPage extends StatefulWidget {
  const LookupPage({this.initialQuery, this.service, super.key});

  /// 带着词进来（比如文章里双击的词），进来就有结果。
  final String? initialQuery;

  /// 测试注入假库用。
  final LookupService? service;

  @override
  State<LookupPage> createState() => _LookupPageState();
}

class _LookupPageState extends State<LookupPage> {
  late final LookupService _service = widget.service ?? LookupService();
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery ?? '');

  Timer? _debounce;
  LookupView? _view;
  LookupResult? _result;
  bool _loading = false;
  bool _adding = false;
  bool _justAdded = false;

  @override
  void initState() {
    super.initState();
    final initial = LookupService.normalize(widget.initialQuery ?? '');
    if (initial.isNotEmpty) unawaited(_run(initial));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final q = LookupService.normalize(raw);
    if (q.isEmpty) {
      setState(() {
        _view = null;
        _result = null;
        _justAdded = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _result = null;
      _justAdded = false;
    });
    // 260ms 与词库页同一个去抖时长，打字时不至于每敲一个字母查一次库。
    _debounce = Timer(const Duration(milliseconds: 260), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    LookupView view;
    try {
      view = await _service.lookup(q);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('词库打不开，稍后再试。');
      return;
    }
    if (!mounted) return;
    setState(() {
      _view = view;
      _result = view.result;
      _loading = false;
    });
  }

  Future<void> _pick(LookupHit hit) async {
    setState(() => _loading = true);
    LookupResult? result;
    try {
      result = await _service.resolve(hit.wordKey);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
    if (result == null) _snack('这个词读不出来，再试一次。');
  }

  Future<void> _speak() async {
    final r = _result;
    if (r == null) return;
    final ok = await Speech.speak(r.wordKey);
    if (!ok && mounted) _snack('这台手机没有可用的英文语音引擎');
  }

  Future<void> _add() async {
    final r = _result;
    if (r == null || _adding || r.inLibrary || _justAdded) return;
    setState(() => _adding = true);
    try {
      final added = await _service.addToLibrary(r);
      if (!mounted) return;
      if (added) {
        // 词库 / 首页配额 / 学习队列都读同一个库，广播一声让它们重算。
        AppSignals.libraryUpdated();
        setState(() => _justAdded = true);
        _snack('「${r.wordKey}」已进生词本，从 0 箱开始。');
      }
    } catch (_) {
      if (mounted) _snack('加入失败，再试一次。');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openDetail() async {
    final r = _result;
    if (r == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailPage(wordKey: r.wordKey, displayWord: r.word),
      ),
    );
    if (!mounted) return;
    // 详情页里可能加了星标 / 斩了词 / 改了箱位，回来重读一遍。
    LookupResult? again;
    try {
      again = await _service.resolve(r.wordKey);
    } catch (_) {
      again = null;
    }
    if (!mounted) return;
    setState(() => _result = again);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('查词')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SearchCapsule(
              key: const ValueKey('lookup-search'),
              controller: _ctrl,
              onChanged: _onChanged,
              // 带词进来时别弹键盘：结果已经在眼前了。
              autofocus: (widget.initialQuery ?? '').isEmpty,
              onClear: () {
                _ctrl.clear();
                _onChanged('');
              },
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
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

    final view = _view;
    if (view == null || view.isEmptyQuery) {
      return const LookupEmptyState(
        key: ValueKey('lookup-hint'),
        icon: Icons.search,
        title: '输入单词、短语或中文',
        note: '英文按开头匹配，中文按释义包含；短语请整串输入。全部离线查，不联网。',
      );
    }

    final result = _result;
    if (result != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          LookupResultCard(
            result: result,
            justAdded: _justAdded,
            adding: _adding,
            onSpeak: _speak,
            onAdd: _add,
            onOpenDetail: _openDetail,
          ),
        ],
      );
    }

    if (view.notFound) {
      return LookupEmptyState(
        key: const ValueKey('lookup-not-found'),
        icon: Icons.search_off,
        title: '未查到「${view.query}」',
        note: '820 词表、自加词、43,350 词离线词典都没命中。不联网查，也不会编一个释义出来。',
      );
    }

    final hits = view.candidates;
    return ListView.builder(
      key: const ValueKey('lookup-candidates'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: hits.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _CandidateHeader(count: hits.length);
        final hit = hits[i - 1];
        return _CandidateRow(hit: hit, onTap: () => _pick(hit));
      },
    );
  }
}

class _CandidateHeader extends StatelessWidget {
  const _CandidateHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '候选 · $count',
        style: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.hit, required this.onTap});

  final LookupHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      key: ValueKey('lookup-hit-${hit.wordKey}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    hit.word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hit.phonetic.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '/${hit.phonetic}/',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  hit.source.label,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hit.gloss,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
