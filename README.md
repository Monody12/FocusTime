# Focus Timer

跨平台计时专注应用，支持 Windows、macOS、Linux、Android。采用 Flutter 开发，原生性能，多端体验一致。

## 核心功能

### 计时器系统
- **单核工作法**：自动计算到最近整点或半点，保证最少专注时长
- **番茄工作法**：专注 25min → 短休息 5min → 循环 → 长休息 15min（每 4 轮）
- 支持循环模式、自动开始下一轮

### 任务管理
- 多清单支持，自定义清单创建、编辑、删除
- **跨清单拖拽**：长按任务拖拽到侧边栏其他清单，快速移动任务
- 重复任务：每天、每周、每月、每年循环
- 截止日期提醒，逾期任务红色高亮
- "我的一天"特殊视图

### 数据同步
- SQLite 本地存储
- 云端同步支持，多设备数据自动合并

## 技术架构

| 组件 | 技术选型 |
|------|----------|
| 框架 | Flutter |
| 状态管理 | Riverpod |
| 数据库 | sqflite |
| 主题 | Material 3 |

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── app.dart                     # 主框架
├── core/                        # 核心配置
│   ├── theme/                   # 主题配置
│   ├── utils/                  # 工具函数
│   └── providers/              # 全局 Provider
├── data/                        # 数据层
│   ├── database/               # SQLite 数据库
│   └── sync/                   # 同步服务
└── features/                   # 功能模块
    ├── timer/                  # 计时器
    ├── tasks/                  # 任务管理
    ├── sidebar/               # 侧边栏
    ├── calendar/               # 日历视图
    └── settings/               # 设置页面
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

# 构建 Release 版本
flutter build windows --release
```

## 文档

- [Flutter 开发经验总结](docs/flutter-lessons.md) — Bug 解决方案、踩坑记录
- [功能模块索引](docs/project-index.md) — 代码文件快速定位

## 版本

当前版本：v1.0.1
