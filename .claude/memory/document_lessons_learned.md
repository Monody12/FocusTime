---
name: document_lessons_learned
description: 遇到非显而易见的问题时必须记录到 KNOWLEDGE_BASE.md 和记忆系统
type: feedback
originSessionId: 669b5b84-c73f-4cea-9e18-eac6c76b730d
---
解决问题后必须将经验记录到 KNOWLEDGE_BASE.md（按模块新增章节）和记忆系统中，尤其是跨平台兼容性、插件行为、系统权限等非显而易见的坑。

**Why:** 用户明确要求同样的错误不要再犯。光靠人的记忆不可靠，必须记录到持久化的知识文件中。用户希望我在后续遇到类似问题时能主动查阅这些记录。

**How to apply:** 每次解决一个非平凡问题后，在 KNOWLEDGE_BASE.md 以"问题现象→根因→方案→教训"格式新增章节，并同步到记忆系统。在后续排查问题时，主动用 Grep 搜索 KNOWLEDGE_BASE.md 和记忆文件看是否有相关经验。
