# 项目文件索引

本文档列出 Focus Timer 项目中每个功能对应的代码文件，方便快速定位。

---

## 一、核心架构

| 功能 | 文件路径 |
|------|----------|
| 应用入口 | `lib/main.dart` |
| 应用主框架 | `lib/app.dart` |
| 主题配置 | `lib/core/theme/app_theme.dart` |
| 数据库 | `lib/data/database/app_database.dart` |

---

## 二、侧边栏

| 功能 | 文件路径 |
|------|----------|
| 侧边栏组件 | `lib/features/sidebar/presentation/widgets/sidebar.dart` |

---

## 三、任务管理

| 功能 | 文件路径 |
|------|----------|
| 任务状态管理 | `lib/features/tasks/providers/task_provider.dart` |
| 任务列表页 | `lib/features/tasks/presentation/pages/task_list_page.dart` |
| 任务详情页 | `lib/features/tasks/presentation/pages/task_detail_page.dart` |
| 任务项组件 | `lib/features/tasks/presentation/widgets/task_item.dart` |

---

## 四、计时器

| 功能 | 文件路径 |
|------|----------|
| 计时器状态管理 | `lib/features/timer/providers/timer_provider.dart` |
| 计时器主页面 | `lib/features/timer/presentation/pages/timer_page.dart` |
| 计时器显示 | `lib/features/timer/presentation/widgets/timer_display.dart` |
| 计时器控制按钮 | `lib/features/timer/presentation/widgets/timer_controls.dart` |
| 模式选择器 | `lib/features/timer/presentation/widgets/mode_selector.dart` |
| 任务输入框 | `lib/features/timer/presentation/widgets/task_input.dart` |

---

## 五、设置

| 功能 | 文件路径 |
|------|----------|
| 设置页面 | `lib/features/settings/presentation/pages/settings_page.dart` |

---

## 六、日历

| 功能 | 文件路径 |
|------|----------|
| 日历页面 | `lib/features/calendar/presentation/pages/calendar_page.dart` |

---

## 七、工具函数

| 功能 | 文件路径 |
|------|----------|
| 循环工具 | `lib/core/utils/recurrence_utils.dart` |
| 时间工具 | `lib/core/utils/time_utils.dart` |

---

## 八、文档

| 文件 | 说明 |
|------|------|
| `docs/flutter-lessons.md` | Flutter 开发经验总结（含 Bug 解决方案） |
| `docs/project-index.md` | 本文件，功能模块索引 |

---

## 九、已知问题修复记录

详见 `docs/flutter-lessons.md`，包含以下经验：

- `LongPressDraggable` 与 `GestureDetector` 嵌套冲突
- `FocusNode` 失焦自动保存
- `Row` 按钮溢出处理
- `DropdownButton` 零尺寸渲染错误
- 异步操作 `mounted` 检查
- `ConsumerWidget` 改为 `ConsumerStatefulWidget` 的注意事项