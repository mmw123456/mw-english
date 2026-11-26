import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/liquid_glass.dart';
import '../../data/dao/detail_dao.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/dao/word_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/word_entry.dart';
import 'word_detail_page.dart';

/// 词库页：我的词表 + 离线查词。
///
/// 数据来自本地 SQLite（assets/db/dict.sqlite 首次启动拷入）。
/// 点任一词条进详情整页；顶部两个开关：排序（原序 / 随机 / 添加时间）与遮盖中文。
class WordsPage extends StatefulWidget {
  const WordsPage({super.key});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  static const _dao = WordDao();
  static const _settings = SettingsDao();
  static const _detailDao = DetailDao();

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;

  int _myCount = 0;
  int _addedCount = 0;
  int _dictCount = 0;
  List<WordEntry> _myWords = const [];
  List<DictEntry> _addedWords = const [];

  /// 当前排序。三态循环，见 [_cycleOrder]。
  _OrderMode _order = _OrderMode.original;

  /// 随机排序后的副本。随机态读它，数据库顺序不动。
  List<WordEntry> _shuffled = const [];

  /// 添加时间序：820 词没有时间戳字段，序号就是收藏顺序，按序号倒序（820→1）。
  List<WordEntry> _byAddedAt = const [];

  bool _masked = false;
  final Set<String> _revealed = <String>{};

  bool _searching = false;
  String _query = '';
  List<WordEntry> _hitMy = const [];
  List<DictEntry> _hitAdded = const [];
  List<DictEntry> _hitDict = const [];

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    try {
      final counts = await Future.wait([
        _dao.countMyWords(),
        _dao.countDictionary(),
        _settings.addedCount(),
      ]);
      final words = await _dao.loadMyWords(limit: 1000);
      final added = await _dao.loadAddedWords();
      final masked = await _settings.maskChinese();
      if (!mounted) return;
      setState(() {
        _myCount = counts[0];
        _dictCount = counts[1];
        _addedCount = counts[2];
        _myWords = words;
        _addedWords = added;
        _byAddedAt = words.reversed.toList();
        _masked = masked;
        _loading = false;
        if (_order == _OrderMode.random) _shuffled = _shuffle(words);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DatabaseUnavailable ? '词库打不开' : '词库读取失败';
        _loading = false;
      });
    }
  }

  List<WordEntry> _shuffle(List<WordEntry> src) {
    final list = List<WordEntry>.of(src);
    list.shuffle();
    return list;
  }

  /// 排序三态循环（v0.6.2）：原序 → 随机 → 添加时间 → 原序。
  ///
  /// 只有进「随机」这一步重洗一次；「添加时间」和「原序」都是现成的顺序，
  /// 不重洗、不写库。
  void _cycleOrder() {
    setState(() {
      _order = switch (_order) {
        _OrderMode.original => _OrderMode.random,
        _OrderMode.random => _OrderMode.addedAt,
        _OrderMode.addedAt => _OrderMode.original,
      };
      if (_order == _OrderMode.random) _shuffled = _shuffle(_myWords);
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

  /// 遮盖开着时点中文：没显示就显示，显示着就恢复遮盖（v0.6.2）。
  /// 只在中文那一行接点击，行内其他地方仍走 [_openDetail]。
  void _toggleReveal(String key) => setState(() {
        if (!_revealed.remove(key)) _revealed.add(key);
      });

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _query = '';
        _hitMy = const [];
        _hitAdded = const [];
        _hitDict = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 260), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    try {
      final results = await Future.wait([
        _dao.searchMyWords(q),
        _dao.searchDictionary(q),
        _dao.searchAddedWords(q),
      ]);
      if (!mounted) return;
      setState(() {
        _query = q;
        _searching = true;
        _hitMy = results[0] as List<WordEntry>;
        _hitDict = results[1] as List<DictEntry>;
        _hitAdded = results[2] as List<DictEntry>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _query = q;
        _searching = true;
        _hitMy = const [];
        _hitAdded = const [];
        _hitDict = const [];
      });
    }
  }

  Future<void> _openDetail(String wordKey, {String? displayWord}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailPage(wordKey: wordKey, displayWord: displayWord),
      ),
    );
    if (!mounted) return;
    _loadBase();
    if (_searching && _query.isNotEmpty) _runSearch(_query);
  }

  Future<void> _removeAdded(String wordKey, String word) async {
    await _detailDao.removeFromMyList(wordKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除 $word'), duration: const Duration(seconds: 2)),
    );
    _loadBase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词库'),
        actions: [
          IconButton(
            tooltip: _masked ? '取消遮盖中文' : '遮盖中文',
            onPressed: _toggleMask,
            icon: Icon(
              _masked ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: _masked ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: _SearchField(
              controller: _searchCtrl,
              onChanged: _onQueryChanged,
              onClear: () {
                _searchCtrl.clear();
                _onQueryChanged('');
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
    if (_error != null) {
      return _EmptyState(
        icon: Icons.storage_outlined,
        title: _error!,
        note: '词库随安装包提供，重装 App 可恢复',
      );
    }
    return _searching ? _searchResult() : _browse();
  }

  Widget _browse() {
    final myWords = switch (_order) {
      _OrderMode.original => _myWords,
      _OrderMode.random => _shuffled,
      _OrderMode.addedAt => _byAddedAt,
    };

    // 「添加时间」：自加词（added_at 倒序）排在 820 词前面；其余两种排后面。
    final addedFirst = _order == _OrderMode.addedAt;
    final myOffset = addedFirst ? _addedWords.length : 0;
    final addedOffset = addedFirst ? 0 : myWords.length;

    return ListView.builder(
      // 底部 96 + 安全区：Tab 栏浮在内容上，最后一行别被挡住。
      padding: ShellPadding.scroll(context),
      itemCount: myWords.length + _addedWords.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _header();

        final j = i - 1;
        final mi = j - myOffset;
        if (mi >= 0 && mi < myWords.length) {
          final entry = myWords[mi];
          return _WordRow(
            entry: entry,
            masked: _masked,
            revealed: _revealed.contains('w-${entry.wordKey}'),
            onToggleMask: () => _toggleReveal('w-${entry.wordKey}'),
            onTap: () => _openDetail(entry.wordKey, displayWord: entry.word),
          );
        }

        final added = _addedWords[j - addedOffset];
        return _AddedRow(
          entry: added,
          masked: _masked,
          revealed: _revealed.contains('w-${added.word}'),
          onToggleMask: () => _toggleReveal('w-${added.word}'),
          onTap: () => _openDetail(added.word, displayWord: added.word),
          onRemove: () => _removeAdded(added.word, added.word),
        );
      },
    );
  }

  /// 列表头部：两张数量卡 + 排序切换。
  Widget _header() {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _LibCard(
                label: '我的词表',
                value: _addedCount > 0 ? '$_myCount+$_addedCount' : '$_myCount',
                unit: '词',
                note: _addedCount > 0 ? '单词本 820 + 自加 $_addedCount' : '单词本 PDF 原序',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LibCard(
                label: '离线词典',
                value: _dictCount.toString().replaceAllMapped(
                      RegExp(r'(\d)(?=(\d{3})+$)'),
                      (m) => '${m[1]},',
                    ),
                unit: '词',
                note: 'ECDICT 裁剪档',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              '词表',
              style: text.labelMedium?.copyWith(
                letterSpacing: 1.2,
                color: AppColors.textTertiary,
              ),
            ),
            const Spacer(),
            _OrderToggle(
              mode: _order,
              onTap: _cycleOrder,
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _searchResult() {
    if (_hitMy.isEmpty && _hitAdded.isEmpty && _hitDict.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        title: '没找到「$_query」',
        note: '我的词表 $_myCount 词 / 离线词典 $_dictCount 词都没命中',
      );
    }
    return ListView(
      padding: ShellPadding.scroll(context),
      children: [
        if (_hitMy.isNotEmpty) ...[
          _GroupLabel('我的词表 · ${_hitMy.length}'),
          for (final e in _hitMy)
            _WordRow(
              entry: e,
              masked: _masked,
              revealed: _revealed.contains('w-${e.wordKey}'),
              onToggleMask: () => _toggleReveal('w-${e.wordKey}'),
              onTap: () => _openDetail(e.wordKey, displayWord: e.word),
            ),
          const SizedBox(height: 24),
        ],
        if (_hitAdded.isNotEmpty) ...[
          _GroupLabel('自加词 · ${_hitAdded.length}'),
          for (final e in _hitAdded)
            _AddedRow(
              entry: e,
              masked: _masked,
              revealed: _revealed.contains('w-${e.word}'),
              onToggleMask: () => _toggleReveal('w-${e.word}'),
              onTap: () => _openDetail(e.word, displayWord: e.word),
              onRemove: () => _removeAdded(e.word, e.word),
            ),
          const SizedBox(height: 24),
        ],
        if (_hitDict.isNotEmpty) ...[
          _GroupLabel('离线词典 · ${_hitDict.length}'),
          for (final e in _hitDict)
            _DictRow(
              entry: e,
              masked: _masked,
              revealed: _revealed.contains('w-${e.word}'),
              onToggleMask: () => _toggleReveal('w-${e.word}'),
              onTap: () => _openDetail(e.word, displayWord: e.word),
            ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // 搜索框是控件层 → 玻璃胶囊（v0.7.0）。列表行仍压纸、不上玻璃。
    return GlassSurface(
      radius: 999,
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: LiquidGlass.ink,
              style: text.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '查词，中英均可',
                hintStyle: text.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 17, color: AppColors.textTertiary),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 词表排序。三态循环：原序 → 随机 → 添加时间 → 原序（v0.6.2）。
enum _OrderMode { original, random, addedAt }

/// 排序切换按钮。文案跟当前状态走；点一次进下一态，随机态每次进都重洗。
class _OrderToggle extends StatelessWidget {
  const _OrderToggle({required this.mode, required this.onTap});

  final _OrderMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = mode != _OrderMode.original;

    final (icon, label) = switch (mode) {
      _OrderMode.original => (Icons.format_list_numbered_rounded, '原序'),
      _OrderMode.random => (Icons.shuffle_rounded, '随机'),
      _OrderMode.addedAt => (Icons.schedule_rounded, '添加时间'),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: on ? AppColors.accent : AppColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: text.labelSmall?.copyWith(
                color: on ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.entry,
    required this.onTap,
    required this.masked,
    required this.revealed,
    required this.onToggleMask,
  });

  final WordEntry entry;
  final VoidCallback onTap;
  final bool masked;

  /// 遮盖开着时，这一行当前是否已显示释义。
  final bool revealed;
  final VoidCallback onToggleMask;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${entry.no}',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          entry.word,
                          style: text.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.phonetic.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '/${entry.phonetic}/',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  _MeaningBlock(
                    text: entry.meaningPdf.replaceAll('\n', ' '),
                    masked: masked,
                    revealed: revealed,
                    onToggle: onToggleMask,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddedRow extends StatelessWidget {
  const _AddedRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
    required this.masked,
    required this.revealed,
    required this.onToggleMask,
  });

  final DictEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool masked;
  final bool revealed;
  final VoidCallback onToggleMask;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 34, child: Icon(Icons.bookmark_rounded, size: 12, color: AppColors.textTertiary)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(child: Text(entry.word, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Text(
                        '自加',
                        style: text.labelSmall?.copyWith(color: AppColors.textTertiary, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  _MeaningBlock(
                    text: entry.translation.replaceAll('\n', ' / '),
                    masked: masked,
                    revealed: revealed,
                    onToggle: onToggleMask,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: '从我的词表移除',
              icon: const Icon(Icons.close, size: 15, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DictRow extends StatelessWidget {
  const _DictRow({
    required this.entry,
    required this.onTap,
    required this.masked,
    required this.revealed,
    required this.onToggleMask,
  });

  final DictEntry entry;
  final VoidCallback onTap;
  final bool masked;
  final bool revealed;
  final VoidCallback onToggleMask;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    entry.word,
                    style: text.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.phonetic.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '/${entry.phonetic}/',
                    style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            _MeaningBlock(
              text: entry.translation.replaceAll('\n', ' / '),
              masked: masked,
              revealed: revealed,
              onToggle: onToggleMask,
            ),
          ],
        ),
      ),
    );
  }
}

/// 释义那一行，三种状态（v0.6.2）：
/// - 没开遮盖：正常显示，点了进详情页（由外层 InkWell 接）
/// - 遮盖且未显示：一条灰条 +「点一下显示」
/// - 遮盖且已显示：显示释义本身，再点同一处恢复遮盖
///
/// 只有文字这一块接点击，行内其他地方仍归外层跳详情页，两者不冲突。
class _MeaningBlock extends StatelessWidget {
  const _MeaningBlock({
    required this.text,
    required this.masked,
    required this.revealed,
    required this.onToggle,
  });

  final String text;
  final bool masked;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    if (!masked) {
      return Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    if (!revealed) return _MaskChineseLine(onTap: onToggle);
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

class _MaskChineseLine extends StatelessWidget {
  const _MaskChineseLine({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 96,
            height: 11,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '点一下显示',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.2,
              color: AppColors.textTertiary,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.note,
  });

  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              title,
              style: text.titleSmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(note, style: text.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LibCard extends StatelessWidget {
  const _LibCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.note,
  });

  final String label;
  final String value;
  final String unit;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: text.headlineSmall),
              const SizedBox(width: 3),
              Text(unit, style: text.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(note, style: text.labelSmall?.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
