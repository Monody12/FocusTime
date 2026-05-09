# FocusMyTime 开发者知识库 & 复盘记录

本文档记录了项目从 Electron 迁移至 Flutter 过程中的核心技术决策、踩坑记录及解决方案，用于后续开发参考。

## 1. 数据库与数据同步 (Synchronization)

### 1.1 增量同步协议 (Incremental Sync)
*   **核心逻辑**：采用 **LWW (Last-Write-Wins)** 策略，基于 `updated_at` 时间戳进行冲突解决。
*   **软删除 (Soft Deletion)**：
    *   所有 `delete` 操作必须转换为 `update` (设置 `deleted = 1`)。
    *   查询时务必增加 `where deleted = 0` 过滤条件。
    *   这是为了确保同步客户端能识别并传播“删除”状态。

### 1.2 数据库迁移 (Migrations)
*   **教训**：在开发环境下，直接在原有版本（如 version 2）的 `onUpgrade` 中修改 SQL 可能会因为用户数据库已处于该版本而导致代码不生效。
*   **最佳实践**：每次修改 Schema（如增加列）必须 **递增版本号 (version)**，并在 `onUpgrade` 中针对新版本编写 `ALTER TABLE` 语句。

### 1.3 数据序列化
*   **教训**：避免使用自定义的字符串拼接（如 `val1:val2;val3`）来存储复杂对象。
*   **解决方案**：统一使用标准的 `jsonEncode` 和 `jsonDecode`。这可以防止任务标题或备注中包含特殊字符（如 `:` 或 `;`）时导致数据解析崩溃。

## 2. Flutter 开发规范 (Best Practices)

### 2.1 导入管理 (Import Standardization)
*   **问题**：混合使用相对路径 (`import '../../...'`) 和包路径 (`import 'package:project/...'`) 会导致编译器认为同一个类（如 `AppDatabase`）属于两个不同的库，触发 "Ambiguous import" 错误。
*   **规范**：本项目统一使用 **`package:focus_my_time/...`** 格式进行导入。

### 2.2 异步操作与 UI 反馈 (Error Handling)
*   **问题**：异步操作（网络请求、数据库读写）如果不加 `try-catch` 保护，报错只会出现在控制台，用户在 UI 上看不到任何反馈，表现为“点击无效”或“程序卡死”。
*   **规范**：
    *   所有涉及外部 IO 的方法必须使用 `try-catch`。
    *   在 `catch` 块中使用 `ScaffoldMessenger.of(context).showSnackBar` 为用户提供即时反馈（红色表示失败，绿色表示成功）。

### 2.3 代码结构完整性
*   **注意**：在使用 AI 辅助编程或自动编辑工具时，务必检查类结构的完整性（如大括号闭合、方法签名是否被误删）。类结构的破坏会导致编译器产生误导性的错误提示（如 "static not allowed here" 或将方法调用误认为构造函数）。

## 3. 日历同步与权限 (Calendar Sync & Permissions)

### 3.1 Android 系统日历操作：UPDATE 优于 DELETE+INSERT

**问题现象**：
- 修改任务提醒时间后，系统日历出现重复日程（旧事件没被清除）
- 点击"X"取消提醒、删除任务后，系统日历中对应事件仍然残留
- 首次设置提醒能成功同步，但后续修改时间不再生效
- **关键线索**：Android 13 正常，Android 16 异常

**根因分析**：

`device_calendar` 插件的 `createOrUpdateEvent` 方法在 Android 端的实现（`CalendarDelegate.kt` 第 398-407 行）：
```kotlin
if (eventId == null) {
    // INSERT（创建新事件）
    val uri = contentResolver?.insert(Events.CONTENT_URI, values)
} else {
    // UPDATE（更新已有事件）
    contentResolver?.update(
        ContentUris.withAppendedId(Events.CONTENT_URI, eventId), values, null, null)
}
```
- 传入 `eventId` → 执行 **UPDATE**
- 不传 `eventId` → 执行 **INSERT**

旧代码采用的模式是「先 `deleteEvent` 删旧 → 再 `createOrUpdateEvent`（不带 eventId）建新」。这意味着每次修改都会触发一次 **DELETE 操作**。

Android 14 (API 34)+ 对 `ContentResolver.delete()` 施加了更严格的权限检查，Android 16 进一步收紧。当 `deleteEvent` 因权限/所有权检查被系统拦截（返回 `success: false`）后，旧代码仍然继续执行 INSERT → **旧事件还在，新事件又创建 → 产生重复**。

**修复方案**：

1. **修改提醒时间时**：直接传入已有 `eventId` 给 `Event()` 构造函数，让插件走 UPDATE 路径，完全跳过 DELETE 操作。只在 UPDATE 失败时回退到 DELETE+CREATE。

2. **取消提醒/删除任务时**：先尝试 `deleteEvent`，如果失败（Android 16 拦截），降级为通过 UPDATE 将事件状态标记为 `EventStatus.Canceled`，让日历应用隐藏该事件。

3. **增强日志**：在 `_ensureCalendar` 中记录日历初始化路径（复用/创建/回退），方便排查日历归属问题。

**教训**：
- 在调用第三方插件做 Android ContentProvider 操作时，**尽量避免 DELETE 操作**。优先使用 UPDATE 来实现修改和"软删除"。
- Android 版本越高，对系统内容提供器（Calendar、Contacts 等）的写操作限制越严格。需要关注 `targetSdk` 对应的行为变更。
- 插件 API 设计上，`createOrUpdateEvent` 本身就是为"有 ID 则更新、无 ID 则创建"设计的——应该善用这个特性，而不是自行维护「先删后建」的逻辑。

### 3.2 跨平台插件缺失：MissingPluginException

**问题现象**：
- Windows 桌面端热重启后控制台输出：`MissingPluginException (No implementation found for method hasPermissions on channel plugins.builttoroam.com/device_calendar)`
- AI 聊天中点击"批准"创建/修改任务时触发
- 不影响功能——任务正常创建，只是控制台有报错日志

**根因分析**：
调用链：`AiOperationEngine.execute()` → `TaskNotifier` → `ReminderService` → `CalendarService.hasPermissions()` → `device_calendar` 插件。`device_calendar` 是 Android/iOS 专属插件，Windows 平台没有对应的 `MethodChannel` 实现。每次任务变更时，`ReminderService` 都会尝试检查日历权限，在 Windows 上必然触发 `MissingPluginException`。

**为什么无害**：
- Flutter 的 `MethodChannel.invokeMethod()` 在平台无响应时抛出异常 → 被 `CalendarService` 的调用链自然吞掉
- `hasPermissions()` 返回 `isSuccess == false` → 后续日历同步逻辑被 `if (hasCalendarPermission)` 跳过
- 任务创建/修改的主体逻辑不受影响，纯属日志噪音

**修复方案**（可选优化）：
可以用 `Platform.isAndroid || Platform.isIOS` 在调用插件前做平台判断，避免不必要的 `MissingPluginException` 打印。但当前行为无害，优先级不高。

**教训**：
- 任何调用原生平台插件的代码，都应该预期在非目标平台（Windows/Linux/Web）上抛出 `MissingPluginException`
- 这类异常是 Flutter 跨平台开发的正常现象，不代表 bug
- 排查此类异常的关键是**追踪调用链**：从 UI 事件一路追到插件调用点
- 项目持久层（ReminderService）接入原生功能时，应在入口处加平台判断或 try-catch 静默

---

## 9. 同步触发覆盖审查：Settings 变更不触发同步

### 9.1 问题

排查发现项目中存在两种持久化机制：

| 数据 | 存储 | 同步到服务器 | 变更后触发同步 |
|---|---|---|---|
| 任务/清单/Sessions | SQLite (AppDatabase) | ✓ | ✓ (task_provider._triggerSync) |
| API Key、AI 配置 | SQLite settings 表 | ✓ (含在 payload) | ✗ **缺失** |
| 计时器配置（番茄钟、提醒等） | SharedPreferences | ✗ | ✗ |

`AppDatabase.setSetting()` 正确设置了 `updated_at`，记录会被纳入上传 payload。但 `DeepSeekApiClient.setApiKey()` 和 `AIChatProvider` 的 4 个保存方法保存后**从未调用同步**，意味着设置变更不会主动同步到服务器，只有等下一次任务/清单操作触发同步时才被顺带上传。

### 9.2 修复

- 在 `SyncService` 添加 `triggerBackgroundSync()` 方法，fire-and-forget 模式，异常静默
- `DeepSeekApiClient.setApiKey()` 和 `AIChatProvider` 所有持久化方法在保存后调用 `triggerBackgroundSync()`
- 实现 `startAutoSync()` / `stopAutoSync()` 周期性后台同步，登录后启动、登出时停止
- 应用启动时如果已登录，自动启动周期性同步

### 9.3 计时器配置不同步的说明

计时器配置（`TimerProvider._saveState`）存在 `SharedPreferences`，不经过 SQLite settings 表。这是有意为之——用户通常不需要在设备间同步番茄钟时长、是否启用声音等本地偏好。如果需要跨设备同步这些配置，需要将它们迁移到 `AppDatabase.setSetting()`。

### 9.4 教训

- **新增持久化调用时必须问：这里是否应该触发同步？**
- **双层存储（SharedPreferences + SQLite）是技术债**：新增开发者可能不知道该把数据往哪存，review 代码时应特别注意存储选型
- **settings 表有排除列表**（`SYNC_KEYS`）：`syncServerUrl`、`syncToken`、`syncUserId`、`lastSyncTime`、`syncDir`——这些是本地凭证，绝不能上传
- **后台同步必须是 fire-and-forget**：不 await、异常静默，绝不能让同步失败影响应用正常运行

---

## 10. AI 模型选择：Chat vs Reasoner

### 10.1 场景分析

FocusTimer 的 AI 助手主要做任务管理操作（增删改查），需要**秒级响应**。`deepseek-reasoner`（推理模型）的思考链需要 20-60 秒，用于任务管理会严重损害体验。

### 10.2 决策

- 默认使用 `deepseek-chat`（快速响应）
- 如果未来需要"帮我规划这周的任务优先级"这类多步分析，可以加一个可选开关让用户手动启用深度思考模式
- **不被模型营销术语误导**：用哪个模型取决于用户等待意愿，不是模型评测榜上的分数

---

## 11. 软件更新机制方案评估

### 11.1 方案对比

| 方案 | 隐私/不开源 | 用户体验 | 实施成本 |
|---|---|---|---|
| GitHub Releases（公开） | ❌ 必须开源 | 中 | 低 |
| GitHub Releases（私有+Token） | ❌ Token 泄露风险 | 差（需登录） | 中 |
| 自建更新服务器 | ✅ 完全自主 | 好（静默检查） | 中 |

### 11.2 推荐：自建更新服务器

复用现有 `1.12.46.222:6677` 服务器，新增两个端点：
- `GET /api/update/check?platform=android&version=10` — 返回最新版本信息
- `GET /downloads/<platform>/<file>` — 静态文件下载

客户端启动时静默检查，有更新弹非阻塞对话框，用户确认后下载并调起系统安装。

### 11.3 时机建议

对于单一开发者且功能仍在迭代的项目，**ADB 安装已经足够**。自动更新的价值随着用户数量增长而增长。建议核心功能稳定后再做。

---

*最后更新日期：2026-05-09*

## 4. 任务删除 Bug：异常导致乐观 UI 更新被跳过

### 4.1 问题现象

- Android 端删除任务后任务仍在列表中显示，不消失
- 列表剩余 >1 个任务时，需要手动同步任务才消失
- 列表仅剩 1 个任务时，无论怎么删除都不消失
- 手动同步后 Android 端任务消失，但 PC 端同步后任务可能还在

### 4.2 根因分析

**`deleteTask` 方法（`task_provider.dart:389`）的执行顺序存在致命缺陷：**

```dart
await AppDatabase.deleteTask(id);           // ✅ 成功
await ReminderService.cancelReminder(id);    // 💥 Android 上可能抛异常
await CalendarService.removeTask(eventId);   // 💥 Android 14+ 权限可能抛异常
// ↓ 以下代码在异常时永远执行不到 ↓
final tasks = state.tasks.where(...).toList();
state = state.copyWith(tasks: tasks, ...);   // 乐观 UI 更新
_triggerSync();                              // 同步触发
```

`cancelReminder`（调用原生 `flutter_local_notifications`）和 `CalendarService.removeTask`（调用原生 `device_calendar`）在 Android 端都可能因权限、系统版本等原因抛出异常。一旦异常发生，乐观 UI 更新和同步触发全部被跳过——任务在界面上纹丝不动，同步也不会执行。

**修复**：重构执行顺序，数据库操作 → 乐观 UI 更新 → 触发同步 紧密排列在前，提醒/日历清理移到最后并用 try-catch 保护。详见 `task_provider.dart` 当前 `deleteTask` 实现。

### 4.3 教训

- **异步操作的执行顺序至关重要**：关键操作（状态更新、UI 通知）必须放在可能失败的操作之前
- **原生平台调用必须用 try-catch 保护**：`flutter_local_notifications` 和 `device_calendar` 在 Android 不同版本上的行为不一致
- **乐观 UI 更新是最后一道防线**：即使后续操作失败，用户也能看到即时反馈

---

## 5. 数据库查询：遗漏 `deleted = 0` 过滤的系统性审查

### 5.1 问题

以下方法在查询/更新时未过滤 `deleted = 0`，可能操作已被软删除的"僵尸"记录：

| 方法 | 风险 |
|------|------|
| `getTaskById` | 可返回已删除任务，导致 `updateTask` 回落逻辑操作僵尸记录 |
| `updateTask` | 可更新已删除任务，刷新 `updated_at` 产生脏同步数据 |
| `toggleTaskComplete` | 可在已删除任务上切换完成状态 |
| `addToMyDay` / `removeFromMyDay` | 可修改已删除任务属性 |
| `getSessionsByTaskId` | 任务详情页显示已删除的专注记录 |
| `getRecurrenceCompletionsByDateRange` | 日期范围查询包含已删除的完成记录 |

### 5.2 修复

全部添加 `AND deleted = 0` 条件。

### 5.3 教训

- 软删除模式下，**每个查询和更新方法都必须检查是否过滤了 `deleted = 0`**
- 新加数据库方法时，这是最容易遗忘的约束
- 遗漏此过滤不会立即报错——它会在特定条件下（如某设备删除了任务，另一设备同步后尝试操作）悄悄产生错误行为

---

## 6. 同步层 Bug：服务器下载可能复活已删除任务

### 6.1 问题现象

- 多设备场景：Android 端删除任务后，PC 端同步时任务又出现

### 6.2 根因分析

`_applyTableChanges`（`app_database.dart:777`）处理服务器返回的非删除记录时：

```dart
row['deleted'] = 0;  // 无条件强制设置 deleted = 0！
await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
```

如果本地已软删除了某任务（`deleted = 1`, `updated_at = T2`），而服务器返回了该任务的旧版本（`deleted = false`, `updated_at = T1 < T2`），本地删除会被服务器旧版本"复活"。

### 6.3 修复

在插入非删除记录前，检查本地是否已有 `deleted = 1` 且 `updated_at` 更新的版本。若本地删除更新，跳过服务器的旧版本。

### 6.4 教训

- **LWW（Last Write Wins）策略必须在客户端也执行**：不能无条件信任服务器返回的数据
- **同步冲突解决应比较时间戳**：本地更新的操作（包括删除）不应被服务器旧版本覆盖
- **测试同步冲突场景**：特别是「设备 A 删除 → 设备 B 修改 → 同步」这种典型冲突

---

## 7. Windows 提醒 Bug：`Future.delayed` 无法取消

### 7.1 问题现象

- Windows 端修改任务提醒时间后，系统仍在原时间弹出提醒
- 用户设置了新提醒时间，但旧时间到了仍然收到通知

### 7.2 根因分析

`_scheduleWindows` 使用 `Future.delayed` 创建延时回调。`Future.delayed` **不支持 cancel()**——`cancelReminder` 只能从 `_windowsTimers` map 中移除条目，但无法阻止已创建的 Future 的回调触发。

更致命的是，修改提醒时间时的执行顺序：
1. `cancelReminder(task.id)` → 从 map 移除旧 Future-3PM（但无法真正取消它）
2. 创建新 Future-4PM → 以同一 `task.id` 写回 map
3. 下午 3:00 → 旧 Future-3PM 回调触发 → `_windowsTimers.containsKey(task.id)` 返回 **true**（新 Future-4PM 在第 2 步已写入）→ 误弹旧时间提醒

### 7.3 修复

将 `Future.delayed` 替换为 `Timer`。`Timer.cancel()` 是真正有效的取消——它阻止回调执行，不需要依赖 map 中的 key 是否存在来做去重判断。

### 7.4 教训

- **定时器/延时操作必须使用可取消的 API**：Dart 中 `Timer` 支持 `cancel()`，`Future.delayed` 不支持
- **去重检查（key exists in map）不能替代真正的 cancel**：在修改场景下，新值会覆盖同一 key，使检查失效
- **定时器相关的代码必须在修改时验证「旧回调是否会被触发」**：构建一个时间线 trace 来验证

---

## 8. 测试安全：测试绝不能操作真实数据库

### 8.1 问题

`test/clear_db_tool_test.dart` 是一个"清空数据库"的测试工具，它通过 `databaseFactoryFfi` 打开**真实 App 数据库文件**并执行：

```dart
await txn.delete('tasks');        // 全部任务
await txn.delete('sessions');     // 全部专注记录
await txn.delete('lists', where: 'is_system = 0');  // 全部自定义清单
```

每次运行 `flutter test` 都会清空用户的全部数据。这不是一个真正的测试——它是一个危险的生产数据销毁脚本。

### 8.2 解决方案

- **已删除该文件**。如需类似的测试辅助脚本，必须在测试专用数据库路径下运行
- `reminder_db_test.dart` 同样操作真实数据库，但它会清理自己创建的测试数据（create → test → soft delete）。仍需注意其副作用

### 8.3 教训

- **测试必须使用隔离的数据库文件**，绝不能复用生产数据库路径
- **任何能清除数据的脚本都应有显式的安全确认机制**
- **CI/CD 中运行的 `flutter test` 不应连接生产数据库**
- 给 `AppDatabase` 添加可配置的数据库路径（如 `setDatabasePath`）是更安全的长期方案
