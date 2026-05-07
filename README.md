# FocusMyTime

跨平台计时专注应用，支持 Windows、macOS、Linux、Android。采用 Flutter 开发，原生性能，多端体验一致。

## 核心功能

### 计时器系统
- **单核工作法**：自动计算到最近整点或半点，保证最少专注时长
- **番茄工作法**：专注 25min → 短休息 5min → 循环 → 长休息 15min（每 4 轮）
- 支持循环模式、自动开始下一轮
- **全方位通知系统**：专注或休息结束时触发铃声提醒、Windows 通知中心 Toast 以及应用内弹窗提醒

### 任务管理
- 多清单支持，自定义清单创建、编辑、删除
- **跨清单拖拽**：长按任务拖拽到侧边栏其他清单，快速移动任务
- 重复任务：每天、每周、每月、每年循环
- 截止日期提醒，逾期任务红色高亮
- "我的一天"特殊视图

### 数据同步 (Cloud Sync)
- **多端同步协议**：基于 LWW (Last-Write-Wins) 的增量同步算法
- **软删除支持**：确保删除操作在所有设备间正确传播
- **自动触发**：任务变动及专注会话结束后自动同步至云端
- **反馈机制**：UI 实时显示同步状态及错误提示

## 技术架构

| 组件 | 技术选型 |
|------|----------|
| 框架 | Flutter (Client) / Node.js (Server) |
| 语言 | Dart / TypeScript |
| 状态管理 | Riverpod |
| 数据库 | SQLite (sqflite v3) |
| 服务端 | Express + Better-SQLite3 |
| 主题 | Material 3 (Outfit Font) |
| 通知 | windows_notification & local_notifications |
| 音频 | audioplayers |
| 同步服务 | LWW 增量同步协议 |

### 🚀 最近更新 (v1.0.7)
- **前后端源码合体**：将同步服务器 (Node.js/TypeScript) 源码集成到主仓库 `server/` 目录下，实现协议同步开发。
- **Android 端 UI 深度优化**：
    - 修复了移动端“任务列表”与“侧边栏”拖拽排序过于灵敏的问题，现统一使用**长按触发**。
    - 彻底解决 Android 端计时过程中的**全局刷新**与**像素溢出**警告，大幅提升流畅度。
- **核心逻辑修复**：修正了番茄钟循环模式下手动切换阶段导致的长休息判定错误。

### 🚀 早期更新 (v1.0.6)
- **自由拖拽排序 (Microsoft To Do 风格)**：
    - **任务手动排序**：支持在清单内自由拖拽任务调整优先级。
    - **清单手动排序**：侧边栏自定义清单支持拖拽排序。
- **增强型专注交互**：计时结束支持“继续专注”，底部状态栏按钮优化。
- **自动化云同步**：登录后自动同步，专注后自动触发后台数据刷新。

## 项目结构

```
FocusTimer (根目录)
├── lib/                        # Flutter 客户端源码
│   ├── main.dart               # 应用入口
│   ├── app.dart                # 主框架
│   └── features/               # 功能模块 (timer, tasks, calendar, etc.)
├── server/                     # 同步服务器源码 (Node.js/TypeScript)
│   ├── src/                    # 服务端核心逻辑 (auth, sync, db)
│   ├── package.json            # 服务端依赖配置
│   └── ecosystem.config.js     # PM2 部署配置
├── data/                       # 数据层相关
└── docs/                       # 项目文档与索引
```

详细文件索引请查看 [docs/project-index.md](docs/project-index.md)。

## 开发

```bash
# 安装依赖
flutter pub get

# 运行开发模式
flutter run

# 构建 Windows 版本
flutter build windows
```

## 文档与学习

- [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md) — **开发者知识库**：记录了从 Electron 到 Flutter 的迁移经验、同步算法细节及解决方案。
- [功能模块索引](docs/project-index.md) — 代码文件快速定位

## 版本

当前版本：v1.0.7 (Monorepo Enabled)
