import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/presentation/pages/memo_page.dart';

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
}
