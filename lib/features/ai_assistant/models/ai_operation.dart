import 'dart:convert';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation_type.dart';

enum AiOperationStatus { pending, approved, rejected, edited, failed }

class AiOperation {
  final String id;
  final String messageId;
  final AiOperationType type;
  final Map<String, dynamic> params;
  final String summary;
  final String? reasoning;
  final AiOperationStatus status;
  final String? errorMessage;
  final int createdAt;

  AiOperation({
    required this.id,
    required this.messageId,
    required this.type,
    required this.params,
    required this.summary,
    this.reasoning,
    this.status = AiOperationStatus.pending,
    this.errorMessage,
    required this.createdAt,
  });

  AiOperation copyWith({
    String? id,
    String? messageId,
    AiOperationType? type,
    Map<String, dynamic>? params,
    String? summary,
    String? reasoning,
    bool clearReasoning = false,
    AiOperationStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    int? createdAt,
  }) =>
      AiOperation(
        id: id ?? this.id,
        messageId: messageId ?? this.messageId,
        type: type ?? this.type,
        params: params ?? this.params,
        summary: summary ?? this.summary,
        reasoning: clearReasoning ? null : (reasoning ?? this.reasoning),
        status: status ?? this.status,
        errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'message_id': messageId,
        'type': type.name,
        'params_json': jsonEncode(params),
        'summary': summary,
        'reasoning': reasoning,
        'status': status.name,
        'error_message': errorMessage,
        'created_at': createdAt,
      };

  factory AiOperation.fromMap(Map<String, dynamic> map) {
    final paramsJson = map['params_json'] as String?;
    return AiOperation(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      type: AiOperationType.values.firstWhere((t) => t.name == map['type']),
      params: (paramsJson != null && paramsJson.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(paramsJson) as Map)
          : <String, dynamic>{},
      summary: map['summary'] as String,
      reasoning: map['reasoning'] as String?,
      status: AiOperationStatus.values.firstWhere((s) => s.name == map['status']),
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as int,
    );
  }

  String get statusLabel {
    switch (status) {
      case AiOperationStatus.pending:
        return '待审批';
      case AiOperationStatus.approved:
        return '已批准';
      case AiOperationStatus.rejected:
        return '已拒绝';
      case AiOperationStatus.edited:
        return '已编辑';
      case AiOperationStatus.failed:
        return '执行失败';
    }
  }

  String get typeLabel {
    switch (type) {
      case AiOperationType.createTask:
        return '创建任务';
      case AiOperationType.updateTask:
        return '修改任务';
      case AiOperationType.deleteTask:
        return '删除任务';
      case AiOperationType.setDueDate:
        return '设置截止日期';
      case AiOperationType.setReminder:
        return '设置提醒';
      case AiOperationType.setRecurrence:
        return '设置重复';
      case AiOperationType.addToMyDay:
        return '加入我的一天';
      case AiOperationType.toggleImportant:
        return '切换重要性';
      case AiOperationType.moveToList:
        return '移动到清单';
      case AiOperationType.reorderTasks:
        return '重新排序';
      case AiOperationType.createList:
        return '创建清单';
      case AiOperationType.updateList:
        return '重命名清单';
      case AiOperationType.deleteList:
        return '删除清单';
    }
  }
}
