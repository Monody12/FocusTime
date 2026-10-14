import { DomainError } from '../domain/errors'
import {
  archiveList,
  calendarDay,
  completeTask,
  createList,
  createTask,
  deleteList,
  deleteTask,
  getList,
  getTask,
  listLists,
  listTasks,
  renameList,
  reorderTasks,
  todayOverview,
  uncompleteTask,
  updateTask
} from '../domain/tasks'
import { focusStats, listSessions, sessionsOnDay } from '../domain/sessions'
import { AuthContext } from './tokens'
import { McpScope, hasScope } from './scopes'

export interface ToolAnnotation {
  readOnlyHint: boolean
  destructiveHint: boolean
  idempotentHint: boolean
  openWorldHint: boolean
}

export interface ToolDefinition {
  name: string
  description: string
  inputSchema: Record<string, unknown>
  annotations: ToolAnnotation
  scopes: McpScope[]
}

const readTask: ToolAnnotation = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false
}
const writeTask: ToolAnnotation = {
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false
}
const destructiveTask: ToolAnnotation = {
  readOnlyHint: false,
  destructiveHint: true,
  idempotentHint: true,
  openWorldHint: false
}

const recurrenceProperties = {
  type: 'object',
  description: '重复规则',
  properties: {
    frequency: { type: 'string', enum: ['daily', 'weekly', 'monthly', 'yearly'] },
    interval: { type: 'integer', minimum: 1 },
    daysOfWeek: { type: 'array', items: { type: 'integer', minimum: 1, maximum: 7 } },
    dayOfMonth: { type: 'integer' },
    endsAt: { type: 'string', description: '结束日期 YYYY-MM-DD' },
    endsAfterOccurrences: { type: 'integer', minimum: 1 }
  }
}

export const TOOLS: ToolDefinition[] = [
  {
    name: 'list_lists',
    description: '列出任务清单（含系统清单：我的一天、重要、任务）。',
    inputSchema: {
      type: 'object',
      properties: {
        includeArchived: { type: 'boolean', description: '是否包含已归档清单' }
      }
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'get_list',
    description: '按 ID 获取清单详情。',
    inputSchema: {
      type: 'object',
      properties: { listId: { type: 'string' } },
      required: ['listId']
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'list_tasks',
    description: '按条件列出任务。listId 可为清单 ID、清单名，或 system-my-day / system-important / system-all-tasks。',
    inputSchema: {
      type: 'object',
      properties: {
        listId: { type: 'string' },
        completed: { type: 'boolean' },
        important: { type: 'boolean' },
        myDay: { type: 'boolean' },
        archived: { type: 'boolean' },
        overdue: { type: 'boolean' },
        query: { type: 'string', description: '标题或备注关键词' },
        dueFrom: { type: 'string', description: '截止日期起 YYYY-MM-DD' },
        dueTo: { type: 'string', description: '截止日期止 YYYY-MM-DD' },
        timeZone: { type: 'string', description: 'IANA 时区，默认跟随用户设置' },
        limit: { type: 'integer', minimum: 1, maximum: 200 }
      }
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'get_task',
    description: '按任务 ID 获取详情。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'search_tasks',
    description: '按标题和备注搜索任务。',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string' },
        limit: { type: 'integer', minimum: 1, maximum: 200 }
      },
      required: ['query']
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'get_today_overview',
    description: '今日摘要：我的一天、今日到期、逾期、重要任务。',
    inputSchema: {
      type: 'object',
      properties: { timeZone: { type: 'string' } }
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'get_calendar_day',
    description: '某一天的任务轨迹（到期、创建、完成、重复命中）。若令牌含 sessions:read，同时返回当日专注记录。',
    inputSchema: {
      type: 'object',
      properties: {
        date: { type: 'string', description: 'YYYY-MM-DD' },
        timeZone: { type: 'string' }
      },
      required: ['date']
    },
    annotations: readTask,
    scopes: ['tasks:read']
  },
  {
    name: 'list_focus_sessions',
    description: '列出专注会话。',
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', description: 'YYYY-MM-DD' },
        to: { type: 'string', description: 'YYYY-MM-DD' },
        timeZone: { type: 'string' },
        limit: { type: 'integer', minimum: 1, maximum: 500 }
      }
    },
    annotations: readTask,
    scopes: ['sessions:read']
  },
  {
    name: 'get_focus_stats',
    description: '按日汇总专注分钟数。',
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string' },
        to: { type: 'string' },
        timeZone: { type: 'string' }
      }
    },
    annotations: readTask,
    scopes: ['sessions:read']
  },
  {
    name: 'create_task',
    description: '创建任务。listId 可以是清单 ID 或名称；不存在的自定义清单会自动创建。reminderAt 是开始/提醒时间，dueDate/dueTime 是截止时间。',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        notes: { type: 'string' },
        listId: { type: 'string' },
        dueDate: { type: 'string', description: 'YYYY-MM-DD' },
        dueTime: { type: 'string', description: 'HH:mm' },
        expectedMinutes: { type: 'integer', minimum: 1 },
        isMyDay: { type: 'boolean' },
        isImportant: { type: 'boolean' },
        reminderAt: { description: 'ISO 8601 或毫秒时间戳' },
        recurrence: recurrenceProperties
      },
      required: ['title']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'update_task',
    description: '修改已有任务的字段，只传需要改的字段。',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: { type: 'string' },
        title: { type: 'string' },
        notes: { type: 'string' },
        listId: { type: 'string' },
        dueDate: { type: 'string' },
        dueTime: { type: 'string' },
        expectedMinutes: { type: 'integer' },
        isMyDay: { type: 'boolean' },
        isImportant: { type: 'boolean' },
        reminderAt: {},
        recurrence: recurrenceProperties,
        completed: { type: 'boolean' }
      },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'complete_task',
    description: '将任务标记为完成。若带重复规则，会生成下一个周期任务。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'uncomplete_task',
    description: '取消完成状态。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'delete_task',
    description: '软删除任务。此操作会同步到所有设备。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: destructiveTask,
    scopes: ['tasks:write']
  },
  {
    name: 'set_task_dates',
    description: '设置或清除截止日期和时间。',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: { type: 'string' },
        dueDate: { type: ['string', 'null'] },
        dueTime: { type: ['string', 'null'] }
      },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'set_reminder',
    description: '设置任务提醒/开始时间。传 null 可清除。',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: { type: 'string' },
        reminderAt: { description: 'ISO 8601、毫秒时间戳或 null' }
      },
      required: ['taskId', 'reminderAt']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'set_recurrence',
    description: '设置或清除重复规则。frequency 为 null 时清除。',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: { type: 'string' },
        frequency: { type: ['string', 'null'], enum: ['daily', 'weekly', 'monthly', 'yearly', null] },
        interval: { type: 'integer', minimum: 1 },
        daysOfWeek: { type: 'array', items: { type: 'integer' } },
        endsAt: { type: 'string' },
        endsAfterOccurrences: { type: 'integer' }
      },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'add_to_my_day',
    description: '将任务加入「我的一天」。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'remove_from_my_day',
    description: '从「我的一天」移除任务。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'toggle_important',
    description: '切换任务重要标记。',
    inputSchema: {
      type: 'object',
      properties: { taskId: { type: 'string' } },
      required: ['taskId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'move_task_to_list',
    description: '把任务移动到指定清单。',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: { type: 'string' },
        listId: { type: 'string', description: '清单 ID 或名称' }
      },
      required: ['taskId', 'listId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'reorder_tasks',
    description: '按给定 ID 顺序重排任务（手动排序）。',
    inputSchema: {
      type: 'object',
      properties: {
        taskIds: { type: 'array', items: { type: 'string' } }
      },
      required: ['taskIds']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'create_list',
    description: '创建自定义清单。若同名清单已存在则返回已有清单。',
    inputSchema: {
      type: 'object',
      properties: { name: { type: 'string' } },
      required: ['name']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'rename_list',
    description: '重命名自定义清单。不能修改系统清单。',
    inputSchema: {
      type: 'object',
      properties: {
        listId: { type: 'string' },
        name: { type: 'string' }
      },
      required: ['listId', 'name']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'archive_list',
    description: '归档或取消归档自定义清单，并级联其下任务。',
    inputSchema: {
      type: 'object',
      properties: {
        listId: { type: 'string' },
        archived: { type: 'boolean', default: true }
      },
      required: ['listId']
    },
    annotations: writeTask,
    scopes: ['tasks:write']
  },
  {
    name: 'delete_list',
    description: '软删除自定义清单及其下任务。不能删除系统清单。',
    inputSchema: {
      type: 'object',
      properties: { listId: { type: 'string' } },
      required: ['listId']
    },
    annotations: destructiveTask,
    scopes: ['tasks:write']
  }
]

const TOOL_MAP = new Map(TOOLS.map((tool) => [tool.name, tool]))

function asArgs(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>
  }
  return {}
}

function requireString(args: Record<string, unknown>, key: string): string {
  const value = args[key]
  if (typeof value !== 'string' || value.trim() === '') {
    throw new DomainError('invalid_argument', `缺少参数 ${key}`, 400)
  }
  return value
}

export function toolsForScopes(scopes: readonly string[]): ToolDefinition[] {
  return TOOLS.filter((tool) => tool.scopes.every((scope) => hasScope(scopes, scope)))
}

export function executeTool(
  auth: AuthContext,
  name: string,
  rawArgs: unknown
): unknown {
  const tool = TOOL_MAP.get(name)
  if (!tool) throw new DomainError('not_found', `未知工具: ${name}`, 404)
  for (const scope of tool.scopes) {
    if (!hasScope(auth.scopes, scope)) {
      throw new DomainError('insufficient_scope', `缺少权限 ${scope}`, 403)
    }
  }
  const args = asArgs(rawArgs)
  const userId = auth.userId
  switch (name) {
    case 'list_lists':
      return listLists(userId, { includeArchived: args.includeArchived === true })
    case 'get_list':
      return getList(userId, requireString(args, 'listId'))
    case 'list_tasks':
      return listTasks(userId, {
        listId: typeof args.listId === 'string' ? args.listId : undefined,
        completed: typeof args.completed === 'boolean' ? args.completed : undefined,
        important: typeof args.important === 'boolean' ? args.important : undefined,
        myDay: typeof args.myDay === 'boolean' ? args.myDay : undefined,
        archived: typeof args.archived === 'boolean' ? args.archived : undefined,
        overdue: typeof args.overdue === 'boolean' ? args.overdue : undefined,
        query: typeof args.query === 'string' ? args.query : undefined,
        dueFrom: typeof args.dueFrom === 'string' ? args.dueFrom : undefined,
        dueTo: typeof args.dueTo === 'string' ? args.dueTo : undefined,
        timeZone: typeof args.timeZone === 'string' ? args.timeZone : undefined,
        limit: typeof args.limit === 'number' ? args.limit : undefined
      })
    case 'get_task':
      return getTask(userId, requireString(args, 'taskId'))
    case 'search_tasks':
      return listTasks(userId, {
        query: requireString(args, 'query'),
        limit: typeof args.limit === 'number' ? args.limit : 50
      })
    case 'get_today_overview':
      return todayOverview(userId, typeof args.timeZone === 'string' ? args.timeZone : undefined)
    case 'get_calendar_day': {
      const date = requireString(args, 'date')
      const timeZone = typeof args.timeZone === 'string' ? args.timeZone : undefined
      const day = calendarDay(userId, date, timeZone)
      if (hasScope(auth.scopes, 'sessions:read')) {
        return { ...day, sessions: sessionsOnDay(userId, date, timeZone) }
      }
      return day
    }
    case 'list_focus_sessions':
      return listSessions(userId, {
        from: typeof args.from === 'string' ? args.from : undefined,
        to: typeof args.to === 'string' ? args.to : undefined,
        timeZone: typeof args.timeZone === 'string' ? args.timeZone : undefined,
        limit: typeof args.limit === 'number' ? args.limit : undefined
      })
    case 'get_focus_stats':
      return focusStats(userId, {
        from: typeof args.from === 'string' ? args.from : undefined,
        to: typeof args.to === 'string' ? args.to : undefined,
        timeZone: typeof args.timeZone === 'string' ? args.timeZone : undefined
      })
    case 'create_task':
      return createTask(userId, {
        title: requireString(args, 'title'),
        notes: typeof args.notes === 'string' ? args.notes : undefined,
        listId: typeof args.listId === 'string' ? args.listId : undefined,
        dueDate: typeof args.dueDate === 'string' ? args.dueDate : undefined,
        dueTime: typeof args.dueTime === 'string' ? args.dueTime : undefined,
        expectedMinutes: typeof args.expectedMinutes === 'number' ? args.expectedMinutes : undefined,
        isMyDay: args.isMyDay === true,
        isImportant: args.isImportant === true,
        reminderAt: args.reminderAt,
        recurrence: args.recurrence as Record<string, unknown> | undefined
      })
    case 'update_task':
      return updateTask(userId, requireString(args, 'taskId'), {
        title: typeof args.title === 'string' ? args.title : undefined,
        notes: typeof args.notes === 'string' ? args.notes : undefined,
        listId: typeof args.listId === 'string' ? args.listId : undefined,
        dueDate: typeof args.dueDate === 'string' ? args.dueDate : args.dueDate === null ? null : undefined,
        dueTime: typeof args.dueTime === 'string' ? args.dueTime : args.dueTime === null ? null : undefined,
        expectedMinutes: typeof args.expectedMinutes === 'number' ? args.expectedMinutes : undefined,
        isMyDay: typeof args.isMyDay === 'boolean' ? args.isMyDay : undefined,
        isImportant: typeof args.isImportant === 'boolean' ? args.isImportant : undefined,
        reminderAt: args.reminderAt,
        recurrence: args.recurrence === null ? null : args.recurrence as Record<string, unknown> | undefined,
        completed: typeof args.completed === 'boolean' ? args.completed : undefined
      })
    case 'complete_task':
      return completeTask(userId, requireString(args, 'taskId'))
    case 'uncomplete_task':
      return uncompleteTask(userId, requireString(args, 'taskId'))
    case 'delete_task':
      return deleteTask(userId, requireString(args, 'taskId'))
    case 'set_task_dates':
      return updateTask(userId, requireString(args, 'taskId'), {
        dueDate: args.dueDate === null ? null : typeof args.dueDate === 'string' ? args.dueDate : undefined,
        dueTime: args.dueTime === null ? null : typeof args.dueTime === 'string' ? args.dueTime : undefined
      })
    case 'set_reminder':
      return updateTask(userId, requireString(args, 'taskId'), { reminderAt: args.reminderAt })
    case 'set_recurrence': {
      const taskId = requireString(args, 'taskId')
      if (args.frequency === null || args.frequency === '') {
        return updateTask(userId, taskId, { recurrence: null })
      }
      return updateTask(userId, taskId, {
        recurrence: {
          frequency: args.frequency,
          interval: args.interval,
          daysOfWeek: args.daysOfWeek,
          endsAt: args.endsAt,
          endsAfterOccurrences: args.endsAfterOccurrences
        }
      })
    }
    case 'add_to_my_day':
      return updateTask(userId, requireString(args, 'taskId'), { isMyDay: true })
    case 'remove_from_my_day':
      return updateTask(userId, requireString(args, 'taskId'), { isMyDay: false })
    case 'toggle_important': {
      const task = getTask(userId, requireString(args, 'taskId'))
      return updateTask(userId, task.id, { isImportant: !task.isImportant })
    }
    case 'move_task_to_list':
      return updateTask(userId, requireString(args, 'taskId'), {
        listId: requireString(args, 'listId')
      })
    case 'reorder_tasks':
      return reorderTasks(userId, Array.isArray(args.taskIds) ? args.taskIds.map(String) : [])
    case 'create_list':
      return createList(userId, { name: requireString(args, 'name') })
    case 'rename_list':
      return renameList(userId, requireString(args, 'listId'), requireString(args, 'name'))
    case 'archive_list':
      return archiveList(userId, requireString(args, 'listId'), args.archived !== false)
    case 'delete_list':
      return deleteList(userId, requireString(args, 'listId'))
    default:
      throw new DomainError('not_found', `未知工具: ${name}`, 404)
  }
}
