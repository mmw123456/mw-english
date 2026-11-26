import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../data/dao/detail_dao.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/word_detail.dart';
import '../../data/morphology/root_whitelist.dart';
import '../../data/tts/speech.dart';

/// 纸面卡：正文区块的容器（v0.7.0）。比纸亮一点 + 0.5px 描边，
/// 不投影 —— 投影留给浮在纸上的玻璃控件。
const BoxDecoration _paperCard = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(AppTheme.cardRadius)),
  border: Border.fromBorderSide(
    BorderSide(color: AppColors.divider, width: 0.5),
  ),
);

/// 词条详情整页。
///
/// 从词库列表、搜索结果、近义词、形近词都能进来。所有区块「有才显示」：
/// - 单词本原文 / 词典补全：哪个有显示哪个
/// - 单词变形：`words.exchange` 解析出内容才显示
/// - 前后缀分析：命中 [kRootWhitelist] 白名单才显示，不命中整块不出现
/// - 近义词：只有 820 词里有数据，其余词整块不出现
/// - 形近词：算不出 3 个以内候选就整块不出现
class WordDetailPage extends StatefulWidget {
  const WordDetailPage({
    required this.wordKey,
    this.displayWord,
    this.showNext = false,
    this.revealChinese = false,
    super.key,
  });

  final String wordKey;
  final String? displayWord;

  /// 从学习会话里进来时置 true：底部出现「下一个」。
  ///
  /// 点按钮或按系统返回键都只是关掉本页，由会话页在 push 返回后推进到
  /// 下一张卡 —— 这样退出详情不会卡在已经答完的卡上。
  /// v0.6.1 去掉了上滑触发，详情页内容照常上下滚动。
  final bool showNext;

  /// 这次进来直接显示中文，不看全局遮盖开关（v0.6.4）。
  ///
  /// 只有从学习会话进来的三种情况会传 true：不认识、答错后答对、新词答对。
  /// 那正是最需要看到释义的时候，再让人点一下才显示没有意义。
  /// 词库列表进详情不传，仍按全局开关走。
  final bool revealChinese;

  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  static const _dao = DetailDao();
  static const _settings = SettingsDao();

  WordDetail? _detail;
  String? _error;
  bool _loading = true;

  bool _masked = false;
  final Set<String> _revealed = <String>{};

  /// 已经点过「下一个」，防止返回动画期间重复 pop。
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await _dao.load(widget.wordKey, displayWord: widget.displayWord);
      final masked = await _settings.maskChinese();
      if (!mounted) return;
      setState(() {
        _detail = detail;
        // 学习会话进来：直接显示，全局开关是关是开都不管。
        _masked = widget.revealChinese ? false : masked;
        _loading = false;
        if (detail == null) _error = '词库里没这个词';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DatabaseUnavailable ? '词库打不开' : '词库读取失败';
        _loading = false;
      });
    }
  }

  Future<void> _toggleStar() async {
    final d = _detail;
    if (d == null) return;
    final next = await _dao.toggleStar(d.wordKey);
    if (!mounted) return;
    setState(() {
      _detail = WordDetail(
        wordKey: d.wordKey,
        word: d.word,
        phonetic: d.phonetic,
        meaningPdf: d.meaningPdf,
        pdfTruncated: d.pdfTruncated,
        meaningEcdict: d.meaningEcdict,
        pos: d.pos,
        tag: d.tag,
        collins: d.collins,
        no: d.no,
        isAdded: d.isAdded,
        starred: next,
        forms: d.forms,
        synonyms: d.synonyms,
        nearWords: d.nearWords,
      );
    });
  }

  Future<void> _toggleMask() async {
    final next = !_masked;
    await _settings.setMaskChinese(next);
    if (!mounted) return;
    setState(() {
      _masked = next;
      _revealed.clear();
    });
  }

  Future<void> _speak(String text) async {
    final ok = await Speech.speak(text);
    if (!mounted) return;
    if (!ok) {
      _toast('这台手机没有可用的英文语音引擎');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _addToList() async {
    final d = _detail;
    if (d == null) return;
    await _dao.addToMyList(d.wordKey);
    if (!mounted) return;
    _toast('已加入我的词表');
    _load();
  }

  Future<void> _removeFromList() async {
    final d = _detail;
    if (d == null) return;
    await _dao.removeFromMyList(d.wordKey);
    if (!mounted) return;
    _toast('已从我的词表移除');
    _load();
  }

  void _openWord(String word) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailPage(wordKey: word, displayWord: word),
      ),
    );
  }

  void _requestNext() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          // 学习会话进来的这一次是「专门来看意思」的，不给遮盖开关：
          // 摆在那里只会让人误以为还能盖回去，实际那个开关是全局的。
          if (!widget.revealChinese)
            IconButton(
              tooltip: _masked ? '取消遮盖中文' : '遮盖中文',
              onPressed: _toggleMask,
              icon: Icon(
                _masked
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: _masked ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
        ],
      ),
      body: _body(),
      bottomNavigationBar:
          widget.showNext && !_loading && _detail != null ? _nextBar() : null,
    );
  }

  /// 学习会话里的「下一个」。v0.6.1 起只保留按钮，上滑不再触发。
  Widget _nextBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _requestNext,
            child: const Text('下一个'),
          ),
        ),
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
    final d = _detail;
    if (d == null) {
      return Center(
        child: Text(
          _error ?? '没找到',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    final root = kRootWhitelist[d.wordKey];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _head(d),
        const SizedBox(height: 20),
        if (d.meaningPdf.isNotEmpty) ...[
          _sourceBlock(
            key: 'pdf',
            label: '单词本原文',
            body: d.meaningPdf,
            note: d.pdfTruncated ? 'PDF 里这条被「…」截断过，完整词义看下方词典补全' : null,
          ),
          const SizedBox(height: 20),
        ],
        _sourceBlock(
          key: 'ecdict',
          label: '词典补全',
          body: d.meaningEcdict.isEmpty ? '词典未收录这个词条' : d.meaningEcdict,
          dim: d.meaningEcdict.isEmpty,
        ),
        if (d.forms.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Section(
            title: '单词变形',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in d.forms)
                  _Chip(label: '${f.label} · ${f.value}'),
              ],
            ),
          ),
        ],
        if (root != null) ...[
          const SizedBox(height: 20),
          _Section(
            title: '前后缀分析',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in root.parts)
                      _Chip(
                        label: m.label,
                        sub: '${m.kindLabel} · ${m.meaning}',
                        highlight: m.kind == MorphemeKind.root,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  root.note,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary, height: 1.6),
                ),
              ],
            ),
          ),
        ],
        if (d.synonyms.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Section(
            title: '近义词',
            child: Column(
              children: [
                for (final s in d.synonyms)
                  _LinkRow(
                    word: s.word,
                    phonetic: s.phonetic,
                    gloss: s.gloss,
                    note: s.distinction,
                    masked: _maskedFor('syn-${s.word}'),
                    onReveal: () => _reveal('syn-${s.word}'),
                    onTap: () => _openWord(s.word),
                  ),
              ],
            ),
          ),
        ],
        if (d.nearWords.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Section(
            title: '形近词',
            child: Column(
              children: [
                for (final n in d.nearWords)
                  _LinkRow(
                    word: n.word,
                    gloss: n.gloss,
                    masked: _maskedFor('near-${n.word}'),
                    onReveal: () => _reveal('near-${n.word}'),
                    onTap: () => _openWord(n.word),
                    trailing: '距离 ${n.distance}',
                  ),
              ],
            ),
          ),
        ],
        if (d.tag.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            d.tag.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.4,
                ),
          ),
        ],
        const SizedBox(height: 32),
        _actionButton(d),
      ],
    );
  }

  bool _maskedFor(String key) => _masked && !_revealed.contains(key);

  void _reveal(String key) {
    setState(() => _revealed.add(key));
  }

  Widget _head(WordDetail d) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                d.word,
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // 星标是控件层 → 圆形玻璃（v0.7.0）。48 的点击区靠 padding 撑。
            Tooltip(
              message: d.starred ? '取消星标' : '加星标',
              child: GlassSurface(
                onTap: _toggleStar,
                radius: 999,
                blur: 0,
                padding: const EdgeInsets.all(11),
                child: Icon(
                  d.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: d.starred ? AppColors.starred : AppColors.textSecondary,
                  size: 26,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (d.phonetic.isNotEmpty) ...[
              Text(
                '/${d.phonetic}/',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
            ],
            _SpeakButton(onTap: () => _speak(d.word)),
            const Spacer(),
            if (d.inWorkbook)
              _Tag(text: '#${d.no}'),
            if (d.isAdded) ...[
              const SizedBox(width: 6),
              const _Tag(text: '自加'),
            ] else if (!d.inWorkbook && d.no == null) ...[
              const SizedBox(width: 6),
              const _Tag(text: '词典'),
            ],
          ],
        ),
      ],
    );
  }

  Widget _sourceBlock({
    required String key,
    required String label,
    required String body,
    String? note,
    bool dim = false,
  }) {
    final text = Theme.of(context).textTheme;
    final masked = _maskedFor('m-$key');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _paperCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (masked)
            _MaskedPlaceholder(onTap: () => _reveal('m-$key'))
          else
            GestureDetector(
              onTap: _masked ? () => _reveal('m-$key') : null,
              child: Text(
                body,
                style: text.bodyMedium?.copyWith(
                  height: 1.75,
                  color: dim ? AppColors.textTertiary : null,
                ),
              ),
            ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              note,
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(WordDetail d) {
    if (d.inWorkbook) {
      return _WideButton(
        label: '已在词表',
        icon: Icons.check_rounded,
        enabled: false,
        onTap: null,
      );
    }
    if (d.isAdded) {
      return _WideButton(
        label: '已加入 · 点此移除',
        icon: Icons.bookmark_remove_outlined,
        onTap: _removeFromList,
      );
    }
    return _WideButton(
      label: '加入我的词表',
      icon: Icons.bookmark_add_outlined,
      onTap: _addToList,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _paperCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.sub, this.highlight = false});

  final String label;
  final String? sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x1F0B0C10) : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? AppColors.divider : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: AppColors.textSecondary, fontSize: 10),
      ),
    );
  }
}

class _SpeakButton extends StatelessWidget {
  const _SpeakButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      onTap: onTap,
      radius: 999,
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.volume_up_rounded,
              size: 15, color: LiquidGlass.ink),
          const SizedBox(width: 5),
          Text(
            '发音',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: LiquidGlass.ink),
          ),
        ],
      ),
    );
  }
}

class _MaskedPlaceholder extends StatelessWidget {
  const _MaskedPlaceholder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_off_outlined,
                size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              '点一下显示中文',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.word,
    required this.gloss,
    required this.masked,
    required this.onReveal,
    required this.onTap,
    this.phonetic,
    this.note,
    this.trailing,
  });

  final String word;
  final String gloss;
  final bool masked;
  final VoidCallback onReveal;
  final VoidCallback onTap;
  final String? phonetic;
  final String? note;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(word, style: text.titleSmall),
                ),
                if (phonetic != null && phonetic!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '/$phonetic/',
                    style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
                const Spacer(),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            if (masked)
              GestureDetector(
                onTap: onReveal,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  '点一下显示中文',
                  style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              )
            else ...[
              if (gloss.isNotEmpty)
                Text(gloss, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (note != null && note!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  note!,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = enabled ? LiquidGlass.ink : LiquidGlass.textDisabled;

    return SizedBox(
      width: double.infinity,
      child: GlassSurface(
        onTap: enabled ? onTap : null,
        radius: 999,
        blur: 0,
        minHeight: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 8),
            Text(label, style: text.labelLarge?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
