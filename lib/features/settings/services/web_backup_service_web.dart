import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:focus_my_time/data/database/app_database.dart';

Future<void> exportWebBackup() async {
  final backup = await AppDatabase.exportBackup();
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup)));
  final now = DateTime.now();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final timestamp =
      '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_'
      '${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';

  await FilePicker.saveFile(
    dialogTitle: '导出浏览器备份',
    fileName: 'focus_my_time_backup_$timestamp.json',
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: bytes,
  );
}

Future<bool> importWebBackup() async {
  final result = await FilePicker.pickFiles(
    dialogTitle: '选择浏览器备份文件',
    type: FileType.custom,
    allowedExtensions: const ['json'],
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return false;

  final file = result.files.single;
  const maxBackupBytes = 50 * 1024 * 1024;
  if (file.size > maxBackupBytes) {
    throw const FormatException('备份文件超过 50 MB，无法在浏览器中安全导入');
  }
  final bytes = file.bytes;
  if (bytes == null) {
    throw const FormatException('无法读取备份文件内容');
  }

  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const FormatException('备份文件格式无效');
  }
  await AppDatabase.importBackup(Map<String, dynamic>.from(decoded));
  return true;
}
