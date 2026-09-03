import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:focus_my_time/features/memos/services/memo_image_service.dart';

class MarkdownImportData {
  const MarkdownImportData({required this.title, required this.body});

  final String title;
  final String body;
}

class MemoExportAttachment {
  const MemoExportAttachment({
    required this.id,
    required this.filename,
    required this.bytes,
  });

  final String id;
  final String filename;
  final Uint8List bytes;
}

class MemoMarkdownTransferService {
  MemoMarkdownTransferService._();

  static const maxImportBytes = 5 * 1024 * 1024;

  static MarkdownImportData decodeImport(String filename, Uint8List bytes) {
    if (bytes.length > maxImportBytes) {
      throw const FormatException('Markdown 文件超过 5 MB');
    }
    var body = utf8.decode(bytes, allowMalformed: false);
    if (body.startsWith('\uFEFF')) body = body.substring(1);
    final extension = RegExp(r'\.(?:md|markdown)$', caseSensitive: false);
    final rawTitle = filename.replaceFirst(extension, '').trim();
    return MarkdownImportData(
      title: rawTitle.isEmpty ? '导入的备忘录' : rawTitle,
      body: body,
    );
  }

  static String safeBaseName(String value, {String fallback = 'memo'}) {
    var result = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (result.length > 80) result = result.substring(0, 80).trimRight();
    const reserved = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    if (result.isEmpty) result = fallback;
    if (reserved.contains(result.toUpperCase())) result = '_$result';
    return result;
  }

  static Uint8List encodeMarkdown(String body) =>
      Uint8List.fromList(utf8.encode(body));

  static Uint8List encodeTyporaZip({
    required String title,
    required String body,
    required List<MemoExportAttachment> attachments,
  }) {
    final archive = Archive();
    final usedNames = <String>{};
    var rewrittenBody = body;
    for (final attachment in attachments) {
      final safeName = _uniqueFilename(attachment.filename, usedNames);
      final relativePath = 'assets/$safeName';
      rewrittenBody = rewrittenBody.replaceAll(
        '${MemoImageService.scheme}${attachment.id}',
        relativePath,
      );
      archive.addFile(ArchiveFile.bytes(relativePath, attachment.bytes));
    }
    archive.addFile(
      ArchiveFile.bytes(
        '${safeBaseName(title)}.md',
        utf8.encode(rewrittenBody),
      ),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  static Future<Uint8List> exportTyporaZip({
    required String memoId,
    required String title,
    required String body,
    required bool isPrivate,
  }) async {
    if (isPrivate && !MemoCryptoService.instance.isUnlocked) {
      throw StateError('请先解锁隐私保险库');
    }
    final rows = await MemoDatabase.getAttachments(memoId: memoId);
    final attachments = <MemoExportAttachment>[];
    for (final row in rows) {
      attachments.add(
        MemoExportAttachment(
          id: row['id'] as String,
          filename: MemoImageService.instance.attachmentFilename(row),
          bytes: await MemoImageService.instance.readAttachmentBytes(row),
        ),
      );
    }
    return encodeTyporaZip(title: title, body: body, attachments: attachments);
  }

  static String _uniqueFilename(String filename, Set<String> usedNames) {
    final dot = filename.lastIndexOf('.');
    final rawBase = dot > 0 ? filename.substring(0, dot) : filename;
    final rawExtension = dot > 0 ? filename.substring(dot + 1) : '';
    final base = safeBaseName(rawBase, fallback: 'attachment');
    final extension = rawExtension
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toLowerCase();
    var candidate = extension.isEmpty ? base : '$base.$extension';
    var suffix = 2;
    while (!usedNames.add(candidate.toLowerCase())) {
      candidate = extension.isEmpty
          ? '$base-$suffix'
          : '$base-$suffix.$extension';
      suffix++;
    }
    return candidate;
  }
}
