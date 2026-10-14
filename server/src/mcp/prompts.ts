import { todayOverview } from '../domain/tasks'
import { focusStats } from '../domain/sessions'
import { AuthContext } from './tokens'
import { hasScope } from './scopes'
import { DomainError } from '../domain/errors'

export interface McpPrompt {
  name: string
  description: string
  arguments?: Array<{ name: string; description: string; required: boolean }>
}

export const PROMPTS: McpPrompt[] = [
  {
    name: 'plan_today',
    description: '根据当前任务排出今天的可执行时间表',
    arguments: [{ name: 'timeZone', description: 'IANA 时区', required: false }]
  },
  {
    name: 'review_overdue',
    description: '处理逾期任务：推迟、拆分或完成',
    arguments: []
  },
  {
    name: 'weekly_review',
    description: '本周完成情况、专注时长与未完成任务',
    arguments: [{ name: 'timeZone', description: 'IANA 时区', required: false }]
  },
  {
    name: 'inbox_triage',
    description: '给没有日期的未完成任务分类：加入今天、设定截止或归档'
  }
]

function textMessage(text: string) {
  return {
    messages: [
      {
        role: 'user' as const,
        content: { type: 'text' as const, text }
      }
    ]
  }
}

export function getPrompt(
  auth: AuthContext,
  name: string,
  args: Record<string, string> = {}
) {
  if (!hasScope(auth.scopes, 'tasks:read')) {
    throw new DomainError('insufficient_scope', '缺少权限 tasks:read', 403)
  }
  const timeZone = args.timeZone
  if (name === 'plan_today') {
    const overview = todayOverview(auth.userId, timeZone)
    return textMessage(
      `请根据以下 FocusMyTime 数据为用户安排今天的可执行时间表。每个被安排的任务需要开始时间、预计时长和结束时间，避免重叠，任务之间留 0-10 分钟间隔。\n\n${JSON.stringify(overview, null, 2)}`
    )
  }
  if (name === 'review_overdue') {
    const overview = todayOverview(auth.userId, timeZone)
    return textMessage(
      `请帮用户处理这些逾期任务：建议完成、改期或拆分，并在得到确认后再调用写工具。\n\n${JSON.stringify(overview.overdue, null, 2)}`
    )
  }
  if (name === 'weekly_review') {
    const stats = hasScope(auth.scopes, 'sessions:read')
      ? focusStats(auth.userId, { timeZone })
      : { note: '无专注记录权限' }
    const overview = todayOverview(auth.userId, timeZone)
    return textMessage(
      `请做本周复盘：专注时长、已完成与仍未完成的任务，给出下周建议。\n\n专注统计:\n${JSON.stringify(stats, null, 2)}\n\n当前任务摘要:\n${JSON.stringify(overview, null, 2)}`
    )
  }
  if (name === 'inbox_triage') {
    const overview = todayOverview(auth.userId, timeZone)
    return textMessage(
      `请整理没有明确日期的未完成任务：加入我的一天、设定截止日期，或说明可以稍后处理的原因。先列出建议，得到确认后再修改。\n\n${JSON.stringify(overview, null, 2)}`
    )
  }
  throw new DomainError('not_found', `未知提示词: ${name}`, 404)
}
