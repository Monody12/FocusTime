# FocusMyTime 开发者知识库 & 复盘记录

本文档记录了项目从 Electron 迁移至 Flutter 过程中的核心技术决策、踩坑记录及解决方案，用于后续开发参考。

## 1. 数据库与数据同步 (Synchronization)

### 1.1 增量同步协议 (Incremental Sync)
*   **核心逻辑**：采用 **LWW (Last-Write-Wins)** 策略，基于 `updated_at` 时间戳进行冲突解决。
*   **软删除 (Soft Deletion)**：
    *   所有 `delete` 操作必须转换为 `update` (设置 `deleted = 1`)。
    *   查询时务必增加 `where deleted = 0` 过滤条件。
    *   这是为了确保同步客户端能识别并传播“删除”状态。

### 1.2 数据库迁移 (Migrations)
*   **教训**：在开发环境下，直接在原有版本（如 version 2）的 `onUpgrade` 中修改 SQL 可能会因为用户数据库已处于该版本而导致代码不生效。
*   **最佳实践**：每次修改 Schema（如增加列）必须 **递增版本号 (version)**，并在 `onUpgrade` 中针对新版本编写 `ALTER TABLE` 语句。

### 1.3 数据序列化
*   **教训**：避免使用自定义的字符串拼接（如 `val1:val2;val3`）来存储复杂对象。
*   **解决方案**：统一使用标准的 `jsonEncode` 和 `jsonDecode`。这可以防止任务标题或备注中包含特殊字符（如 `:` 或 `;`）时导致数据解析崩溃。

## 2. Flutter 开发规范 (Best Practices)

### 2.1 导入管理 (Import Standardization)
*   **问题**：混合使用相对路径 (`import '../../...'`) 和包路径 (`import 'package:project/...'`) 会导致编译器认为同一个类（如 `AppDatabase`）属于两个不同的库，触发 "Ambiguous import" 错误。
*   **规范**：本项目统一使用 **`package:focus_my_time/...`** 格式进行导入。

### 2.2 异步操作与 UI 反馈 (Error Handling)
*   **问题**：异步操作（网络请求、数据库读写）如果不加 `try-catch` 保护，报错只会出现在控制台，用户在 UI 上看不到任何反馈，表现为“点击无效”或“程序卡死”。
*   **规范**：
    *   所有涉及外部 IO 的方法必须使用 `try-catch`。
    *   在 `catch` 块中使用 `ScaffoldMessenger.of(context).showSnackBar` 为用户提供即时反馈（红色表示失败，绿色表示成功）。

### 2.3 代码结构完整性
*   **注意**：在使用 AI 辅助编程或自动编辑工具时，务必检查类结构的完整性（如大括号闭合、方法签名是否被误删）。类结构的破坏会导致编译器产生误导性的错误提示（如 "static not allowed here" 或将方法调用误认为构造函数）。

---
*最后更新日期：2026-05-05*
