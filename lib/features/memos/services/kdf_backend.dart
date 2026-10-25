/// Argon2id 密钥派生后端（平台条件导入）。
///
/// - Web：hash-wasm（WASM SIMD，主线程约 300ms，异步 Promise 不冻结页面）；
/// - 原生（Windows/Android/Linux）与 VM 测试：hashlib（纯 Dart 优化实现，约 0.55s）。
///
/// 两者均为 RFC 9106 合规实现，输出与原 pointycastle 实现逐字节一致
/// （发布前已做对比测试：向量 416f6b02...）。
library;

export 'kdf_backend_stub.dart'
    if (dart.library.io) 'kdf_backend_io.dart'
    if (dart.library.js_interop) 'kdf_backend_web.dart';
