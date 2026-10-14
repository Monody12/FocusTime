import { asBoolean, asNumber, asString, listRecords } from './records'
import { dayRangeUtc, formatYmd, isYmd, userTimeZone } from './time'
import { invalid } from './errors'

export interface SessionView {
  id: string
  taskId: string | null
  taskTitle: string
  timerMode: string
  durationSeconds: number
  plannedDurationSeconds: number
  completed: boolean
  startedAt: number
  completedAt: number | null
}

function toSession(record: ReturnType<typeof listRecords>[number]): SessionView {
  const data = record.data
  return {
    id: record.id,
    taskId: asString(data.taskId) ?? null,
    taskTitle: asString(data.taskTitle) || '',
    timerMode: asString(data.timerMode) || '',
    durationSeconds: asNumber(data.durationSeconds) ?? 0,
    plannedDurationSeconds: asNumber(data.plannedDurationSeconds) ?? 0,
    completed: asBoolean(data.completed) === true,
    startedAt: asNumber(data.startedAt) ?? record.updatedAt,
    completedAt: asNumber(data.completedAt) ?? null
  }
}

export function listSessions(
  userId: string,
  options: { from?: string; to?: string; timeZone?: string; limit?: number } = {}
): SessionView[] {
  const tz = userTimeZone(userId, options.timeZone)
  if (options.from && !isYmd(options.from)) throw invalid('from 必须是 YYYY-MM-DD')
  if (options.to && !isYmd(options.to)) throw invalid('to 必须是 YYYY-MM-DD')
  const limit = Math.min(Math.max(options.limit ?? 100, 1), 500)
  const sessions = listRecords(userId, 'sessions')
    .map(toSession)
    .filter((session) => {
      const day = formatYmd(session.startedAt, tz)
      if (options.from && day < options.from) return false
      if (options.to && day > options.to) return false
      return true
    })
    .sort((a, b) => b.startedAt - a.startedAt)
  return sessions.slice(0, limit)
}

export function focusStats(
  userId: string,
  options: { from?: string; to?: string; timeZone?: string } = {}
): Record<string, unknown> {
  const tz = userTimeZone(userId, options.timeZone)
  const sessions = listSessions(userId, { ...options, limit: 500 })
  const byDay = new Map<string, { minutes: number; count: number }>()
  let totalSeconds = 0
  for (const session of sessions) {
    totalSeconds += session.durationSeconds
    const day = formatYmd(session.startedAt, tz)
    const current = byDay.get(day) || { minutes: 0, count: 0 }
    current.minutes += Math.floor(session.durationSeconds / 60)
    current.count += 1
    byDay.set(day, current)
  }
  return {
    timeZone: tz,
    from: options.from ?? null,
    to: options.to ?? null,
    sessionCount: sessions.length,
    totalMinutes: Math.floor(totalSeconds / 60),
    byDay: [...byDay.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, value]) => ({ date, ...value }))
  }
}

export function sessionsOnDay(userId: string, date: string, timeZone?: string): SessionView[] {
  if (!isYmd(date)) throw invalid('date 必须是 YYYY-MM-DD')
  const tz = userTimeZone(userId, timeZone)
  const range = dayRangeUtc(date, tz)
  return listRecords(userId, 'sessions')
    .map(toSession)
    .filter((session) => session.startedAt >= range.start && session.startedAt <= range.end)
    .sort((a, b) => a.startedAt - b.startedAt)
}
