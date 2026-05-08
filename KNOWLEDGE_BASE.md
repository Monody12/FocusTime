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

---
*最后更新日期：2026-05-07*
