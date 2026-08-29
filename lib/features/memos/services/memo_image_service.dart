import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/memos/services/memo_attachment_service.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';

/// 备忘录图片与附件的本地文件管理、压缩和上传队列。
///
/// - 本地文件保存在应用支持目录 `memo_attachments/<附件id>.<ext>`，
///   正文里通过 `memo-attachment://<附件id>` 引用。
/// - 插入时默认清理 EXIF 并压缩超大图（GIF 为保留动画不改写字节）。
/// - 私密附件上传前先用会话主密钥加密字节，服务端只保存密文。
/// - 上传队列：`uploadStatus = pending` 的附件在保存/登录后自动重试。
class MemoImageService {
  MemoImageService._();

  static final MemoImageService instance = MemoImageService._();

  static const scheme = 'memo-attachment://';
  static const _maxDimension = 2560;
  static const _supportedExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

  bool _flushing = false;

  static String extForMime(String mimeType) {
    switch (mimeType) {
      case 'image/png':
        return 'png';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'bin';
    }
  }

  Future<Directory> _attachmentDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}memo_attachments',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> localFile(String attachmentId, String mimeType) async {
    final dir = await _attachmentDir();
    return File(
      '${dir.path}${Platform.pathSeparator}$attachmentId.${extForMime(mimeType)}',
    );
  }

  /// 从 file_picker 结果落盘：清理 EXIF、压缩超大图并登记附件记录。
  Future<Map<String, dynamic>> saveImportedImage({
    required String filename,
    required Uint8List bytes,
    String? memoId,
    bool isPrivate = false,
  }) async {
    final ext = filename.toLowerCase().split('.').lastOrNull ?? '';
    if (!_supportedExtensions.contains(ext)) {
      throw const FormatException('仅支持 PNG、JPEG、WebP 或 GIF 图片');
    }
    final processed = _processImage(bytes, ext);
    final attachment = await MemoDatabase.createAttachment(
      memoId: memoId,
      filename: filename,
      mimeType: processed.mimeType,
      sizeBytes: processed.bytes.length,
      width: processed.width,
      height: processed.height,
      isPrivate: isPrivate,
      uploadStatus: 'pending',
    );
    if (isPrivate) {
      // 私密附件的文件名不落明文，用会话密钥加密保存。
      await MemoDatabase.updateAttachment(attachment['id'] as String, {
        'encryptedPayload':
            MemoCryptoService.instance.encryptBytes(utf8.encode(filename)),
      });
    }
    final file = await localFile(attachment['id'] as String, processed.mimeType);
    await file.writeAsBytes(processed.bytes, flush: true);
    return attachment;
  }

  _Processed _processImage(Uint8List bytes, String ext) {
    if (ext == 'gif') {
      // GIF 动画重编码会丢帧，保持原始字节；宽高取第一帧。
      final frame = img.decodeGif(bytes, frame: 0);
      return _Processed(
        bytes: bytes,
        mimeType: 'image/gif',
        width: frame?.width,
        height: frame?.height,
      );
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('无法解析该图片');
    var image = decoded;
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > _maxDimension) {
      final ratio = _maxDimension / longest;
      image = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
      );
    }
    // 重编码同时完成 EXIF 清理：PNG 保持无损与透明通道，其余压成 JPEG。
    if (ext == 'png') {
      return _Processed(
        bytes: Uint8List.fromList(img.encodePng(image)),
        mimeType: 'image/png',
        width: image.width,
        height: image.height,
      );
    }
    return _Processed(
      bytes: Uint8List.fromList(img.encodeJpg(image, quality: 88)),
      mimeType: 'image/jpeg',
      width: image.width,
      height: image.height,
    );
  }

  /// 解析正文里的 `memo-attachment://<id>` 引用为可显示的 ImageProvider。
  Future<ImageProvider?> resolveProvider(String href) async {
    if (!href.startsWith(scheme)) return null;
    final id = href.substring(scheme.length);
    final attachment = await MemoDatabase.getAttachment(id);
    if (attachment == null) return null;
    final file = await localFile(
      id,
      attachment['mimeType'] as String? ?? 'image/png',
    );
    if (file.existsSync()) {
      return FileImage(file);
    }
    // 本地文件缺失（例如换设备）且已上传时，从服务器下载。
    final storageKey = attachment['storageKey'] as String?;
    if (storageKey == null || storageKey.isEmpty) return null;
    try {
      var bytes = await MemoAttachmentService.instance.download(storageKey);
      if (attachment['isPrivate'] == true) {
        bytes = _unwrapPrivateBytes(bytes);
      }
      await file.writeAsBytes(bytes, flush: true);
      return FileImage(file);
    } catch (_) {
      return null;
    }
  }

  Uint8List _unwrapPrivateBytes(Uint8List stored) {
    final decoded = jsonDecode(utf8.decode(stored));
    if (decoded is! Map || decoded['encrypted'] != true) {
      throw const FormatException('私密附件格式无效');
    }
    return MemoCryptoService.instance.decryptBytes(decoded['content'] as String);
  }

  /// 刷新上传队列。返回 null 表示全部成功或无网络会话，否则返回失败提示。
  Future<String?> flushUploadQueue() async {
    if (!SyncService.isLoggedIn || _flushing) return null;
    _flushing = true;
    final failures = <String>[];
    try {
      final pending = (await MemoDatabase.getAttachments())
          .where(
            (a) =>
                a['uploadStatus'] == 'pending' &&
                a['deleted'] == false &&
                a['memoId'] != null,
          )
          .toList();
      for (final attachment in pending) {
        try {
          await _uploadAttachment(attachment);
        } catch (error) {
          failures.add('${attachment['filename'] ?? '附件'}：$error');
        }
      }
    } finally {
      _flushing = false;
    }
    return failures.isEmpty ? null : failures.join('\n');
  }

  Future<void> _uploadAttachment(Map<String, dynamic> attachment) async {
    final id = attachment['id'] as String;
    final mimeType =
        attachment['mimeType'] as String? ?? 'application/octet-stream';
    final file = await localFile(id, mimeType);
    if (!file.existsSync()) {
      throw StateError('本地文件不存在');
    }
    final isPrivate = attachment['isPrivate'] == true;
    final bytes = await file.readAsBytes();
    Uint8List uploadBytes;
    if (isPrivate) {
      uploadBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'encrypted': true,
            'content': MemoCryptoService.instance.encryptBytes(bytes),
          }),
        ),
      );
    } else {
      uploadBytes = bytes;
    }
    final result = await MemoAttachmentService.instance.upload(
      filename:
          attachment['filename'] as String? ??
          (isPrivate ? 'private-attachment' : 'attachment'),
      mimeType: mimeType,
      bytes: uploadBytes,
      isPrivate: isPrivate,
    );
    final storageKey =
        result['objectKey']?.toString() ?? result['key']?.toString();
    if (storageKey == null || storageKey.isEmpty) {
      throw StateError('服务端未返回对象键');
    }
    await MemoDatabase.updateAttachment(id, {
      'storageKey': storageKey,
      'uploadStatus': 'uploaded',
    });
  }

  /// 手动重试单个附件上传。
  Future<void> retryUpload(String attachmentId) async {
    final attachment = await MemoDatabase.getAttachment(attachmentId);
    if (attachment == null) return;
    await _uploadAttachment(attachment);
  }
}

class _Processed {
  const _Processed({
    required this.bytes,
    required this.mimeType,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int? width;
  final int? height;
}
