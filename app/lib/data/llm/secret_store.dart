import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// DeepSeek Key 的读写口。
///
/// 抽成接口是因为 `flutter test` 里没有 Android Keystore：
/// 生产用 [SecureSecretStore]，测试塞 [MemorySecretStore]。
abstract class SecretStore {
  /// 没填 / 读不出来都返回 null —— 调用方只关心「能不能用」。
  Future<String?> readKey();

  Future<void> writeKey(String key);

  Future<void> clearKey();
}

/// 加密存 Key。
///
/// Android 走 `EncryptedSharedPreferences`（AndroidX Security，密钥在 Keystore 里，
/// minSdk 23 起可用；本项目 minSdk 24）。**不落 `shared_preferences` 明文**，
/// 不进日志、不进备份 —— 决策 116。
class SecureSecretStore implements SecretStore {
  SecureSecretStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  /// 存储键。改名等于让所有人的 Key 失效，不要动。
  static const String storageKey = 'deepseek_api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readKey() async {
    try {
      final value = await _storage.read(key: storageKey);
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } catch (_) {
      // 换机 / 恢复备份 / Keystore 被清之后读不出来会抛。
      // 当「没填」处理，让用户重填一次，不要把设置页整页打挂。
      return null;
    }
  }

  @override
  Future<void> writeKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return clearKey();
    await _storage.write(key: storageKey, value: trimmed);
  }

  @override
  Future<void> clearKey() async {
    try {
      await _storage.delete(key: storageKey);
    } catch (_) {
      // 删不掉也不算错：下次 write 会覆盖。
    }
  }
}

/// 内存实现，只给测试用。进程退出就没了，这正是测试想要的行为。
class MemorySecretStore implements SecretStore {
  MemorySecretStore([this._key]);

  String? _key;

  @override
  Future<String?> readKey() async => _key;

  @override
  Future<void> writeKey(String key) async {
    final t = key.trim();
    _key = t.isEmpty ? null : t;
  }

  @override
  Future<void> clearKey() async => _key = null;
}
