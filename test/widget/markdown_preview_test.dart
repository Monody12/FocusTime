import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/memos/presentation/widgets/markdown_preview.dart';

void main() {
  Future<void> pumpPreview(WidgetTester tester, String data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MarkdownPreview(data: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染标题、列表、表格、删除线和代码块', (tester) async {
    await pumpPreview(
      tester,
      '# 主标题\n\n- [x] 已完成项\n- [ ] 待办项\n\n'
      '| 列A | 列B |\n|-----|-----|\n| 1   | 2   |\n\n'
      '~~删除线~~ **加粗** *斜体* `行内代码`\n\n'
      '```dart\nvoid main() {}\n```\n\n> 引用内容\n',
    );
    expect(find.text('主标题'), findsOneWidget);
    expect(find.text('已完成项'), findsOneWidget);
    expect(find.text('待办项'), findsOneWidget);
    expect(find.text('列A'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // 行内样式位于 TextSpan 中，需要显式搜索 RichText 的整段文本
    final paragraph = find.textContaining('删除线', findRichText: true);
    expect(paragraph, findsOneWidget);
    expect(find.textContaining('加粗', findRichText: true), findsOneWidget);
    expect(find.textContaining('行内代码', findRichText: true), findsOneWidget);
    expect(find.textContaining('void main()'), findsOneWidget);
    expect(find.text('引用内容'), findsOneWidget);
  });

  testWidgets('原始 HTML 按纯文本渲染，不执行标签', (tester) async {
    await pumpPreview(
      tester,
      '<script>alert(1)</script>\n\n普通段落',
    );
    expect(find.text('<script>alert(1)</script>'), findsOneWidget);
    expect(find.text('普通段落'), findsOneWidget);
  });

  testWidgets('memo-attachment 图片引用走附件解析且缺失时优雅降级', (tester) async {
    await pumpPreview(
      tester,
      '![图片](memo-attachment://not-exists-id)',
    );
    // 不存在的附件不应导致崩溃
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据变化后重新渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownPreview(data: '# 第一版'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一版'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownPreview(data: '# 第二版'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第二版'), findsOneWidget);
    expect(find.text('第一版'), findsNothing);
  });
}
