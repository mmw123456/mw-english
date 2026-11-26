import 'package:material_ui/material_ui.dart';

import '../../app/app_defaults.dart';
import '../../app/shell/shell_padding.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/liquid_glass.dart';

/// 版本行文案（版本号跟 pubspec 走）。
///
/// [shaderOn] 为 null 表示还在探测 —— 这时只显示版本号，不猜一个状态
/// 出来（猜错比慢一帧更糟）。探测完才补 `· 真折射开` / `· 玻璃回落`。
@visibleForTesting
String versionLabel(bool? shaderOn) {
  const base = '0.7.6 (2021)';
  if (shaderOn == null) return base;
  return '$base · ${shaderOn ? '真折射开' : '玻璃回落'}';
}

/// 我的：设置入口。
///
/// 阶段 2 只列条目，点击统一提示未接。等 P0 有了真实数据再逐项实现。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  /// null = 探测中；true = 真折射开；false = 回落近似玻璃。
  bool? _shaderOn;

  /// 划走再划回来不重建（v0.7.3）：shader 探测结果不用重跑，滚动位置也在。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _probeShader();
  }

  /// 和 [GlassSurface] 读同一份状态：后端支不支持 `ImageFilter.shader`
  /// （Impeller）+ shader program 有没有加载成功。`ensureLoaded` 带缓存，
  /// 不会重复加载；这里只是把结果显示出来，不改任何玻璃行为。
  Future<void> _probeShader() async {
    var on = false;
    if (GlassRefraction.supported) {
      on = await GlassRefraction.ensureLoaded() != null;
    }
    if (!mounted) return;
    setState(() => _shaderOn = on);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求先调 super.build
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        // 底部 96 + 安全区：Tab 栏浮在内容上，最后一行别被挡住。
        padding: ShellPadding.scroll(context),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppColors.divider, width: 0.5),
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
          const SizedBox(height: 20),
          const _GroupLabel('学习'),
          const _Tile(
            icon: Icons.tune,
            title: '学习计划',
            value: '每日 ${AppDefaults.dailyNewWordTarget} 词',
          ),
          const _Tile(icon: Icons.timeline, title: '复习节奏', value: 'Leitner 六箱'),
          const SizedBox(height: 20),
          const _GroupLabel('数据'),
          const _Tile(icon: Icons.file_download_outlined, title: '导出进度', value: '未接'),
          const _Tile(icon: Icons.file_upload_outlined, title: '导入进度', value: '未接'),
          const SizedBox(height: 20),
          const _GroupLabel('关于'),
          _Tile(
            icon: Icons.article_outlined,
            title: '版本',
            value: versionLabel(_shaderOn),
          ),
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
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppColors.divider, width: 0.5),
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
