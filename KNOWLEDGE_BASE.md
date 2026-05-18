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

---

## 9. 同步触发覆盖审查：Settings 变更不触发同步

### 9.1 问题

项目中存在两种持久化机制：SQLite (AppDatabase) 和 SharedPreferences (TimerProvider)。Settings 表变更（API key、AI 配置）正确设置了 `updated_at` 会被纳入同步 payload，但保存后从不触发同步调用。

### 9.2 修复

- `SyncService.triggerBackgroundSync()` — fire-and-forget 后台同步
- `SyncService.startAutoSync()` / `stopAutoSync()` — 每 5 分钟周期性同步
- 所有 `AppDatabase.setSetting()` 调用点都加上了 `triggerBackgroundSync()`

### 9.3 教训

- 新增持久化操作时必须问：这里是否应该触发同步？
- 后台同步必须是 fire-and-forget，异常静默，不能阻塞 UI
- SharedPreferences（计时器配置）与 SQLite（业务数据）是两层存储，这是有意设计，但需注意不同步

---

## 10. AI 模型选择：Chat 优于 Reasoner

### 10.1 决策

任务管理 AI 助手默认使用 `deepseek-chat`。Reasoner 模型 20-60s 的思考延迟适合复杂规划，但对增删改查操作是不可接受的。未来可加"深度思考"可选开关。

---

## 11. 软件更新机制方案

自建更新服务器（复用 `1.12.46.222:6677`）是当前最佳选择。项目不开源，私有 GitHub Releases 有 Token 泄露风险。实现优先级低于核心功能。

---

## 12. Windows 提醒系统局限性

### 12.1 问题

Windows 任务提醒从 APP 生命周期的第一天就存在根本性局限：

| 场景 | Android (zonedSchedule) | Android (Calendar) | Windows |
|---|---|---|---|
| APP 运行中 | ✓ | ✓ | ✓ (Dart Timer) |
| APP 关闭 | ✓ | ✓ | ✗ **全部丢失** |
| APP 强制停止 | ✗ | ✓ | ✗ |
| 设备重启 | ✓ (BootReceiver) | ✓ | ✗ |
| 重启后未打开 APP | ✓ | ✓ | ✗ |

**根因：** `windows_notification` 插件（v1.3.0）只支持即时弹出 Toast，没有定时推送能力。所有 Windows 提醒都是 Dart 内存 `Timer`，APP 关闭即消失。

### 12.2 缓解措施

- 启动时 `refreshAll` 从数据库恢复所有未来提醒的 Timer
- 在 `refreshAll` 中检测过去 30 分钟内的提醒，弹出"错过了提醒"通知
- 提醒触发后自动清除数据库中的 `reminder_at`，防止死数据累积
- 数据库添加 `(deleted, completed, reminder_at)` 复合索引加速提醒查询

### 12.3 未来改进方向

- 集成 Windows Task Scheduler（需写原生 C++ 代码，处理 UAC 权限）
- 系统托盘最小化而非关闭（需 `system_tray` 包）
- 当前阶段：APP 需保持运行提醒才有效，这是已知局限

### 12.4 教训

- **跨平台功能的可用性差异必须明确记录**，否则用户会假设所有平台行为一致
- **提醒系统的可靠性取决于底层平台的调度能力**，Dart Timer 是最弱的一层
- **Android 日历是提醒最可靠的路径**，应优先引导用户开启日历同步

---

## 13. 提醒系统数据丢失事故复盘

### 13.1 问题现象

- 用户反馈"提醒时间全都没了"
- 45 个设有提醒的任务中，42 个的 `reminder_at` 被清空，仅 3 个幸存（未来时间或刚创建）
- 事故发生在 APP 重启后，由 `refreshAll` 触发

### 13.2 根因分析

`_doRefreshAll` 方法中存在以下逻辑：

```dart
if (reminderTime.isAfter(now)) {
  await scheduleUnifiedReminders(task);  // 未来 → 调度
} else if (Platform.isWindows && task.reminderAt! >= missedThreshold && _winNotifier != null) {
  // 过去 30 分钟 → 弹"错过"通知
} 
// ❌ 隐含行为：所有其他过去的提醒，reminder_at 保留在数据库中
```

但在之前的一个版本中，代码包含了：

```dart
// 过期提醒自动清理（已废弃，该逻辑非常危险）
await AppDatabase.updateTask(task.id, {'reminderAt': null});
```

这行代码对**所有过去时间**的提醒执行了清除操作。问题在于：

1. **没有区分"提醒已触发"和"提醒时间已过"**：APP 关闭期间错过的是"已过期但未触发"，重启后直接清除 = 用户数据丢失
2. **清理条件过于宽泛**：没有宽限期、没有二次确认，所有过去的提醒一律清除
3. **在初始化路径中执行破坏性操作**：`refreshAll` 是启动/同步后的恢复流程，不应承担数据清理职责

### 13.3 修复

- 立即移除 `refreshAll` / `_doRefreshAll` 中所有自动清除 `reminder_at` 的代码
- 保留唯一清除点：Windows `_scheduleWindows` 的 Timer 回调中（提醒实际弹出后才清除）
- Android `zonedSchedule` 由系统调度，不需要应用层清除
- 过期提醒不自动删除，保留用户数据完整性

### 13.4 教训

- **绝不能在初始化/恢复流程中自动删除用户数据**：`refreshAll` 的语义是"恢复"，不是"清理"
- **清理逻辑必须在提醒实际触发后执行**：只有用户收到了通知，才算提醒完成
- **任何自动删除用户数据的代码都需要明确的宽限期和用户可感知的反馈**
- **"所有过去的提醒"≠"所有已触发的提醒"**：APP 关闭期间错过的提醒，时间已过但未触发
- **修改涉及数据删除的代码时，先问自己：如果这里有 bug，最坏会丢什么？**

---

## 14. 提醒系统代码审查：发现的潜在问题

以下是在全面代码审查中发现的 17 个潜在问题（按严重程度分类）：

### Critical / High（已修复）

| # | 问题 | 位置 | 修复 |
|---|------|------|------|
| 1 | `sync()` 无条件调用 `refreshAll`，每次 auto-sync（5 分钟）都重调度 | task_provider.dart:303 | 已在 sync 中调用 refreshAll（保留，性能可接受） |
| 2 | `scheduleUnifiedReminders` 中日历 `syncTask` 失败后无回退 | reminder_service.dart:244 | 已添加 try-catch + 回退到通知 |
| 3 | `CalendarService.hasPermissions()` 桌面平台抛 MissingPluginException | calendar_service.dart:31 | 已添加 Platform 判断 + try-catch |
| 4 | `forceRebuildCalendar` 不更新 `updated_at`，同步不传播 | calendar_service.dart:221 | 已添加 `updated_at = ?` |
| 5 | Android `zonedSchedule` 前不 cancel，部分 OEM 重复通知 | reminder_service.dart:320 | 已添加 `await _androidPlugin.cancel(notificationId)` |
| 6 | `_scheduleWindows` 使用 `CalendarService.syncTask` 而非 `scheduleUnifiedReminders` | （历史代码） | 已统一使用 `scheduleUnifiedReminders` |

### Medium（已知限制，未修复）

| # | 问题 | 说明 |
|---|------|------|
| 7 | 时区降级仅支持 UTC+8 和 UTC | `initialize()` 中只有 `Asia/Shanghai` 硬编码 |
| 8 | 日历同步每个任务串行调用 OS API | 100 个任务 = 100 次系统调用，可考虑批量 |
| 9 | `getAllTasks()` 无分页 | 任务量极大时可能内存压力 |
| 10 | Windows 错过提醒 toast 可能重复弹出 | 如果 APP 多次重启，30 分钟窗口内的提醒每次都会弹 |
| 11 | `_androidPlugin` 是 static final，无法热替换 | 测试友好性差 |

### Low / 观察项

| # | 问题 | 说明 |
|---|------|------|
| 12 | iOS/macOS 日历同步路径无平台判断 | iOS 日历 API 行为与 Android 不同，`createCalendar` 可能失败 |
| 13 | Linux 提醒完全无支持 | 无 `windows_notification` 也无 `flutter_local_notifications` |
| 14 | `refreshAll` 中使用 `scheduleUnifiedReminders`（async），for 循环中串行 await | 大量任务时刷新慢，但比并发安全 |
| 15 | 数据库 reminder_at 过期值永不清除 | 设计决策：保护用户数据优先，未来可考虑"30 天以上自动清理" |
| 16 | Windows 的 `applicationId` 是 PowerShell GUID | 应替换为 APP 自身 GUID，当前无害但不够规范 |
| 17 | `_windowsTimers` Map 类型为 `Map<String, dynamic>` | 可以更精确地类型化为 `Map<String, Timer>` |

### 关键结论

当前提醒系统在以下条件下工作正常：
- Android：推荐开启日历同步（最可靠），zonedSchedule 为备选
- Windows：APP 必须保持运行，重启后从数据库恢复 Timer，30 分钟内错过的提醒会弹出通知
- 数据安全：不会自动删除用户的 `reminder_at`，仅在提醒实际弹出后清除

---

*最后更新日期：2026-05-17*

## 15. 跨设备同步后日历事件未创建（PC 创建任务，手机同步无日历）

### 15.1 问题现象

- 在 PC 端创建带提醒的任务，登录同一账号的手机端同步后，任务本身同步成功，但系统日历中没有对应事件
- 手动在手机上创建带提醒的任务，日历正常
- 手机端反复同步也无法补上缺失的日历事件

### 15.2 根因分析

**三个独立 bug 叠加导致：**

**Bug 1 — `syncTask` 返回 null 但 isSuccess=true（Critical）**

`calendar_service.dart:133`:
```dart
final result = await _calendarPlugin.createOrUpdateEvent(event);
if (result != null && result.isSuccess) {        // ← isSuccess=true 不足以说明成功
  return result.data;                              // ← data 可能为 null！
}
```

部分 Android 设备上，`createOrUpdateEvent` 返回 `isSuccess=true` 但 `data=null`（日历写入被系统拒绝但 API 认为"成功"）。原代码直接返回 `result.data`（即 null），调用方误认为"无 eventId"，后续判断 `eventId != task.calendarEventId` 跳过数据库更新，导致日历事件 ID 永远无法持久化。

**Bug 2 — `createTask` 创建后不持久化 eventId（High）**

`task_provider.dart:354`:
```dart
if (task.reminderAt != null) {
  ReminderService.scheduleUnifiedReminders(task);  // ← 异步调用，不 await
  // ← eventId 没有被写回数据库！
}
```

`createTask` 调用 `scheduleUnifiedReminders` 后没有等待其完成，也没有将返回的 eventId 写回数据库。新任务的 `calendarEventId` 始终为 null。同步到其他设备时，其他设备看到的仍是 null。

**Bug 3 — `sync()` 只对当前视图任务调用 `refreshAll`（Medium）**

`task_provider.dart:303`:
```dart
ReminderService.refreshAll(state.tasks);  // ← state.tasks 是当前视图过滤后的列表！
CalendarService.refreshAll(state.tasks);  // ← 不是所有有提醒的任务！
```

`loadTasks()` 的查询受 `state.currentViewType` 和 `state.currentListId` 控制。用户在"我的一天"视图时，`state.tasks` 只包含"我的一天"的任务（is_my_day=1）。其他清单（如"任务"）中有提醒的任务完全被跳过，`refreshAll` 不会为它们重建日历事件。

### 15.3 修复

1. **Bug 1**: 增加 `result.data != null` 检查，并添加详细日志输出 `result.errors`（便于排查日历写入被拒的原因）

2. **Bug 2**: `createTask` 中 await `scheduleUnifiedReminders`，将返回的 eventId 写回数据库：
   ```dart
   final eventId = await ReminderService.scheduleUnifiedReminders(task);
   if (eventId != null && eventId != task.calendarEventId) {
     await AppDatabase.updateTask(task.id, {'calendarEventId': eventId});
   }
   ```

3. **Bug 3**: 在 `sync()` 中改为加载所有有 reminder 的任务，同时在 `refreshAll` 内部，对于每个成功创建的 eventId 也写回数据库。

### 15.4 教训

- **第三方 API 返回值必须同时检查 `isSuccess` 和 `data` 是否为 null**：API 文档说"成功"不一定代表所有字段都有值
- **异步调用必须 await 并处理返回值**：fire-and-forget 适用于"通知用户成功、忽略失败"的场景，不适用于"需要持久化结果"的场景
- **同步后的刷新操作必须针对完整数据集**：不能依赖内存中可能被视图过滤的任务列表
- **日志要包含足够诊断信息**：当 `isSuccess=true` 但 `data=null` 时，只有 `result.errors` 能说明真相

---

*最后更新日期：2026-05-17*

---

## 16. 专注完成提示音与专注时长 Bug 修复

### 16.1 问题现象
- **提示音问题**：在 Windows 平台上，专注完成后本应循环播放闹钟铃声，但实际上只播放了一次系统默认的提示音。
- **专注时长问题**：在选择带有“预期时长”的任务后，如果处于非任务模式（如番茄模式），专注时长会被错误地覆盖为任务的预期时长，破坏了番茄钟的固定时长逻辑。
- **通知中时长显示为0**：在任务模式下，专注完成后的通知中显示“已专注 0秒”，即使实际专注了很长时间。

### 16.2 根因分析

**Bug 1 — Windows 提示音未循环且使用默认声音**
1. 原代码在 `triggerAlarm` 中排除了 Windows 平台调用 `audioplayers` 播放自定义铃声（`!Platform.isWindows`）。
2. 在 Windows 通知 XML 中，虽然尝试设置 `loop="true"`，但因为 `duration` 默认值为 `'long'`，导致 `scenario` 被设置为 `'reminder'` 或 `'default'`，而在 Windows 中，只有 `scenario="alarm"`（或在某些情况下 `reminder`）且配合特定的系统声音事件才能可靠地触发循环。
3. 用户期望使用 **Windows 系统默认的闹钟铃声** 且循环播放，而不是应用内置的 `alarm.wav`。

**Bug 2 — 专注时长被错误覆盖**
在 `timer_provider.dart` 的 `_doStartFocus` 方法中，存在以下逻辑：
```dart
if (taskExpectedMinutes != null && taskExpectedMinutes > 0 && effectiveMode != TimerMode.task) {
  totalSeconds = taskExpectedMinutes * 60;
}
```
这段代码导致了只要任务有预期时间，无论是番茄模式还是单核模式，都会强制使用任务的预期时间，完全破坏了番茄钟等模式的独立性。

**Bug 3 — 任务模式完成时时长被重置**
在 `_onComplete` 方法中，任务模式完成时会执行 `state = state.copyWith(..., totalSeconds: 0, ...)`。而通知触发方法 `_triggerCompletionNotification` 是在此之后调用的，它直接读取了已经变为 0 的 `state.totalSeconds`，导致显示错误。

### 16.3 修复方案

1. **Windows 提示音修复**：
   - 保持 Windows 平台不播放内置 `alarm.wav` 铃声的限制。
   - 在 `_sendActionableToast` 中，当 `duration != 'short'` 时，强制将 `scenario` 设置为 `alarm`。
   - 使用 Windows 系统 looping 声音源 `ms-winsoundevent:Notification.Looping.Alarm`，并设置 `loop="true"`。
2. **专注时长修复**：
   - 删除了 `timer_provider.dart` 中上述强制覆盖时长的 `if` 语句。现在各模式将严格遵循自身的时长逻辑。
3. **通知时长显示修复**：
   - 在 `_onComplete` 中状态更新前，先捕获 `totalSeconds` 的值。
   - 将捕获的时长传递给 `_triggerCompletionNotification`，确保通知能正确显示实际完成的时长。

### 16.4 教训
- **Windows 通知机制的特殊性**：Windows 的 Toast 通知对于循环声音有严格s 的 `scenario` 要求。在设计跨平台通知时，必须深入了解各平台的原生限制。
- **模式独立性原则**：在具有多种工作模式的应用中，各模式的参数应保持高内聚低耦合。避免跨模式的隐式覆盖逻辑。
- **状态更新与副作用的顺序**：在重置状态（如清零计数器）前，务必检查是否有后续操作（如发送通知）依赖于当前状态值。

*最后更新日期：2026-05-18*
