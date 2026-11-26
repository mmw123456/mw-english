import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';

/// 阅读页。
///
/// P2 才做：用 DeepSeek 把当天学过的词编成短文，断网时降级为只显示本地缓存。
/// 阶段 2 只保留入口与说明，不埋假 UI。
class ReadingPage extends StatelessWidget {
  const ReadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('阅读')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 72),
            Icon(
              Icons.auto_stories_outlined,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 20),
            Text(
              'P2 才做',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Text(
              '把当天学过的词编成一段短文，在语境里再过一遍。\n'
              '需要联网调用模型；断网时只显示已缓存的旧文章，不白屏。',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(height: 1.7),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'P0 只做学习闭环：能背单词。这一页在闭环验证通过后才开始。',
                      style: text.labelSmall?.copyWith(height: 1.6),
                    ),
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
