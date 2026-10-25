import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/memos/services/kdf_backend.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';

/// 账号托管（opt-in 的"忘记一切"找回路径）。
///
/// 内容密钥额外用"托管密钥"再包一层并随同步上传。托管密钥由客户端在本地
/// 派生：Argon2id(同步账号密码 + 服务器下发的随机 pepper)，服务器不参与
/// 派生、也无法用库存数据直接解出任何密钥；pepper 只下发给通过鉴权的设备，
/// 用于抬高数据库泄露后的离线暴力破解成本。
class MemoEscrowService {
  MemoEscrowService._();

  static const int _iterations = 4;
  static const int _memoryKiB = 64 * 1024;
  static const int _lanes = 2;
  static const int _keyLength = 32;

  /// 当前是否具备开启托管的条件：已登录同步账号且服务器支持托管。
  static Future<bool> get isAvailable async {
    if (!SyncService.isLoggedIn) return false;
    if (SyncService.savedAccountPassword.isEmpty) return false;
    final supported = await AppDatabase.getSetting('serverSupportsLockSync');
    return supported == 'true';
  }

  /// 向服务器请求（或首次生成）当前用户的 pepper。
  static Future<String> fetchPepper() async {
    final serverUrl = await AppDatabase.getSetting('syncServerUrl');
    final token = await AppDatabase.getSetting('syncToken');
    if (serverUrl == null || serverUrl.isEmpty) {
      throw StateError('未配置同步服务器');
    }
    if (token == null || token.isEmpty) {
      throw StateError('请先登录同步账号');
    }
    final response = await http
        .get(
          Uri.parse('$serverUrl/api/escrow/pepper'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('获取托管 pepper 失败 (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    final pepper = data['pepper'];
    if (pepper is! String || pepper.isEmpty) {
      throw StateError('服务器返回的托管 pepper 无效');
    }
    return pepper;
  }

  /// 从账号密码 + pepper 派生托管密钥（与服务器参数无关，客户端固定）。
  static Future<Uint8List> deriveEscrowKey(
    String accountPassword,
    String pepper,
  ) =>
      deriveArgon2id(
        password: accountPassword,
        salt: Uint8List.fromList(utf8.encode(pepper)),
        iterations: _iterations,
        memoryKiB: _memoryKiB,
        lanes: _lanes,
        length: _keyLength,
      );

  /// 为文件夹锁开启账号托管（要求该文件夹已解锁）。
  static Future<void> enableForFolder(String folderId) async {
    final password = SyncService.savedAccountPassword;
    if (password.isEmpty) throw StateError('请先登录同步账号');
    final pepper = await fetchPepper();
    final escrowKey = await deriveEscrowKey(password, pepper);
    await MemoCryptoService.instance.enableEscrow(folderId, escrowKey);
  }

  /// 尝试用账号托管密钥解锁文件夹（"忘记一切"找回路径）。
  static Future<bool> unlockFolder(String folderId) async {
    final password = SyncService.savedAccountPassword;
    if (password.isEmpty) return false;
    try {
      final pepper = await fetchPepper();
      final escrowKey = await deriveEscrowKey(password, pepper);
      return await MemoCryptoService.instance.unlockFolderWithEscrow(
        folderId,
        escrowKey,
      );
    } catch (_) {
      return false;
    }
  }
}
