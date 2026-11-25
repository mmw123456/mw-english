import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';

/// 词库页。
///
/// 阶段 2 只做骨架。搜索、详情、星标/错题/斩标记在 P0 第 3 步之后接。
class WordsPage extends StatelessWidget {
  const WordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('词库')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // 搜索框：先做成不可用，明确告诉用户还没接
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 10),
                Text(
                  '查词（P0 之后再接）',
                  style: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(
                child: _LibCard(
                  label: '我的词表',
                  value: '820',
                  unit: '词',
                  note: '来自单词本 PDF',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _LibCard(
                  label: '离线词典',
                  value: '43,350',
                  unit: '词',
                  note: 'ECDICT 裁剪档 · 5.5 MB',
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
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 34,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  '还没导入',
                  style: text.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '820 词与词典在 P0 第 3 步写入 SQLite',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
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
