---
name: update-mechanism-design
description: 推荐自建更新服务器而非 GitHub Releases，利用现有公网服务器
type: reference
---

项目推荐使用自建更新服务器（复用 `1.12.46.222:6677`），而非 GitHub Releases。

**Why:** 项目不开源，公开 GitHub Releases 不可行；私有仓库需要内嵌 Token 有安全风险。已有公网服务器和同步 API，新增更新检查端点成本很低。

**How to apply:** 
- 服务器新增 `GET /api/update/check?platform=android&version=N` 端点和 `/downloads/` 静态文件目录
- 客户端启动时静默检查，有更新弹非阻塞对话框
- Android 下 APK 调系统 Intent 安装；Windows 下下载 exe 用 Process.start 运行
- 当前阶段（单开发者、功能迭代中）ADB 安装已足够，自动更新模块优先级低于核心功能
