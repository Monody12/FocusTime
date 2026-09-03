import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

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
  Brightness? _parsedBrightness;
  bool? _parsedNarrowLayout;
  List<Widget>? _parsedBlocks;
  bool _narrowLayout = false;

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
    // 中文输入法常把行首的 ``` 转成全角引号（''' / ‘’‘），渲染层把
    // 行首连续 3 个及以上弯引号宽容处理为代码围栏。仅影响预览显示，
    // 正文原文仍按用户输入保存。
    final normalized = widget.data.replaceAllMapped(
      RegExp('^[‘’]{3,}', multiLine: true),
      (_) => '```',
    );
    final nodes = document.parse(normalized);
    return [for (final node in nodes) ..._buildBlock(node, baseLevel: 0)];
  }

  @override
  Widget build(BuildContext context) {
    // 解析依赖主题色，必须在 build 中进行；按 data 缓存避免重复解析。
    // 窄屏（手机）下调整排版：正文字号加大、表格横向滚动。
    _narrowLayout = MediaQuery.sizeOf(context).width < 600;
    final brightness = Theme.of(context).brightness;
    if (_parsedBlocks == null ||
        _parsedData != widget.data ||
        _parsedBrightness != brightness ||
        _parsedNarrowLayout != _narrowLayout) {
      _disposeRecognizers();
      _parsedData = widget.data;
      _parsedBrightness = brightness;
      _parsedNarrowLayout = _narrowLayout;
      _parsedBlocks = _parseBlocks();
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _parsedBlocks!,
      ),
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
              style: TextStyle(
                height: 1.55,
                fontSize: _narrowLayout ? 15 : null,
              ),
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
        final codeText = _decodeHtmlEntities(
          code is md.Element ? code.textContent : node.textContent,
        );
        final highlighted = _highlightSpans(context, codeText, code);
        final baseColor = Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFABB2BF)
            : const Color(0xFF383A42);
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
              child: highlighted != null
                  ? RichText(text: highlighted)
                  : Text(
                      codeText.endsWith('\n')
                          ? codeText.substring(0, codeText.length - 1)
                          : codeText,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: baseColor,
                      ),
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

  /// 围栏代码块按语言做语法高亮；语言未知或解析失败时返回 null，
  /// 由调用方回退为纯文本等宽渲染。
  TextSpan? _highlightSpans(
    BuildContext context,
    String codeText,
    md.Node? codeNode,
  ) {
    final classAttr = codeNode is md.Element
        ? codeNode.attributes['class'] ?? ''
        : '';
    if (!classAttr.startsWith('language-')) return null;
    final language = classAttr.substring('language-'.length).trim();
    if (language.isEmpty || language == 'text' || language == 'plain') {
      return null;
    }
    final hl.Result result;
    try {
      result = hl.highlight.parse(codeText, language: language);
    } catch (_) {
      return null;
    }
    final spans = <InlineSpan>[];
    final palette = Theme.of(context).brightness == Brightness.dark
        ? _darkCodePalette
        : _lightCodePalette;

    // highlight 包把 token 颜色标在分支节点上、文本放在 children 里，
    // 需要沿子树继承父节点的配色。
    void walk(List<hl.Node>? nodes, TextStyle? inherited) {
      for (final node in nodes ?? const <hl.Node>[]) {
        final tokenClass = node.className?.split(' ').first;
        final color = tokenClass == null ? null : palette[tokenClass];
        final style = color == null ? inherited : TextStyle(color: color);
        if (node.value != null && node.value!.isNotEmpty) {
          spans.add(TextSpan(text: node.value, style: style));
        }
        walk(node.children, style);
      }
    }

    final baseColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFABB2BF)
        : const Color(0xFF383A42);
    walk(result.nodes, TextStyle(color: baseColor));
    if (spans.isEmpty) return null;
    return TextSpan(
      style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: baseColor),
      children: spans,
    );
  }

  /// markdown 包会把代码块内容做 HTML 转义，自渲染时需要还原实体。
  String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
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
          final align =
              (cellElement?.attributes['style'] ?? '').contains(
                'text-align:right',
              )
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
                ? BoxDecoration(color: context.appColors.surfaceElevated)
                : null,
            children: cells,
          ),
        );
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    // 窄屏（手机）表格列宽按内容计算并横向滚动，避免列被挤压成不可读。
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: _narrowLayout
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                border: TableBorder.all(color: context.appColors.border),
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: rows,
              ),
            )
          : Table(
              border: TableBorder.all(color: context.appColors.border),
              children: rows,
            ),
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
                background: Paint()..color = context.appColors.surfaceElevated,
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
          spans.add(
            WidgetSpan(child: _MemoImage(href: node.attributes['src'] ?? '')),
          );
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        default:
          spans.add(_buildInline(node.children, inherited));
      }
    }
    return TextSpan(
      children: spans.isEmpty ? [TextSpan(text: '', style: inherited)] : spans,
    );
  }
}

Future<void> openExternalLink(BuildContext context, String href) async {
  if (href.isEmpty || href.startsWith('memo-attachment://')) return;
  final uri = Uri.tryParse(href);
  final supported =
      uri != null &&
      uri.hasScheme &&
      const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase());
  try {
    if (supported && await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      return;
    }
  } catch (_) {
    // 启动器不可用时复制链接，用户仍可手动打开。
  }
  await Clipboard.setData(ClipboardData(text: href));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(supported ? '无法直接打开，链接已复制' : '链接已复制到剪贴板')),
  );
}

/// 代码高亮配色（按 highlight.js 的 className 分组）。
const Map<String, Color> _darkCodePalette = {
  'keyword': Color(0xFFC678DD),
  'built_in': Color(0xFFE6C07B),
  'type': Color(0xFFE5C07B),
  'literal': Color(0xFFD19A66),
  'number': Color(0xFFD19A66),
  'operator': Color(0xFF56B6C2),
  'regexp': Color(0xFF56B6C2),
  'string': Color(0xFF98C379),
  'subst': Color(0xFFABB2BF),
  'symbol': Color(0xFF56B6C2),
  'class': Color(0xFFE6C07B),
  'function': Color(0xFF61AFEF),
  'title': Color(0xFF61AFEF),
  'params': Color(0xFFABB2BF),
  'comment': Color(0xFF7F848E),
  'doctag': Color(0xFFC678DD),
  'meta': Color(0xFF61AFEF),
  'variable': Color(0xFFE06C75),
  'variable.language': Color(0xFFE06C75),
  'attr': Color(0xFFD19A66),
  'attribute': Color(0xFFD19A66),
  'name': Color(0xFFE06C75),
  'tag': Color(0xFFE06C75),
  'section': Color(0xFFE06C75),
  'selector-tag': Color(0xFFE06C75),
  'selector-id': Color(0xFF61AFEF),
  'selector-class': Color(0xFFD19A66),
  'selector-attr': Color(0xFFD19A66),
  'selector-pseudo': Color(0xFF56B6C2),
  'template-variable': Color(0xFFE06C75),
  'addition': Color(0xFF98C379),
  'deletion': Color(0xFFE06C75),
  'quote': Color(0xFF5C6370),
  'bullet': Color(0xFFD19A66),
  'code': Color(0xFF98C379),
  'emphasis': Color(0xFFE06C75),
  'strong': Color(0xFFE06C75),
  'formula': Color(0xFFC678DD),
  'link': Color(0xFF61AFEF),
  'link_quote': Color(0xFF98C379),
};

const Map<String, Color> _lightCodePalette = {
  'keyword': Color(0xFF0033B3),
  'built_in': Color(0xFF326D74),
  'type': Color(0xFF000000),
  'literal': Color(0xFF871094),
  'number': Color(0xFF871094),
  'operator': Color(0xFF0033B3),
  'regexp': Color(0xFF871094),
  'string': Color(0xFF067D17),
  'symbol': Color(0xFF871094),
  'class': Color(0xFF000000),
  'function': Color(0xFF00627A),
  'title': Color(0xFF00627A),
  'params': Color(0xFF080808),
  'comment': Color(0xFF8C8C8C),
  'doctag': Color(0xFF0033B3),
  'meta': Color(0xFF871094),
  'variable': Color(0xFF080808),
  'attr': Color(0xFF871094),
  'attribute': Color(0xFF871094),
  'name': Color(0xFF871094),
  'tag': Color(0xFF0033B3),
  'section': Color(0xFF0033B3),
  'selector-tag': Color(0xFF0033B3),
  'selector-id': Color(0xFF00627A),
  'selector-class': Color(0xFF871094),
  'selector-attr': Color(0xFF871094),
  'selector-pseudo': Color(0xFF326D74),
  'template-variable': Color(0xFF871094),
  'addition': Color(0xFF067D17),
  'deletion': Color(0xFF871094),
  'quote': Color(0xFF8C8C8C),
  'bullet': Color(0xFF871094),
  'code': Color(0xFF067D17),
  'emphasis': Color(0xFF871094),
  'strong': Color(0xFF871094),
  'formula': Color(0xFF0033B3),
  'link': Color(0xFF00627A),
  'link_quote': Color(0xFF067D17),
};

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
