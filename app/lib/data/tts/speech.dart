import 'package:flutter/services.dart';

/// 系统离线发音（Android 自带 TTS 引擎）。
///
/// 不引第三方插件：走一个 MethodChannel 到 `MainActivity`，
/// 由它调 `android.speech.tts.TextToSpeech`。断网也能读，
/// 手机没装英文语音引擎时返回 false，界面提示一句，不报错。
class Speech {
  const Speech._();

  static const MethodChannel _channel = MethodChannel('com.mwenglish.app/tts');

  /// 单词发音。立即返回，不等说完。
  static Future<bool> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('speak', t);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 朗读用：等到这一段说完才返回 true。
  ///
  /// 被打断（stop / 下一段插进来）返回 false —— 调用方的循环据此停下。
  /// 这是「暂停」能实现的前提：Android TTS 没有 pause，只能 stop + 记住位置。
  static Future<bool> speakSegment(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('speakSegment', t);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 停掉当前朗读。所有还在等的 [speakSegment] 会拿到 false。
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {
      // 停不掉不算错：下一次 speak 会 FLUSH 掉旧的。
    }
  }
}
