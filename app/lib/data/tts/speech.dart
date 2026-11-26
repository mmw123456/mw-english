import 'package:flutter/services.dart';

/// 系统离线发音（Android 自带 TTS 引擎）。
///
/// 不引第三方插件：走一个 MethodChannel 到 `MainActivity`，
/// 由它调 `android.speech.tts.TextToSpeech`。断网也能读，
/// 手机没装英文语音引擎时返回 false，界面提示一句，不报错。
class Speech {
  const Speech._();

  static const MethodChannel _channel = MethodChannel('com.mwenglish.app/tts');

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
}
