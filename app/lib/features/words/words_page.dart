import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dao/detail_dao.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/dao/word_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/word_entry.dart';
import 'word_detail_page.dart';

/// 词库页：我的词表 + 离线查词。
///
/// 数据来自本地 SQLite（assets/db/dict.sqlite 首次启动拷入）。
/// 点任一词条进详情整页；顶部两个开关：排序（原序 / 随机）与遮盖中文。
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

  /// 随机排序后的副本。true 时列表读它，数据库顺序不动。
  bool _randomOrder = false;
  List<WordEntry> _shuffled = const [];

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
        _masked = masked;
        _loading = false;
        if (_randomOrder) _shuffled = _shuffle(words);
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

  void _toggleOrder() {
    setState(() {
      _randomOrder = !_randomOrder;
      if (_randomOrder) _shuffled = _shuffle(_myWords);
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

  bool _isMasked(String key) => _masked && !_revealed.contains(key);

  void _reveal(String key) => setState(() => _revealed.add(key));

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
              color: _masked ? AppColors.accent : AppColors.textSecondary,
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
    final text = Theme.of(context).textTheme;
    final words = _randomOrder ? _shuffled : _myWords;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: words.length + _addedWords.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _LibCard(
                      label: '我的词表',
                      value: _addedCount > 0
                          ? '$_myCount+$_addedCount'
                          : '$_myCount',
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
                    random: _randomOrder,
                    onTap: _toggleOrder,
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          );
        }

        final wi = i - 1;
        if (wi < words.length) {
          final entry = words[wi];
          return _WordRow(
            entry: entry,
            masked: _isMasked('w-${entry.wordKey}'),
            onReveal: () => _reveal('w-${entry.wordKey}'),
            onTap: () => _openDetail(entry.wordKey, displayWord: entry.word),
          );
        }

        final added = _addedWords[wi - words.length];
        return _AddedRow(
          entry: added,
          masked: _isMasked('w-${added.word}'),
          onReveal: () => _reveal('w-${added.word}'),
          onTap: () => _openDetail(added.word, displayWord: added.word),
          onRemove: () => _removeAdded(added.word, added.word),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (_hitMy.isNotEmpty) ...[
          _GroupLabel('我的词表 · ${_hitMy.length}'),
          for (final e in _hitMy)
            _WordRow(
              entry: e,
              masked: _isMasked('w-${e.wordKey}'),
              onReveal: () => _reveal('w-${e.wordKey}'),
              onTap: () => _openDetail(e.wordKey, displayWord: e.word),
            ),
          const SizedBox(height: 24),
        ],
        if (_hitAdded.isNotEmpty) ...[
          _GroupLabel('自加词 · ${_hitAdded.length}'),
          for (final e in _hitAdded)
            _AddedRow(
              entry: e,
              masked: _isMasked('w-${e.word}'),
              onReveal: () => _reveal('w-${e.word}'),
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
              masked: _isMasked('w-${e.word}'),
              onReveal: () => _reveal('w-${e.word}'),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: AppColors.accent,
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

/// 排序切换：原序 / 随机。点一次随机重排一次，不动数据库顺序。
class _OrderToggle extends StatelessWidget {
  const _OrderToggle({required this.random, required this.onTap});

  final bool random;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              random ? Icons.shuffle_rounded : Icons.format_list_numbered_rounded,
              size: 14,
              color: random ? AppColors.accent : AppColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              random ? '随机' : '原序',
              style: text.labelSmall?.copyWith(
                color: random ? AppColors.accent : AppColors.textTertiary,
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
    required this.onReveal,
  });

  final WordEntry entry;
  final VoidCallback onTap;
  final bool masked;
  final VoidCallback onReveal;

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
                  if (masked)
                    _MaskChineseLine(onTap: onReveal)
                  else
                    Text(
                      entry.meaningPdf.replaceAll('\n', ' '),
                      style: text.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
    required this.onReveal,
  });

  final DictEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool masked;
  final VoidCallback onReveal;

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
                  if (masked)
                    _MaskChineseLine(onTap: onReveal)
                  else
                    Text(
                      entry.translation.replaceAll('\n', ' / '),
                      style: text.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
    required this.onReveal,
  });

  final DictEntry entry;
  final VoidCallback onTap;
  final bool masked;
  final VoidCallback onReveal;

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
            if (masked)
              _MaskChineseLine(onTap: onReveal)
            else
              Text(
                entry.translation.replaceAll('\n', ' / '),
                style: text.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
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
