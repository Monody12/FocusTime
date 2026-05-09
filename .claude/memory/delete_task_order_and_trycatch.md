---
name: deleteTask-order-and-trycatch
description: deleteTask 中乐观 UI 更新必须在可能失败的原生调用之前
type: feedback
---

任务删除方法中，乐观 UI 更新和同步触发必须放在 `cancelReminder`/`CalendarService.removeTask` 等原生调用**之前**，且原生调用必须用 try-catch 包裹。

**Why:** `cancelReminder`（flutter_local_notifications）和 `CalendarService.removeTask`（device_calendar）在 Android 不同版本上可能因权限问题抛异常。如果它们排在乐观更新前面，异常会阻止 UI 更新和同步触发——任务在界面上纹丝不动。

**How to apply:** 删除操作的执行顺序：①DB 操作 → ②乐观 UI 更新 → ③触发同步 → ④try-catch 保护的提醒/日历清理。永远不要把可能失败的操作放在关键路径前面。
