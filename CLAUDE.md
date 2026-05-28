# FocusMyTime 项目指南

## 项目全局约束

- 使用 `package:focus_my_time/...` 格式导入，禁止相对路径
- 数据库 Schema 变更必须递增版本号
- 异步 IO 操作必须 try-catch 并给用户 SnackBar 反馈
- 软删除：所有 delete 操作转为 update 设置 `deleted = 1`

## Android 日历同步

**核心原则：用 UPDATE 替代 DELETE+INSERT。**

`device_calendar` 插件的 `createOrUpdateEvent` 在 Android 端行为：
- 传入 `eventId` → `ContentResolver.update()`（修改已有事件）
- 不传 `eventId` → `ContentResolver.insert()`（创建新事件）

Android 14+ 对 `ContentResolver.delete()` 施加严格权限检查，Android 16 更严。因此：
1. 修改提醒时间：传入已有 eventId 走 UPDATE，不删旧事件
2. 取消提醒/删除任务：先尝试 deleteEvent，失败则 UPDATE 标记 `EventStatus.Canceled`
3. 遇到「低版本正常、高版本异常」的 bug，首先排查系统 ContentProvider 权限行为变更

详见 [KNOWLEDGE_BASE.md §3](KNOWLEDGE_BASE.md) 和 [.claude/memory/calendar_sync.md](.claude/memory/calendar_sync.md)。

## macOS 日历同步

**`device_calendar` 不提供 macOS 实现**，通过 `MacOsCalendarPlugin` + `MainFlutterWindow.swift` 桥接 EventKit。

- Dart 层：`MacOsCalendarPlugin` 通过 MethodChannel `com.focusmytime.calendar` 调用原生
- Swift 层：`MainFlutterWindow` 中实现 EventKit 操作，返回与 `device_calendar` 相同的 `Result<T>` 接口
- 权限兼容：macOS 14+ 用 `requestFullAccessToEvents`，Ventura 用 `requestAccess(to: .event)`
- `CalendarService` 通过 `Platform.isMacOS` 分发到不同插件实现

## macOS 通知权限

**macOS 不能使用 `permission_handler`**（无 macOS 实现），必须通过 `flutter_local_notifications` 的 `MacOSFlutterLocalNotificationsPlugin` 检查和请求权限。

- 检查权限：`macOsPlugin.checkPermissions()`
- 请求权限：`macOsPlugin.requestPermissions(alert:, badge:, sound:)`
- 打开设置：`Process.run('open', ['x-apple.systempreferences:com.apple.Notifications-Settings.extension'])`

## 文档与复盘

修复重要 bug 后：KNOWLEDGE_BASE.md 新增章节（问题现象→根因→方案→教训）→ 按模块拆分 commit → 推送。
