---
name: test-safety-no-real-db
description: 测试绝不能操作生产数据库，flutter test 会清除用户数据
type: feedback
---

测试文件绝不能使用生产数据库路径。`flutter test` 会运行所有测试，任何操作真实 `focus_my_time.db` 的测试都会破坏用户数据。

**Why:** `test/clear_db_tool_test.dart` 通过 `databaseFactoryFfi` 直接打开并清空了真实 App 数据库，每次 `flutter test` 都删除了用户全部任务/会话/清单。该文件已删除。

**How to apply:** 写新测试时，检查是否有直接操作数据库的代码。测试必须使用隔离的数据库路径。给 `AppDatabase` 添加可配置的数据库路径是长期方案。
