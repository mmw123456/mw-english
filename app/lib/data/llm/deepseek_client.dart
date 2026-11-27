import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 调模型失败。
///
/// [message] 是给人看的一句话，直接显示在阅读页的错误条上。
/// **绝不带 Key**：这里只拼状态码与接口返回的 error.message（截断 120 字）。
class LlmException implements Exception {
  const LlmException(this.message, {this.retryable = false});

  final String message;

  /// true = 换个时间再点一次可能就好（超时、限流、5xx）。
  /// false = 现在重试也没用（Key 错、余额不足）。
  final bool retryable;

  @override
  String toString() => message;
}

/// 「生成一篇英文短文」这个能力。
///
/// 抽成接口是为了测试：`flutter test` 里不许真的打 DeepSeek 接口
/// （按量付费，且不稳定）。测试塞 [FakeArticleLlm]，走完整条生成链。
abstract class ArticleLlm {
  /// 返回模型原文（由 article_parser 去解析格式）。
  Future<String> complete({required String system, required String user});
}

/// DeepSeek 的实现（OpenAI 兼容的 `/chat/completions`）。
class DeepSeekClient implements ArticleLlm {
  DeepSeekClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? endpoint,
    this.model = defaultModel,
    this.timeout = const Duration(seconds: 90),
  }) : _http = httpClient ?? http.Client(),
       _endpoint = endpoint ?? Uri.parse(defaultEndpoint);

  static const String defaultEndpoint =
      'https://api.deepseek.com/chat/completions';

  /// 只有这一个模型。`deepseek-reasoner` 会把 token 花在思考上，
  /// 生成 500 词短文用不上，也更容易超时。
  static const String defaultModel = 'deepseek-chat';

  final String apiKey;
  final String model;
  final Duration timeout;
  final http.Client _http;
  final Uri _endpoint;

  @override
  Future<String> complete({
    required String system,
    required String user,
  }) async {
    final payload = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      // 1.0：再高格式开始飘（加粗标记会漏），再低文字发干。
      'temperature': 1.0,
      'max_tokens': 2048,
      'stream': false,
    });

    http.Response resp;
    try {
      resp = await _http
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: payload,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw LlmException(
        '生成超时（${timeout.inSeconds} 秒没返回）。再点一次试试。',
        retryable: true,
      );
    } on SocketException {
      throw const LlmException('连不上网。检查网络后再点生成。', retryable: true);
    } on http.ClientException {
      throw const LlmException('网络请求失败。检查网络后再点生成。', retryable: true);
    } catch (_) {
      throw const LlmException('网络出问题了。检查网络后再点生成。', retryable: true);
    }

    if (resp.statusCode != 200) {
      throw LlmException(_statusMessage(resp), retryable: _retryable(resp.statusCode));
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw const LlmException('接口返回的不是正常 JSON，再点一次试试。', retryable: true);
    }

    final content = _extractContent(decoded);
    if (content == null || content.trim().isEmpty) {
      throw const LlmException('接口返回了空内容，再点一次试试。', retryable: true);
    }
    return content;
  }

  /// 状态码 → 人话。**不带 Key、不带请求头。**
  String _statusMessage(http.Response resp) {
    final detail = _errorMessage(resp);
    switch (resp.statusCode) {
      case 400:
        return '请求被拒（400）${detail.isEmpty ? '' : '：$detail'}';
      case 401:
        return 'DeepSeek Key 不对或已失效。去「我的 → 设置」换一个。';
      case 402:
        return 'DeepSeek 账户余额不足，充值后再生成。';
      case 403:
        return '这个 Key 没有调用权限（403）。';
      case 429:
        return '请求太频繁，等一会儿再点。';
      default:
        if (resp.statusCode >= 500) {
          return 'DeepSeek 服务暂时不可用（${resp.statusCode}），过一会儿再试。';
        }
        return '生成失败（HTTP ${resp.statusCode}）'
            '${detail.isEmpty ? '' : '：$detail'}';
    }
  }

  bool _retryable(int status) => status == 429 || status >= 500;

  /// 从接口的错误体里挖 `error.message`，截到 120 字。
  String _errorMessage(http.Response resp) {
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] != null) {
          var msg = err['message'].toString().replaceAll(RegExp(r'\s+'), ' ').trim();
          // 接口有时会把请求头原样回显。**Key 绝不许出现在任何给人看的字符串里**，
          // 所以先按已知 Key 整串抹掉，再把 `sk-…` 形状的串统一打成星号。
          if (apiKey.isNotEmpty) msg = msg.replaceAll(apiKey, '***');
          msg = msg.replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]{6,}'), 'sk-***');
          return msg.length > 120 ? '${msg.substring(0, 120)}…' : msg;
        }
      }
    } catch (_) {
      // 不是 JSON 就算了，状态码本身够用。
    }
    return '';
  }

  /// `choices[0].message.content`。
  String? _extractContent(Object? decoded) {
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final msg = first['message'];
    if (msg is! Map) return null;
    final content = msg['content'];
    return content is String ? content : null;
  }
}
