import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/providers/memo_provider.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:focus_my_time/features/memos/services/memo_escrow_service.dart';
import 'package:focus_my_time/features/memos/services/memo_private_payload.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 文件夹锁（OneNote 式分区锁）单元测试。
///
/// 覆盖：锁生命周期、三条解锁路径、密码更改/恢复密钥轮换（只重包装）、
/// v17 零解密迁移（旧密码继续有效）、同步补传与 memo_locks 应用、
/// 锁设置时对存量明文备忘录的整篇加密转换。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 独立临时目录，避免与其他并发测试文件争抢同一个数据库文件。
    tempDir = await Directory.systemTemp.createTemp('memo_lock_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
    final db = await AppDatabase.database;
    await db.delete('memo_locks');
    await db.delete('privacy_vault');
    MemoCryptoService.instance.lockAll();
  });

  tearDownAll(() async {
    MemoCryptoService.instance.lockAll();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // 每个用例从空表开始（数据库文件复用，仅清数据）。
    final db = await AppDatabase.database;
    await db.delete('memo_locks');
    await db.delete('memo_tag_links');
    await db.delete('memos');
    await db.delete('memo_folders');
    await db.delete('privacy_vault');
    MemoCryptoService.instance.lockAll();
  });

  const testFolder = 'memo-folder-test-1';
  const password = 'lock-password-1';
  const legacyPassword = 'legacy-vault-pass';

  group('文件夹锁生命周期', () {
    test('设置锁 → 密码解锁 → 锁定 → 内容密文可解', () async {
      await MemoDatabase.createFolder('工作');
      final recoveryKey = await MemoCryptoService.instance.setupFolderLock(
        testFolder,
        password,
      );
      expect(recoveryKey.length, 52);
      expect(MemoCryptoService.instance.isFolderUnlocked(testFolder), isTrue);

      MemoCryptoService.instance.lockFolder(testFolder);
      expect(MemoCryptoService.instance.isFolderUnlocked(testFolder), isFalse);

      final ok = await MemoCryptoService.instance.unlockFolderWithPassword(
        testFolder,
        password,
      );
      expect(ok, isTrue);
      expect(
        MemoCryptoService.instance.keyForMemoFolder(testFolder),
        isNotNull,
      );
    });

    test('错误密码返回 false 且不留会话', () async {
      await MemoCryptoService.instance.setupFolderLock(testFolder, password);
      MemoCryptoService.instance.lockFolder(testFolder);
      final ok = await MemoCryptoService.instance.unlockFolderWithPassword(
        testFolder,
        'wrong-password',
      );
      expect(ok, isFalse);
      expect(MemoCryptoService.instance.isFolderUnlocked(testFolder), isFalse);
    });

    test('恢复密钥解锁；轮换后旧密钥失效新密钥有效', () async {
      final oldKey = await MemoCryptoService.instance.setupFolderLock(
        testFolder,
        password,
      );
      MemoCryptoService.instance.lockFolder(testFolder);
      expect(
        await MemoCryptoService.instance.unlockFolderWithRecoveryKey(
          testFolder,
          oldKey,
        ),
        isTrue,
      );
      final newKey = await MemoCryptoService.instance.rotateRecoveryKey(
        testFolder,
      );
      expect(newKey, isNot(oldKey));
      MemoCryptoService.instance.lockFolder(testFolder);
      expect(
        await MemoCryptoService.instance.unlockFolderWithRecoveryKey(
          testFolder,
          oldKey,
        ),
        isFalse,
      );
      expect(
        await MemoCryptoService.instance.unlockFolderWithRecoveryKey(
          testFolder,
          newKey,
        ),
        isTrue,
      );
    });

    test('更改密码只重包装内容密钥（已加密内容仍可解）', () async {
      await MemoCryptoService.instance.setupFolderLock(testFolder, password);
      final key = MemoCryptoService.instance.keyForMemoFolder(testFolder)!;
      final envelope = MemoCryptoService.instance.encryptTextWithKey(
        encodeMemoPrivatePayload(title: '标题', bodyMd: '正文'),
        key,
      );

      await MemoCryptoService.instance.changeFolderLockPassword(
        testFolder,
        'brand-new-pass-9',
      );
      // 内容密钥不变：旧密文仍可解。
      final keyAfter = MemoCryptoService.instance.keyForMemoFolder(
        testFolder,
      )!;
      final decoded = decodeMemoPrivatePayload(
        MemoCryptoService.instance.decryptTextWithKey(envelope, keyAfter),
      );
      expect(decoded.title, '标题');
      expect(decoded.bodyMd, '正文');

      MemoCryptoService.instance.lockFolder(testFolder);
      expect(
        await MemoCryptoService.instance.unlockFolderWithPassword(
          testFolder,
          'brand-new-pass-9',
        ),
        isTrue,
      );
      expect(
        await MemoCryptoService.instance.unlockFolderWithPassword(
          testFolder,
          password,
        ),
        isFalse,
      );
    });

    test('lockAll 清空全部会话', () async {
      await MemoCryptoService.instance.setupFolderLock(
        testFolder,
        password,
      );
      await MemoCryptoService.instance.setupFolderLock(
        'memo-folder-test-2',
        'password-2x',
      );
      expect(MemoCryptoService.instance.isUnlocked, isTrue);
      MemoCryptoService.instance.lockAll();
      expect(MemoCryptoService.instance.isUnlocked, isFalse);
      expect(
        MemoCryptoService.instance.isFolderUnlocked(testFolder),
        isFalse,
      );
    });
  });

  group('v17 零解密迁移', () {
    test('旧保险库 → 默认锁：旧密码继续有效，备忘录归入默认文件夹', () async {
      // 1) 用旧流程建立全局保险库并创建私有备忘录。
      await MemoCryptoService.instance.setupPassword(legacyPassword);
      await MemoDatabase.createMemo(
        title: '私密一',
        bodyMd: '内容一',
        folderId: null,
        isPrivate: true,
        encryptTitle: false,
        encryptedPayload: MemoCryptoService.instance.encryptText(
          encodeMemoPrivatePayload(title: '私密一', bodyMd: '内容一'),
        ),
      );
      await MemoDatabase.createMemo(
        title: '普通备忘录',
        bodyMd: '明文内容',
        isPrivate: false,
      );

      final db = await AppDatabase.database;
      // 2) 执行迁移（幂等，跑两次结果一致）。
      await AppDatabase.migrateLegacyVaultToLocks(db);
      await AppDatabase.migrateLegacyVaultToLocks(db);

      // 3) 默认锁存在且包装字段与保险库一致（同一把内容密钥）。
      final lock = await MemoDatabase.getLock(MemoDatabase.defaultLockId);
      expect(lock, isNotNull);
      final vault = await MemoDatabase.getVault();
      expect(lock!['wrappedContentKey'], vault!['wrappedMasterKey']);
      expect(lock['salt'], vault['salt']);

      // 4) 默认文件夹存在；私有备忘录归入且不再持有明文标题。
      final folders = await MemoDatabase.getAllFolders();
      final defaultFolder = folders.firstWhere(
        (f) => f['id'] == MemoDatabase.defaultPrivacyFolderId,
      );
      expect(defaultFolder['name'], MemoDatabase.defaultPrivacyFolderName);
      final memos = await MemoDatabase.getMemos();
      final privateMemo = memos.firstWhere((m) => m['isPrivate'] == true);
      expect(privateMemo['folderId'], MemoDatabase.defaultPrivacyFolderId);
      expect(privateMemo['title'], isNull);
      expect(privateMemo['encryptTitle'], false);
      final normalMemo = memos.firstWhere((m) => m['isPrivate'] == false);
      expect(normalMemo['folderId'], isNull);

      // 5) 旧密码解锁默认锁后，旧密文可解（无需重设密码）。
      final ok = await MemoCryptoService.instance.unlockFolderWithPassword(
        MemoDatabase.defaultPrivacyFolderId,
        legacyPassword,
      );
      expect(ok, isTrue);
      final key = MemoCryptoService.instance.keyForMemoFolder(
        MemoDatabase.defaultPrivacyFolderId,
      )!;
      final decoded = decodeMemoPrivatePayload(
        MemoCryptoService.instance.decryptTextWithKey(
          privateMemo['encryptedPayload'] as String,
          key,
        ),
      );
      expect(decoded.title, '私密一');
      expect(decoded.bodyMd, '内容一');
    });
  });

  group('同步：配置型补传与 memo_locks 应用', () {
    test('锁记录无视水位线全量上传', () async {
      await MemoCryptoService.instance.setupFolderLock(testFolder, password);
      final payload = await MemoDatabase.getSyncPayload(0);
      expect(payload['memo_locks'], isNotEmpty);
      // 水位线推到未来也不丢锁记录。
      final futurePayload = await MemoDatabase.getSyncPayload(
        DateTime.now().millisecondsSinceEpoch + 86400000,
      );
      expect(futurePayload['memo_locks'], isNotEmpty);
    });

    test('applySyncChanges 可应用远端 memo_locks 记录', () async {
      final remoteLock = {
        'id': 'memo-lock-remote-1',
        'folderId': 'memo-folder-remote',
        'kdfName': 'argon2id',
        'kdfParams': '{"iterations":3,"memoryKiB":65536,"lanes":2,"keyLength":32}',
        'salt': 'c2FsdA==',
        'wrappedContentKey': 'd3JhcHBlZA==',
        'wrapNonce': 'bm9uY2U=',
        'recoveryWrappedContentKey': 'cmVjb3Zlcnk=',
        'recoveryNonce': 'cmVjb3Zlcnktbm9uY2U=',
        'cryptoVersion': 1,
        'configRevision': 1,
        'createdAt': 1700000000000,
      };
      await MemoDatabase.applySyncChanges({
        'memo_locks': [
          {
            'id': 'memo-lock-remote-1',
            'updatedAt': 1700000001000,
            'deleted': false,
            'data': remoteLock,
          },
        ],
      });
      final lock = await MemoDatabase.getLock('memo-lock-remote-1');
      expect(lock, isNotNull);
      expect(lock!['folderId'], 'memo-folder-remote');
      expect(lock['wrappedContentKey'], 'd3JhcHBlZA==');
    });
  });

  group('锁设置时的存量内容转换', () {
    test('setupFolderLock 将文件夹内普通备忘录整篇加密', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(memoProvider.notifier);
      await container.read(memoProvider.future);

      final folder = await MemoDatabase.createFolder('待加密');
      final memo = await MemoDatabase.createMemo(
        title: '明文标题',
        bodyMd: '明文正文',
        folderId: folder['id'] as String,
        isPrivate: false,
      );

      await notifier.setupFolderLock(
        folder['id'] as String,
        'folder-pass-123',
      );

      final updated = await MemoDatabase.getMemo(memo['id'] as String);
      expect(updated!['isPrivate'], true);
      expect(updated['title'], isNull);
      expect(updated['bodyMd'], isNull);
      expect(updated['encryptedPayload'], isNotNull);

      // 解锁后可读回原文。
      final hydrated = container.read(memoProvider).value!;
      final row = hydrated.firstWhere((m) => m['id'] == memo['id']);
      expect(row['title'], '明文标题');
      expect(row['bodyMd'], '明文正文');
      expect(row['locked'], false);

      // 锁定后同一行变为锁定占位。
      await notifier.lockFolder(folder['id'] as String);
      final lockedRows = container.read(memoProvider).value!;
      final lockedRow = lockedRows.firstWhere((m) => m['id'] == memo['id']);
      expect(lockedRow['locked'], true);
      expect(lockedRow['title'], isNull);
    });
  });

  group('解锁后列表即时水合（web 端回归）', () {
    test('unlockFolderWithPassword 后 provider state 应显示解锁内容', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(memoProvider.notifier);
      await container.read(memoProvider.future);

      final folder = await MemoDatabase.createFolder('解锁刷新');
      await MemoDatabase.createMemo(
        title: '待水合',
        bodyMd: '解锁后可见',
        folderId: folder['id'] as String,
        isPrivate: false,
      );
      await notifier.setupFolderLock(folder['id'] as String, 'refresh-pass-1');
      await notifier.lockFolder(folder['id'] as String);

      // 锁定态：行应为 locked 占位
      final lockedRows = container.read(memoProvider).value!;
      final lockedRow = lockedRows.firstWhere((m) => m['title'] == null || m['locked'] == true,
          orElse: () => throw StateError('没有锁定行: ${lockedRows.map((r) => r['title']).toList()}'));
      expect(lockedRow['locked'], true);

      // 解锁后：行应立即水合为明文
      final ok = await notifier.unlockFolderWithPassword(
        folder['id'] as String,
        'refresh-pass-1',
      );
      expect(ok, true);
      final rows = container.read(memoProvider).value!;
      final row = rows.firstWhere((m) => m['isPrivate'] == true);
      expect(row['locked'], false);
      expect(row['bodyMd'], '解锁后可见');
    });
  });

  group('账号托管派生', () {
    test('deriveEscrowKey 输出确定且为 32 字节', () {
      final a = MemoEscrowService.deriveEscrowKey('monody12', 'cGVwcGVy');
      final b = MemoEscrowService.deriveEscrowKey('monody12', 'cGVwcGVy');
      final c = MemoEscrowService.deriveEscrowKey('other-password', 'cGVwcGVy');
      expect(a.length, 32);
      expect(base64Encode(a), base64Encode(b));
      expect(base64Encode(a), isNot(base64Encode(c)));
    });
  });
}

// 临时回归测试：解锁后 provider 列表应立即水合（web 端发现的 bug）
void runUnlockRefreshRegression() {}
