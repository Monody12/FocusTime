import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/memos/services/memo_markdown_transfer_service.dart';

void main() {
  test('Markdown 导入严格按 UTF-8 解码并使用文件名作为标题', () {
    final imported = MemoMarkdownTransferService.decodeImport(
      '会议记录.md',
      Uint8List.fromList(utf8.encode('\uFEFF# 主题\n正文')),
    );
    expect(imported.title, '会议记录');
    expect(imported.body, '# 主题\n正文');
    expect(
      () => MemoMarkdownTransferService.decodeImport(
        'bad.md',
        Uint8List.fromList([0xff, 0xfe]),
      ),
      throwsFormatException,
    );
  });

  test('导出文件名移除路径与 Windows 非法字符', () {
    expect(MemoMarkdownTransferService.safeBaseName('../计划:第一版?'), '__计划_第一版_');
    expect(MemoMarkdownTransferService.safeBaseName('CON'), '_CON');
  });

  test('Typora ZIP 改写附件引用并处理重复附件名', () {
    final zip = MemoMarkdownTransferService.encodeTyporaZip(
      title: '项目/记录',
      body: '![甲](memo-attachment://a-1)\n![乙](memo-attachment://a-2)',
      attachments: [
        MemoExportAttachment(
          id: 'a-1',
          filename: '截图.png',
          bytes: Uint8List.fromList([1, 2]),
        ),
        MemoExportAttachment(
          id: 'a-2',
          filename: '截图.png',
          bytes: Uint8List.fromList([3, 4]),
        ),
      ],
    );
    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.findFile('assets/截图.png'), isNotNull);
    expect(archive.findFile('assets/截图-2.png'), isNotNull);
    final markdown = archive.findFile('项目_记录.md');
    expect(markdown, isNotNull);
    final text = utf8.decode(markdown!.content as List<int>);
    expect(text, contains('](assets/截图.png)'));
    expect(text, contains('](assets/截图-2.png)'));
    expect(text, isNot(contains('memo-attachment://')));
  });
}
