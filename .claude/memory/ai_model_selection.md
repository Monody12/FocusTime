---
name: ai-model-selection
description: AI 任务助手应使用 chat 模型而非 reasoner 模型，响应速度优先
type: feedback
---

AI 助手默认使用 `deepseek-chat`，不用 `deepseek-reasoner`。

**Why:** 任务管理操作（创建、修改、删除、查询）需要秒级响应。Reasoner 模型的思考链耗时 20-60 秒，用于日常任务操作会严重损害用户体验。用户说"添加一个任务"然后看 loading 转 30 秒——这比没有 AI 更糟糕。

**How to apply:** 
- 保持 `DeepSeekApiClient._model = 'deepseek-chat'`
- 如果未来需要复杂规划功能（如"分析我本周所有任务并建议优先级"），可以加一个可选的"深度思考"开关，用户手动启用并知晓会慢
- 模型选择的标准是「用户等待意愿」，不是评测榜单
