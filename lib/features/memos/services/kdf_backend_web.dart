import 'dart:js_interop';
import 'dart:typed_data';

/// Web 平台：hash-wasm 的 Argon2id（WASM SIMD，29KB 单文件内嵌 WASM，
/// 由 web/index.html 加载为全局 `hashwasm`）。
///
/// 实测 Firefox 下同样参数从纯 Dart 的 90s+ 降到亚秒级；异步 Promise
/// 不冻结主线程，派生期间页面保持可交互。
@JS()
external JSObject get _hashwasm;

extension type _HashWasmModule._(JSObject o) implements JSObject {
  external JSPromise argon2id(JSObject options);
}

Future<Uint8List> deriveArgon2id({
  required String password,
  required Uint8List salt,
  required int iterations,
  required int memoryKiB,
  required int lanes,
  required int length,
}) async {
  final module = _hashwasm as _HashWasmModule;
  if (module.isUndefinedOrNull) {
    throw StateError('hash-wasm 未加载：index.html 缺少 hash-wasm-argon2.min.js');
  }
  final options = <String, JSAny?>{
    'password': password.toJS,
    'salt': salt.toJS,
    'parallelism': lanes.toJS,
    'iterations': iterations.toJS,
    'memorySize': memoryKiB.toJS,
    'hashLength': length.toJS,
    'outputType': 'binary'.toJS,
  }.jsify()! as JSObject;

  final result = await module.argon2id(options).toDart;
  return (result as JSUint8Array).toDart;
}
