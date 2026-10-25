/// 兜底后端（正常情况下 io/web 条件分支总能命中其一）。
import 'dart:typed_data';

Future<Uint8List> deriveArgon2id({
  required String password,
  required Uint8List salt,
  required int iterations,
  required int memoryKiB,
  required int lanes,
  required int length,
}) async =>
    throw UnsupportedError('Argon2id backend unavailable on this platform');
