package com.mwenglish.app

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * 词条发音走系统自带 TTS，不引第三方插件。
 *
 * 通道：`com.mwenglish.app/tts`，方法 `speak(text)`，返回 Boolean。
 * 引擎没装好或手机缺英文语音包时返回 false，Dart 侧提示一句，不崩。
 */
class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var ready = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val r = tts?.setLanguage(Locale.US)
                ready = r != TextToSpeech.LANG_MISSING_DATA && r != TextToSpeech.LANG_NOT_SUPPORTED
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mwenglish.app/tts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = (call.arguments as? String)?.trim().orEmpty()
                        val engine = tts
                        if (!ready || engine == null || text.isEmpty()) {
                            result.success(false)
                        } else {
                            val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "mw-$text")
                            result.success(code == TextToSpeech.SUCCESS)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
