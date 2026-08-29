import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/services/memo_ai_gate.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _password = 'unit-test-passphrase';
const _newPassword = 'unit-test-new-passphrase';
String _recoveryKey = '';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 使用独立临时目录，避免与其他并发测试文件争抢同一个数据库文件
    final tempDir = await Directory.systemTemp.createTemp('memo_privacy_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
    // 保证测试从“未设置隐私密码”状态开始
    final db = await AppDatabase.database;
    await db.delete('privacy_vault');
    MemoCryptoService.instance.lock();
  });

  tearDownAll(() {
    MemoCryptoService.instance.lock();
  });

  final runSuffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  String tamperEnvelope(String envelope) {
    final decoded = Map<String, dynamic>.from(
      const JsonDecoder().convert(envelope) as Map<String, dynamic>,
    );
    final cipher = decoded['c'] as String;
    decoded['c'] = '${cipher[0] == 'A' ? 'B' : 'A'}${cipher.substring(1)}';
    return const JsonEncoder().convert(decoded);
  }

  test('恢复密钥 Base32 编码解码往返且拒绝无效输入', () {
    final key = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));
    final encoded = MemoCryptoService.encodeRecoveryKey(key, clearAfterEncode: false);
    expect(encoded.length, 52);
    expect(encoded.contains(RegExp('[01]')), isFalse);
    final decoded = MemoCryptoService.decodeRecoveryKey(encoded);
    expect(decoded, key);
    expect(
      () => MemoCryptoService.decodeRecoveryKey('AAAA'),
      throwsFormatException,
    );
    expect(
      () => MemoCryptoService.decodeRecoveryKey('${encoded}A'),
      throwsFormatException,
    );
  });

  test('首次设置隐私密码返回恢复密钥并建立解锁会话', () async {
    expect(await MemoCryptoService.instance.isConfigured, isFalse);
    final recovery = await MemoCryptoService.instance.setupPassword(_password);
    _recoveryKey = recovery;
    expect(recovery.length, 52);
    expect(await MemoCryptoService.instance.isConfigured, isTrue);
    expect(MemoCryptoService.instance.isUnlocked, isTrue);
    expect(
      MemoCryptoService.instance.setupPassword(_password),
      throwsStateError,
    );
    expect(
      MemoCryptoService.instance.setupPassword('short'),
      throwsFormatException,
    );
  });

  test('锁定后错误密码解锁失败且正确密码解锁成功', () async {
    MemoCryptoService.instance.lock();
    expect(MemoCryptoService.instance.isUnlocked, isFalse);
    expect(
      await MemoCryptoService.instance.unlockWithPassword('wrong-password'),
      isFalse,
    );
    expect(await MemoCryptoService.instance.unlockWithPassword(_password), isTrue);
    expect(
      await MemoCryptoService.instance.unlockWithPassword('short'),
      isFalse,
    );
  });

  test('加密解密往返且密文篡改会被检测', () async {
    final crypto = MemoCryptoService.instance;
    expect(await crypto.unlockWithPassword(_password), isTrue);
    final envelope = crypto.encryptText('隐私正文 #1', associatedData: 'memo-1');
    expect(crypto.decryptText(envelope, associatedData: 'memo-1'), '隐私正文 #1');

    // AAD 不匹配时解密必须失败
    expect(
      () => crypto.decryptText(envelope, associatedData: 'memo-2'),
      throwsFormatException,
    );

    // 篡改密文后 GCM 校验必须失败
    expect(
      () => crypto.decryptText(tamperEnvelope(envelope), associatedData: 'memo-1'),
      throwsFormatException,
    );

    // 两次加密产生不同密文（随机 nonce）
    final again = crypto.encryptText('隐私正文 #1', associatedData: 'memo-1');
    expect(again, isNot(envelope));
  });

  test('锁定状态下读取隐私内容会抛出状态错误', () async {
    final crypto = MemoCryptoService.instance;
    final envelope = crypto.encryptText('锁定前内容');
    crypto.lock();
    expect(() => crypto.decryptText(envelope), throwsStateError);
  });

  test('恢复密钥可以解锁并保持修改密码后仍然有效', () async {
    final crypto = MemoCryptoService.instance;
    crypto.lock();
    expect(await crypto.unlockWithPassword(_password), isTrue);
    final envelope = crypto.encryptText('修改密码前正文');
    await crypto.changePassword(currentPassword: _password, newPassword: _newPassword);

    crypto.lock();
    expect(await crypto.unlockWithPassword(_password), isFalse);
    expect(await crypto.unlockWithPassword(_newPassword), isTrue);
    expect(
      MemoCryptoService.instance.decryptText(envelope),
      '修改密码前正文',
    );

    // 修改密码只重新包装主密钥，恢复密钥仍然有效
    crypto.lock();
    expect(await crypto.unlockWithRecoveryKey(_recoveryKey), isTrue);
  });

  test('自动锁定会在无操作超时后清除会话', () async {
    final crypto = MemoCryptoService.instance;
    expect(crypto.isUnlocked, isTrue);
    crypto.setAutoLockDuration(const Duration(milliseconds: 80));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(crypto.isUnlocked, isFalse);
    crypto.setAutoLockDuration(const Duration(hours: 1));
  });

  test('启动时加载持久化的自动锁定偏好', () async {
    await AppDatabase.setSetting('memoAutoLockMinutes', '30');
    await AppDatabase.setSetting('memoLockOnBackground', 'false');
    await MemoCryptoService.instance.loadPersistedSettings();
    expect(MemoCryptoService.instance.autoLockDuration, const Duration(minutes: 30));
    expect(MemoCryptoService.instance.lockOnBackground, isFalse);
    await AppDatabase.setSetting('memoAutoLockMinutes', '60');
    await AppDatabase.setSetting('memoLockOnBackground', 'true');
    await MemoCryptoService.instance.loadPersistedSettings();
    expect(MemoCryptoService.instance.autoLockDuration, const Duration(hours: 1));
    expect(MemoCryptoService.instance.lockOnBackground, isTrue);
  });

  test('备忘录增删改查遵循软删除并可恢复', () async {
    final memo = await MemoDatabase.createMemo(
      title: '软删除测试',
      bodyMd: '# 正文',
      isPrivate: false,
    );
    expect((await MemoDatabase.getMemo(memo['id'] as String))!['title'], '软删除测试');

    await MemoDatabase.deleteMemo(memo['id'] as String);
    final raw = await (await AppDatabase.database).query(
      'memos',
      where: 'id = ?',
      whereArgs: [memo['id']],
    );
    expect(raw.single['deleted'], 1);
    final listed = await MemoDatabase.getMemos();
    expect(listed.any((m) => m['id'] == memo['id']), isFalse);

    await MemoDatabase.restoreMemo(memo['id'] as String);
    final restored = await MemoDatabase.getMemo(memo['id'] as String);
    expect(restored, isNotNull);
    expect(restored!['archived'], isFalse);
  });

  test('文件夹层级最多 10 层且禁止循环引用与同级重名', () async {
    String? parentId;
    final chain = <String>[];
    for (var i = 1; i <= 10; i++) {
      final folder = await MemoDatabase.createFolder(
        '层级$i-$runSuffix',
        parentId: parentId,
      );
      chain.add(folder['id'] as String);
      parentId = folder['id'] as String;
    }
    expect(
      () => MemoDatabase.createFolder('层级11-$runSuffix', parentId: parentId),
      throwsFormatException,
    );

    // 同一父级下 ASCII 大小写不同的名称视为重复
    await MemoDatabase.createFolder('child-folder-$runSuffix', parentId: chain.first);
    expect(
      () => MemoDatabase.createFolder('child-folder-$runSuffix', parentId: chain.first),
      throwsFormatException,
    );
    expect(
      () => MemoDatabase.createFolder('CHILD-FOLDER-$runSuffix', parentId: chain.first),
      throwsFormatException,
    );

    // 不能移动到自身或自己的子文件夹
    final root = chain.first;
    final child = chain[1];
    expect(
      () => MemoDatabase.updateFolder(root, parentId: root),
      throwsFormatException,
    );
    expect(
      () => MemoDatabase.updateFolder(child, parentId: root),
      returnsNormally,
    );
    expect(
      () => MemoDatabase.updateFolder(root, parentId: child),
      throwsFormatException,
    );

    // 移动到根目录需要显式清除父级
    await MemoDatabase.updateFolder(child, clearParent: true);
    final moved = (await MemoDatabase.getAllFolders())
        .firstWhere((f) => f['id'] == child);
    expect(moved['parentId'], isNull);
  });

  test('标签全局忽略大小写防重复并可关联备忘录', () async {
    final tag = await MemoDatabase.createTag('Work-$runSuffix');
    expect(
      () => MemoDatabase.createTag('WORK-$runSuffix'),
      throwsFormatException,
    );
    final memo = await MemoDatabase.createMemo(title: '标签测试');
    await MemoDatabase.setMemoTags(memo['id'] as String, [tag['id'] as String]);
    final tags = await MemoDatabase.getMemoTags(memo['id'] as String);
    expect(tags.map((t) => t['name']), ['Work-$runSuffix']);
    await MemoDatabase.setMemoTags(memo['id'] as String, []);
    expect(await MemoDatabase.getMemoTags(memo['id'] as String), isEmpty);
  });

  test('版本历史最多保留 20 个历史版本', () async {
    final memo = await MemoDatabase.createMemo(title: '版本测试', bodyMd: 'v0');
    for (var i = 1; i <= 25; i++) {
      await MemoDatabase.createVersion(
        memo['id'] as String,
        title: '版本测试',
        bodyMd: 'v$i',
      );
    }
    final versions = await MemoDatabase.getVersions(memo['id'] as String);
    expect(versions.length, MemoDatabase.maxHistoryVersions);
    expect(versions.first['bodyMd'], 'v25');
    expect(versions.last['bodyMd'], 'v6');
  });

  test('回收站清理会物理删除备忘录、版本历史和标签关系', () async {
    final memo = await MemoDatabase.createMemo(title: '彻底删除测试-$runSuffix');
    await MemoDatabase.createVersion(memo['id'] as String, title: 'x', bodyMd: 'y');
    final tag = await MemoDatabase.createTag('清理标签-$runSuffix');
    await MemoDatabase.setMemoTags(memo['id'] as String, [tag['id'] as String]);

    await MemoDatabase.deleteMemo(memo['id'] as String);
    await MemoDatabase.purgeMemo(memo['id'] as String);

    final db = await AppDatabase.database;
    expect(
      (await db.query('memos', where: 'id = ?', whereArgs: [memo['id']])),
      isEmpty,
    );
    expect(
      (await db.query(
        'memo_versions',
        where: 'memo_id = ?',
        whereArgs: [memo['id']],
      )),
      isEmpty,
    );
    expect(
      (await db.query(
        'memo_tag_links',
        where: 'memo_id = ?',
        whereArgs: [memo['id']],
      )),
      isEmpty,
    );
  });

  test('AI 授权门拒绝未授权和未确认的读取', () async {
    MemoCryptoService.instance.lock();
    final normal = await MemoDatabase.createMemo(
      title: 'AI 测试-$runSuffix',
      bodyMd: '普通正文',
      aiAllowed: false,
    );
    expect(
      () => MemoAiGate.contentForAi(normal['id'] as String, userConfirmed: true),
      throwsStateError,
    );

    final allowed = await MemoDatabase.createMemo(
      title: 'AI 允许-$runSuffix',
      bodyMd: '允许正文',
      aiAllowed: true,
    );
    final content = await MemoAiGate.contentForAi(
      allowed['id'] as String,
      userConfirmed: true,
    );
    expect(content!['body'], '允许正文');
  });

  test('AI 授权门对隐私备忘录要求解锁和再次确认', () async {
    final crypto = MemoCryptoService.instance;
    if (!crypto.isUnlocked) {
      expect(await crypto.unlockWithPassword(_newPassword), isTrue);
    }
    // 没有加密负载的私密记录没有可读正文
    final bare = await MemoDatabase.createMemo(
      title: '隐私AI裸-$runSuffix',
      bodyMd: '',
      isPrivate: true,
      aiAllowed: true,
    );
    final bareContent = await MemoAiGate.contentForAi(
      bare['id'] as String,
      userConfirmed: true,
    );
    expect(bareContent!['body'], '');

    final privateMemo = await MemoDatabase.createMemo(
      title: '',
      bodyMd: '',
      isPrivate: true,
      aiAllowed: true,
      encryptedPayload: MemoCryptoService.instance.encryptText(
        '隐私AI-$runSuffix\u0000隐私正文',
      ),
    );
    // 未解锁时返回 null，不泄露任何内容
    MemoCryptoService.instance.lock();
    expect(
      await MemoAiGate.contentForAi(
        privateMemo['id'] as String,
        userConfirmed: true,
      ),
      isNull,
    );

    // 解锁但未二次确认时拒绝
    expect(
      await MemoCryptoService.instance.unlockWithPassword(_newPassword),
      isTrue,
    );
    expect(
      () => MemoAiGate.contentForAi(
        privateMemo['id'] as String,
        userConfirmed: false,
      ),
      throwsStateError,
    );

    // 解锁且确认后可读取解密正文
    final content = await MemoAiGate.contentForAi(
      privateMemo['id'] as String,
      userConfirmed: true,
    );
    expect(content!['title'], '隐私AI-$runSuffix');
    expect(content['body'], '隐私正文');
  });

  test('隐私备忘录同步负载包含备忘录和保险库表', () async {
    final payload = await MemoDatabase.getSyncPayload(0);
    for (final table in MemoDatabase.syncTables) {
      expect(payload[table], isNotNull, reason: '缺少同步表 $table');
    }
    final vaultRecords = payload['privacy_vault']!;
    expect(vaultRecords, isNotEmpty);
    final vault = vaultRecords.first['data'] as Map<String, dynamic>;
    expect(vault['wrappedMasterKey'], isNotNull);
    expect(vault['recoveryWrappedMasterKey'], isNotNull);
    expect(vault['salt'], isNotNull);
  });
}
