import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';

/// AI 助手读取备忘录内容的唯一授权入口。
///
/// 未来任何把备忘录内容送入 AI 上下文的功能都必须经过这里：
/// - 未开启 `aiAllowed` 的备忘录一律拒绝；
/// - 隐私备忘录需要用户在当前会话中显式确认（[userConfirmed]），
///   且隐私保险库必须处于解锁状态；
/// - 只允许发送正文文本，图片与附件永远不会进入 AI 请求。
class MemoAiGate {
  MemoAiGate._();

  /// 返回可发送给 AI 的备忘录标题与正文。
  ///
  /// 未授权时抛出 [StateError]；解锁会话失效时返回 null。
  static Future<Map<String, String>?> contentForAi(
    String memoId, {
    required bool userConfirmed,
  }) async {
    final memo = await MemoDatabase.getMemo(memoId);
    if (memo == null || memo['deleted'] == true) {
      throw StateError('备忘录不存在');
    }
    if (memo['aiAllowed'] != true) {
      throw StateError('该备忘录未授权 AI 读取');
    }
    if (memo['isPrivate'] == true) {
      final crypto = MemoCryptoService.instance;
      if (!crypto.isUnlocked) return null;
      if (!userConfirmed) {
        throw StateError('隐私备忘录需要再次确认后才能发送给 AI');
      }
    }
    final title = memo['title'] as String? ?? '';
    final body = memo['bodyMd'] as String? ?? '';
    if (memo['isPrivate'] == true) {
      final payload = memo['encryptedPayload'] as String?;
      if (payload == null) return {'title': title, 'body': body};
      final decoded = MemoCryptoService.instance.decryptText(payload);
      final separator = decoded.indexOf('\u0000');
      return separator >= 0
          ? {
              'title': decoded.substring(0, separator),
              'body': decoded.substring(separator + 1),
            }
          : {'title': title, 'body': decoded};
    }
    return {'title': title, 'body': body};
  }
}
