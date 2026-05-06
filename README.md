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

## 最近更新 (v1.0.6)

### 🚀 新特性
- **自由拖拽排序 (Microsoft To Do 风格)**：
    - **任务手动排序**：支持在清单内自由拖拽任务调整优先级。采用“全域拖拽”设计，在任务项任意位置点击并移动即可直接排序，交互简洁直观。
    - **清单手动排序**：侧边栏自定义清单支持拖拽排序，方便根据使用频率整理清单位置。
- **极致流畅体验**：
    - **乐观更新算法 (Optimistic UI)**：排序操作在释放瞬间 UI 立即完成响应，无需等待数据库 IO，彻底消除操作滞后感。
    - **静默后台同步**：排序变动采用静默加载机制，不再触发加载圈闪烁，保证操作流程的丝滑连贯。
    - **确定性排序逻辑**：引入多级排序键（sort_order + created_at），确保在序号冲突时列表顺序依然绝对稳定。

### 🚀 早期更新 (v1.0.5)
- **增强型专注交互**：计时结束支持“继续专注”，底部状态栏按钮优化。
- **自动化云同步**：登录后自动同步，专注后自动触发后台数据刷新。

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

当前版本：v1.0.6 (Flutter Stable Ready)
