import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';
import 'package:focus_my_time/features/ai_assistant/presentation/widgets/chat_bubble.dart';
import 'package:focus_my_time/features/ai_assistant/presentation/widgets/operation_detail_sheet.dart';
import 'package:focus_my_time/features/ai_assistant/presentation/widgets/operation_preview_card.dart';
import 'package:focus_my_time/features/ai_assistant/providers/ai_chat_provider.dart';

class AiChatPage extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const AiChatPage({super.key, required this.onClose});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _focusNode.requestFocus();
    ref.read(aiChatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiChatProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(aiChatProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.streamingText != next.streamingText) {
        _scrollToBottom();
      }
      if (next.errorMessage != null &&
          prev?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(aiChatProvider.notifier).clearError();
      }
    });

    final activeOps = ref.read(aiChatProvider.notifier).activePendingOps;

    return Container(
      decoration: BoxDecoration(
        color: context.appColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(isDark),
          const Divider(height: 1),
          // Pending operations preview
          if (activeOps.isNotEmpty) _buildOperationsPreview(isDark, activeOps),
          // Messages
          Expanded(child: _buildMessageList(isDark, state)),
          const Divider(height: 1),
          // Input bar
          _buildInputBar(isDark, state),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 20),
            color: context.appColors.text,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Text(
            'AI 任务助手',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.appColors.text,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _showSettingsSheet(context, isDark),
            icon: const Icon(Icons.tune, size: 20),
            color: context.appColors.textSecondary,
            tooltip: '偏好设置',
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () =>
                ref.read(aiChatProvider.notifier).newConversation(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新对话'),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsPreview(bool isDark, List<AiOperation> ops) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: (context.appColors.accent).withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: context.appColors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.preview, size: 16, color: context.appColors.accent),
                const SizedBox(width: 6),
                Text(
                  '操作预览 (${ops.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.accent,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      ref.read(aiChatProvider.notifier).rejectAllOperations(),
                  child: const Text('全部拒绝', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(aiChatProvider.notifier).approveAllOperations(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.appColors.success,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('全部批准', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: ops.length,
              itemBuilder: (context, index) {
                final op = ops[index];
                return OperationPreviewCard(
                  operation: op,
                  onApprove: () =>
                      ref.read(aiChatProvider.notifier).approveOperation(op.id),
                  onEdit: () => showOperationDetailSheet(
                    context,
                    operation: op,
                    onSave: (newParams) {
                      ref
                          .read(aiChatProvider.notifier)
                          .editOperation(op.id, newParams);
                    },
                  ),
                  onReject: () =>
                      ref.read(aiChatProvider.notifier).rejectOperation(op.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(bool isDark, AiChatState state) {
    if (state.messages.isEmpty && !state.isStreaming) {
      return Center(
        child: _buildEmptyState(isDark),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final msg = state.messages[index];
        final isLastAssistant = index == state.messages.length - 1 &&
            msg.role.name == 'assistant' &&
            state.isStreaming;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatBubble(
              message: msg,
              isStreaming: isLastAssistant,
            ),
            if (msg.operations != null && msg.operations!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 16, top: 4),
                child: Text(
                  '已生成 ${msg.operations!.length} 个操作建议 (见上方预览区)',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appColors.textSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    if (!ref.read(aiChatProvider).isApiKeyConfigured) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.key, size: 48, color: context.appColors.textSecondary),
          const SizedBox(height: 16),
          Text(
            '未配置 API 密钥',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.appColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请在设置页面配置 DeepSeek API 密钥',
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.smart_toy_outlined,
            size: 48, color: context.appColors.textSecondary),
        const SizedBox(height: 16),
        Text(
          'AI 任务助手',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.appColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '试试这些：',
          style: TextStyle(
            fontSize: 13,
            color: context.appColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...['帮我安排今天下午的工作', '我的日程合理吗？', '给写周报添加每周五的提醒'].map(
          (hint) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () {
                _textController.text = hint;
                _sendMessage();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: context.appColors.border,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar(bool isDark, AiChatState state) {
    final canSend = !state.isStreaming && state.isApiKeyConfigured;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.delete): () {
                  final text = _textController.text;
                  final sel = _textController.selection;
                  if (!sel.isValid || text.isEmpty) return;
                  // If text is selected, let default behavior handle it
                  if (!sel.isCollapsed) return;
                  // Delete character after cursor
                  if (sel.start < text.length) {
                    final newText = text.substring(0, sel.start) +
                        text.substring(sel.start + 1);
                    _textController.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(offset: sel.start),
                    );
                  }
                },
              },
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                enabled: canSend,
                onSubmitted: (_) => _sendMessage(),
                style: TextStyle(
                  color: context.appColors.text,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: state.isStreaming ? 'AI 正在回复...' : '输入任务安排...',
                  hintStyle: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 14,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: context.appColors.border,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: context.appColors.border,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: context.appColors.accent,
                    ),
                  ),
                  filled: true,
                  fillColor: context.appColors.surface,
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              onPressed: canSend ? _sendMessage : null,
              icon: state.isStreaming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.send_rounded,
                      color: canSend ? (context.appColors.accent) : Colors.grey,
                    ),
              style: IconButton.styleFrom(
                backgroundColor: canSend
                    ? (context.appColors.accent).withOpacity(0.15)
                    : Colors.grey.withOpacity(0.1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, bool isDark) {
    final notifier = ref.read(aiChatProvider.notifier);
    final state = ref.read(aiChatProvider);

    final promptController = TextEditingController(text: state.customPrompt);
    final formatController = TextEditingController(text: state.datedListFormat);
    var datedEnabled = state.datedListEnabled;
    var reminderOnCreate = state.reminderOnCreate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 偏好设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.appColors.text,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Custom prompt
                    Text(
                      '自定义提示词',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: promptController,
                      maxLines: 4,
                      minLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: '如：我偏好下午5点锻炼。早上做有挑战的工作...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              notifier.saveCustomPrompt(promptController.text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('设置已保存，下次对话生效'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Dated list
                    Row(
                      children: [
                        Text(
                          '日期清单模式',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.appColors.text,
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: datedEnabled,
                          onChanged: (v) {
                            setSheetState(() => datedEnabled = v);
                            notifier.setDatedListEnabled(v);
                          },
                        ),
                      ],
                    ),
                    if (datedEnabled) ...[
                      const SizedBox(height: 8),
                      Text(
                        '日期格式',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appColors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: formatController,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.appColors.text,
                              ),
                              decoration: InputDecoration(
                                hintText: 'yyyyMMdd',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              notifier
                                  .setDatedListFormat(formatController.text);
                            },
                            child: const Text('应用'),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '当前日期清单名称: ${_getFormattedDate(state.datedListFormat)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Reminder on create
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '创建任务时自动添加提醒',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.appColors.text,
                                ),
                              ),
                              Text(
                                '将提醒时间设为任务计划开始时间',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.appColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: reminderOnCreate,
                          onChanged: (v) {
                            setSheetState(() => reminderOnCreate = v);
                            notifier.setReminderOnCreate(v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getFormattedDate(String format) {
    final now = AppTime.now();
    return format
        .replaceAll('yyyy', now.year.toString())
        .replaceAll('MM', now.month.toString().padLeft(2, '0'))
        .replaceAll('dd', now.day.toString().padLeft(2, '0'))
        .replaceAll('yy', (now.year % 100).toString().padLeft(2, '0'))
        .replaceAll('M', now.month.toString())
        .replaceAll('d', now.day.toString());
  }
}
