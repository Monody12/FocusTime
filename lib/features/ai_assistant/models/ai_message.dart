import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';

enum AiMessageRole { user, assistant, system }

class AiMessage {
  final String id;
  final String conversationId;
  final AiMessageRole role;
  final String content;
  final String? toolCallsJson;
  final List<AiOperation>? operations;
  final int createdAt;

  AiMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.toolCallsJson,
    this.operations,
    required this.createdAt,
  });

  AiMessage copyWith({
    String? id,
    String? conversationId,
    AiMessageRole? role,
    String? content,
    String? toolCallsJson,
    List<AiOperation>? operations,
    bool clearToolCallsJson = false,
    bool clearOperations = false,
    int? createdAt,
  }) =>
      AiMessage(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        role: role ?? this.role,
        content: content ?? this.content,
        toolCallsJson: clearToolCallsJson ? null : (toolCallsJson ?? this.toolCallsJson),
        operations: clearOperations ? null : (operations ?? this.operations),
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'role': role.name,
        'content': content,
        'tool_calls_json': toolCallsJson,
        'created_at': createdAt,
      };

  factory AiMessage.fromMap(Map<String, dynamic> map) => AiMessage(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String,
        role: AiMessageRole.values.firstWhere((r) => r.name == map['role']),
        content: map['content'] as String,
        toolCallsJson: map['tool_calls_json'] as String?,
        createdAt: map['created_at'] as int,
      );
}
