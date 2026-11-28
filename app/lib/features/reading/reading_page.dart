import 'package:material_ui/material_ui.dart';

import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../data/article/article_service.dart';
import '../../data/llm/deepseek_client.dart';
import '../../data/models/article.dart';
import 'article_page.dart';

/// 阅读 Tab（v0.10.0）。
///
/// 从占位改成真功能：文章列表 + 今日推荐 + 「生成下一篇」。
///
/// 三条不能破的规矩：
/// - **只有用户点「生成下一篇」才请求接口**，不自动生成、不进页面就生成
///   （DeepSeek 按量付费，自动跑 33 篇就是烧钱）；
/// - 没网 / 没 Key / 接口失败：已生成的文章照常读，只在生成那一步报原因；
/// - 文章全存本地 SQLite，断网也能打开。
class ReadingPage extends StatefulWidget {
  const ReadingPage({super.key, this.service});

  /// 测试注入。生产为 null，用默认依赖（真 DeepSeek + 真 SQLite）。
  final ArticleService? service;

  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage>
    with AutomaticKeepAliveClientMixin {
  late final ArticleService _service = widget.service ?? ArticleService();

  bool _loading = true;
  String? _loadError;
  List<Article> _articles = const [];

  bool _generating = false;
  String _stageText = '';
  String? _genError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.list();
      if (!mounted) return;
      setState(() {
        _articles = list;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '读不出本地的文章列表：$e';
      });
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _genError = null;
      _stageText = '正在挑词…';
    });

    try {
      final article = await _service.generateNext(
        onProgress: (stage, message) {
          if (mounted) setState(() => _stageText = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _generating = false;
        _stageText = '';
      });
      await _load();
      if (!mounted) return;
      await _open(article);
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _stageText = '';
        _genError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _stageText = '';
        _genError = '生成失败：$e';
      });
    }
  }

  Future<void> _open(Article article) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ArticlePage(article: article)),
    );
    if (!mounted) return;
    // 详情页里可能标了已读，回来刷一下「未读」点。
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(title: const Text('阅读')),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Center(
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.7),
          ),
        ),
      );
    }

    if (_articles.isEmpty) {
      return ListView(
        padding: ShellPadding.scroll(context),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.auto_stories_outlined, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 18),
          Text(
            '还没有文章',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Text(
            '按你的词库生成短文：每篇 25 个词、350–500 词，\n'
            '目标词在正文里加粗，双击能查意思。\n'
            '只有你点「生成下一篇」时才联网，一次一篇。',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.8),
          ),
          const SizedBox(height: 28),
          _GenerateButton(
            generating: _generating,
            stageText: _stageText,
            onTap: _generate,
          ),
          if (_genError != null) ...[
            const SizedBox(height: 12),
            _ErrorNote(message: _genError!, onClose: () => setState(() => _genError = null)),
          ],
        ],
      );
    }

    final latest = _articles.first;
    final rest = _articles.skip(1).toList();

    return RefreshIndicator(
      color: AppColors.textSecondary,
      onRefresh: _load,
      child: ListView(
        padding: ShellPadding.scroll(context),
        children: [
          const _SectionLabel('今日推荐'),
          _ArticleCard(
            key: ValueKey('article-latest-${latest.id}'),
            article: latest,
            featured: true,
            onTap: () => _open(latest),
          ),
          const SizedBox(height: 16),
          _GenerateButton(
            generating: _generating,
            stageText: _stageText,
            onTap: _generate,
          ),
          if (_genError != null) ...[
            const SizedBox(height: 12),
            _ErrorNote(message: _genError!, onClose: () => setState(() => _genError = null)),
          ],
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionLabel('全部文章'),
            for (final a in rest)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ArticleCard(
                  key: ValueKey('article-${a.id}'),
                  article: a,
                  onTap: () => _open(a),
                ),
              ),
          ] else ...[
            const SizedBox(height: 24),
            Text(
              '再生成几篇，往期文章会列在这里。',
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '文章由 DeepSeek 生成，只存在本机。断网也能读。',
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 段落小标题：与设置页的 `_GroupLabel` 同一套观感（12px、次要墨、字距略开）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 一张文章卡。
class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    super.key,
    required this.article,
    this.featured = false,
    required this.onTap,
  });

  final Article article;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Container(
          padding: EdgeInsets.all(featured ? 18 : 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (article.unread) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.ringOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (featured ? text.titleMedium : text.bodyLarge)?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${article.targetWords.length} 个目标词 · ${article.wordCount} 词 · '
                '生词率 ${article.rarePercent}% · ${formatDate(article.createdAt)}',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              if (featured) ...[
                const SizedBox(height: 12),
                Text(
                  previewText(article.body),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.75,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「生成下一篇」——列表里那颗按钮。
///
/// 生成中禁用并显示阶段文案（挑词 / 生成 / 重写 / 保存），
/// 不让用户连点两次把两份钱都花了。
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.generating,
    required this.stageText,
    required this.onTap,
  });

  final bool generating;
  final String stageText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('generate-next'),
        onTap: generating ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: generating ? AppColors.surfaceMuted : AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (generating)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else
                Icon(Icons.auto_awesome_outlined, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  generating ? (stageText.isEmpty ? '正在生成…' : stageText) : '生成下一篇',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页内错误条：一句人话 + 关闭。
///
/// 不用 SnackBar —— 底部 Tab 栏浮在内容上，SnackBar 容易被压住看不到。
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: text.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('generate-error-close'),
            onPressed: onClose,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: '知道了',
            icon: const Icon(Icons.close, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// `11月27日`。文章都是本机生成的，不需要年份。
String formatDate(DateTime t) => '${t.month}月${t.day}日';

/// 卡片上的预览：去掉 `**`，压成一行，截到 [maxChars]。
String previewText(String body, {int maxChars = 120}) {
  final plain = body.replaceAll('**', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (plain.length <= maxChars) return plain;
  return '${plain.substring(0, maxChars)}…';
}
