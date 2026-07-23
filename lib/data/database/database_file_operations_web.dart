import 'package:sqflite/sqflite.dart';

Never _unsupported() {
  throw UnsupportedError('浏览器环境不支持 SQLite 文件操作');
}

Future<bool> databaseFileExists(String path) async => false;

Future<void> ensureDatabaseOutputParent(String path) async => _unsupported();

Future<void> copyDatabaseFile(
  String sourcePath,
  String destinationPath,
) async => _unsupported();

Future<void> deleteDatabaseFileIfExists(String path) async => _unsupported();

Future<Database> openReadOnlyDatabaseFile(String path) async => _unsupported();
