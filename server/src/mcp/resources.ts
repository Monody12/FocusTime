import { calendarDay, getTask, listLists, listTasks, todayOverview } from '../domain/tasks'
import { listSessions } from '../domain/sessions'
import { AuthContext } from './tokens'
import { hasScope } from './scopes'
import { DomainError } from '../domain/errors'

export interface McpResource {
  uri: string
  name: string
  description: string
  mimeType: string
}

export const RESOURCES: McpResource[] = [
  {
    uri: 'focustime://overview',
    name: '今日摘要',
    description: '我的一天、今日到期、逾期与重要任务',
    mimeType: 'application/json'
  },
  {
    uri: 'focustime://lists',
    name: '清单列表',
    description: '全部任务清单',
    mimeType: 'application/json'
  },
  {
    uri: 'focustime://today',
    name: '今日任务',
    description: '我的一天与今日到期任务',
    mimeType: 'application/json'
  }
]

export function resourcesForScopes(scopes: readonly string[]): McpResource[] {
  if (!hasScope(scopes, 'tasks:read')) return []
  return RESOURCES
}

export function readResource(auth: AuthContext, uri: string): { uri: string; mimeType: string; text: string } {
  if (!hasScope(auth.scopes, 'tasks:read')) {
    throw new DomainError('insufficient_scope', '缺少权限 tasks:read', 403)
  }
  const userId = auth.userId
  let body: unknown
  if (uri === 'focustime://overview') {
    body = todayOverview(userId)
  } else if (uri === 'focustime://lists') {
    body = listLists(userId)
  } else if (uri === 'focustime://today') {
    const overview = todayOverview(userId)
    body = { date: overview.date, myDay: overview.myDay, dueToday: overview.dueToday }
  } else if (uri.startsWith('focustime://lists/')) {
    const listId = decodeURIComponent(uri.slice('focustime://lists/'.length))
    body = listTasks(userId, { listId, limit: 200 })
  } else if (uri.startsWith('focustime://tasks/')) {
    const taskId = decodeURIComponent(uri.slice('focustime://tasks/'.length))
    body = getTask(userId, taskId)
  } else if (uri.startsWith('focustime://calendar/')) {
    const date = uri.slice('focustime://calendar/'.length)
    body = calendarDay(userId, date)
  } else if (uri.startsWith('focustime://sessions')) {
    if (!hasScope(auth.scopes, 'sessions:read')) {
      throw new DomainError('insufficient_scope', '缺少权限 sessions:read', 403)
    }
    body = listSessions(userId, { limit: 100 })
  } else {
    throw new DomainError('not_found', `未知资源: ${uri}`, 404)
  }
  return { uri, mimeType: 'application/json', text: JSON.stringify(body, null, 2) }
}
