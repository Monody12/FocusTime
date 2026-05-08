import 'package:flutter/material.dart';

class StreamingText extends StatefulWidget {
  final String text;
  final bool isStreaming;
  final TextStyle? style;

  const StreamingText({
    super.key,
    required this.text,
    required this.isStreaming,
    this.style,
  });

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.text.isEmpty ? '思考中...' : widget.text,
            style: widget.style,
          ),
        ),
        if (widget.isStreaming)
          FadeTransition(
            opacity: _cursorController,
            child: Container(
              width: 2,
              height: (widget.style?.fontSize ?? 14) * 1.2,
              margin: const EdgeInsets.only(left: 2, bottom: 2),
              color: widget.style?.color ?? Colors.grey,
            ),
          ),
      ],
    );
  }
}
