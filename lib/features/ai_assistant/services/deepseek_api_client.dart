import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';

class ChatResponseChunk {
  final String? textDelta;
  final Map<String, dynamic>? toolCall;
  final bool isDone;
  final String? finishReason;
  final String? error;

  ChatResponseChunk.text(this.textDelta)
      : toolCall = null,
        isDone = false,
        finishReason = null,
        error = null;

  ChatResponseChunk.tool({required Map<String, dynamic> toolCall})
      : textDelta = null,
        toolCall = toolCall,
        isDone = false,
        finishReason = null,
        error = null;

  ChatResponseChunk.done({this.finishReason})
      : textDelta = null,
        toolCall = null,
        isDone = true,
        error = null;

  ChatResponseChunk.error(this.error)
      : textDelta = null,
        toolCall = null,
        isDone = true,
        finishReason = null;
}

class DeepSeekApiClient {
  static const String _baseUrl = 'https://api.deepseek.com/v1';
  static const String _model = 'deepseek-chat';
  static String? _apiKey;
  static bool _initialized = false;

  static String? get apiKey => _apiKey;
  static bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  static Future<void> init() async {
    if (_initialized) return;
    _apiKey = 'sk-5fda9d63ba3d4c25b13f6cbd96ac7e1c';
    _initialized = true;
  }

  static Future<void> setApiKey(String key) async {
    _apiKey = key;
    await AppDatabase.setSetting('deepseekApiKey', key);
    SyncService.triggerBackgroundSync();
  }

  static Future<void> loadApiKey() async {
    final saved = await AppDatabase.getSetting('deepseekApiKey');
    if (saved != null && saved.isNotEmpty) {
      _apiKey = saved;
    }
  }

  static Stream<ChatResponseChunk> chatStream({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
  }) async* {
    if (!isConfigured) {
      yield ChatResponseChunk.error('API 密钥未配置');
      return;
    }

    final body = <String, dynamic>{
      'model': model ?? _model,
      'messages': messages,
      'stream': true,
    };

    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final request = http.Request('POST', Uri.parse('$_baseUrl/chat/completions'));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode(body);

    try {
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        await streamedResponse.stream.drain();
        String errorMsg;
        if (streamedResponse.statusCode == 401) {
          errorMsg = 'API 密钥无效，请在设置中更新';
        } else if (streamedResponse.statusCode == 429) {
          errorMsg = '请求过于频繁，请稍后重试';
        } else {
          errorMsg = 'API 请求失败 (${streamedResponse.statusCode})';
        }
        yield ChatResponseChunk.error(errorMsg);
        return;
      }

      final lineStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final textBuffer = StringBuffer();
      final toolCallAccumulators = <int, _ToolCallAccumulator>{};

      await for (final line in lineStream) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          // Emit accumulated tool calls
          for (final acc in toolCallAccumulators.values) {
            final parsed = acc.tryParse();
            if (parsed != null) {
              yield ChatResponseChunk.tool(toolCall: parsed);
            }
          }
          yield ChatResponseChunk.done();
          return;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final choice = choices.first as Map<String, dynamic>;
          final finishReason = choice['finish_reason'] as String?;
          final delta = choice['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // Text content
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            textBuffer.write(content);
            yield ChatResponseChunk.text(content);
          }

          // Tool calls
          final toolCalls = delta['tool_calls'] as List?;
          if (toolCalls != null) {
            for (final tc in toolCalls) {
              final index = tc['index'] as int;
              final id = tc['id'] as String?;
              final func = tc['function'] as Map<String, dynamic>?;

              toolCallAccumulators.putIfAbsent(index, () => _ToolCallAccumulator(index));
              final acc = toolCallAccumulators[index]!;
              if (id != null) acc.id = id;
              if (func != null) {
                if (func['name'] != null) acc.name = func['name'] as String;
                if (func['arguments'] != null) {
                  acc.argumentsBuffer.write(func['arguments'] as String);
                }
              }
            }
          }

          // Finish reason
          if (finishReason != null && finishReason.isNotEmpty) {
            for (final acc in toolCallAccumulators.values) {
              final parsed = acc.tryParse();
              if (parsed != null) {
                yield ChatResponseChunk.tool(toolCall: parsed);
              }
            }
            yield ChatResponseChunk.done(finishReason: finishReason);
            return;
          }
        } catch (_) {
          // Skip malformed chunks
        }
      }

      // Stream ended without [DONE] or finish_reason
      for (final acc in toolCallAccumulators.values) {
        final parsed = acc.tryParse();
        if (parsed != null) {
          yield ChatResponseChunk.tool(toolCall: parsed);
        }
      }
      yield ChatResponseChunk.done();
    } on http.ClientException catch (e) {
      yield ChatResponseChunk.error('网络连接失败: ${e.message}');
    } catch (e) {
      yield ChatResponseChunk.error('未知错误: $e');
    }
  }

  static Future<Map<String, dynamic>?> chatSync({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
  }) async {
    if (!isConfigured) return null;

    final body = <String, dynamic>{
      'model': model ?? _model,
      'messages': messages,
      'stream': false,
    };

    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> testConnection() async {
    if (!isConfigured) return false;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
          'stream': false,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class _ToolCallAccumulator {
  final int index;
  String? id;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();

  _ToolCallAccumulator(this.index);

  Map<String, dynamic>? tryParse() {
    if (id == null || name == null) return null;
    try {
      final argsJson = argumentsBuffer.toString();
      final arguments = argsJson.isNotEmpty
          ? jsonDecode(argsJson) as Map<String, dynamic>
          : <String, dynamic>{};
      return {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': jsonEncode(arguments),
        },
        '_parsedArguments': arguments,
      };
    } catch (_) {
      return null;
    }
  }
}
