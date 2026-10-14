export interface RecurrenceConfig {
  frequency: 'daily' | 'weekly' | 'monthly' | 'yearly'
  interval: number
  daysOfWeek?: number[]
  daysOfMonth?: number[]
  dayOfMonth?: number
  weekOrdinal?: number
  weekDay?: number
  monthlyMode?: string
  weekDayGroup?: string
  monthOfYear?: number
  endsAt?: string
  endsAfterOccurrences?: number
  overflowPolicy: string
}

interface CivilDate {
  year: number
  month: number
  day: number
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

function weekday(date: CivilDate): number {
  const js = new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay()
  return js === 0 ? 7 : js
}

function fromYmd(value: string): CivilDate | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim())
  if (!match) return undefined
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  if (month < 1 || month > 12 || day < 1 || day > 31) return undefined
  return { year, month, day }
}

function toYmd(date: CivilDate): string {
  return `${date.year}-${String(date.month).padStart(2, '0')}-${String(date.day).padStart(2, '0')}`
}

function addDays(date: CivilDate, days: number): CivilDate {
  const utc = Date.UTC(date.year, date.month - 1, date.day + days)
  const next = new Date(utc)
  return {
    year: next.getUTCFullYear(),
    month: next.getUTCMonth() + 1,
    day: next.getUTCDate()
  }
}

function addMonths(date: CivilDate, months: number): CivilDate {
  return { year: date.year, month: date.month + months, day: 1 }
}

function compare(a: CivilDate, b: CivilDate): number {
  if (a.year !== b.year) return a.year - b.year
  if (a.month !== b.month) return a.month - b.month
  return a.day - b.day
}

function dateWithOverflow(year: number, month: number, day: number): CivilDate {
  const normalized = new Date(Date.UTC(year, month - 1, 1))
  const actualYear = normalized.getUTCFullYear()
  const actualMonth = normalized.getUTCMonth() + 1
  const max = daysInMonth(actualYear, actualMonth)
  return { year: actualYear, month: actualMonth, day: Math.min(day, max) }
}

function weekDaysForGroup(config: RecurrenceConfig): number[] {
  if (config.weekDayGroup === 'weekdays') return [1, 2, 3, 4, 5]
  if (config.weekDayGroup === 'weekend') return [6, 7]
  if (config.weekDayGroup === 'all') return [1, 2, 3, 4, 5, 6, 7]
  return [config.weekDay ?? 1]
}

function nthWeekdayOfMonth(
  year: number,
  month: number,
  ordinal: number,
  weekdays: number[]
): CivilDate | undefined {
  const dates: CivilDate[] = []
  const max = daysInMonth(year, month)
  for (let day = 1; day <= max; day++) {
    const date = { year, month, day }
    if (weekdays.includes(weekday(date))) dates.push(date)
  }
  if (dates.length === 0) return undefined
  if (ordinal === -1) return dates[dates.length - 1]
  const index = ordinal - 1
  if (index < 0 || index >= dates.length) return undefined
  return dates[index]
}

function nextMonthlyDateWithOverflow(
  from: CivilDate,
  sortedDays: number[],
  config: RecurrenceConfig
): CivilDate {
  let target = addMonths(from, config.interval)
  for (let i = 0; i < 240; i++) {
    const year = new Date(Date.UTC(target.year, target.month - 1, 1)).getUTCFullYear()
    const month = new Date(Date.UTC(target.year, target.month - 1, 1)).getUTCMonth() + 1
    for (const day of sortedDays) {
      if (day <= daysInMonth(year, month)) {
        return { year, month, day }
      }
    }
    if (config.overflowPolicy !== 'skip') {
      return dateWithOverflow(year, month, sortedDays[0])
    }
    target = addMonths({ year, month, day: 1 }, config.interval)
  }
  return dateWithOverflow(target.year, target.month, sortedDays[0])
}

function nextYearlyDateWithOverflow(current: CivilDate, config: RecurrenceConfig): CivilDate {
  let targetYear = current.year + config.interval
  for (let i = 0; i < 80; i++) {
    if (current.day <= daysInMonth(targetYear, current.month)) {
      return { year: targetYear, month: current.month, day: current.day }
    }
    if (config.overflowPolicy !== 'skip') {
      return dateWithOverflow(targetYear, current.month, current.day)
    }
    targetYear += config.interval
  }
  return dateWithOverflow(targetYear, current.month, current.day)
}

export function parseRecurrenceConfig(raw: unknown): RecurrenceConfig | undefined {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined
  const data = raw as Record<string, unknown>
  const frequency = data.frequency
  if (
    frequency !== 'daily' &&
    frequency !== 'weekly' &&
    frequency !== 'monthly' &&
    frequency !== 'yearly'
  ) {
    return undefined
  }
  const interval = typeof data.interval === 'number' && data.interval > 0 ? data.interval : 1
  return {
    frequency,
    interval,
    daysOfWeek: Array.isArray(data.daysOfWeek) ? data.daysOfWeek.map(Number) : undefined,
    daysOfMonth: Array.isArray(data.daysOfMonth) ? data.daysOfMonth.map(Number) : undefined,
    dayOfMonth: typeof data.dayOfMonth === 'number' ? data.dayOfMonth : undefined,
    weekOrdinal: typeof data.weekOrdinal === 'number' ? data.weekOrdinal : undefined,
    weekDay: typeof data.weekDay === 'number' ? data.weekDay : undefined,
    monthlyMode: typeof data.monthlyMode === 'string' ? data.monthlyMode : undefined,
    weekDayGroup: typeof data.weekDayGroup === 'string' ? data.weekDayGroup : undefined,
    monthOfYear: typeof data.monthOfYear === 'number' ? data.monthOfYear : undefined,
    endsAt: typeof data.endsAt === 'string' ? data.endsAt : undefined,
    endsAfterOccurrences:
      typeof data.endsAfterOccurrences === 'number' ? data.endsAfterOccurrences : undefined,
    overflowPolicy: typeof data.overflowPolicy === 'string' ? data.overflowPolicy : 'lastDay'
  }
}

export function getNextDate(current: CivilDate, config: RecurrenceConfig): CivilDate {
  switch (config.frequency) {
    case 'daily':
      return addDays(current, config.interval)
    case 'weekly': {
      if (config.daysOfWeek && config.daysOfWeek.length > 0) {
        let next = addDays(current, 1)
        const anchorWeekStart = addDays(current, -(weekday(current) - 1))
        for (let count = 0; count < 7 * config.interval + 7; count++) {
          const nextWeekStart = addDays(next, -(weekday(next) - 1))
          const weekDistance = Math.floor(
            (Date.UTC(nextWeekStart.year, nextWeekStart.month - 1, nextWeekStart.day) -
              Date.UTC(anchorWeekStart.year, anchorWeekStart.month - 1, anchorWeekStart.day)) /
              (7 * 24 * 3600 * 1000)
          )
          const weekAllowed = weekDistance % config.interval === 0
          if (weekAllowed && config.daysOfWeek.includes(weekday(next))) return next
          next = addDays(next, 1)
        }
        return next
      }
      return addDays(current, 7 * config.interval)
    }
    case 'monthly': {
      if (config.monthlyMode === 'weekday' && config.weekOrdinal != null) {
        let monthCursor = addMonths(current, config.interval)
        for (let i = 0; i < 24; i++) {
          const normalized = new Date(Date.UTC(monthCursor.year, monthCursor.month - 1, 1))
          const next = nthWeekdayOfMonth(
            normalized.getUTCFullYear(),
            normalized.getUTCMonth() + 1,
            config.weekOrdinal,
            weekDaysForGroup(config)
          )
          if (next) return next
          monthCursor = addMonths(
            { year: normalized.getUTCFullYear(), month: normalized.getUTCMonth() + 1, day: 1 },
            config.interval
          )
        }
      }
      const days = config.daysOfMonth ?? [config.dayOfMonth ?? current.day]
      const sortedDays = [...days].sort((a, b) => a - b)
      for (const day of sortedDays) {
        if (day > current.day) {
          const candidate = dateWithOverflow(current.year, current.month, day)
          if (candidate.month === current.month && compare(candidate, current) > 0) {
            return candidate
          }
        }
      }
      return nextMonthlyDateWithOverflow(current, sortedDays, config)
    }
    case 'yearly':
      return nextYearlyDateWithOverflow(current, config)
  }
}

export function getNextDateOnOrAfter(
  currentYmd: string,
  config: RecurrenceConfig,
  minimumYmd: string
): string {
  const current = fromYmd(currentYmd) ?? fromYmd(minimumYmd)
  const minimum = fromYmd(minimumYmd)
  if (!current || !minimum) return minimumYmd
  let next = getNextDate(current, config)
  for (let i = 0; i < 10000; i++) {
    if (compare(next, minimum) >= 0) return toYmd(next)
    const following = getNextDate(next, config)
    if (compare(following, next) <= 0) break
    next = following
  }
  return toYmd(next)
}

export function recurrenceHitsDate(
  anchorYmd: string,
  config: RecurrenceConfig,
  targetYmd: string
): boolean {
  const anchor = fromYmd(anchorYmd)
  const target = fromYmd(targetYmd)
  if (!anchor || !target) return false
  if (compare(target, anchor) < 0) return false
  const configuredEnd = config.endsAt ? fromYmd(config.endsAt) : undefined
  if (configuredEnd && compare(target, configuredEnd) > 0) return false
  let current = anchor
  let occurrence = 1
  for (let i = 0; i < 10000; i++) {
    if (config.endsAfterOccurrences != null && occurrence > config.endsAfterOccurrences) {
      return false
    }
    if (compare(current, target) === 0) return true
    if (compare(current, target) > 0) return false
    const next = getNextDate(current, config)
    if (compare(next, current) <= 0) return false
    current = next
    occurrence += 1
  }
  return false
}

export function decrementOccurrences(config: RecurrenceConfig): RecurrenceConfig {
  if (config.endsAfterOccurrences == null) return config
  return {
    ...config,
    endsAfterOccurrences: Math.max(1, config.endsAfterOccurrences - 1)
  }
}
