import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_message.dart';
import 'package:focus_my_time/features/ai_assistant/presentation/widgets/streaming_text.dart';

class ChatBubble extends StatelessWidget {
  final AiMessage message;
  final bool isStreaming;

  const ChatBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  void _copyContent(BuildContext context) {
    if (message.content.isEmpty) return;
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiMessageRole.user;
    final hasContent = message.content.isNotEmpty;

    return GestureDetector(
      onLongPress: hasContent ? () => _copyContent(context) : null,
      onSecondaryTap: hasContent ? () => _copyContent(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              _buildAvatar(context, false),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser
                          ? (context.appColors.accent)
                          : (context.appColors.surface),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: isStreaming &&
                            message.role == AiMessageRole.assistant
                        ? StreamingText(
                            text: message.content,
                            isStreaming: isStreaming,
                            style: TextStyle(
                              color: isUser
                                  ? Colors.white
                                  : (context.appColors.text),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          )
                        : Text(
                            message.content.isEmpty ? '...' : message.content,
                            style: TextStyle(
                              color: isUser
                                  ? Colors.white
                                  : (context.appColors.text),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                  ),
                  if (hasContent && !isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                      child: InkWell(
                        onTap: () => _copyContent(context),
                        borderRadius: BorderRadius.circular(4),
                        child: Icon(
                          Icons.copy,
                          size: 14,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 8),
              _buildAvatar(context, true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, bool isUser) {
    return CircleAvatar(
      radius: 16,
      backgroundColor:
          isUser ? (context.appColors.accent) : (context.appColors.surface),
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy_outlined,
        size: 18,
        color: isUser ? Colors.white : (context.appColors.accent),
      ),
    );
  }
}
