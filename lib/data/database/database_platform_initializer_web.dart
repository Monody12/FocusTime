import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> initializeDatabasePlatform() async {
  // SharedWorker initialization is unreliable on some browser environments.
  // The no-worker factory still stores SQLite data in IndexedDB via Wasm.
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
