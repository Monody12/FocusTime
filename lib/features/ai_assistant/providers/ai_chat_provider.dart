import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_message.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';
import 'package:focus_my_time/features/ai_assistant/services/ai_context_builder.dart';
import 'package:focus_my_time/features/ai_assistant/services/ai_operation_engine.dart';
import 'package:focus_my_time/features/ai_assistant/services/deepseek_api_client.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';

// Tool definitions sent to DeepSeek
const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'create_task',
      'description': '创建一个新任务。dueDate/dueTime 是截止时间（结束时间），不能早于当前时间。如果用户指定了开始时间和时长，截止时间 = 开始时间 + 时长。',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '任务标题'},
          'notes': {'type': 'string', 'description': '备注（可选）'},
          'listId': {'type': 'string', 'description': '清单 ID，默认 system-all-tasks'},
          'dueDate': {
            'type': 'string',
            'description': '截止日期（任务结束日期），格式 YYYY-MM-DD。不是开始日期。',
          },
          'dueTime': {
            'type': 'string',
            'description': '截止时间（任务结束时间），格式 HH:mm（24小时制）。不是开始时间。',
          },
          'expectedMinutes': {'type': 'integer', 'description': '任务持续时长（分钟）。截止时间 = 开始时间 + 持续时长'},
          'isMyDay': {'type': 'boolean', 'description': '是否添加到"我的一天"'},
          'isImportant': {'type': 'boolean', 'description': '是否标记为重要'},
          'reminderAt': {
            'type': 'string',
            'description': '任务开始时间/提醒时间，ISO 8601 格式（如 "2026-05-07T14:00:00"）。注意：这是开始时间，不是截止时间。',
          },
        },
        'required': ['title'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'update_task',
      'description': '修改已有任务的字段。只传需要修改的字段。',
      'parameters': {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'string', 'description': '要修改的任务 ID'},
          'title': {'type': 'string', 'description': '新标题'},
          'notes': {'type': 'string', 'description': '新备注'},
          'dueDate': {'type': 'string', 'description': '新截止日期 YYYY-MM-DD'},
          'dueTime': {'type': 'string', 'description': '新截止时间 HH:mm'},
          'expectedMinutes': {'type': 'integer', 'description': '新预计分钟数'},
          'isImportant': {'type': 'boolean', 'description': '是否重要'},
          'reminderAt': {'type': 'string', 'description': '新提醒时间 ISO 8601'},
        },
        'required': ['taskId'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'delete_task',
      'description': '删除一个任务。请谨慎使用，需确认任务确实不需要了。',
      'parameters': {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'string', 'description': '要删除的任务 ID'},
          'title': {'type': 'string', 'description': '任务标题（用于显示确认信息）'},
        },
        'required': ['taskId'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'set_recurrence',
      'description': '为任务设置重复规则，使其定期重复。',
      'parameters': {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'string', 'description': '任务 ID'},
          'title': {'type': 'string', 'description': '任务标题（用于显示）'},
          'frequency': {
            'type': 'string',
            'enum': ['daily', 'weekly', 'monthly', 'yearly'],
            'description': '重复频率',
          },
          'interval': {
            'type': 'integer',
            'description': '间隔，如每2天/每2周',
          },
        },
        'required': ['taskId', 'frequency'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'add_to_my_day',
      'description': '将任务添加到"我的一天"列表。',
      'parameters': {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'string', 'description': '任务 ID'},
          'title': {'type': 'string', 'description': '任务标题（用于显示）'},
        },
        'required': ['taskId'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'create_list',
      'description': '创建一个新的任务清单。如果用户要求按日期创建清单，使用指定的日期格式。',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '清单名称'},
        },
        'required': ['name'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'update_list',
      'description': '重命名一个已有的任务清单。不能修改系统清单。',
      'parameters': {
        'type': 'object',
        'properties': {
          'listId': {'type': 'string', 'description': '要修改的清单 ID'},
          'name': {'type': 'string', 'description': '新名称'},
        },
        'required': ['listId', 'name'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'delete_list',
      'description': '删除一个自定义任务清单及其下所有任务。不能删除系统清单。请谨慎使用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'listId': {'type': 'string', 'description': '要删除的清单 ID'},
          'name': {'type': 'string', 'description': '清单名称（用于确认显示）'},
        },
        'required': ['listId'],
      },
    },
  },
];

class AiChatState {
  final List<AiMessage> messages;
  final List<AiOperation> pendingOperations;
  final String? currentConversationId;
  final bool isStreaming;
  final String streamingText;
  final String? errorMessage;
  final bool isApiKeyConfigured;
  final String customPrompt;
  final bool datedListEnabled;
  final String datedListFormat;
  final bool reminderOnCreate;

  AiChatState({
    this.messages = const [],
    this.pendingOperations = const [],
    this.currentConversationId,
    this.isStreaming = false,
    this.streamingText = '',
    this.errorMessage,
    this.isApiKeyConfigured = false,
    this.customPrompt = '',
    this.datedListEnabled = false,
    this.datedListFormat = 'yyyyMMdd',
    this.reminderOnCreate = false,
  });

  AiChatState copyWith({
    List<AiMessage>? messages,
    List<AiOperation>? pendingOperations,
    String? currentConversationId,
    bool? isStreaming,
    String? streamingText,
    String? errorMessage,
    bool clearError = false,
    bool? isApiKeyConfigured,
    String? customPrompt,
    bool? datedListEnabled,
    String? datedListFormat,
    bool? reminderOnCreate,
  }) =>
      AiChatState(
        messages: messages ?? this.messages,
        pendingOperations: pendingOperations ?? this.pendingOperations,
        currentConversationId: currentConversationId ?? this.currentConversationId,
        isStreaming: isStreaming ?? this.isStreaming,
        streamingText: streamingText ?? this.streamingText,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        isApiKeyConfigured: isApiKeyConfigured ?? this.isApiKeyConfigured,
        customPrompt: customPrompt ?? this.customPrompt,
        datedListEnabled: datedListEnabled ?? this.datedListEnabled,
        datedListFormat: datedListFormat ?? this.datedListFormat,
        reminderOnCreate: reminderOnCreate ?? this.reminderOnCreate,
      );
}

class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;
  StreamSubscription<ChatResponseChunk>? _streamSubscription;
  bool _disposed = false;

  AiChatNotifier(this._ref) : super(AiChatState()) {
    _init();
  }

  Future<void> _init() async {
    await DeepSeekApiClient.loadApiKey();
    await _loadSettings();
    if (!_disposed) {
      state = state.copyWith(
        isApiKeyConfigured: DeepSeekApiClient.isConfigured,
      );
    }
  }

  Future<void> _loadSettings() async {
    final prompt = await AppDatabase.getSetting('aiCustomPrompt');
    final datedEnabled = await AppDatabase.getSetting('aiDatedListEnabled');
    final datedFormat = await AppDatabase.getSetting('aiDatedListFormat');
    final reminderOnCreate = await AppDatabase.getSetting('aiReminderOnCreate');
    if (!_disposed) {
      state = state.copyWith(
        customPrompt: prompt ?? '',
        datedListEnabled: datedEnabled == 'true',
        datedListFormat: datedFormat?.isNotEmpty == true ? datedFormat! : 'yyyyMMdd',
        reminderOnCreate: reminderOnCreate == 'true',
      );
    }
  }

  Future<void> saveCustomPrompt(String text) async {
    await AppDatabase.setSetting('aiCustomPrompt', text);
    state = state.copyWith(customPrompt: text);
    SyncService.triggerBackgroundSync();
  }

  Future<void> setDatedListEnabled(bool enabled) async {
    await AppDatabase.setSetting('aiDatedListEnabled', enabled.toString());
    state = state.copyWith(datedListEnabled: enabled);
    SyncService.triggerBackgroundSync();
  }

  Future<void> setDatedListFormat(String format) async {
    await AppDatabase.setSetting('aiDatedListFormat', format);
    state = state.copyWith(datedListFormat: format);
    SyncService.triggerBackgroundSync();
  }

  Future<void> setReminderOnCreate(bool enabled) async {
    await AppDatabase.setSetting('aiReminderOnCreate', enabled.toString());
    state = state.copyWith(reminderOnCreate: enabled);
    SyncService.triggerBackgroundSync();
  }

  @override
  void dispose() {
    _disposed = true;
    _streamSubscription?.cancel();
    super.dispose();
  }

  Future<void> checkApiKey() async {
    await DeepSeekApiClient.loadApiKey();
    if (!_disposed) {
      state = state.copyWith(
        isApiKeyConfigured: DeepSeekApiClient.isConfigured,
      );
    }
  }

  Future<void> newConversation() async {
    _streamSubscription?.cancel();
    final result = await AppDatabase.createAiConversation();
    if (!_disposed) {
      state = AiChatState(
        currentConversationId: result['id'] as String,
        isApiKeyConfigured: DeepSeekApiClient.isConfigured,
      );
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (!DeepSeekApiClient.isConfigured) {
      state = state.copyWith(errorMessage: '请先在设置中配置 API 密钥');
      return;
    }

    // Ensure we have a conversation
    String convId = state.currentConversationId ?? '';
    if (convId.isEmpty) {
      final result = await AppDatabase.createAiConversation();
      convId = result['id'] as String;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Create user message
    final userMessage = AiMessage(
      id: 'msg-$now',
      conversationId: convId,
      role: AiMessageRole.user,
      content: text,
      createdAt: now,
    );

    // Save to DB
    await AppDatabase.insertAiMessage(
      conversationId: convId,
      role: 'user',
      content: text,
    );

    // Auto-title conversation from first message
    if (state.messages.isEmpty) {
      final title = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      await AppDatabase.updateAiConversationTitle(convId, title);
    }

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      currentConversationId: convId,
      isStreaming: true,
      streamingText: '',
      pendingOperations: [],
      clearError: true,
    );

    // Build context
    final taskState = _ref.read(taskProvider);
    final systemPrompt = AiContextBuilder.buildSystemPrompt(
      allTasks: taskState.tasks,
      lists: taskState.lists,
      now: DateTime.now(),
      customPrompt: state.customPrompt,
      datedListEnabled: state.datedListEnabled,
      datedListFormat: state.datedListFormat,
      reminderOnCreate: state.reminderOnCreate,
    );

    // Build messages array
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      for (final msg in state.messages) // exclude latest user message
        if (msg.id != userMessage.id)
          {'role': msg.role.name, 'content': msg.content},
      {'role': 'user', 'content': text},
    ];

    final textBuffer = StringBuffer();
    final toolCallsReceived = <Map<String, dynamic>>[];

    try {
      final stream = DeepSeekApiClient.chatStream(
        messages: apiMessages,
        tools: _tools,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          if (_disposed) return;

          if (chunk.textDelta != null) {
            textBuffer.write(chunk.textDelta);
            state = state.copyWith(streamingText: textBuffer.toString());
          }

          if (chunk.toolCall != null) {
            toolCallsReceived.add(chunk.toolCall!);
          }

          if (chunk.error != null) {
            state = state.copyWith(
              isStreaming: false,
              errorMessage: chunk.error,
            );
          }

          if (chunk.isDone) {
            _finalizeMessage(
              convId,
              textBuffer.toString(),
              toolCallsReceived,
            );
          }
        },
        onError: (e) {
          if (!_disposed) {
            state = state.copyWith(
              isStreaming: false,
              errorMessage: '连接中断: $e',
            );
          }
        },
      );
    } catch (e) {
      if (!_disposed) {
        state = state.copyWith(
          isStreaming: false,
          errorMessage: '发送失败: $e',
        );
      }
    }
  }

  Future<void> _finalizeMessage(
    String convId,
    String content,
    List<Map<String, dynamic>> toolCalls,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final msgId = 'msg-$now';

    final toolCallsJson = toolCalls.isNotEmpty ? jsonEncode(toolCalls) : null;

    // Save assistant message
    await AppDatabase.insertAiMessage(
      conversationId: convId,
      role: 'assistant',
      content: content,
      toolCallsJson: toolCallsJson,
    );

    // Create operations from tool calls
    final operations = AiOperationEngine.fromToolCalls(toolCalls, msgId);

    // Save operations to DB
    for (final op in operations) {
      await AppDatabase.insertAiOperation(
        messageId: msgId,
        type: op.type.name,
        paramsJson: jsonEncode(op.params),
        summary: op.summary,
        reasoning: op.reasoning,
      );
    }

    final assistantMessage = AiMessage(
      id: msgId,
      conversationId: convId,
      role: AiMessageRole.assistant,
      content: content,
      toolCallsJson: toolCallsJson,
      operations: operations,
      createdAt: now,
    );

    if (!_disposed) {
      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        pendingOperations: operations,
        isStreaming: false,
        streamingText: '',
      );
    }
  }

  void rejectOperation(String operationId) {
    final ops = state.pendingOperations.map((op) {
      if (op.id == operationId) {
        AppDatabase.updateAiOperationStatus(operationId, 'rejected');
        return op.copyWith(status: AiOperationStatus.rejected);
      }
      return op;
    }).toList();
    state = state.copyWith(pendingOperations: ops);
  }

  void rejectAllOperations() {
    for (final op in state.pendingOperations) {
      AppDatabase.updateAiOperationStatus(op.id, 'rejected');
    }
    final ops = state.pendingOperations
        .map((op) => op.copyWith(status: AiOperationStatus.rejected))
        .toList();
    state = state.copyWith(pendingOperations: ops);
  }

  void editOperation(String operationId, Map<String, dynamic> newParams) {
    final ops = state.pendingOperations.map((op) {
      if (op.id == operationId) {
        final updated = op.copyWith(
          params: newParams,
          status: AiOperationStatus.edited,
        );
        return updated;
      }
      return op;
    }).toList();
    state = state.copyWith(pendingOperations: ops);
  }

  Future<void> approveOperation(String operationId) async {
    final taskNotifier = _ref.read(taskProvider.notifier);
    final taskState = _ref.read(taskProvider);
    final op = state.pendingOperations.firstWhere((o) => o.id == operationId);

    // Validate
    final error = AiOperationEngine.validate(op, currentTasks: taskState.tasks, currentLists: taskState.lists);
    if (error != null) {
      final failedOp = op.copyWith(
        status: AiOperationStatus.failed,
        errorMessage: error,
      );
      final ops = state.pendingOperations.map((o) => o.id == operationId ? failedOp : o).toList();
      state = state.copyWith(pendingOperations: ops, errorMessage: error);
      return;
    }

    // Mark as approved first (optimistic)
    var ops = state.pendingOperations.map((o) {
      if (o.id == operationId) return o.copyWith(status: AiOperationStatus.approved);
      return o;
    }).toList();
    state = state.copyWith(pendingOperations: ops);

    // Execute
    final result = await AiOperationEngine.execute(
      operation: op,
      taskNotifier: taskNotifier,
      currentLists: taskState.lists,
    );

    ops = state.pendingOperations.map((o) {
      if (o.id == operationId) return result;
      return o;
    }).toList();
    state = state.copyWith(pendingOperations: ops);

    await AppDatabase.updateAiOperationStatus(
      operationId,
      result.status.name,
      errorMessage: result.errorMessage,
    );
  }

  Future<void> approveAllOperations() async {
    final taskNotifier = _ref.read(taskProvider.notifier);
    final taskState = _ref.read(taskProvider);

    // Validate all first
    for (final op in state.pendingOperations) {
      if (op.status == AiOperationStatus.rejected) continue;
      final error = AiOperationEngine.validate(op, currentTasks: taskState.tasks, currentLists: taskState.lists);
      if (error != null) {
        var ops = state.pendingOperations.map((o) {
          if (o.id == op.id) return o.copyWith(status: AiOperationStatus.failed, errorMessage: error);
          return o;
        }).toList();
        state = state.copyWith(pendingOperations: ops, errorMessage: error);
        return;
      }
    }

    final results = await AiOperationEngine.executeAll(
      operations: state.pendingOperations,
      taskNotifier: taskNotifier,
      currentLists: taskState.lists,
    );

    for (final r in results) {
      await AppDatabase.updateAiOperationStatus(
        r.id,
        r.status.name,
        errorMessage: r.errorMessage,
      );
    }

    state = state.copyWith(pendingOperations: results);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  List<AiOperation> get activePendingOps =>
      state.pendingOperations
          .where((op) => op.status == AiOperationStatus.pending || op.status == AiOperationStatus.edited)
          .toList();
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});
