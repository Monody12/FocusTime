import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/memos/services/memo_image_service.dart';

/// 备忘录 Markdown 预览。
///
/// 使用 `markdown` 包解析为 AST 后自行渲染为 Flutter 组件：
/// 支持 GFM 表格、任务列表、删除线、自动链接、引用、有序/无序列表和
/// 围栏代码块。原始 HTML 一律按纯文本展示，不参与渲染。
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({super.key, required this.data});

  final String data;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final _linkRecognizers = <TapGestureRecognizer>[];
  String? _parsedData;
  List<Widget>? _parsedBlocks;

  void _disposeRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  List<Widget> _parseBlocks() {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nodes = document.parse(widget.data);
    return [for (final node in nodes) ..._buildBlock(node, baseLevel: 0)];
  }

  @override
  Widget build(BuildContext context) {
    // 解析依赖主题色，必须在 build 中进行；按 data 缓存避免重复解析。
    if (_parsedBlocks == null || _parsedData != widget.data) {
      _disposeRecognizers();
      _parsedData = widget.data;
      _parsedBlocks = _parseBlocks();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _parsedBlocks!,
    );
  }

  List<Widget> _buildBlock(md.Node node, {required int baseLevel}) {
    if (node is! md.Element) {
      final text = node.textContent.trim();
      return text.isEmpty ? const [] : [Text(text)];
    }
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        final sizes = [28.0, 24.0, 20.0, 18.0, 16.0, 15.0];
        return [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              node.textContent.trim(),
              style: TextStyle(
                fontSize: sizes[level - 1],
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
          ),
        ];
      case 'p':
        final image = _soleImage(node);
        if (image != null) return [image];
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              _buildInline(node.children, null),
              style: const TextStyle(height: 1.5),
            ),
          ),
        ];
      case 'blockquote':
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: context.appColors.textSecondary,
                ),
              ),
              color: context.appColors.surfaceElevated.withValues(alpha: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in node.children ?? const <md.Node>[])
                  ..._buildBlock(child, baseLevel: baseLevel),
              ],
            ),
          ),
        ];
      case 'pre':
        final code = node.children?.firstOrNull;
        final codeText = code is md.Element ? code.textContent : node.textContent;
        return [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                codeText.endsWith('\n')
                    ? codeText.substring(0, codeText.length - 1)
                    : codeText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ];
      case 'ul':
      case 'ol':
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 8, left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < (node.children ?? []).length; i++)
                  ..._buildListItem(node.children![i], node.tag, i),
              ],
            ),
          ),
        ];
      case 'table':
        return [_buildTable(node)];
      case 'hr':
        return [const Divider(height: 24)];
      default:
        final text = node.textContent.trim();
        return text.isEmpty
            ? const []
            : [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(_buildInline(node.children, null)),
                ),
              ];
    }
  }

  List<Widget> _buildListItem(md.Node node, String listTag, int index) {
    if (node is! md.Element) {
      return [Text('• ${node.textContent}')];
    }
    Widget content;
    var marker = listTag == 'ol' ? '${index + 1}.' : '•';
    var isCheckbox = false;
    var checked = false;
    if (node.children case final children? when children.isNotEmpty) {
      final first = children.first;
      if (first is md.Element && first.tag == 'input') {
        isCheckbox = true;
        checked = first.attributes['checked'] != null;
        content = Text.rich(_buildInline(children.sublist(1), null));
        marker = '';
      } else {
        content = Text.rich(_buildInline(children, null));
      }
    } else {
      content = const SizedBox.shrink();
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: isCheckbox
                ? Checkbox(
                    value: checked,
                    onChanged: null,
                    visualDensity: VisualDensity.compact,
                  )
                : Text(marker),
          ),
          Expanded(child: content),
        ],
      ),
    ];
  }

  Widget _buildTable(md.Element table) {
    final rows = <TableRow>[];
    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final isHead = section.tag == 'thead';
      for (final tr in section.children ?? const <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final cells = <Widget>[];
        for (final cell in tr.children ?? const <md.Node>[]) {
          final cellElement = cell is md.Element ? cell : null;
          final align = (cellElement?.attributes['style'] ?? '')
              .contains('text-align:right')
              ? TextAlign.right
              : TextAlign.left;
          cells.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text.rich(
                _buildInline(cellElement?.children, null),
                textAlign: align,
                style: isHead
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
              ),
            ),
          );
        }
        rows.add(
          TableRow(
            decoration: isHead
                ? BoxDecoration(
                    color: context.appColors.surfaceElevated,
                  )
                : null,
            children: cells,
          ),
        );
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(border: TableBorder.all(color: context.appColors.border), children: rows),
    );
  }

  /// 段落里只有一张图片时按独立图片渲染。
  Widget? _soleImage(md.Element paragraph) {
    final children = paragraph.children;
    if (children == null || children.length != 1) return null;
    final only = children.first;
    if (only is! md.Element || only.tag != 'img') return null;
    return _MemoImage(href: only.attributes['src'] ?? '');
  }

  InlineSpan _buildInline(List<md.Node>? nodes, TextStyle? inherited) {
    final spans = <InlineSpan>[];
    for (final node in nodes ?? const <md.Node>[]) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: inherited));
        continue;
      }
      if (node is! md.Element) continue;
      switch (node.tag) {
        case 'strong':
          spans.add(
            _buildInline(
              node.children,
              (inherited ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        case 'em':
          spans.add(
            _buildInline(
              node.children,
              (inherited ?? const TextStyle()).copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        case 'del':
          spans.add(
            _buildInline(
              node.children,
              (inherited ?? const TextStyle()).copyWith(
                decoration: TextDecoration.lineThrough,
              ),
            ),
          );
        case 'code':
          spans.add(
            TextSpan(
              text: node.textContent,
              style: (inherited ?? const TextStyle()).copyWith(
                fontFamily: 'monospace',
                fontSize: 13,
                background: Paint()
                  ..color = context.appColors.surfaceElevated,
              ),
            ),
          );
        case 'a':
          final href = node.attributes['href'] ?? '';
          final recognizer = TapGestureRecognizer()
            ..onTap = () => openExternalLink(context, href);
          _linkRecognizers.add(recognizer);
          spans.add(
            TextSpan(
              recognizer: recognizer,
              style: (inherited ?? const TextStyle()).copyWith(
                color: context.appColors.accent,
                decoration: TextDecoration.underline,
              ),
              children: [
                _buildInline(
                  node.children,
                  (inherited ?? const TextStyle()).copyWith(
                    color: context.appColors.accent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          );
        case 'img':
          spans.add(WidgetSpan(child: _MemoImage(href: node.attributes['src'] ?? '')));
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        default:
          spans.add(_buildInline(node.children, inherited));
      }
    }
    return TextSpan(children: spans.isEmpty ? [TextSpan(text: '', style: inherited)] : spans);
  }
}

/// 打开外部链接。当前依赖集没有 url_launcher，先复制到剪贴板兜底，
/// 后续接入启动器后改为直接打开浏览器。
Future<void> openExternalLink(BuildContext context, String href) async {
  if (href.isEmpty || href.startsWith('memo-attachment://')) return;
  await Clipboard.setData(ClipboardData(text: href));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('链接已复制到剪贴板')));
}

class _MemoImage extends StatelessWidget {
  const _MemoImage({required this.href});

  final String href;

  @override
  Widget build(BuildContext context) {
    if (href.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 360),
      alignment: Alignment.centerLeft,
      child: FutureBuilder<ImageProvider?>(
        future: MemoImageService.instance.resolveProvider(href),
        builder: (context, snapshot) {
          final provider = snapshot.data;
          if (provider == null) {
            if (snapshot.hasError) {
              return Text('图片加载失败：${snapshot.error}');
            }
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return InteractiveViewer(
            panEnabled: false,
            child: Image(image: provider, fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}
