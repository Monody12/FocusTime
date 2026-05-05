# Focus Timer

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
| 框架 | Flutter |
| 状态管理 | Riverpod |
| 数据库 | sqflite (v3) |
| 主题 | Material 3 (Google Fonts / Outfit) |
| 通知 | windows_notification & flutter_local_notifications |
| 音频 | audioplayers |
| 同步服务 | http 增量同步协议 |

## 最近更新 (v1.0.4)

### 🚀 新特性
- **交互式 Windows 通知**：通知中心现在支持直接操作。用户可以直接在通知弹窗上点击“开始休息”、“开始专注”或“跳过休息”，操作会实时同步至计时器状态。
- **深度复刻老架构铃声系统**：
    - **系统级音效**：接入 Windows 原生闹钟音效（`ms-winsoundevent`），提供更悦耳、更专业的提醒体验。
    - **智能响铃模式**：根据设置（短、长、常驻）自动切换 `default`、`reminder` 和 `alarm` 场景，支持系统级循环播放。
    - **全自动控制**：计时器进入下一阶段或应用内手动操作时，系统级响铃会同步自动停止。

### 🛠️ 优化与修复
- **Windows 通知回调修复**：修复了插件底层回调参数类型不匹配导致的编译错误。
- **循环播放 Bug 修复**：解决了“长”模式下无法循环响铃的问题。
- **状态同步优化**：确保通知中心按钮动作与本地状态管理（Riverpod）的强一致性。

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── app.dart                     # 主框架
├── core/                        # 核心配置
│   ├── theme/                   # 主题配置
│   ├── services/                # 业务服务 (通知、音频等)
│   ├── utils/                  # 工具函数
│   └── providers/              # 全局 Provider
├── data/                        # 数据层
│   ├── database/               # SQLite 数据库 (支持迁移与软删除)
│   └── sync/                   # 同步服务 (协议实现)
└── features/                   # 功能模块
    ├── timer/                  # 计时器 (支持单核/番茄钟)
    ├── tasks/                  # 任务管理 (清单/重复/拖拽)
    ├── sidebar/               # 侧边栏 (右键菜单/清单编辑)
    ├── calendar/               # 日历视图 (专注记录概览)
    └── settings/               # 设置页面 (同步配置/调试信息)
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

当前版本：v1.0.3 (Flutter Stable Ready)
