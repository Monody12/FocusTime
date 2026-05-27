# 日历同步跨平台经验

## Android 日历同步

Android 14 (API 34)+ 对 Calendar ContentProvider 的 `ContentResolver.delete()` 施加了严格权限检查，Android 16 进一步收紧。

### 问题现象（2026-05-07）

1. 修改任务提醒时间后，系统日历出现重复日程
2. 点击"X"取消提醒或删除任务后，日历事件残留
3. 只有首次设置能同步，后续修改不生效
4. Android 13 正常，Android 16 异常

### 根因

`device_calendar` v4.3.3 插件 `CalendarDelegate.kt` 第 398-407 行：

```kotlin
if (eventId == null) {
    contentResolver?.insert(Events.CONTENT_URI, values)  // 新建
} else {
    contentResolver?.update(ContentUris.withAppendedId(Events.CONTENT_URI, eventId), ...)  // 更新
}
```

旧代码模式：「deleteEvent → createOrUpdateEvent(不带 eventId)」。
Android 16 上 deleteEvent 被系统拦截（返回 success: false），但代码继续执行 INSERT → 旧事件残留 + 新事件创建 = 重复。

### 修复方案（已实施于 86b6194, 0cff99a）

1. **修改**：传入已有 `eventId` 给 `Event()`，让插件走 UPDATE，完全跳过 DELETE。UPDATE 失败才回退 DELETE+CREATE
2. **删除**：先尝试 `deleteEvent`，失败则通过 UPDATE 标记 `EventStatus.Canceled`（软删除）
3. **状态同步**：`scheduleUnifiedReminders` 返回 `Future<String?>`，调用方据此更新 state 中的 calendarEventId

### 跨设备同步后日历事件未创建（2026-05-17）

PC 端创建带提醒任务，手机同步后日历无事件。三个 bug 叠加：

1. **Bug 1 (Critical)**：`createOrUpdateEvent` 返回 `isSuccess=true` 但 `data=null`。原代码直接返回 `result.data` 导致返回 null，调用方跳过数据库更新。修复：增加 `result.data != null` 检查并记录 `result.errors`
2. **Bug 2 (High)**：`createTask` 不 await `scheduleUnifiedReminders`，eventId 从未写回数据库。修复：await 并写回
3. **Bug 3 (Medium)**：`sync()` 中 `refreshAll(state.tasks)` 只包含当前视图过滤后的任务，其他清单的任务被跳过。修复：使用完整数据集

详见 `KNOWLEDGE_BASE.md §15`。

## macOS 日历同步（2026-05-28）

### 架构

`device_calendar` 不提供 macOS 实现。采用 MethodChannel 桥接 EventKit：

- **Dart 层**：`MacOsCalendarPlugin`（`lib/features/calendar/services/macos_calendar_plugin.dart`）
- **Swift 层**：`MainFlutterWindow.swift` 中注册 `com.focusmytime.calendar` channel
- **分发层**：`CalendarService` 通过 `Platform.isMacOS` 选择 `DeviceCalendarPlugin` 或 `MacOsCalendarPlugin`

### 权限兼容性

| macOS 版本 | API | 状态枚举 |
|---|---|---|
| 10.14 及更早 | 无需权限 | N/A |
| 10.15 ~ 13.x (Ventura) | `requestAccess(to: .event)` | `.authorized` |
| 14.0+ (Sonoma) | `requestFullAccessToEvents` | `.fullAccess` / `.writeOnly` / `.authorized` |

### 注意事项

- EventKit 权限回调在后台线程，必须 `DispatchQueue.main.async` 切回主线程调用 FlutterResult
- Dart 传入的时间戳是毫秒，Swift 需要 `/1000.0` 转为秒
- macOS 日历源优先选择 `.local`，其次回退到默认日历源

## 通用教训

- Android 版本越高，系统 ContentProvider（日历、联系人等）写操作限制越严
- 优先使用 UPDATE 实现修改和软删除，避免直接 DELETE
- 插件 API 的 `createOrUpdateEvent` 命名暗示了「有 ID 则更新」的设计意图，应善用
- **第三方 API 返回值必须同时检查 `isSuccess` 和 `data` 是否为 null**
- **同步后的刷新操作必须针对完整数据集**，不能依赖内存中可能被视图过滤的任务列表
- **macOS 日历操作必须通过原生桥接**：`device_calendar` 在 macOS 上会抛 MissingPluginException
