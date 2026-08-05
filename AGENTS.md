# FocusMyTime 项目指南

## 项目全局约束

- 使用 `package:focus_my_time/...` 格式导入，禁止相对路径
- 数据库 Schema 变更必须递增版本号
- 异步 IO 操作必须 try-catch 并给用户 SnackBar 反馈
- 软删除：所有 delete 操作转为 update 设置 `deleted = 1`
- 语言要求：与用户的沟通及对话的最终结果必须始终使用简体中文。

## Android 日历同步

**核心原则：用 UPDATE 替代 DELETE+INSERT。**

`device_calendar` 插件的 `createOrUpdateEvent` 在 Android 端行为：
- 传入 `eventId` → `ContentResolver.update()`（修改已有事件）
- 不传 `eventId` → `ContentResolver.insert()`（创建新事件）

Android 14+ 对 `ContentResolver.delete()` 施加严格权限检查，Android 16 更严。因此：
1. 修改提醒时间：传入已有 eventId 走 UPDATE，不删旧事件
2. 取消提醒/删除任务：先尝试 deleteEvent，失败则 UPDATE 标记 `EventStatus.Canceled`
3. 遇到「低版本正常、高版本异常」的 bug，首先排查系统 ContentProvider 权限行为变更

详见 [KNOWLEDGE_BASE.md §3](KNOWLEDGE_BASE.md) 和 [.Codex/memory/calendar_sync.md](.Codex/memory/calendar_sync.md)。

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

## 版本号与发布管理

- **推送前检查**：每次推送代码或发布新版本前，必须检查并更新版本号（主文件为 `pubspec.yaml`）。
- **版本一致性**：确保项目中各个位置展示或记录的版本号保持统一和一致（如 `README.md` 的更新日志、GitHub Actions `.github/workflows` 中的版本号过滤等）。

## 生产发布完成条件（强制）

**创建 GitHub Release 不代表发布完成。** `https://focus.dluserver.cn/` 同时承载 Web 前端，并将 `/api/` 反向代理到本机同步服务；每次发版都必须更新这台服务器上的前端和服务端。

1. GitHub Actions 三端构建和 GitHub Release 全部成功后，在生产服务器的项目根目录执行 `tool/deploy_production.sh`。
2. 脚本必须完成服务端程序备份、PM2 更新、Web 生产构建、时间戳目录部署和 `current` 符号链接原子切换；不得覆盖 `.env`、SQLite 数据或日志。
3. 发布结束前必须确认：
   - `https://focus.dluserver.cn/version.json` 与 `pubspec.yaml` 的版本号和 build number 一致；
   - PM2 中 `focus-timer-sync` 的版本与客户端版本一致且状态为 `online`；
   - `https://focus.dluserver.cn/api/health` 返回 `status=ok`；
   - 线上 `main.dart.js` 与本次本机构建哈希一致；
   - 真实浏览器桌面和移动视口可正常加载；涉及 Web 交互时必须验证对应交互。
4. 任一项未完成或无法验证时，必须明确告诉用户“GitHub Release 已创建，但生产部署未完成”，不能用“已发布”结束任务。

生产路径、构建参数和回滚说明见 [docs/web-deployment.md](docs/web-deployment.md)。
