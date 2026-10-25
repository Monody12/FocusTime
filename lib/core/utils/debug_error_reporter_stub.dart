/// 非 Web 平台的空实现。
void reportDebugError(String message) {}

/// 非 Web 平台的空实现（调试面包屑）。
void debugLog(String tag, String message) {}

/// 非 Web 平台：解锁会话恢复为空（桌面/移动端解锁耗时已由 hashlib 优化，
/// 且应用生命周期内会话常驻内存）。
Map<String, ({String keyBase64, int expiresAt})> restoreUnlockSessions() => {};

void persistUnlockSession(String folderId, String keyBase64, int expiresAt) {}

void forgetUnlockSession(String folderId) {}

void forgetAllUnlockSessions() {}
