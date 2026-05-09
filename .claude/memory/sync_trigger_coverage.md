---
name: sync-trigger-coverage
description: 所有持久化变更都必须触发后台同步，包括 settings 表
type: feedback
---

任何写入持久存储的操作（不管是 task、list、session 还是 setting），只要改了数据，就必须触发后台同步。

**Why:** `AppDatabase.setSetting()` 正确设置了 `updated_at`，记录会被纳入上传 payload。但如果没有主动触发 `SyncService.fullSync()`，这些变更会一直滞留在本地，直到下次任务/清单操作触发同步时才被顺带上传——可能是几小时甚至几天后。在多设备场景下，这导致设置变更无法及时同步到其他设备。

**How to apply:** 
- 新增任何持久化方法时，问自己：「这个方法改了数据库后，需要触发同步吗？」
- Settings 同步触发用 `SyncService.triggerBackgroundSync()`（fire-and-forget，不阻塞 UI）
- 计时器配置目前存在 SharedPreferences，**不经过 SQLite**，因此不会同步。这是有意的设计选择（本地偏好不跨设备），新增计时器配置项时注意存哪里
