import { getSettingValue } from './records'

export function userTimeZone(userId: string, override?: string): string {
  const trimmed = override?.trim()
  if (trimmed) return trimmed
  const mode = getSettingValue(userId, 'appTimeZoneMode')
  if (mode === 'unitedStates') return 'America/New_York'
  if (mode === 'system') return 'UTC'
  return 'Asia/Shanghai'
}

export function formatYmd(ms: number, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).formatToParts(new Date(ms))
  const year = parts.find((part) => part.type === 'year')?.value
  const month = parts.find((part) => part.type === 'month')?.value
  const day = parts.find((part) => part.type === 'day')?.value
  return `${year}-${month}-${day}`
}

export function formatHm(ms: number, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(new Date(ms))
  const hour = parts.find((part) => part.type === 'hour')?.value
  const minute = parts.find((part) => part.type === 'minute')?.value
  return `${hour}:${minute}`
}

export function todayYmd(userId: string, timeZoneOverride?: string): string {
  return formatYmd(Date.now(), userTimeZone(userId, timeZoneOverride))
}

export function isYmd(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value)
}

export function isHm(value: string): boolean {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(value)
}

export function parseReminderAt(value: unknown): number | null | undefined {
  if (value === null) return null
  if (value === undefined) return undefined
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value)
  if (typeof value === 'string' && value.trim() !== '') {
    const asNumber = Number(value)
    if (Number.isFinite(asNumber) && /^\d+$/.test(value.trim())) {
      return Math.trunc(asNumber)
    }
    const parsed = Date.parse(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return undefined
}

export function dayRangeUtc(ymd: string, timeZone: string): { start: number; end: number } {
  // Walk 25 hours around a UTC guess and pick instants that format to ymd in tz.
  const [year, month, day] = ymd.split('-').map(Number)
  const guess = Date.UTC(year, month - 1, day, 12, 0, 0)
  let start = guess
  let end = guess
  for (let offset = -36 * 3600 * 1000; offset <= 36 * 3600 * 1000; offset += 60 * 1000) {
    const instant = guess + offset
    if (formatYmd(instant, timeZone) === ymd) {
      start = Math.min(start, instant)
      end = Math.max(end, instant)
    }
  }
  return { start, end: end + 59 * 1000 }
}
