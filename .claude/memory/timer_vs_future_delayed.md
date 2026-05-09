---
name: timer-vs-future-delayed
description: Dart 定时器必须用 Timer 而非 Future.delayed，因为 Future 无法取消
type: feedback
---

Windows 提醒必须使用 `Timer`（`dart:async`），不能用 `Future.delayed`。

**Why:** `Timer.cancel()` 真正阻止回调执行。`Future.delayed` 无法取消，即使从 map 中移除引用，旧回调仍会触发。修改提醒时间时，新旧 Timer/Future 共用同一个 task.id 作为 map key，旧回调的 `containsKey` 检查会被新值击败。

**How to apply:** 写任何需要取消的延时操作时，默认用 `Timer`。`Future.delayed` 只适用于不需要取消的一次性延迟。
