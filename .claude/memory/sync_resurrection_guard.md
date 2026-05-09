---
name: sync-resurrection-guard
description: 同步下载不能无条件复活本地已删除的任务
type: feedback
---

`applySyncChanges` 处理服务器返回的非删除记录时，必须检查本地是否有更新的软删除版本。

**Why:** `_applyTableChanges` 原先无条件设置 `deleted = 0` 并用 `ConflictAlgorithm.replace` 插入。如果本地已删除该任务（`deleted=1`, `updated_at=T2`），服务器返回旧版本（`deleted=false`, `updated_at=T1<T2`），本地删除会被复活。在多设备场景下，这导致"删了又出现"。

**How to apply:** 同步写入非删除记录前，先查询本地是否存在 `deleted=1` 且 `updated_at` ≥ 服务器版本的同 ID 记录。若是，跳过（保留本地删除）。
