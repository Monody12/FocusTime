---
name: soft-delete-filter-audit
description: 软删除模式下每个数据库查询和更新都必须过滤 deleted = 0
type: reference
---

所有数据库查询和更新方法都必须添加 `WHERE deleted = 0`（或 `AND deleted = 0`）条件。遗漏此条件的方法可以操作已被软删除的"僵尸"记录，产生脏同步数据或 UI 异常。

**已修复的方法清单（2026-05-09）：**
- `getTaskById`, `updateTask`, `toggleTaskComplete`, `addToMyDay`, `removeFromMyDay`, `getSessionsByTaskId`, `getRecurrenceCompletionsByDateRange`

**原本就有过滤的方法（无需修改）：**
- `getLists`, `getTasksByList`, `getMyDayTasks`, `getImportantTasks`, `getAllTasks`, `getSessionsByDate`, `getSessionsByDateRange`, `getRecurrenceCompletions`

**How to apply:** 新增数据库方法时，首先确认是否正确处理了 `deleted` 列。写查询时问自己："如果这条记录被软删除了，这个方法还应该返回/操作它吗？"
