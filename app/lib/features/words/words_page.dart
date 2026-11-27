import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/app_signals.dart';
import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../app/widgets/box_badge.dart';
import '../../data/dao/detail_dao.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/dao/study_dao.dart';
import '../../data/dao/word_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/models/killed_word.dart';
import '../../data/models/word_entry.dart';
import 'import_page.dart';
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

class _WordsPageState extends State<WordsPage>
    with AutomaticKeepAliveClientMixin {
  static const _dao = WordDao();
  static const _settings = SettingsDao();
  static const _detailDao = DetailDao();
  static const _studyDao = StudyDao();

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;

  /// 设置变了、或词库变了（导入 / 恢复）都走这一条监听。
  late final Listenable _signals = Listenable.merge([
    AppSignals.settingsChanged,
    AppSignals.libraryChanged,
  ]);

  int _myCount = 0;
  int _addedCount = 0;
  int _dictCount = 0;
  List<WordEntry> _myWords = const [];
  List<DictEntry> _addedWords = const [];

  /// 每个词的当前箱位（v0.7.7）。没学过的词不在表里 → 按箱 0 画灰点。
  /// 读失败时留空表，色点全部退成箱 0，不影响词库本身打开。
  ///
  /// v0.8.0：自加词也进调度，所以这张表同样适用于自加词；`AddedRow`
  /// 不再固定画箱 0。
  Map<String, int> _boxOf = const {};

  /// 已斩的词（v0.8.0）。词库保留，这里给一个可展开的分组 + 行内「恢复」。
  List<KilledWord> _killed = const [];

  /// 已斩分组是否展开。默认收起，不占词表空间。
  bool _showKilled = false;

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
    _signals.addListener(_onDataChanged);
    _loadBase();
  }

  @override
  void dispose() {
    _signals.removeListener(_onDataChanged);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 设置页改了遮盖中文 / 每日目标后重读。遮盖是这一页的显示状态，
  /// 目标不直接显示，但配额与箱位可能变，一起刷新不亏。
  void _onDataChanged() {
    if (!mounted) return;
    _loadBase();
    if (_searching && _query.isNotEmpty) _runSearch(_query);
  }

  /// 划走再划回来不重建（v0.7.3）：搜索框内容、滚动位置、遮盖状态都在，
  /// 也不重新读库。列表上下滑仍是自己的 ListView，只认纵向。
  @override
  bool get wantKeepAlive => true;

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
      // 箱位读不到就不画色点，不能因为一张辅助表把整页打进错误态。
      var boxOf = const <String, int>{};
      try {
        boxOf = await _studyDao.boxByWord();
      } catch (_) {}
      // 已斩列表同理：读不到就整组不出现，不拦词库。
      var killed = const <KilledWord>[];
      try {
        killed = await _studyDao.killedWords();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _myCount = counts[0];
        _dictCount = counts[1];
        _addedCount = counts[2];
        _myWords = words;
        _addedWords = added;
        _byAddedAt = words.reversed.toList();
        _boxOf = boxOf;
        _killed = killed;
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

  /// 打开导入页（v0.9.0）。导入页自己负责解析与预览，这里只接结果：
  /// 真的写进去了就重读词库，并弹一句「导入了 N 个」。
  Future<void> _openImport() async {
    final imported = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(builder: (_) => const ImportPage()),
    );
    if (!mounted || imported == null) return;
    _loadBase();
    if (_searching && _query.isNotEmpty) _runSearch(_query);
    if (imported > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $imported 个词，按添加顺序排进每日新词')),
      );
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
    super.build(context); // AutomaticKeepAliveClientMixin 要求先调 super.build
    return Scaffold(
      appBar: AppBar(
        title: const Text('词库'),
        actions: [
          // 导入词表（v0.9.0）：词库页唯一入口，不占 Tab、不上首页。
          IconButton(
            key: const ValueKey('import-entry'),
            tooltip: '导入词表',
            onPressed: _openImport,
            icon: const Icon(Icons.file_upload_outlined,
                size: 20, color: AppColors.textSecondary),
          ),
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

  Future<void> _restoreKilled(KilledWord k) async {
    try {
      await _studyDao.restore(k.wordKey);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复没写进库，稍后再试')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已恢复 ${k.word}'), duration: const Duration(seconds: 2)),
    );
    _loadBase();
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

    // 已斩分组（v0.8.0）紧跟在头部：一条可点的分组条，默认收起。
    final hasKilled = _killed.isNotEmpty;
    final killedRows = hasKilled && _showKilled ? _killed.length : 0;
    final headCount = 1 + (hasKilled ? 1 : 0) + killedRows;

    return ListView.builder(
      // 底部 96 + 安全区：Tab 栏浮在内容上，最后一行别被挡住。
      padding: ShellPadding.scroll(context),
      itemCount: headCount + myWords.length + _addedWords.length,
      itemBuilder: (context, i) {
        if (i == 0) return _header();
        if (hasKilled && i == 1) return _killedHeader();
        if (hasKilled && _showKilled && i >= 2 && i < 2 + _killed.length) {
          final k = _killed[i - 2];
          return KilledRow(
            entry: k,
            masked: _masked,
            revealed: _revealed.contains('k-${k.wordKey}'),
            onToggleMask: () => _toggleReveal('k-${k.wordKey}'),
            onRestore: () => _restoreKilled(k),
          );
        }

        final j = i - headCount;
        final mi = j - myOffset;
        if (mi >= 0 && mi < myWords.length) {
          final entry = myWords[mi];
          return WordRow(
            entry: entry,
            box: _boxOf[entry.wordKey] ?? 0,
            masked: _masked,
            revealed: _revealed.contains('w-${entry.wordKey}'),
            onToggleMask: () => _toggleReveal('w-${entry.wordKey}'),
            onTap: () => _openDetail(entry.wordKey, displayWord: entry.word),
          );
        }

        final added = _addedWords[j - addedOffset];
        return AddedRow(
          entry: added,
          box: _boxOf[added.word] ?? 0,
          masked: _masked,
          revealed: _revealed.contains('w-${added.word}'),
          onToggleMask: () => _toggleReveal('w-${added.word}'),
          onTap: () => _openDetail(added.word, displayWord: added.word),
          onRemove: () => _removeAdded(added.word, added.word),
        );
      },
    );
  }

  /// 已斩分组条（v0.8.0）：点一下展开 / 收起，收起时不占词表空间。
  Widget _killedHeader() {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: const ValueKey('killed-group'),
        onTap: () => setState(() => _showKilled = !_showKilled),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.block_rounded,
                  size: 15, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Text(
                '已斩',
                style: text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_killed.length} 词',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              const Spacer(),
              Text(
                _showKilled ? '收起' : '查看',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              Icon(
                _showKilled ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
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
        const SizedBox(height: 20),
        Row(
          children: [
            // T2 区块标题：700 / 墨 62%（v0.7.9）。
            Text(
              '词表',
              style: text.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
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
            WordRow(
              entry: e,
              box: _boxOf[e.wordKey] ?? 0,
              masked: _masked,
              revealed: _revealed.contains('w-${e.wordKey}'),
              onToggleMask: () => _toggleReveal('w-${e.wordKey}'),
              onTap: () => _openDetail(e.wordKey, displayWord: e.word),
            ),
          const SizedBox(height: 20),
        ],
        if (_hitAdded.isNotEmpty) ...[
          _GroupLabel('自加词 · ${_hitAdded.length}'),
          for (final e in _hitAdded)
            AddedRow(
              entry: e,
              box: _boxOf[e.word] ?? 0,
              masked: _masked,
              revealed: _revealed.contains('w-${e.word}'),
              onToggleMask: () => _toggleReveal('w-${e.word}'),
              onTap: () => _openDetail(e.word, displayWord: e.word),
              onRemove: () => _removeAdded(e.word, e.word),
            ),
          const SizedBox(height: 20),
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

/// 我的词表的一行（v0.7.7 起公开）。
///
/// 公开是为了让 widget 测试能直接喂一份固定的箱位、断言色点颜色 ——
/// [WordsPage] 本身依赖 sqflite，`flutter test` 里打不开库（踩坑 21），
/// 从页面层测不到这一行。同 [TodayCard] 的处理方式。
class WordRow extends StatelessWidget {
  const WordRow({
    required this.entry,
    required this.onTap,
    required this.masked,
    required this.revealed,
    required this.onToggleMask,
    this.box = 0,
    super.key,
  });

  final WordEntry entry;
  final VoidCallback onTap;
  final bool masked;

  /// 当前箱位（v0.7.7）。没学过 = 0，画墨 35% 灰点。
  final int box;

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
                style: AppTheme.numeric(
                  text.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
            // 箱位色点（v0.7.7）：序号与单词之间，8px 实心圆。
            // 行高与释义排版不动，只是整行右移 16px。
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: BoxDot(box: box),
            ),
            const SizedBox(width: 8),
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

/// 自加词的一行（v0.7.7 起公开，原因同 [WordRow]）。
///
/// v0.8.0：自加词进同一套 Leitner 调度，箱位色点是**真实箱位**，
/// 不再固定画箱 0 灰点（决策 107）。没学过 = 0，与 820 词同一支。
class AddedRow extends StatelessWidget {
  const AddedRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
    required this.masked,
    required this.revealed,
    required this.onToggleMask,
    this.box = 0,
    super.key,
  });

  final DictEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool masked;
  final bool revealed;
  final VoidCallback onToggleMask;

  /// 当前箱位（v0.8.0）。没学过 = 0，画墨 35% 灰点。
  final int box;

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
            // 自加词也进调度（v0.8.0），色点画真实箱位；没学过 = 箱 0 灰点。
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: BoxDot(box: box),
            ),
            const SizedBox(width: 8),
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

/// 已斩的一行（v0.8.0）。公开原因同 [WordRow]：`WordsPage` 依赖 sqflite，
/// widget 测试只能单独喂这一行。
///
/// 行首仍画箱位点：斩只改队列状态，不改箱位；恢复后回到原来的箱。
class KilledRow extends StatelessWidget {
  const KilledRow({
    required this.entry,
    required this.masked,
    required this.revealed,
    required this.onToggleMask,
    required this.onRestore,
    super.key,
  });

  final KilledWord entry;
  final bool masked;
  final bool revealed;
  final VoidCallback onToggleMask;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 34,
            child: Icon(Icons.block_rounded,
                size: 12, color: AppColors.textTertiary),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: BoxDot(box: entry.box),
          ),
          const SizedBox(width: 8),
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
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                    if (entry.isAdded) ...[
                      const SizedBox(width: 8),
                      Text(
                        '自加',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                _MeaningBlock(
                  text: entry.meaning.replaceAll('\n', ' '),
                  masked: masked,
                  revealed: revealed,
                  onToggle: onToggleMask,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: ValueKey('restore-${entry.wordKey}'),
            onPressed: onRestore,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '恢复',
              style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
              fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
              Text(value, style: AppTheme.numeric(text.headlineSmall)),
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
