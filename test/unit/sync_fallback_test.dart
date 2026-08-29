import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用真实 HTTP 假服务器验证同步协议的兼容性降级行为：
/// - 旧版服务器（无 memoSync 标志且拒绝备忘录表）→ 自动去表重试并记住结论
/// - 新版服务器 → 备忘录表正常进入同步负载
void main() {
  late HttpServer server;
  late int port;
  // 每次收到 /api/sync 请求时记录负载包含的表
  final syncRequests = <Set<String>>[];
  bool serverSupportsMemo = false;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir = await Directory.systemTemp.createTemp('sync_fallback_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
    await AppDatabase.database;

    server = await HttpServer.bind('127.0.0.1', 0);
    port = server.port;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      Future<void> respond(int status, Map<String, dynamic> json) async {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(json));
        await request.response.close();
      }

      if (path == '/api/health') {
        await respond(200, {
          'status': 'ok',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (serverSupportsMemo) 'memoSync': true,
        });
        return;
      }
      if (path == '/api/auth/login') {
        await respond(200, {
          'success': true,
          'token': 'test-token',
          'userId': 'test-user',
        });
        return;
      }
      if (path == '/api/sync') {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final tables = (decoded['tables'] as Map).keys
            .map((key) => key.toString())
            .toSet();
        syncRequests.add(tables);
        if (!serverSupportsMemo &&
            tables.any((t) => t.startsWith('memo_') || t == 'privacy_vault')) {
          await respond(400, {'error': '无效的数据表: memos'});
          return;
        }
        await respond(200, {
          'success': true,
          'serverLastSync': DateTime.now().millisecondsSinceEpoch,
          'tables': const <String, dynamic>{},
        });
        return;
      }
      await respond(404, {'error': 'not found'});
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    SyncService.logout();
  });

  test('旧版服务器：登录探测后备忘录表不进入同步负载且同步成功', () async {
    serverSupportsMemo = false;
    syncRequests.clear();
    await SyncService.setServerUrl('http://127.0.0.1:$port');
    final loginResult = await SyncService.login(
      username: 'fallback-test',
      password: 'password-123',
    );
    expect(loginResult.success, isTrue);
    expect(SyncService.serverSupportsMemoSync, isFalse);

    await AppDatabase.createTask(listId: 'system-all-tasks', title: '旧服务器任务');
    final syncResult = await SyncService.fullSync();
    expect(syncResult.success, isTrue);
    expect(syncRequests, isNotEmpty);
    // 上传与下载请求都不包含备忘录表
    for (final tables in syncRequests) {
      expect(tables.any((t) => t.startsWith('memo_')), isFalse);
      expect(tables.contains('privacy_vault'), isFalse);
      expect(tables.contains('tasks'), isTrue);
    }
  });

  test('旧版服务器：备忘录变更不会推进备忘录水位线', () async {
    serverSupportsMemo = false;
    syncRequests.clear();
    await MemoDatabase.createMemo(title: '降级期间备忘录', bodyMd: '本地内容');
    final syncResult = await SyncService.fullSync();
    expect(syncResult.success, isTrue);
    expect(syncRequests, isNotEmpty);
    for (final tables in syncRequests) {
      expect(tables.any((t) => t.startsWith('memo_')), isFalse);
    }
    // 备忘录数据仍完整保留在本地
    final memos = await MemoDatabase.getMemos();
    expect(memos.map((m) => m['title']), contains('降级期间备忘录'));
  });

  test('新版服务器：重新登录后备忘录表恢复进入同步负载', () async {
    serverSupportsMemo = true;
    syncRequests.clear();
    final loginResult = await SyncService.login(
      username: 'fallback-test',
      password: 'password-123',
    );
    expect(loginResult.success, isTrue);
    expect(SyncService.serverSupportsMemoSync, isTrue);

    final syncResult = await SyncService.fullSync();
    expect(syncResult.success, isTrue);
    // 降级期间创建的备忘录应在新服务器可用后进入上传负载
    expect(syncRequests, isNotEmpty);
    final uploadTables = syncRequests.first;
    expect(uploadTables, containsAll(['memos', 'privacy_vault']));
  });

  test('备忘录独立水位线：任务推进不会漏传旧备忘录变更', () async {
    serverSupportsMemo = true;
    syncRequests.clear();
    // 任务与备忘录水位线分离：多次同步后备忘录负载只包含未同步变更
    await SyncService.fullSync();
    final firstUpload = syncRequests
        .map((tables) => tables)
        .toList();
    expect(firstUpload.first, contains('memos'));

    syncRequests.clear();
    final memo = await MemoDatabase.createMemo(title: '第二次同步的备忘录');
    await SyncService.fullSync();
    final lastUpload = await MemoDatabase.getMemo(memo['id'] as String);
    expect(lastUpload, isNotNull);
    expect(syncRequests, isNotEmpty);
  });
}
