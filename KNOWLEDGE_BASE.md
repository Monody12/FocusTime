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

Android 14 (API 34)+ 对部分系统 ContentProvider 操作有更严格的权限/所有权校验；在部分 Android 16 或 OEM 日历实现上，`deleteEvent` 更容易返回失败或被系统拦截。官方 Android 16 行为变更文档没有声明“第三方应用不能修改/删除自己写入的日历事件”，Calendar Provider 文档仍然说明具备 `WRITE_CALENDAR` 权限的应用可以 insert/update/delete。实际风险来自插件实现和系统 Provider 细节：当 `deleteEvent` 失败后旧代码仍然继续执行 INSERT → **旧事件还在，新事件又创建 → 产生重复**。

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

### 3.3 Android 16 日历提醒重复：避免删除 Reminders 子表

**问题现象**：
- Android 16 上修改任务提醒时间后，系统日历出现新的事件或旧提醒时间仍然存在。
- 删除应用内提醒后，系统日历事件可能没有被删除。
- 添加提醒后再次手动同步，可能显示“同步失败或未配置”；退出重登或删除提醒也无法恢复，只能清除应用数据。
- Android 13 与 Windows 路径正常。

**联网核对结论**：
- Android Calendar Provider 官方文档仍然支持 `Events` 的 query/insert/update/delete，前提是应用拥有 `WRITE_CALENDAR` 等权限。
- Android 16 官方行为变更文档没有列出“禁止第三方应用修改或删除自己创建的日历事件”的限制。
- `CalendarContract.Events` 文档说明普通应用删除事件时通常是设置 `deleted` 标记，真正硬删除更偏向 sync adapter 场景。因此不能把 Android 16 上的失败简单归因于“系统完全不允许改删”。

**根因分析**：

`device_calendar` 的 Android 更新路径虽然会对 `Events` 执行 UPDATE，但同步提醒子项时仍可能先删除旧 `Reminders` 再插入新 `Reminders`。在 Android 16/OEM 日历 Provider 上，这类对子表的 delete 可能失败，从而让整个更新流程失败；调用层随后如果回退到新建事件，就会造成旧时间残留或重复事件。

另一个触发点是 `calendar_event_id` 属于本机外部系统引用，不能作为跨设备业务字段同步。把它写入任务并推进 `updated_at`，会把本机日历后处理变成一次业务同步，进而放大同步失败或并发同步的概率。

**修复方案**：

1. Android 改用项目自有原生 `MethodChannel` 写 Calendar Provider：
   - 修改提醒时间：直接 UPDATE `Events.CONTENT_URI/{eventId}`，不改变 `CALENDAR_ID`。
   - 更新 reminders：查询已有 reminders 后优先 UPDATE/INSERT，只有多余子项才 best-effort DELETE；删除失败不让主事件更新失败。
   - 删除事件：按 app delete → sync-adapter delete → UPDATE 标记 `STATUS_CANCELED` 并移到当前时间的顺序降级。

2. `calendar_event_id` 改成本机私有字段：
   - 新增 `updateTaskCalendarEventId()`，只更新本机事件 ID，不刷新 `updated_at`。
   - 同步 payload 不因本机事件 ID 变化而产生脏任务。

3. 同步完成后的提醒/日历刷新改为后处理：
   - 后处理失败只记录日志，不把已经成功的业务同步显示为失败。
   - 正在进行后台同步时，手动同步等待同一个同步结果，不再立刻返回“未配置/失败”。

**教训**：
- 对系统日历这类外部 Provider，主业务同步与本机集成后处理必须解耦。
- UPDATE 主事件比 DELETE+INSERT 更可靠；对子表也应尽量 UPDATE/INSERT，DELETE 只能作为 best-effort。
- `calendar_event_id`、通知 ID、平台权限状态等都属于本机状态，不能推进业务数据的同步时间戳。

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

*最后更新日期：2026-06-10*

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

---

## 17. macOS Ventura 通知、日历与数据库备份适配修复

### 17.1 问题现象
- macOS 设置页中”检查权限””发送测试通知””测试系统闹钟””测试日历同步”等按钮点击后无明显效果，或返回失败但缺少可诊断原因。
- 任务提醒在 macOS 上不能稳定触发类似闹钟的响铃体验。
- 数据库导入/导出直接复制主 `.db` 文件，存在 SQLite WAL 数据未 checkpoint 导致备份不完整、恢复后数据不是预期结果的风险。

### 17.2 根因分析
1. **通知权限模型混用**：macOS 端未注册 `permission_handler_apple`，但提醒服务使用 `Permission.notification` 判断权限，容易得到 `MissingPluginException` 或错误状态。macOS 应使用 `flutter_local_notifications` 的 `MacOSFlutterLocalNotificationsPlugin.checkPermissions/requestPermissions`。
2. **日历插件契约不一致**：`device_calendar` 不提供 macOS 实现，项目新增 EventKit MethodChannel 后用 `dynamic` 伪装成同一插件接口，导致方法签名、错误信息和返回值不一致时容易被吞掉。
3. **EventKit 版本差异**：Ventura 使用 `requestAccess(to: .event)`，新版 macOS 使用 full access API；权限状态和回调需要按系统版本处理。
4. **SQLite 备份不一致**：启用 WAL 时，最新事务可能在 `focus_my_time.db-wal` 中；只复制 `focus_my_time.db` 可能得到旧数据或半完整备份。
5. **macOS 通知展示不完整**：DarwinNotificationDetails 缺少 `presentBanner` 和 `presentList` 参数，导致通知在 macOS 上只以弹窗形式出现，不在横幅和通知中心列表中显示。

### 17.3 修复方案
1. **通知/闹钟**：
   - macOS 通知权限改为通过 `flutter_local_notifications` 的 macOS 平台实现检查与请求。
   - macOS 测试闹钟使用系统通知 + 应用内响铃（`TimerNotificationService.triggerAlarm`），符合 macOS 平台限制。
   - 为 macOS 任务提醒增加应用运行期间的 `Timer` 响铃补充（`_scheduleMacOsAlarmTimer`），同时保留系统 `zonedSchedule` 通知调度。
   - 所有 DarwinNotificationDetails 统一添加 `presentBanner: true, presentList: true`。
2. **日历同步**：
   - `CalendarService` 改为显式分发 Android `DeviceCalendarPlugin` 与 macOS `MacOsCalendarPlugin`，避免 `dynamic` 隐藏契约错误。
   - 新增 `macos_calendar_plugin.dart`：通过 MethodChannel 桥接 EventKit，返回与 `device_calendar` 相同的 `Result<T>` 类型。
   - `MainFlutterWindow.swift` 中注册 `com.focusmytime.calendar` channel，实现 hasPermissions / requestPermissions / retrieveCalendars / createCalendar / createOrUpdateEvent / deleteEvent / deleteCalendar 全部 7 个方法。
   - macOS EventKit 桥接支持 Ventura（`requestAccess(to: .event)`）与 Sonoma+（`requestFullAccessToEvents`）权限 API，并增强时间戳参数解析与错误返回。
   - macOS 同步优先创建/复用 `FocusMyTime 提醒` 专用日历。
3. **数据库导入/导出**：
   - 导出前执行 `PRAGMA wal_checkpoint(TRUNCATE)` 并关闭数据库连接，再复制主库文件。
   - 导入前校验备份文件版本号和必要表（lists, tasks, sessions, settings），导入时关闭连接、清理 WAL/SHM/journal sidecar，再覆盖数据库并重新加载任务、提醒和日历同步。
   - 新增 `file_picker` 依赖，设置页实现完整的文件选择器导入/导出流程。

### 17.4 技术细节

**macOS EventKit 权限兼容性矩阵**：

| macOS 版本 | 权限 API | 授权状态枚举 |
|---|---|---|
| 10.14 及更早 | 无需权限 | N/A |
| 10.15 ~ 13.x (Ventura) | `requestAccess(to: .event)` | `.authorized` |
| 14.0+ (Sonoma) | `requestFullAccessToEvents` | `.fullAccess` / `.writeOnly` / `.authorized` |

**macOS 闹钟实现策略**：
- 系统通知（`zonedSchedule`）：APP 退出后仍可触发，但无循环铃声
- 应用内 Timer（`_scheduleMacOsAlarmTimer`）：APP 运行时补充循环铃声，退出后失效
- 两者并行，确保提醒时刻 APP 运行中时有完整闹钟体验

**SQLite WAL 备份流程**：
1. `PRAGMA wal_checkpoint(TRUNCATE)` — 将 WAL 日志合并到主库
2. `close()` — 释放文件句柄
3. `File.copy()` — 安全复制完整数据库
4. `database` getter — 重新打开连接

### 17.5 教训
- **跨平台插件不能只看 Dart API 名字**：同一个权限概念在 Android、Windows、macOS 上可能由完全不同的插件或系统能力承载。`permission_handler` 在 macOS 上无实现，必须用 `flutter_local_notifications` 的平台实现。
- **桌面平台要显式处理原生桥接错误**：MethodChannel 失败要返回可见错误，不能让 UI 只收到 `false`。
- **SQLite 备份必须考虑 WAL**：生产级导入/导出不能直接复制主数据库文件，必须先 checkpoint。
- **macOS 通知需要完整配置 DarwinNotificationDetails**：`presentBanner` 和 `presentList` 缺失会导致通知不在横幅和通知中心显示，用户可能以为通知没发出。

---

## 18. MaterialApp 结构重构：ProviderScope 层级调整

### 18.1 问题
原代码中 `MaterialApp` 在 `FocusMyTimeApp`（ConsumerStatefulWidget）的 `build` 方法内创建，导致 `themeProvider` 的 `ref.watch` 必须在 `MaterialApp` 之上才能生效，但 `MaterialApp` 本身就是 `build` 的返回值。

### 18.2 修复
将 `MaterialApp` 上移到 `main.dart` 的 `ProviderScope > Consumer` 中，`FocusMyTimeApp` 改为返回 `CallbackShortcuts > mainContent`（不再包裹 MaterialApp）。

```dart
// main.dart — MaterialApp 在 ProviderScope 内部
ProviderScope(
  child: Consumer(
    builder: (context, ref, child) {
      final themeMode = ref.watch(themeProvider);
      return MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: const FocusMyTimeApp(),
      );
    },
  ),
);
```

### 18.3 教训
- **MaterialApp 应在 ProviderScope 内部但 Consumer 外部或内部均可**，关键是确保 `ref.watch` 能访问到 Provider。
- **FocusMyTimeApp 不再需要关心主题/路由**，职责更清晰：只负责侧边栏 + 内容区布局和键盘快捷键。

---

## 19. setState 中的闭包捕获警告修复

### 19.1 问题
`task_detail_page.dart` 中 `setState` 回调内直接使用了外层 `async` 方法中可能为 null 的 `task` 变量，Dart 静态分析器发出 `unnecessary_null_comparison` 警告。

### 19.2 修复
在 `setState` 调用前，先将 `task` 捕获到一个 `final currentTask = task` 局部变量中，确保 `setState` 内引用的是一个确定非空的值。

```dart
// 修复前
if (task != null && mounted) {
  setState(() {
    _titleController.text = task.title; // ⚠️ task 可能在 async gap 后为 null
  });
}

// 修复后
if (task != null && mounted) {
  final currentTask = task; // 捕获到局部变量
  setState(() {
    _titleController.text = currentTask.title; // ✅ 确定非空
  });
}
```

### 19.3 教训
- **async 方法中使用 `mounted` 检查后，变量仍可能被重新赋值**：`setState` 回调是延迟执行的，回调闭包捕获的是变量引用而非值。
- **在 `setState` 调用前用 `final` 局部变量捕获异步结果**：这是 Dart async/await 与 Flutter setState 搭配使用的标准安全模式。

---

## 20. 跨平台设置页的平台守卫模式

### 20.1 问题
设置页中”精确闹钟””电池优化”等按钮在 macOS 上点击后无效果或报错，因为这些功能是 Android 专属的。

### 20.2 修复模式
对每个平台专属操作添加 `Platform.isXxx` 判断，非目标平台显示提示 SnackBar：

```dart
onPressed: () async {
  if (Platform.isAndroid) {
    await ReminderService.requestExactAlarmPermission();
  } else {
    _showSnackBar('精确闹钟权限仅在 Android 平台上需要');
  }
},
```

### 20.3 教训
- **桌面端不应暴露移动端专属的权限操作**：或者至少给出明确的”当前平台不需要此操作”反馈。
- **所有异步操作都需要 try-catch**：设置页的按钮回调中统一添加了错误捕获和 SnackBar 反馈，避免静默失败。

---

## 21. Windows 平台运行崩溃与 Flutter SDK 降级适配 (Windows DLL Load Crash & Theme Mismatch)

### 21.1 问题现象
- 使用 Flutter 3.22.3 (适配 macOS Ventura SDK 限制) 时，编译 Windows 报错，提示找不到 `CardThemeData`。
- Windows 平台在启动时发生 Native Crash (进程退出码 `0xC0000139` / `STATUS_ENTRYPOINT_NOT_FOUND` / 找不到入口点)。

### 21.2 根因分析
1. **CardThemeData 编译报错**：`CardThemeData` 是较新 Flutter 版本才引入的。在 Flutter 3.22.3 下，CardTheme 的配置类是 `CardTheme` 而不是 `CardThemeData`。
2. **Windows DLL 入口点缺失**：在 Windows 10 LTSC (21H2) 系统中，系统内置的 `icu.dll` 并不包含 `ucal_getHostTimeZone` 函数。`flutter_timezone` 插件的 v2.x.x+ 版本在 Windows 下编译时使用了较新的 Windows SDK API，该 API 在运行时会加载此缺失的符号，从而导致程序运行时载入 DLL 失败 (ERROR_PROC_NOT_FOUND / 错误 127 / 状态码 `0xC0000139`)。
3. **时区库版本限制**：尝试升级 `flutter_timezone` 到 `v5.x.x` 受到 `meta` 版本限制（v5.x.x 要求 `meta >= 1.16.0`），而 Flutter 3.22.3 固定依赖了 `meta 1.12.0`。

### 21.3 修复方案
1. **修改时区依赖**：在 `pubspec.yaml` 中将 `flutter_timezone` 升级为 `^4.1.1`。该版本已包含完整的 Windows 支持，且不依赖高于 `1.12.0` 的 `meta`，同时避开了旧版 icu.dll 动态链接缺失函数的问题，兼顾了 Windows 10 LTSC 兼容性与 Flutter 3.22.3 SDK 限制。
2. **替换 CardThemeData 为 CardTheme**：在 `lib/core/theme/app_theme.dart` 中，将 `CardThemeData` 替换为 `CardTheme`，确保在 Flutter 3.22.3 (macOS Ventura + Xcode 15.2 兼容版本) 下能够顺利通过编译。

### 21.4 教训
- 在适配特定低版本系统（如 macOS Ventura）降级 Flutter SDK 时，必须同步检查第三方依赖在不同目标平台（如 Windows 10 LTSC 物理机）上的行为差异。
- 时区插件等涉及 Native / FFI 装载的项目，应通过独立的测试脚本（如 `DynamicLibrary.open`）来排查原生 DLL 的加载问题，防止 Native crash 导致 Flutter 无法捕获堆栈。
- 多设备开发中，对于被 SDK 严格锁定的 Transitive 依赖 (如 `meta`)，应找到能平衡各端限制的兼容版本（如 `flutter_timezone 4.1.1`）。

*最后更新日期：2026-05-29*

---

## 24. AI 创建任务误判清单不存在

### 24.1 问题现象
- AI 创建任务时反复提示需要先创建任务清单。
- 即使目标清单已经存在，AI 仍可能生成 `create_list` 操作。
- 用户点击“全部批准”后，重复创建清单的校验失败会阻断后续 `create_task`，导致任务无法创建。

### 24.2 根因分析
1. AI 上下文直接读取当前 `taskProvider` 状态；如果清单仍在异步加载中，系统提示里的“任务清单”可能为空，模型会误判目标清单不存在。
2. `create_list` 本地校验把“清单已存在”当作失败处理。AI 常会先生成 `create_list` 再生成 `create_task`，重复清单失败后会让批量批准提前终止。
3. `create_task` 的 `listId` 虽然允许传清单名，但校验只按 ID 判断，容易把已存在的清单名当作不存在。

### 24.3 修复方案
1. 发送 AI 消息前，如果清单状态为空，先调用 `loadLists()`，确保提示词包含已有清单。
2. 强化系统提示：目标清单已存在时必须直接使用清单 ID，不要调用 `create_list`；日期清单已存在时直接写入该清单 ID。
3. 将 AI `create_list` 变成幂等操作：清单已存在时直接复用，不再阻断后续任务创建。
4. `create_task` 和 `move_to_list` 统一通过 ID 或名称解析清单引用；创建任务时可直接指定目标清单，避免先创建到当前清单再移动。

### 24.4 教训
- AI 工具调用必须对模型的冗余步骤有容错，尤其是 `create_*` 这类容易重复生成的操作。
- 提示词要给模型明确的“已有资源复用”规则，但本地执行层也必须兜底，不能依赖模型始终遵守。
- 构造 AI 上下文前应确保关键状态已加载，否则空上下文会把正确数据变成错误推理。

*最后更新日期：2026-06-12*

---

## 23. Windows Release 安装包缺失 sqlite3.dll

### 23.1 问题现象
- GitHub Actions 生成的 Windows 安装包可以正常安装。
- 安装后首次启动即进入红屏错误页，提示 `Failed to load dynamic library 'sqlite3.dll'`，错误码为 126。
- 同一台开发机上直接运行开发环境或旧构建目录不一定复现，因为开发模式可以从 Pub Cache 或本机环境找到 SQLite 动态库。

### 23.2 根因分析
`sqflite_common_ffi` 在 Windows debug/development 模式可以使用包内调试用的 `sqlite3.dll`，但 Windows release 模式要求 `sqlite3.dll` 位于 exe 同目录。原安装包脚本只打包 `build/windows/x64/runner/Release`，而该目录没有 SQLite 原生库，导致安装后的独立环境无法加载 FFI 动态库。

### 23.3 修复方案
在 `pubspec.yaml` 添加 `sqlite3_flutter_libs` 作为直接依赖，让 Flutter Windows 插件构建流程自动把 SQLite 原生库作为 bundled library 复制到 release 输出目录。Inno Setup 继续打包 `build/windows/x64/runner/Release/*`，即可随安装包携带 `sqlite3.dll`。

### 23.4 教训
- FFI/Native 依赖不能只验证开发机运行，必须验证安装后的独立目录运行。
- Windows Flutter release 包要检查 exe 同级目录是否包含所有 Native DLL，尤其是 SQLite、通知、时区、音频等插件依赖。
- 对 GitHub Release 安装包问题，优先复现“安装后的目录”，不要只看 `flutter run` 或开发机 PATH。

*最后更新日期：2026-06-03*

---

## 22. 密码同步本地加密与密码显示功能 (Encrypted Local Password Sync & Visibility Toggle)

### 22.1 问题现象
- 记住密码功能在登录或注册成功后，为了界面美观及隐私保护显示的是虚拟密码 `••••••••`，而真实的密码在客户端本地并未进行持久化。
- 当用户登录 Token 过期（Session 过期）需要重新登录时，密码框内仍然默认填充着 `••••••••`，用户直接点击"登录"会把该假密码字符串发送到服务器，导致一直提示登录失败。
- 密码框无显示明文（眼睛图标）功能，用户也无法在不知道原密码的情况下直接通过点击登录来恢复 Session，体验十分糟糕。

### 22.2 根因分析
1. 之前的设计只保存了 `syncToken`、`syncUserId` 和 `syncFakePassword`，导致真实的明文密码根本没有在本地存留。
2. 即使有 Session 过期，点击登录时，客户端没有逻辑去自动将 `••••••••` 替换为真实的密码发送，导致直接把掩码当做真实密码上传。
3. 输入框没有眼睛图标控制 `obscureText` 的布尔值，无法切换显隐状态。

### 22.3 修复方案
1. **密码本地加密存储**：在 `SyncService` 中实现基于 Base64 + XOR 的轻量级本地混淆加密与解密算法（使用 `FocusMyTimeSecretKey!` 作为 Key），将真实的密码加密后，在登录/注册成功后以 `syncRealPassword` 为键保存到 SQLite `settings` 表中。
2. **登出彻底清理**：在用户主动登出（logout）时，连同 `syncRealPassword` 一并从数据库和内存缓存中彻底清空。
3. **明文切换与自动解密填充**：
   - 扩展 `_buildTextSetting` 支持传入 `isPassword` 及 `onPasswordVisibilityToggle` 回调，增加精致的 InkWell 眼睛切换按钮。
   - 当眼睛按钮点击、密码框显示为明文状态，且当前文本内容是假密码掩码 `••••••••` 时，自动将其替换为解密后的真实明文密码展示。
4. **登录/注册拦截替换**：
   - 当点击“登录”或“注册”按钮时，如果密码框内的值为 `••••••••`，则在触发 API 请求前自动用本地解密出的真实密码替代，从而使过期后的“一键重新登录”逻辑完全闭环。

### 22.4 教训
- 设计“记住密码/自动登录”流程时，不仅要考虑 UI 层面上的掩码显示，更要关注 Token 失效后重新登录的恢复逻辑。
- 在本地存储密码时，为了防止明文泄露，应始终使用加密（哪怕是基础的 XOR 混淆）后再写入持久化层。
- 敏感配置（如 Token、加密密码）在登出时必须做全面、彻底的物理清理，避免信息残留。

*最后更新日期：2026-05-29*

---

## 25. Android 任务清单触控操作与软键盘遮挡修复

### 25.1 问题现象
- Android 端自定义清单较多时，点击“新建清单”后输入框位于侧栏底部，软键盘弹出会遮挡输入内容。
- Android 端长按任务或自定义清单已经用于拖拽排序/跨清单移动，无法像桌面鼠标一样通过右键打开归档、删除菜单。
- 用户在触屏设备上难以完成清单归档、删除，任务归档入口也不够明显。

### 25.2 根因分析
1. `sidebar.dart` 中新建/重命名清单是侧栏 `ListView` 内的内联 `TextField`，原实现只设置 `autofocus`，没有根据 `MediaQuery.viewInsets` 增加键盘避让空间，也没有在输入框出现后调用 `Scrollable.ensureVisible`。
2. 任务和自定义清单的管理菜单只绑定到 `onSecondaryTapDown`。这适合桌面右键，但普通 Android 触控没有二级点击。
3. 移动端长按手势已经被 `ReorderableDelayedDragStartListener` 和 `LongPressDraggable` 占用，不能再安全地复用为上下文菜单，否则会与排序和跨清单拖拽冲突。

### 25.3 修复方案
1. 侧栏 `ListView` 增加 `ScrollController`、键盘底部 padding 和 `keyboardDismissBehavior`，新建/重命名输入框出现后通过 `Scrollable.ensureVisible` 自动滚动到可见位置。
2. Android/iOS 自定义清单行尾新增“更多操作”入口，使用 bottom sheet 暴露重命名、归档、删除操作；桌面端继续保留右键菜单。
3. Android/iOS 任务行尾新增“更多操作”入口，使用 bottom sheet 暴露“我的一天”、重要、完成、到期日、移动、归档、删除等操作；长按继续保留给拖拽。
4. 任务详情页补齐“归档任务”按钮，并为本次触及的异步清单/任务操作增加 `try-catch` 与 SnackBar 反馈。
5. README 新增待发布条目，记录 Android 清单输入和触控操作优化，便于下次发版说明。

### 25.4 教训
- 移动端触控交互不能简单复用桌面右键菜单；当长按已有拖拽语义时，应提供显式按钮或移动端操作面板。
- 抽屉、侧栏等内嵌滚动区域里的自动聚焦输入框，需要同时处理键盘 inset 和滚动可见性，不能只依赖 Activity 的 `adjustResize`。
- 归档、删除、移动等涉及数据库/提醒/日历后处理的异步操作都应给用户明确成功或失败反馈，避免“点击无效”的体验。

*最后更新日期：2026-07-04*

---

## 27. Android 重复任务、防重复日历账号与清单取消体验修复

### 27.1 问题现象
- Android 勾选过期重复任务时界面像卡住一样没有即时反馈，连续点击后会生成多个下一次重复任务。
- Android 平板横屏创建任务清单时，输入框无法通过点击空白处或关闭输入法取消；竖屏时还可能被软键盘遮挡。
- Android 系统日历中可能出现多个 `FocusMyTime` 本地账号/日历，用户需要手动清理。

### 27.2 根因分析
1. 重复任务完成流程在 Provider 层分多步执行：清除原任务重复配置、切换完成、查询原任务、复制下一次任务、刷新 UI、再调度提醒。Android 日历/通知调度较慢时，UI 刷新被后置，用户连续点击会触发多次生成。
2. 新建清单输入框仅依赖 `FocusNode` 失焦逻辑，Android 平板横屏关闭输入法时焦点可能仍停留在输入框，点击其它区域也不一定触发预期失焦。
3. Android 日历创建仍依赖 `device_calendar.createCalendar`；虽然 Dart 层会按名称复用已有日历，但历史版本或部分系统 Provider 行为可能仍残留多个本地账号/日历。

### 27.3 修复方案
1. 新增 `AppDatabase.completeRecurringTaskAndCreateNext`，在 SQLite 事务中原子完成旧重复任务并创建下一次任务；只有当旧任务仍是未完成且带重复配置时才会创建下一条。
2. `TaskNotifier.toggleTaskComplete` 增加 `_completionInProgress` 防重入集合，并先做乐观完成状态更新；提醒和日历调度放到 UI 刷新之后执行。
3. 重复规则扩展为支持间隔、周几复选、每月按日期/星期、缺失日期回退/跳过、结束日期和结束次数。
4. 新建清单改为“提交才创建，失焦/点外部/关闭输入法只取消并保留草稿”，并继续使用键盘 inset 与 `Scrollable.ensureVisible` 保证输入框可见。
5. Android 日历桥接新增 `ensureLocalCalendar`，通过 `CalendarContract.Calendars` 按 `ACCOUNT_NAME = FocusMyTime`、`ACCOUNT_TYPE_LOCAL` 和日历名精确查询，存在则复用，不存在才通过 SyncAdapter URI 插入。

### 27.4 验证
- `flutter analyze` 无问题。
- `flutter test` 全量通过，并新增重复日期规则、清单置顶同步字段、自动归档相关单测。
- `flutter build apk --debug` 成功，Android 原生日历桥接通过编译；构建过程仅提示现有插件建议升级 compileSdk/NDK。

### 27.5 教训
- 移动端任何会触发外部系统 Provider 的交互，都应先保证本地 UI 和数据库状态快速、原子地落地，再异步处理外部集成。
- 重复任务生成必须有数据库层幂等保护，不能只依赖 UI 防抖。
- Android 软键盘收起不等于输入框失焦，取消输入类交互应同时监听点外部、焦点变化和窗口 inset 变化。
- 系统日历账号/日历属于外部持久状态，创建前应按账号类型和名称精确查询复用，不能只依赖上层插件的封装行为。

*最后更新日期：2026-07-07*

---

## 28. Android 16 更新弹窗无法跳转浏览器

### 28.1 问题现象
- APP 检查到 GitHub Releases 新版本后显示更新弹窗。
- 在 Android 16 手机上点击“立即下载”，弹窗直接消失，但没有跳转到浏览器下载页面。
- 用户没有收到失败提示，容易误以为按钮无效或更新流程中断。

### 28.2 根因分析
1. 更新弹窗按钮先调用 `canLaunchUrl` 判断是否能打开下载链接，再调用 `launchUrl`；无论判断或打开是否成功，最后都会关闭弹窗。
2. Android 11+ 引入包可见性限制，应用如果没有在 `AndroidManifest.xml` 的 `<queries>` 中声明 `ACTION_VIEW` + `http/https`，`canLaunchUrl` 可能返回 `false`，即使系统实际存在浏览器。
3. 旧逻辑没有对外部浏览器打开失败提供 SnackBar 反馈，导致 Android 16 上表现为“点击后弹窗消失但没有任何事发生”。

### 28.3 修复方案
1. `AndroidManifest.xml` 的 `<queries>` 增加 `android.intent.action.VIEW` 对 `https` 和 `http` scheme 的查询声明，满足 Android 11+ 包可见性要求。
2. 更新弹窗不再用 `canLaunchUrl` 作为门禁，改为直接 `launchUrl(url, mode: LaunchMode.externalApplication)` 尝试打开外部浏览器。
3. 只有浏览器成功唤起后才关闭弹窗；打开失败或链接异常时保留弹窗，并通过 SnackBar 告知用户失败原因。
4. “立即下载”打开过程中禁用弹窗其它操作，避免用户连续点击造成重复状态变化。

### 28.4 教训
- 在 Android 11+ 上，`canLaunchUrl` 的结果会受到包可见性声明影响，不能把它作为唯一的外部跳转门禁。
- 外部应用跳转类交互必须“成功后再关闭当前 UI”，失败时应保留上下文并给用户明确反馈。
- 更新、浏览器、日历、通知等依赖系统 Provider/Intent 的功能，在新版 Android 上要优先检查 Manifest 权限、queries 与系统行为变更。

*最后更新日期：2026-07-07*

---

## 26. 跨设备归档/删除同步可靠性修复

### 26.1 问题现象
- 电脑端归档或删除任务、任务清单后，长期未打开的手机端再次同步时存在边界风险。
- 清单归档会批量修改子任务状态，但子任务字段级版本未同步推进，服务端字段级合并可能保留旧归档字段。
- 远端删除落地到客户端时如果物理删除本地行，会丢失 tombstone，后续设备可能无法继续传播删除状态。
- 旧设备离线期间产生的非删除更新可能在服务端复活已删除记录。

### 26.2 根因分析
1. `archiveList` / `restoreList` 更新子任务归档字段时，只改了 `tasks` 表，没有同步写入 `sync_field_versions` 中的 `archived` / `archivedAt` 字段版本。
2. 客户端应用远端 `deleted=true` 变更时删除本地记录，破坏了离线优先同步需要的软删除墓碑语义。
3. 服务端普通表和任务表的删除冲突仍按整记录时间戳 LWW 处理，缺少“删除优先、普通更新不能复活”的产品语义。
4. 清单远端归档/删除只改清单本身，客户端没有对本地子任务和关联 sessions 做防御性级联修正。

### 26.3 修复方案
1. 客户端保留远端删除 tombstone：远端 `deleted=true` 落地时写入 `deleted = 1`，不再物理删除本地行，任务删除同时保留本机 `calendar_event_id`。
2. 清单归档/恢复时同步推进子任务 `archived` / `archivedAt` 字段版本，避免服务端字段级合并丢失归档状态。
3. 删除任务和删除清单改为事务化软删除；清单删除级联软删除子任务和关联 sessions，并补写任务字段版本。
4. 应用远端清单删除时防御性级联软删除本地子任务和 sessions；应用远端清单归档/恢复时防御性同步子任务归档字段。
5. 服务端同步算法改为删除 tombstone 优先：已删除记录不能被普通非删除更新复活，重复 tombstone 幂等处理，任务非删除更新继续保留字段级合并。
6. `/api/sync` 应用客户端多表变更时使用 better-sqlite3 transaction，避免清单、任务、会话半应用。

### 26.4 验证
- 新增同步单测覆盖清单归档/恢复字段版本、远端任务删除 tombstone、本地 tombstone 防复活、远端清单归档/删除级联。
- 本地已通过 `flutter test test/unit/sync_task_fields_test.dart`、`flutter test` 和服务端 `npm run build`。
- 线上同步服务已部署并通过 `/api/health` 健康检查。

### 26.5 教训
- 离线优先同步中，删除 tombstone 是协议数据，不能在任一客户端过早物理清理。
- 字段级合并要求所有批量写入路径同步维护字段版本，否则局部字段可能被旧设备覆盖。
- 产品没有“恢复删除”功能时，服务端冲突策略应明确删除优先，而不是默认 LWW 允许复活。
- 跨表语义（清单删除影响任务和 sessions）必须事务化应用，避免同步中途失败产生不一致。

*最后更新日期：2026-07-04*

---

## 29. Flutter 3.44 Android Release 编译歧义

### 29.1 问题现象
- `v1.5.1` 的 GitHub Actions Windows 安装包构建成功，但 Android `flutter build apk --release` 失败，Release 任务因此被跳过。
- 失败位置在 `flutter_local_notifications 16.3.3` 的 Android 原生代码：`BigPictureStyle.bigLargeIcon(null)`。
- Java 编译器同时匹配到 `Bitmap` 和 `Icon` 两个重载，报出 `reference to bigLargeIcon is ambiguous`。

### 29.2 根因分析
Flutter 3.44 使用的新版 Android SDK 为 `BigPictureStyle.bigLargeIcon` 提供了 `Bitmap` 与 `Icon` 两个可匹配重载。旧版插件把 `null` 直接传入，Java 无法推断应选择哪个类型；这发生在第三方插件源码中，与应用签名配置和业务通知代码无关。

### 29.3 修复方案
将 `flutter_local_notifications` 从 `^16.0.0` 升级至 `^17.2.4`。该系列在 `17.2.1` 已修复 Android API 重载编译问题；本地缓存源码确认使用 `bigLargeIcon((Bitmap) null)`，消除了歧义。保持现有 Dart 通知 API 不变，只更新依赖定义和锁文件。

### 29.4 验证
- `flutter analyze` 通过。
- `flutter test` 全量 90 项通过。
- 已确认新插件 Java 源码包含 `Bitmap` 强制转换。
- 本机没有 Android SDK，无法在本地执行 APK 构建；以重新触发的 GitHub Actions Android Release 构建作为最终验证。

### 29.5 教训
- 升级 Flutter SDK 时，必须将 Android Release 构建作为发布前的独立门禁，Dart 分析和单测无法覆盖插件 Java 编译错误。
- 遇到 Android SDK API 重载变更，应优先检查原生插件版本与其更新说明，而不是修改应用业务层或降低签名配置。
- 已失败且未生成 Release 的版本标签可以在修复提交后安全地移动到正确提交，再重新触发同一版本的发布流程。

*最后更新日期：2026-07-23*

---

## 30. Web 新增提醒同步到 Android 后日历重复事件

### 30.1 问题现象
- 在 Web 端给已有任务添加提醒时间后，Android 手机同步完成，系统日历中可能出现两条同名 `FocusMyTime` 提醒事件。
- 同一个任务如果直接在 Android 创建提醒，或通过 Windows 客户端创建提醒后再同步到 Android，日历通常只有一条事件。
- Web 端右键任务或清单时，可能同时弹出浏览器原生右键菜单和应用内菜单。
- Windows 客户端编辑任务标题后，“任务标题已保存”SnackBar 显示时间过长且只有“撤销”按钮，没有关闭入口。

### 30.2 根因分析
1. 同步完成后提醒刷新可能被启动加载、前台同步、同步完成监听等路径并发触发。`ReminderService.refreshAll` 已有串行化保护，但待重跑逻辑复用了第一次传入的旧任务快照。
2. 第一次刷新在 Android 日历插入事件后，会把新 `calendarEventId` 写回本机数据库；第二次待重跑仍使用旧快照，其中 `calendarEventId = null`，于是 Android 桥接再次走 INSERT，留下第二条日历事件。
3. `calendarEventId` 属于本机系统集成状态，不能跨设备同步。虽然同步负载已排除该字段，但普通 `updateTask` 仍允许传入该字段并推进 `updated_at`，存在无意义同步和未来误用风险。
4. Android 原生桥接遇到旧 eventId 无法更新时直接报错，上层回退通知并保留旧 ID；如果本机日历被系统清理或用户删除事件，后续无法自动恢复为新的日历事件。
5. Web 端没有全局禁用浏览器 context menu；Flutter 的 `onSecondaryTapDown` 只能显示应用菜单，不能自动阻止浏览器原生菜单。
6. 标题保存 SnackBar 使用默认行为且带 Action，在桌面端会显得停留过久；没有 close icon，用户只能等它消失或点“撤销”。

### 30.3 修复方案
1. `ReminderService.scheduleUnifiedReminders` 在真正写日历或通知前，从数据库重新读取当前任务，使用最新的 `reminderAt`、`completed` 和本机 `calendarEventId`，避免旧快照重复插入事件。
2. `ReminderService.refreshAll` 的待重跑分支改为重新读取数据库中的全部当前任务，不再复用旧参数列表。
3. `AppDatabase.updateTask` 将 `calendarEventId` 作为本机字段处理：只有它一个字段时调用 `updateTaskCalendarEventId`，不推进 `updated_at`，不写同步字段版本。
4. Android `MainActivity.createOrUpdateEvent` 对有 eventId 的任务优先 UPDATE；只有 `updateCount == 0` 表示旧事件确实不存在时，才 INSERT 替代事件并返回新 ID。权限异常仍抛出，不盲目新建。
5. Web 启动阶段调用 `BrowserContextMenu.disableContextMenu()`，阻止浏览器原生右键菜单。
6. 任务详情保存提示增加较短 `duration` 和 `showCloseIcon`，保留撤销操作。
7. Release 工作流新增 Web 构建 zip，并同步更新 `pubspec.yaml`、Windows Inno Setup、GitHub Actions 默认版本与 README 版本号。

### 30.4 验证
- 新增单测覆盖普通任务更新误带 `calendarEventId` 时不推进同步时间戳、不进入增量同步负载。
- `flutter analyze` 通过。
- `flutter test` 全量通过。
- `npm run build` 在 `server/` 下通过，服务端包版本显示 `1.5.2`。
- `flutter build web --release` 通过，新增的 Web zip 打包命令已本地验证可生成产物。
- 本机缺 Android SDK，无法执行 Android release build；Windows 安装包也需要 Windows runner。Android APK、Windows 安装包与 Web zip 的最终发布验证以 GitHub Actions `v1.5.2` Release 工作流为准。

### 30.5 教训
- 提醒和日历刷新必须把数据库当前状态作为权威来源；任何合并并发请求的逻辑，都不能用旧快照重放外部系统写入。
- 本机外部系统 ID 既不能跨设备同步，也不应该推进业务记录的同步时间戳。
- Android 日历 UPDATE 失败要区分“事件不存在”和“权限/Provider 拒绝”。前者可以安全新建，后者不能 INSERT 兜底，否则可能制造重复事件。
- Web 桌面式右键交互需要显式关闭浏览器原生 context menu，否则应用内菜单无法独占右键行为。

*最后更新日期：2026-08-02*

---

## 31. Windows 裸机缺少 MSVC 运行库与 Web 原生右键菜单

### 31.1 问题现象
- Windows 用户重装系统后安装 FocusMyTime，启动时报“由于找不到 MSVCP140.dll，无法继续执行代码”；手动安装 Visual C++ Redistributable 2015-2022 后才能运行。
- Web 端已经调用 `BrowserContextMenu.disableContextMenu()`，部分用户右键页面时仍会看到浏览器原生菜单，干扰应用内任务和清单菜单。

### 31.2 根因分析
1. Flutter Windows 引擎及原生插件动态依赖 Visual C++ v14 x64 运行库。旧发布流程只打包 `build/windows/x64/runner/Release` 原有内容，没有安装或随应用部署 MSVC CRT；开发机和长期使用的系统通常已有运行库，因此问题只在重装后的干净系统暴露。
2. 仅依赖 Flutter 引擎层的右键菜单开关缺少宿主页面兜底。调用异常只会写入调试日志，而且浏览器事件发生在宿主 DOM，单一引擎层防护无法保证加载阶段及不同浏览器环境都阻止原生默认行为。

### 31.3 修复方案
1. 新增 `windows/packaging/bundle_msvc_runtime.ps1`，从 Visual Studio 的 `VCToolsRedistDir` 或 `vswhere` 定位当前工具链对应的 `x64/Microsoft.VC143.CRT`，将其中全部 DLL 复制到 Windows Release 目录。
2. 脚本强制校验 `msvcp140.dll` 和 `vcruntime140.dll` 已进入产物；任一文件缺失就终止构建。Inno Setup 继续递归打包 Release 目录，因此运行库与 EXE 安装到同一应用目录，不需要联网、管理员权限或用户手工安装。
3. Web `index.html` 在 Flutter 引擎加载前，以捕获阶段注册全局 `contextmenu` 监听并调用 `preventDefault()`。监听器不停止事件传播，Flutter 仍可接收二级点击并显示应用内菜单；Dart 层原有开关继续作为第二层保护。
4. Release 工作流新增版本一致性门禁，校验标签/手动发布版本、`pubspec.yaml`、服务端包、Inno Setup 和 README 当前版本一致。

### 31.4 验证
- `npm run build` 服务端 TypeScript 构建通过，项目版本一致性脚本通过。
- Chromium 桌面 `1440x900` 与移动 `390x844` 视口均通过真实右键输入验证：事件继续传播且 `defaultPrevented = true`，页面无横向或纵向溢出。
- GitHub Actions `v1.5.3` 的 Web、Android 和 Windows Release 构建全部通过，三个产物均成功上传并发布。
- Windows 构建日志确认从 Visual Studio 2022 的 VC143 CRT 目录复制了 10 个 DLL；Inno Setup 日志确认 `msvcp140.dll`、`vcruntime140.dll` 及其配套 DLL 已实际压缩进安装包。
- 使用本机 `/opt/flutter` 的 Flutter 3.44.7 执行 `flutter analyze` 无问题，`flutter test` 全量 91 项通过；服务端 `npm run build` 通过。
- Web 按生产参数重新构建并原子部署到 `/www/wwwroot/focus.dluserver.cn/releases/20260804224844`，线上 `version.json` 为 `1.5.3+26`，生产 `main.dart.js` 哈希与本机构建一致。
- 本机 PM2 同步服务已更新为 1.5.3，保留原 `.env`、SQLite 数据与日志；重启后本机及同域 `/api/health`、登录参数校验路由均正常。

### 31.5 教训
- Windows 桌面发布不能把开发机已安装的系统运行库当作用户环境前提；安装包必须明确处理所有 Native DLL，并在 CI 对关键文件做断言。
- 应用本地部署避免了额外安装和提权，但 CRT 安全更新不会由系统集中维护；每次发布都应使用构建机当前受支持的运行库重新打包。
- 浏览器默认行为应在最接近浏览器的 DOM 层阻止，框架层开关可以保留为附加保护，不能作为唯一保障。
- 发布版本一致性应自动校验，不能只依赖人工同步多个文件。

*最后更新日期：2026-08-04*

---

## 32. 跨清单移动后归档导致任务在 Android 消失

### 32.1 问题现象
- Web 端创建新清单，把任务从旧清单拖到新清单，再归档旧清单并同步。
- Android 能看到新清单和新建任务，但被拖动的任务不可见；之后在 Web 修改该任务标题，Android 仍然无法显示。
- 任务实际已经指向新清单，只是本地 `archived = 1`，因此普通标题修改不能恢复可见性。

### 32.2 根因分析
1. 客户端下载同一批变更时先应用 `lists`，后应用 `tasks`。
2. Android 应用旧清单归档时，本地任务尚未收到本批次的 `listId` 移动字段，因此清单级联先把任务标记为归档，并把 `archived` / `archivedAt` 字段版本推进到清单归档时间。
3. 随后任务移动虽然把 `listId` 合并到新清单，但远端任务的未归档字段版本更旧，字段级 LWW 会保留 Android 刚产生的错误归档状态。
4. 改标题只推进 `title` 字段版本，不会改动归档字段，所以任务持续隐藏；若错误状态以后被回传，还可能污染服务端和其它客户端。

### 32.3 修复与历史数据恢复
1. `applySyncChanges` 改为先应用任务，再应用清单。这样同批次的任务移动会先落地，旧清单归档级联不会再命中已移动任务。
2. 数据库 Schema 升级到 13，在迁移和每次下载事务结束时检查历史错误指纹：任务位于活动清单、归档时间等于另一已归档清单时间、`listId` 版本早于归档版本，且 `archived`、`archivedAt` 版本和实际归档时间完全相同。
3. 命中指纹的任务恢复为未归档，并把两个归档字段版本推进到所有旧版本之后，使修复进入下一次增量上传。严格指纹避免误恢复用户主动归档或归档后再次移动的任务。
4. 同步服务在启动时和每次用户同步事务末尾执行同样的修复，权威数据若已被污染也会产生新的服务端游标并下发到所有设备。
5. 自动同步在登录/应用启动后立即运行，此后任务、清单、专注记录及撤销操作仍通过 2 秒防抖合并增量上传；本地增量查询包含时间水位边界，避免同毫秒修改漏传。
6. 标题/备注保存提示设置 10 秒时限，并增加独立关闭计时器；Flutter 在无障碍导航开启时会保留带 Action 的 SnackBar，不能只依赖 `SnackBar.duration`。

### 32.4 验证
- Flutter 回归测试覆盖同批次“移动任务 + 归档旧清单”、已污染任务自动恢复、修改后撤销只上传最终字段状态、同步水位同毫秒边界。
- 服务端单元测试覆盖应修复场景，以及主动归档、归档后移动两种不得误修场景。
- 发布前检查生产服务端 483 条任务记录，没有发现服务端已污染记录；用户复现场景的错误状态预计保留在 Android 本地，将由 Schema 13 迁移自动恢复。

### 32.5 教训
- 有跨表级联语义的同步批次必须明确依赖顺序；父记录先应用可能基于尚未合并的子记录状态产生新的错误写入。
- 字段级 LWW 能保留并放大错误状态，不能把“最终整行看起来更新过”当作一致性证明，必须验证每个相关字段的版本来源。
- 严重同步修复不能只阻止新错误，还要为客户端和服务端设计可重复、幂等且低误判的历史数据收敛路径。
- 增量同步水位必须定义边界语义；时间戳精度有限时应容忍边界记录幂等重发，不能用严格大于冒险漏传。
- 带操作按钮的提示在无障碍模式下可能不遵守框架默认超时；产品明确要求自动关闭时，需要独立计时器并处理撤销、关闭、新提示和页面销毁之间的竞争。

*最后更新日期：2026-08-05*

---

## 33. 英文浏览器环境输入中文时重复请求缺失字体

### 33.1 问题现象
- 生产 Web 在中文浏览器语言下加载正常，但 Playwright 默认英文语言环境输入中文任务后，会反复请求同一个 `notosansjp` WOFF2 文件并收到 404。
- 页面仍可由内置中文 UI 子集或系统字体显示文字，因此肉眼不一定立即发现，但会制造无效网络请求并降低字体渲染确定性。

### 33.2 根因分析
1. Flutter Web 字体回退管理器直接使用 `navigator.language` 选择中日韩字体；英文语言环境没有明确的简体中文优先项，部分汉字集合会选择 Noto Sans JP。
2. 项目把 `fontFallbackBaseUrl` 指向站点本地目录，避免生产依赖外部 CDN，但字体准备脚本只下载 Noto Sans SC、符号和 Emoji，没有下载 Flutter 清单中的 Noto Sans JP。
3. 用户输入包含内置 UI 字体子集之外的汉字时，缺失的 JP 子集被重复探测，Nginx 正确返回 404。

### 33.3 修复方案
1. `tool/setup_web_fonts.sh` 从当前 Flutter SDK 的 `font_fallback_data.dart` 同时解析并下载 Noto Sans SC 与 Noto Sans JP 全部子集。
2. 资源数量门禁从 100 提高到 230，避免 Flutter 升级或正则失效时只生成不完整字体目录。
3. 在英文与中文浏览器语言、桌面和移动视口下分别输入中文任务，检查所有响应状态、控制台、文字渲染和视口溢出。

### 33.4 教训
- HTML 的 `lang=zh-CN` 不代表 Flutter Web 字体回退一定按中文选择；引擎可能直接读取浏览器语言。
- 本地化 Web 字体资源不能只覆盖界面静态文字，还要覆盖用户输入和目标用户可能使用的系统语言组合。
- 视觉正常不等于资源完整，生产验收应同时收集 4xx 响应和控制台错误。

*最后更新日期：2026-08-05*

---

## 34. 日历任务历史聚合与归档详情

### 34.1 问题现象
- 日历过去只按截止日期展示普通任务，无法看到当天新建或当天完成的任务。
- 已归档任务被 `getAllTasks()` 过滤，归档后会从历史日期消失。
- 如果分别增加“创建任务”和“完成任务”分组，同一天创建并完成的任务会重复出现，日期格计数也会重复。
- 应用外层在日历打开时禁止普通任务详情面板，日历条目没有可用的详情入口。

### 34.2 根因分析
1. 日历直接复用面向当前任务清单的查询，该查询有 `archived = 0` 过滤，不适合作为历史记录来源。
2. 日历数据没有独立的活动聚合模型，只维护截止任务和循环任务两个列表，无法表达一个任务同时命中创建、完成、截止和循环的关系。
3. 普通任务详情依赖当前 Riverpod 任务列表，归档任务不在列表中；其数据库读取也默认排除归档记录，直接复用会停留在加载状态或产生不可保存的编辑控件。
4. 循环范围计算没有应用结束日期和剩余次数，无效的同步间隔还可能让日期推进失效。

### 34.3 修复方案
1. 新增日历范围查询，只读取可能影响目标日期范围的未删除任务，保留归档任务，并关联清单名称；软删除记录仍严格排除。
2. 使用 `CalendarTaskActivity` 按任务 ID 聚合当天创建、当天完成、截止当天和循环计划。四类关系只生成一条任务活动记录；“当天创建并完成”作为独立主状态显示。
3. checkbox 表示任务当前完成状态，归档、循环和截止作为辅助状态；月视图的任务数、完成数和循环数也使用 ID 集合去重。归档日期是计划关系的上限，归档后的循环和未来截止不再继续生成日历项。
4. 新增日历只读详情页。桌面端以侧栏保留月历上下文，移动端全屏展示；归档任务可查看完成状态、清单、创建/完成时间、截止、重复、备注和专注记录，但不会显示失效的编辑操作。
5. 循环日期范围遵守 `endsAt` 和 `endsAfterOccurrences`，同步数据中的非正数间隔回退为 1，并设置日期推进与迭代上限。
6. 移动端日历图标增加语义名称，自绘 checkbox 暴露 checked 状态，月份箭头增加“上个月/下个月”提示。

### 34.4 验证
- 单元测试覆盖同日创建并完成去重、创建日反映后续完成状态、归档任务保留、多来源月统计去重、损坏循环配置隔离、循环结束条件，以及真实 SQLite 范围查询排除软删除。
- `flutter analyze` 通过，完整 Flutter 测试 106 项通过。
- Chromium 桌面 `1440x900` 和移动 `390x844` 通过真实创建、完成、归档、设置循环、打开/关闭详情及月份/日期切换；长标题和高密度列表无横向溢出、控制台错误、失败请求或 HTTP 错误。

### 34.5 教训
- 日历是历史视图，不能直接复用只面向活动任务的清单查询；归档与删除必须有不同的可见性语义。
- “事件来源”不等于“展示分组”。同一实体命中多个时间关系时，应先按实体聚合，再选择一个主状态和若干辅助状态。
- 历史详情应明确只读，不能让归档数据进入看似可编辑但数据库拒绝更新的界面。
- 循环配置来自同步数据时必须按不可信输入处理；结束条件、正向推进和迭代上限缺一不可。

*最后更新日期：2026-08-06*
