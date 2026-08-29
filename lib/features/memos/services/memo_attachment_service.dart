import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:focus_my_time/data/sync/sync_service.dart';

/// 备忘录附件网络服务。文件正文不进入同步 JSON，而是通过对象存储 API
/// 上传；本地数据库只保存对象键、大小、哈希和上传状态。
class MemoAttachmentService {
  MemoAttachmentService._();

  static final MemoAttachmentService instance = MemoAttachmentService._();

  Future<Map<String, dynamic>> upload({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    bool isPrivate = false,
  }) async {
    if (!SyncService.isLoggedIn) throw StateError('请先登录同步服务');
    final response = await http
        .post(
          Uri.parse('${SyncService.serverUrl}/api/storage/upload'),
          headers: {
            'Authorization': 'Bearer ${SyncService.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'filename': filename,
            'mimeType': mimeType,
            'contentBase64': base64Encode(bytes),
            'private': isPrivate,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw StateError(
        body is Map ? body['error']?.toString() ?? '附件上传失败' : '附件上传失败',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Uint8List> download(String objectKey) async {
    final response = await http.get(
      Uri.parse(
        '${SyncService.serverUrl}/api/storage/download/${Uri.encodeComponent(objectKey)}',
      ),
      headers: {'Authorization': 'Bearer ${SyncService.token}'},
    );
    if (response.statusCode != 200) throw StateError('附件下载失败');
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> usage() async {
    final response = await http.get(
      Uri.parse('${SyncService.serverUrl}/api/storage/usage'),
      headers: {'Authorization': 'Bearer ${SyncService.token}'},
    );
    if (response.statusCode != 200) throw StateError('无法读取服务器容量');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from((decoded as Map)['usage'] as Map);
  }

  Future<String> createShare({
    required String objectKey,
    DateTime? expiresAt,
    String? password,
  }) async {
    final response = await http.post(
      Uri.parse('${SyncService.serverUrl}/api/storage/shares'),
      headers: {
        'Authorization': 'Bearer ${SyncService.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'objectKey': objectKey,
        'expiresAt': expiresAt?.millisecondsSinceEpoch,
        'password': password,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('创建分享失败');
    }
    final decoded = jsonDecode(response.body) as Map;
    return decoded['token'] as String;
  }

  Future<void> revokeShare(String shareId) async {
    final response = await http.delete(
      Uri.parse('${SyncService.serverUrl}/api/storage/shares/$shareId'),
      headers: {'Authorization': 'Bearer ${SyncService.token}'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('撤销分享失败');
    }
  }
}
