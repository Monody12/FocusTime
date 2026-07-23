import 'dart:io';

import 'package:sqflite/sqflite.dart';

Future<bool> databaseFileExists(String path) => File(path).exists();

Future<void> ensureDatabaseOutputParent(String path) async {
  await File(path).parent.create(recursive: true);
}

Future<void> copyDatabaseFile(String sourcePath, String destinationPath) async {
  await File(sourcePath).copy(destinationPath);
}

Future<void> deleteDatabaseFileIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

Future<Database> openReadOnlyDatabaseFile(String path) {
  return openDatabase(path, readOnly: true);
}
