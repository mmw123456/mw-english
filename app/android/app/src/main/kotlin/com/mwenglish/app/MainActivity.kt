package com.mwenglish.app

import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * 发音走系统自带 TTS，不引第三方插件。
 *
 * 通道：`com.mwenglish.app/tts`
 * - `speak(text)`：单词发音，`QUEUE_FLUSH` 立即返回 Boolean，不等说完。
 * - `speakSegment(text)`：朗读用，**等到这段说完才回** true。
 *   被打断（stop 或新的一段插进来）回 false —— Dart 侧的循环看到 false 就停。
 * - `stop()`：停掉当前朗读，并给所有还在等的 result 回 false。
 *
 * 为什么 speakSegment 要「等说完」：Android 的 TTS 没有 pause，只有 stop。
 * 「暂停朗读」只能实现成「记住读到第几句 → stop」，继续时从那一句重播。
 * 所以每段都必须有一个明确的结束信号，否则界面不知道该停在哪。
 *
 * 注意：UtteranceProgressListener 的回调不在主线程，`Result.success` 必须
 * 切回主线程调（`runOnUiThread`），否则偶发 "Reply already submitted" 或崩溃。
 */
class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var seq = 0

    /** utteranceId → 还在等的 result。stop / onDone / onError 三处都会结算它。 */
    private val pending = HashMap<String, MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val r = tts?.setLanguage(Locale.US)
                ready = r != TextToSpeech.LANG_MISSING_DATA && r != TextToSpeech.LANG_NOT_SUPPORTED
            }
            if (ready) installListener()
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
                            val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), "mw-$text")
                            result.success(code == TextToSpeech.SUCCESS)
                        }
                    }

                    "speakSegment" -> {
                        val text = (call.arguments as? String)?.trim().orEmpty()
                        val engine = tts
                        if (!ready || engine == null || text.isEmpty()) {
                            result.success(false)
                        } else {
                            // 同一时刻只允许一段在等：先把上一段的 result 结算成 false，
                            // 再挂新的。Dart 侧是串行 await，正常不会撞上；这条是
                            // 「stop 之后立刻又点播放」的兜底。
                            flushPending(false)
                            val id = "mw-seg-${seq++}"
                            pending[id] = result
                            val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), id)
                            if (code != TextToSpeech.SUCCESS) {
                                pending.remove(id)
                                result.success(false)
                            }
                        }
                    }

                    "stop" -> {
                        tts?.stop()
                        flushPending(false)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun installListener() {
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = Unit

            override fun onDone(utteranceId: String?) {
                settle(utteranceId, true)
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                settle(utteranceId, false)
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                settle(utteranceId, false)
            }

            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                settle(utteranceId, false)
            }
        })
    }

    /** 结算一个 result。remove 返回 null 说明已经被别处结算过，不能回第二次。 */
    private fun settle(utteranceId: String?, value: Boolean) {
        val r = pending.remove(utteranceId) ?: return
        runOnUiThread { r.success(value) }
    }

    private fun flushPending(value: Boolean) {
        val ids = pending.keys.toList()
        for (id in ids) {
            val r = pending.remove(id) ?: continue
            runOnUiThread { r.success(value) }
        }
    }

    override fun onDestroy() {
        flushPending(false)
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
