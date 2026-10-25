import 'dart:typed_data';

import 'package:hashlib/hashlib.dart';

/// 原生平台（Windows/Android/Linux/VM 测试）：hashlib 优化版 Argon2id。
Future<Uint8List> deriveArgon2id({
  required String password,
  required Uint8List salt,
  required int iterations,
  required int memoryKiB,
  required int lanes,
  required int length,
}) async {
  final digest = Argon2(
    type: Argon2Type.argon2id,
    version: Argon2Version.v13,
    parallelism: lanes,
    memorySizeKB: memoryKiB,
    iterations: iterations,
    hashLength: length,
    salt: salt,
  ).convert(password.codeUnits);
  return Uint8List.fromList(digest.bytes);
}
