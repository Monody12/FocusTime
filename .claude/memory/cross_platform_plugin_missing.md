---
name: cross_platform_plugin_missing
description: device_calendar 插件在 Windows 端报 MissingPluginException，无害但需记录调用链
type: project
originSessionId: 669b5b84-c73f-4cea-9e18-eac6c76b730d
---
device_calendar 是 Android/iOS 专属插件，在 Windows 桌面端任何调用都会抛出 MissingPluginException。

**Why:** 调用链为 TaskNotifier → ReminderService → CalendarService.hasPermissions() → device_calendar 插件。每次任务 CRUD 都可能触发。异常被框架吞掉，日历同步自动跳过，不影响功能。

**How to apply:** 排查此类 MissingPluginException 时，追踪 UI 事件 → Provider → Service → 原生插件的完整调用链。这不是 bug，是跨平台开发的正常现象。如需优化，可在 ReminderService 入口处加 `Platform.isAndroid || Platform.isIOS` 判断。
