import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dao/word_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/word_entry.dart';

/// 词库页：我的词表 + 离线查词。
///
/// 数据来自本地 SQLite（assets/db/dict.sqlite 首次启动拷入）。
/// 点任一词条弹出详情，释义分「单词本原文」与「词典补全」两段并标注来源。
class WordsPage extends StatefulWidget {
  const WordsPage({super.key});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  static const _dao = WordDao();

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;

  int _myCount = 0;
  int _dictCount = 0;
  List<WordEntry> _myWords = const [];

  bool _searching = false;
  String _query = '';
  List<WordEntry> _hitMy = const [];
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
      ]);
      final words = await _dao.loadMyWords(limit: 1000);
      if (!mounted) return;
      setState(() {
        _myCount = counts[0];
        _dictCount = counts[1];
        _myWords = words;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DatabaseUnavailable ? '词库打不开' : '词库读取失败';
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _query = '';
        _hitMy = const [];
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
      ]);
      if (!mounted) return;
      setState(() {
        _query = q;
        _searching = true;
        _hitMy = results[0] as List<WordEntry>;
        _hitDict = results[1] as List<DictEntry>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _query = q;
        _searching = true;
        _hitMy = const [];
        _hitDict = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('词库')),
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: _myWords.length + 1,
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
                      value: '$_myCount',
                      unit: '词',
                      note: '单词本 PDF 原序',
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
              const SizedBox(height: 28),
              Text(
                '词表',
                style: text.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
            ],
          );
        }
        final entry = _myWords[i - 1];
        return _WordRow(entry: entry, onTap: () => _showDetail(entry));
      },
    );
  }

  Widget _searchResult() {
    if (_hitMy.isEmpty && _hitDict.isEmpty) {
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
            _WordRow(entry: e, onTap: () => _showDetail(e)),
          const SizedBox(height: 24),
        ],
        if (_hitDict.isNotEmpty) ...[
          _GroupLabel('离线词典 · ${_hitDict.length}'),
          for (final e in _hitDict) _DictRow(entry: e),
        ],
      ],
    );
  }

  void _showDetail(WordEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxHeight: 560),
      builder: (_) => _WordDetailSheet(entry: entry),
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

class _WordRow extends StatelessWidget {
  const _WordRow({required this.entry, required this.onTap});

  final WordEntry entry;
  final VoidCallback onTap;

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

class _DictRow extends StatelessWidget {
  const _DictRow({required this.entry});

  final DictEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
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
          Text(
            entry.translation.replaceAll('\n', ' / '),
            style: text.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 词条详情：两段释义并列，明确标注来源。
class _WordDetailSheet extends StatelessWidget {
  const _WordDetailSheet({required this.entry});

  final WordEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                entry.word,
                style: text.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.phonetic.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                '/${entry.phonetic}/',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 22),
        _SourceBlock(
          label: '单词本原文',
          body: entry.meaningPdf,
          note: entry.pdfTruncated ? 'PDF 里这条被「…」截断过，完整词义看下方词典' : null,
        ),
        const SizedBox(height: 18),
        _SourceBlock(
          label: '词典补全',
          body: entry.meaningEcdict.isEmpty
              ? '词典未收录这个词条'
              : entry.meaningEcdict,
          dim: entry.meaningEcdict.isEmpty,
        ),
        if (entry.tag.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            entry.tag.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceBlock extends StatelessWidget {
  const _SourceBlock({
    required this.label,
    required this.body,
    this.note,
    this.dim = false,
  });

  final String label;
  final String body;
  final String? note;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
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
        Text(
          body,
          style: text.bodyMedium?.copyWith(
            height: 1.75,
            color: dim ? AppColors.textTertiary : null,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
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
