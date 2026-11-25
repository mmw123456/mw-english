import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';

/// 我的：设置入口。
///
/// 阶段 2 只列条目，点击统一提示未接。等 P0 有了真实数据再逐项实现。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Text('MW', style: text.labelLarge),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('本地账号', style: text.titleSmall),
                      const SizedBox(height: 3),
                      Text('无登录 · 数据只存本机', style: text.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _GroupLabel('学习'),
          const _Tile(icon: Icons.tune, title: '学习计划', value: '每日 20 词'),
          const _Tile(icon: Icons.timeline, title: '复习节奏', value: 'Leitner 六箱'),
          const SizedBox(height: 24),
          const _GroupLabel('数据'),
          const _Tile(icon: Icons.file_download_outlined, title: '导出进度', value: '未接'),
          const _Tile(icon: Icons.file_upload_outlined, title: '导入进度', value: '未接'),
          const SizedBox(height: 24),
          const _GroupLabel('关于'),
          const _Tile(icon: Icons.article_outlined, title: '版本', value: '0.2.0 (2)'),
          const _Tile(icon: Icons.cloud_off_outlined, title: '网络', value: '完全离线'),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'MW English',
              style: text.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 2,
              ),
            ),
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
      padding: const EdgeInsets.only(left: 4, bottom: 10),
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: text.bodyMedium)),
            Text(value, style: text.labelSmall),
          ],
        ),
      ),
    );
  }
}
