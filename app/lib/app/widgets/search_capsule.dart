import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/liquid_glass.dart';

/// 查词搜索框（v0.11.0 从词库页抽出来，词库页与查词页共用一套）。
///
/// 搜索框是控件层 → 玻璃胶囊（v0.7.0）。列表行仍压纸、不上玻璃。
class SearchCapsule extends StatelessWidget {
  const SearchCapsule({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hint = '查词，中英均可',
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hint;

  /// 从放大镜进来时置 true：直接弹键盘，少点一次。
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

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
              autofocus: autofocus,
              cursorColor: LiquidGlass.ink,
              style: text.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
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

/// 空态 / 未查到（v0.11.0 统一）：查词页的三种空态共用一套排版。
class LookupEmptyState extends StatelessWidget {
  const LookupEmptyState({
    required this.icon,
    required this.title,
    this.note,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note!,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
