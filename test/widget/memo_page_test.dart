import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/presentation/pages/memo_page.dart';
import 'package:focus_my_time/features/memos/presentation/widgets/markdown_preview.dart';

const _alphaTitle = 'Alpha 排序测试';
const _zuluTitle = 'Zulu 排序测试';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir = await Directory.systemTemp.createTemp('memo_page_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
    await AppDatabase.database;
    await MemoDatabase.createMemo(title: _zuluTitle, bodyMd: '第二篇');
    await MemoDatabase.createMemo(title: _alphaTitle, bodyMd: '第一篇');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('排序菜单提供六种方式并按名称排序后记住选择', (tester) async {
    Future<void> waitForIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: MemoPage(onClose: () {})),
        ),
      ),
    );
    await tester.pump();
    await waitForIo();

    await tester.tap(find.text('最近修改'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in const [
      '最近修改',
      '最早修改',
      '名称 A-Z',
      '名称 Z-A',
      '最近创建',
      '最早创建',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('名称 A-Z').last);
    await tester.pump();
    await waitForIo();

    expect(
      tester.getTopLeft(find.text(_alphaTitle)).dy,
      lessThan(tester.getTopLeft(find.text(_zuluTitle)).dy),
    );
    final preferences = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(preferences.getString('memo_sort'), 'titleAsc');
  });

  testWidgets('已有备忘录默认预览，快捷键支持返回、搜索和新建', (tester) async {
    SharedPreferences.setMockInitialValues({'memo_view_mode': 'edit'});

    Future<void> waitForIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> pressShortcut(
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
      await tester.sendKeyUpEvent(modifier);
    }

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: MemoPage(onClose: () {})),
        ),
      ),
    );
    await tester.pump();
    await waitForIo();

    await tester.tap(find.text(_alphaTitle).first);
    await tester.pump();
    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.text('第一篇'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await waitForIo();
    expect(find.text('选择一篇备忘录开始编辑'), findsOneWidget);

    await pressShortcut(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF);
    expect(find.text('搜索备忘录（解锁后可搜索隐私内容）'), findsOneWidget);

    await pressShortcut(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN);
    expect(find.text('搜索备忘录（解锁后可搜索隐私内容）'), findsNothing);
  });

  testWidgets('Ctrl+S 从正文编辑框触发保存', (tester) async {
    Future<void> waitForIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: MemoPage(onClose: () {})),
        ),
      ),
    );
    await tester.pump();
    await waitForIo();
    await tester.tap(find.text(_alphaTitle).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();

    final bodyField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '使用 Markdown 编写内容，可粘贴或拖入图片',
    );
    expect(bodyField, findsOneWidget);
    await tester.tap(bodyField);
    await tester.enterText(bodyField, '快捷键保存后的正文');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    final saveButton = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .firstWhere((button) => button.tooltip == '保存');
    expect(saveButton.onPressed, isNull);
    await waitForIo();
  });

  testWidgets('标题输入框的 Ctrl+V 使用原生粘贴，不会误写正文', (tester) async {
    Future<void> waitForIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: MemoPage(onClose: () {})),
        ),
      ),
    );
    await tester.pump();
    await waitForIo();
    await tester.tap(find.text(_alphaTitle).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();

    final titleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == '标题',
    );
    final bodyField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '使用 Markdown 编写内容，可粘贴或拖入图片',
    );
    await tester.enterText(titleField, '原标题');
    await tester.tap(titleField);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(tester.widget<TextField>(titleField).controller!.text, '原标题');
    expect(tester.widget<TextField>(bodyField).controller!.text, '第一篇');
    await waitForIo();
    await tester.pump(const Duration(seconds: 3));
  });
}
