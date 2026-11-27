import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../data/llm/secret_store.dart';

/// 「我的 → 设置」里的 DeepSeek Key 卡（v0.10.0）。
///
/// 规矩（决策 116）：
/// - Key 走 `flutter_secure_storage` 加密存，**不进 shared_preferences、不进日志、不进备份**；
/// - 界面只显示掩码（`sk-••••abcd`），从不回显完整 Key；
/// - 没填时「生成下一篇」直接说「先去设置填 Key」，不发请求。
class DeepSeekKeyCard extends StatefulWidget {
  const DeepSeekKeyCard({super.key, this.store});

  /// 测试注入。生产为 null，用 [SecureSecretStore]。
  final SecretStore? store;

  @override
  State<DeepSeekKeyCard> createState() => _DeepSeekKeyCardState();
}

class _DeepSeekKeyCardState extends State<DeepSeekKeyCard> {
  late final SecretStore _store = widget.store ?? SecureSecretStore();

  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _savedKey;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await _store.readKey();
    if (!mounted) return;
    setState(() {
      _savedKey = key;
      _loading = false;
      _editing = key == null;
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _snack(context, '先粘贴 Key 再保存。');
      return;
    }
    setState(() => _saving = true);
    try {
      await _store.writeKey(text);
      final saved = await _store.readKey();
      if (!mounted) return;
      setState(() {
        _savedKey = saved;
        _editing = false;
        _controller.clear();
      });
      _snack(context, 'Key 已保存（加密存在本机）。');
    } catch (_) {
      if (mounted) _snack(context, 'Key 保存失败，再试一次。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await _store.clearKey();
      if (!mounted) return;
      setState(() {
        _savedKey = null;
        _editing = true;
        _controller.clear();
      });
      _snack(context, 'Key 已清除，生成文章要重新填。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.key_outlined, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Text('DeepSeek API Key', style: text.bodyMedium),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '只用来生成阅读文章。Key 加密存在本机，不上传、不进日志、不进备份。'
          '不填也能读已生成的文章。',
          style: text.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_editing) ...[
          TextField(
            key: const ValueKey('deepseek-key-input'),
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: text.bodyMedium,
            decoration: InputDecoration(
              hintText: 'sk-…',
              hintStyle: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.divider),
              ),
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                key: const ValueKey('deepseek-key-save'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(_saving ? '保存中…' : '保存'),
              ),
              if (_savedKey != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _editing = false;
                          _controller.clear();
                        }),
                  child: const Text('取消'),
                ),
              ],
            ],
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: Text(
                  maskKey(_savedKey ?? ''),
                  key: const ValueKey('deepseek-key-mask'),
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('deepseek-key-replace'),
                onPressed: _saving ? null : () => setState(() => _editing = true),
                child: const Text('替换'),
              ),
              TextButton(
                key: const ValueKey('deepseek-key-clear'),
                onPressed: _saving ? null : _clear,
                child: const Text('清除'),
              ),
            ],
          ),
      ],
    );
  }
}

/// 只露头尾：`sk-abc123def456` → `sk-••••••f456`。
///
/// 少于 8 位的（不像真 Key）整串盖掉，别因为太短反而露出来。
String maskKey(String key) {
  final k = key.trim();
  if (k.isEmpty) return '';
  if (k.length < 8) return '••••••••';

  final head = k.startsWith('sk-') ? 'sk-' : k.substring(0, 3);
  final tail = k.substring(k.length - 4);
  return '$head••••••$tail';
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
