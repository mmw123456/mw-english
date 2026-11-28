import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_signals.dart';
import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';
import '../../data/dao/import_dao.dart';
import '../../data/import/document_readers.dart';
import '../../data/import/import_service.dart';

/// 纸面卡：与设置页、详情页同一套（比纸亮一点 + 0.5px 描边）。
const BoxDecoration _paperCard = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(AppTheme.cardRadius)),
  border: Border.fromBorderSide(
    BorderSide(color: AppColors.divider, width: 0.5),
  ),
);

/// 导入词表（v0.9.0）。
///
/// 流程按需求走：**先解析 → 再预览 → 用户勾选改删 → 点确认才写库**。
/// 没有「解析完直接入库」这条路，解析不确定的地方宁可让人挑。
///
/// 支持 `.pdf` / `.docx`；退路是 `.txt` / `.csv` 与粘贴文本。`.doc` 老格式不做，
/// 读不了就明说「请另存为 .docx」。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.initialPreview});

  /// 测试用：直接进预览态，跳过选文件与解析。
  ///
  /// 为什么留这个口子：预览页要断言排版与勾选行为，但正常路径依赖
  /// 文件选择器（平台通道）和 sqflite（`flutter test` 里打不开库，踩坑 21）。
  /// 真机上这个参数永远是 null。
  @visibleForTesting
  final ImportPreview? initialPreview;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

enum _Stage { idle, parsing, preview }

class _ImportPageState extends State<ImportPage> {
  static const _service = ImportService();

  _Stage _stage = _Stage.idle;

  /// 给人看的一句话错误（解析失败 / 写库失败）。不弹崩溃。
  String? _error;

  ImportPreview? _preview;
  List<ImportCandidate> _items = const [];
  Set<int> _selected = <int>{};

  int _done = 0;
  int _total = 0;
  bool _committing = false;
  bool _showUnparsed = false;

  bool get _isPdfBusy => _stage == _Stage.parsing && _total > 0;

  @override
  void initState() {
    super.initState();
    final preview = widget.initialPreview;
    if (preview != null) {
      _preview = preview;
      _items = List<ImportCandidate>.of(preview.candidates);
      _selected = <int>{for (var i = 0; i < _items.length; i++) i};
      _stage = _Stage.preview;
    }
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: '词表（PDF / Word / 文本）',
      extensions: <String>['pdf', 'docx', 'txt', 'csv', 'tsv'],
      // Android 上 extension 不一定能过 SAF 过滤，mime 兜一层
      mimeTypes: <String>[
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'text/plain',
        'text/csv',
        'text/comma-separated-values',
      ],
    );
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [group]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '打不开文件选择器：$e');
      return;
    }
    if (file == null) return;

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '读不到这个文件：$e');
      return;
    }
    await _parseBytes(bytes, file.name);
  }

  Future<void> _parseBytes(Uint8List bytes, String fileName) async {
    setState(() {
      _stage = _Stage.parsing;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final preview = await _service.buildPreview(
        fileName: fileName,
        bytes: bytes,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _items = List<ImportCandidate>.of(preview.candidates);
        _selected = <int>{for (var i = 0; i < _items.length; i++) i};
        _stage = _Stage.preview;
        _showUnparsed = false;
      });
    } on DocumentReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = '解析失败：$e';
      });
    }
  }

  Future<void> _pasteText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴单词表'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 10,
            minLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '一行一个词，或「词 + 释义」\n例如：\nabandon v. 放弃\nabandon, 放弃',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            key: const ValueKey('paste-confirm'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('解析'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;

    setState(() {
      _stage = _Stage.parsing;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final preview = await _service.buildPreviewFromText(text);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _items = List<ImportCandidate>.of(preview.candidates);
        _selected = <int>{for (var i = 0; i < _items.length; i++) i};
        _stage = _Stage.preview;
        _showUnparsed = false;
      });
    } on DocumentReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = e.message;
      });
    }
  }

  Future<void> _commit() async {
    final chosen = <ImportCandidate>[
      for (var i = 0; i < _items.length; i++)
        if (_selected.contains(i)) _items[i],
    ];
    if (chosen.isEmpty) return;
    final preview = _preview;
    setState(() {
      _committing = true;
      _error = null;
    });
    try {
      final result = await _service.commit(
        fileName: preview?.fileName ?? '粘贴的单词表',
        candidates: chosen,
        skipped: (preview?.duplicateCount ?? 0) +
            (preview?.inFileDuplicateCount ?? 0) +
            (preview?.unparsedLines.length ?? 0),
      );
      AppSignals.libraryUpdated();
      if (!mounted) return;
      Navigator.of(context).pop(result.inserted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _committing = false;
        _error = '写库失败：$e';
      });
    }
  }

  Future<void> _edit(int index) async {
    final item = _items[index];
    final wordCtrl = TextEditingController(text: item.word);
    final meaningCtrl = TextEditingController(
      text: item.meaning == ImportService.missingMeaning ? '' : item.meaning,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改这一条'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wordCtrl,
              decoration: const InputDecoration(labelText: '词', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: meaningCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '释义（留空则用词典补）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            key: const ValueKey('edit-save'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final word = wordCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final meaning = meaningCtrl.text.trim();
    wordCtrl.dispose();
    meaningCtrl.dispose();
    if (saved != true || word.isEmpty) return;
    setState(() {
      _items[index] = ImportCandidate(
        word: word,
        meaning: meaning.isEmpty ? ImportService.missingMeaning : meaning,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入词表'),
        actions: [
          if (_stage == _Stage.preview && _items.isNotEmpty)
            TextButton(
              key: const ValueKey('toggle-all'),
              onPressed: () {
                setState(() {
                  if (_selected.length == _items.length) {
                    _selected = <int>{};
                  } else {
                    _selected = <int>{for (var i = 0; i < _items.length; i++) i};
                  }
                });
              },
              child: Text(_selected.length == _items.length ? '全不选' : '全选'),
            ),
        ],
      ),
      body: switch (_stage) {
        _Stage.idle => _idleBody(context),
        _Stage.parsing => _parsingBody(context),
        _Stage.preview => _previewBody(context),
      },
      bottomNavigationBar: _stage == _Stage.preview && _items.isNotEmpty
          ? _confirmBar(context)
          : null,
    );
  }

  // ---------- 选来源 ----------

  Widget _idleBody(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: ShellPadding.scroll(context),
      children: [
        if (_error != null) _ErrorBox(message: _error!),
        _OptionCard(
          icon: Icons.upload_file_rounded,
          title: '选择文件',
          subtitle: 'PDF / Word（.docx）；退路是 .txt / .csv',
          key: const ValueKey('pick-file'),
          onTap: _pickFile,
        ),
        const SizedBox(height: 12),
        _OptionCard(
          icon: Icons.content_paste_rounded,
          title: '粘贴文本',
          subtitle: '把词表直接粘进来，一行一个词',
          key: const ValueKey('pick-paste'),
          onTap: _pasteText,
        ),
        const SizedBox(height: 20),
        Text(
          '支持这几种排版：编号列表（1. abandon）、一行一词、词 + 词性 + 释义、'
          '逗号或分号分隔、Tab 分隔。短语会整串保留。\n'
          '解析完先进预览，勾选确认后才写进词库。老版 .doc 请另存为 .docx。',
          style: text.labelSmall?.copyWith(
            color: AppColors.textTertiary,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // ---------- 解析中 ----------

  Widget _parsingBody(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: _isPdfBusy ? _done / _total : null,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isPdfBusy ? '正在解析 $_done / $_total 页' : '正在解析…',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '全程在本机解析，不上传文件、不联网',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ---------- 预览 ----------

  Widget _previewBody(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();

    return ListView.builder(
      padding: ShellPadding.scroll(context),
      itemCount: _items.length + 1 + (preview.unparsedLines.isEmpty ? 0 : 1),
      itemBuilder: (context, i) {
        if (i == 0) return _summary(context, preview);
        final idx = i - 1;
        if (idx >= _items.length) {
          return _unparsedBlock(context, preview);
        }
        final item = _items[idx];
        final checked = _selected.contains(idx);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(idx);
                  } else {
                    _selected.remove(idx);
                  }
                }),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _edit(idx),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.word, style: text.bodyMedium),
                        const SizedBox(height: 2),
                        Text(
                          item.meaning,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            color: item.meaning == ImportService.missingMeaning
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '改这一条',
                onPressed: () => _edit(idx),
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AppColors.textTertiary,
              ),
              IconButton(
                tooltip: '不要这个',
                onPressed: () => setState(() {
                  _items.removeAt(idx);
                  // 勾选集合按下标存，删掉中间一条要整体往前挪一位。
                  // 被删那条对应下标在新集合里已经不存在（映射里直接跳过），
                  // 这里不要再 remove 一次 —— 会多删掉后面的一条。
                  _selected = <int>{
                    for (final s in _selected)
                      if (s < idx) s else if (s > idx) s - 1,
                  };
                }),
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textTertiary,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summary(BuildContext context, ImportPreview preview) {
    final text = Theme.of(context).textTheme;
    final parts = <String>[
      '解析出 ${preview.parsedTotal} 个词',
      if (preview.duplicateCount > 0) '重复跳过 ${preview.duplicateCount}',
      if (preview.inFileDuplicateCount > 0) '文件内重复 ${preview.inFileDuplicateCount}',
      if (preview.unparsedLines.isEmpty) '全部解析成功' else '${preview.unparsedLines.length} 行没认出来',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) _ErrorBox(message: _error!),
          Text(
            preview.fileName,
            style: text.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            parts.join(' · '),
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _unparsedBlock(BuildContext context, ImportPreview preview) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('unparsed-toggle'),
            onTap: () => setState(() => _showUnparsed = !_showUnparsed),
            child: Row(
              children: [
                Text(
                  '没认出来的 ${preview.unparsedLines.length} 行',
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showUnparsed ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
          if (_showUnparsed) ...[
            const SizedBox(height: 8),
            for (final line in preview.unparsedLines.take(50))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            if (preview.unparsedLines.length > 50)
              Text(
                '（只显示前 50 行）',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ],
      ),
    );
  }

  Widget _confirmBar(BuildContext context) {
    final count = _selected.length;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          key: const ValueKey('confirm-import'),
          onPressed: (_committing || count == 0) ? null : _commit,
          child: _committing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('导入 $count 个新词'),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: _paperCard,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppColors.textSecondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.bodyMedium),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: LiquidGlass.wrongPink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: LiquidGlass.wrongPink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: text.labelSmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
