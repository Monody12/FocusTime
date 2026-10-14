import { v4 as uuidv4 } from 'uuid'
import { SyncRecord } from '../sync/types'
import { forbidden, invalid, notFound } from './errors'
import {
  TASK_SYNC_FIELDS,
  StoredRecord,
  asBoolean,
  asNumber,
  asString,
  getRecord,
  listRecords,
  stripInternal,
  writeRecords,
  writeTables
} from './records'
import {
  RecurrenceConfig,
  decrementOccurrences,
  getNextDateOnOrAfter,
  parseRecurrenceConfig,
  recurrenceHitsDate
} from './recurrence'
import { isHm, isYmd, parseReminderAt, todayYmd, userTimeZone } from './time'

export const SYSTEM_LISTS = [
  {
    id: 'system-my-day',
    name: '我的一天',
    iconKey: 'myDay',
    sortOrder: 0,
    topOrder: 0
  },
  {
    id: 'system-important',
    name: '重要',
    iconKey: 'important',
    sortOrder: 1,
    topOrder: 1
  },
  {
    id: 'system-all-tasks',
    name: '任务',
    iconKey: 'tasks',
    sortOrder: 2,
    topOrder: 2
  }
] as const

const SYSTEM_LIST_IDS = new Set<string>(SYSTEM_LISTS.map((list) => list.id))

export interface ListView {
  id: string
  name: string
  isSystem: boolean
  sortOrder: number
  iconKey: string
  pinned: boolean
  topOrder: number | null
  hidden: boolean
  archived: boolean
  archivedAt: number | null
  createdAt: number
  updatedAt: number
  taskCount?: number
}

export interface TaskView {
  id: string
  listId: string
  listName?: string
  title: string
  notes: string | null
  completed: boolean
  completedAt: number | null
  dueDate: string | null
  dueTime: string | null
  sortOrder: number
  isMyDay: boolean
  myDayAddedAt: number | null
  recurrenceConfig: RecurrenceConfig | Record<string, unknown> | null
  expectedMinutes: number | null
  isImportant: boolean
  reminderAt: number | null
  archived: boolean
  archivedAt: number | null
  createdAt: number
  updatedAt: number
}

function fieldVersions(now: number, fields: readonly string[]): Record<string, number> {
  const versions: Record<string, number> = {}
  for (const field of fields) versions[field] = now
  return versions
}

function toListView(record: StoredRecord): ListView {
  const data = record.data
  return {
    id: record.id,
    name: asString(data.name) || record.id,
    isSystem: asBoolean(data.isSystem) === true || SYSTEM_LIST_IDS.has(record.id),
    sortOrder: asNumber(data.sortOrder) ?? 0,
    iconKey: asString(data.iconKey) || 'list',
    pinned: asBoolean(data.pinned) === true,
    topOrder: asNumber(data.topOrder) ?? null,
    hidden: asBoolean(data.hidden) === true,
    archived: asBoolean(data.archived) === true,
    archivedAt: asNumber(data.archivedAt) ?? null,
    createdAt: asNumber(data.createdAt) ?? record.updatedAt,
    updatedAt: record.updatedAt
  }
}

function toTaskView(record: StoredRecord, lists: Map<string, ListView>): TaskView {
  const data = record.data
  const listId = asString(data.listId) || 'system-all-tasks'
  return {
    id: record.id,
    listId,
    listName: lists.get(listId)?.name,
    title: asString(data.title) || '',
    notes: asString(data.notes) ?? null,
    completed: asBoolean(data.completed) === true,
    completedAt: asNumber(data.completedAt) ?? null,
    dueDate: asString(data.dueDate) ?? null,
    dueTime: asString(data.dueTime) ?? null,
    sortOrder: asNumber(data.sortOrder) ?? 0,
    isMyDay: asBoolean(data.isMyDay) === true,
    myDayAddedAt: asNumber(data.myDayAddedAt) ?? null,
    recurrenceConfig: (data.recurrenceConfig as RecurrenceConfig | null) ?? null,
    expectedMinutes: asNumber(data.expectedMinutes) ?? null,
    isImportant: asBoolean(data.isImportant) === true,
    reminderAt: asNumber(data.reminderAt) ?? null,
    archived: asBoolean(data.archived) === true,
    archivedAt: asNumber(data.archivedAt) ?? null,
    createdAt: asNumber(data.createdAt) ?? record.updatedAt,
    updatedAt: record.updatedAt
  }
}

function listMap(userId: string): Map<string, ListView> {
  const map = new Map<string, ListView>()
  for (const record of listRecords(userId, 'lists')) {
    map.set(record.id, toListView(record))
  }
  return map
}

export function ensureSystemLists(userId: string): void {
  const existing = new Set(listRecords(userId, 'lists').map((record) => record.id))
  const missing = SYSTEM_LISTS.filter((list) => !existing.has(list.id))
  if (missing.length === 0) return
  const now = Date.now()
  writeRecords(
    userId,
    'lists',
    missing.map((list) => ({
      id: list.id,
      updatedAt: now,
      deleted: false,
      data: {
        id: list.id,
        name: list.name,
        isSystem: true,
        sortOrder: list.sortOrder,
        iconKey: list.iconKey,
        pinned: true,
        topOrder: list.topOrder,
        hidden: false,
        createdAt: now,
        updatedAt: now,
        archived: false,
        archivedAt: null,
        deleted: false
      }
    }))
  )
}

export function listLists(
  userId: string,
  options: { includeArchived?: boolean } = {}
): ListView[] {
  ensureSystemLists(userId)
  const tasks = listRecords(userId, 'tasks')
  const counts = new Map<string, number>()
  for (const task of tasks) {
    if (asBoolean(task.data.archived) === true) continue
    const listId = asString(task.data.listId)
    if (!listId) continue
    counts.set(listId, (counts.get(listId) || 0) + 1)
  }
  return listRecords(userId, 'lists')
    .map(toListView)
    .filter((list) => options.includeArchived || !list.archived)
    .sort((a, b) => a.sortOrder - b.sortOrder)
    .map((list) => ({ ...list, taskCount: counts.get(list.id) || 0 }))
}

export function getList(userId: string, listId: string): ListView {
  ensureSystemLists(userId)
  const record = getRecord(userId, 'lists', listId)
  if (!record) throw notFound(`清单不存在: ${listId}`)
  return toListView(record)
}

function findListByName(userId: string, name: string): ListView | undefined {
  const normalized = name.trim().toLowerCase()
  return listLists(userId, { includeArchived: true }).find(
    (list) => list.name.trim().toLowerCase() === normalized
  )
}

export function resolveListId(
  userId: string,
  listRef: string | undefined,
  options: { createIfMissing?: boolean } = {}
): string {
  ensureSystemLists(userId)
  if (!listRef || listRef.trim() === '') return 'system-all-tasks'
  const trimmed = listRef.trim()
  if (trimmed === 'system-my-day' || trimmed === 'system-important') {
    return 'system-all-tasks'
  }
  const byId = getRecord(userId, 'lists', trimmed)
  if (byId && !byId.deleted) return trimmed
  const byName = findListByName(userId, trimmed)
  if (byName) return byName.id
  if (options.createIfMissing) {
    return createList(userId, { name: trimmed }).id
  }
  throw notFound(`清单不存在: ${trimmed}`)
}

export interface ListTasksQuery {
  listId?: string
  completed?: boolean
  important?: boolean
  myDay?: boolean
  archived?: boolean
  overdue?: boolean
  query?: string
  dueFrom?: string
  dueTo?: string
  timeZone?: string
  limit?: number
}

type TaskListFilter =
  | { kind: 'all' }
  | { kind: 'myDay' }
  | { kind: 'important' }
  | { kind: 'list'; id: string }

function resolveTaskListFilter(userId: string, listRef?: string): TaskListFilter | undefined {
  if (!listRef || listRef.trim() === '') return undefined
  const trimmed = listRef.trim()
  if (trimmed === 'system-my-day' || trimmed === '我的一天') return { kind: 'myDay' }
  if (trimmed === 'system-important' || trimmed === '重要') return { kind: 'important' }
  if (trimmed === 'system-all-tasks' || trimmed === '任务') return { kind: 'all' }
  return { kind: 'list', id: resolveListId(userId, trimmed) }
}

export function listTasks(userId: string, query: ListTasksQuery = {}): TaskView[] {
  ensureSystemLists(userId)
  const lists = listMap(userId)
  const today = todayYmd(userId, query.timeZone)
  const limit = Math.min(Math.max(query.limit ?? 50, 1), 200)
  const needle = query.query?.trim().toLowerCase()
  const listFilter = resolveTaskListFilter(userId, query.listId)
  const results: TaskView[] = []
  for (const record of listRecords(userId, 'tasks')) {
    const task = toTaskView(record, lists)
    if (query.archived === true) {
      if (!task.archived) continue
    } else if (task.archived) {
      continue
    }
    if (listFilter) {
      if (listFilter.kind === 'myDay') {
        if (!task.isMyDay) continue
      } else if (listFilter.kind === 'important') {
        if (!task.isImportant) continue
      } else if (listFilter.kind === 'list' && task.listId !== listFilter.id) {
        continue
      }
    }
    if (query.completed != null && task.completed !== query.completed) continue
    if (query.important != null && task.isImportant !== query.important) continue
    if (query.myDay != null && task.isMyDay !== query.myDay) continue
    if (query.overdue === true) {
      if (task.completed || !task.dueDate || task.dueDate >= today) continue
    }
    if (query.dueFrom && (!task.dueDate || task.dueDate < query.dueFrom)) continue
    if (query.dueTo && (!task.dueDate || task.dueDate > query.dueTo)) continue
    if (needle) {
      const haystack = `${task.title}\n${task.notes || ''}`.toLowerCase()
      if (!haystack.includes(needle)) continue
    }
    results.push(task)
  }
  results.sort((a, b) => {
    if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder
    return a.createdAt - b.createdAt
  })
  return results.slice(0, limit)
}

export function getTask(userId: string, taskId: string): TaskView {
  ensureSystemLists(userId)
  const record = getRecord(userId, 'tasks', taskId)
  if (!record) throw notFound(`任务不存在: ${taskId}`)
  return toTaskView(record, listMap(userId))
}

function nextSortOrder(userId: string, listId: string): number {
  let max = -1
  for (const record of listRecords(userId, 'tasks')) {
    if (asString(record.data.listId) !== listId) continue
    if (asBoolean(record.data.archived) === true) continue
    max = Math.max(max, asNumber(record.data.sortOrder) ?? 0)
  }
  return max + 1
}

function taskRecord(
  id: string,
  now: number,
  fields: Record<string, unknown>,
  deleted = false
): SyncRecord {
  return {
    id,
    updatedAt: now,
    deleted,
    data: {
      ...fields,
      updatedAt: now,
      deleted,
      _fieldUpdatedAt: fieldVersions(now, TASK_SYNC_FIELDS)
    }
  }
}

function patchRecord(
  id: string,
  now: number,
  patch: Record<string, unknown>,
  deleted = false
): SyncRecord {
  const versions = fieldVersions(now, Object.keys(patch))
  return {
    id,
    updatedAt: now,
    deleted,
    data: {
      ...patch,
      _fieldUpdatedAt: versions
    }
  }
}

function validateDue(dueDate?: string | null, dueTime?: string | null): void {
  if (dueDate != null && dueDate !== '' && !isYmd(dueDate)) {
    throw invalid('dueDate 必须是 YYYY-MM-DD')
  }
  if (dueTime != null && dueTime !== '' && !isHm(dueTime)) {
    throw invalid('dueTime 必须是 HH:mm')
  }
}

export interface CreateTaskInput {
  title: string
  notes?: string
  listId?: string
  dueDate?: string
  dueTime?: string
  expectedMinutes?: number
  isMyDay?: boolean
  isImportant?: boolean
  reminderAt?: unknown
  recurrence?: RecurrenceConfig | Record<string, unknown>
}

export function createTask(userId: string, input: CreateTaskInput): TaskView {
  const title = input.title?.trim()
  if (!title) throw invalid('任务标题不能为空')
  validateDue(input.dueDate, input.dueTime)
  const listRef = input.listId?.trim() || 'system-all-tasks'
  let isMyDay = input.isMyDay === true
  let isImportant = input.isImportant === true
  if (listRef === 'system-my-day') isMyDay = true
  if (listRef === 'system-important') isImportant = true
  const listId = resolveListId(userId, listRef, { createIfMissing: true })
  const now = Date.now()
  const id = `task-${uuidv4()}`
  const reminderAt = parseReminderAt(input.reminderAt)
  if (input.reminderAt !== undefined && input.reminderAt !== null && reminderAt === undefined) {
    throw invalid('reminderAt 必须是 ISO 8601 或毫秒时间戳')
  }
  const recurrence = input.recurrence ? parseRecurrenceConfig(input.recurrence) : null
  if (input.recurrence && !recurrence) throw invalid('recurrence 无效')
  writeRecords(userId, 'tasks', [
    taskRecord(id, now, {
      id,
      listId,
      title,
      notes: input.notes ?? null,
      completed: false,
      completedAt: null,
      dueDate: input.dueDate ?? null,
      dueTime: input.dueTime ?? null,
      sortOrder: nextSortOrder(userId, listId),
      isMyDay,
      myDayAddedAt: isMyDay ? now : null,
      recurrenceConfig: recurrence,
      expectedMinutes: input.expectedMinutes ?? null,
      isImportant,
      reminderAt: reminderAt ?? null,
      archived: false,
      archivedAt: null,
      createdAt: now
    })
  ])
  return getTask(userId, id)
}

export interface UpdateTaskInput {
  title?: string
  notes?: string | null
  listId?: string
  dueDate?: string | null
  dueTime?: string | null
  expectedMinutes?: number | null
  isMyDay?: boolean
  isImportant?: boolean
  reminderAt?: unknown
  recurrence?: RecurrenceConfig | Record<string, unknown> | null
  completed?: boolean
}

export function updateTask(userId: string, taskId: string, input: UpdateTaskInput): TaskView {
  const existing = getTask(userId, taskId)
  const patch: Record<string, unknown> = {}
  if (input.title !== undefined) {
    const title = input.title.trim()
    if (!title) throw invalid('任务标题不能为空')
    patch.title = title
  }
  if (input.notes !== undefined) patch.notes = input.notes
  if (input.listId !== undefined) {
    patch.listId = resolveListId(userId, input.listId, { createIfMissing: true })
  }
  if (input.dueDate !== undefined) {
    if (input.dueDate && !isYmd(input.dueDate)) throw invalid('dueDate 必须是 YYYY-MM-DD')
    patch.dueDate = input.dueDate
  }
  if (input.dueTime !== undefined) {
    if (input.dueTime && !isHm(input.dueTime)) throw invalid('dueTime 必须是 HH:mm')
    patch.dueTime = input.dueTime
  }
  if (input.expectedMinutes !== undefined) patch.expectedMinutes = input.expectedMinutes
  if (input.isMyDay !== undefined) {
    patch.isMyDay = input.isMyDay
    patch.myDayAddedAt = input.isMyDay ? Date.now() : null
  }
  if (input.isImportant !== undefined) patch.isImportant = input.isImportant
  if (input.reminderAt !== undefined) {
    const reminderAt = parseReminderAt(input.reminderAt)
    if (input.reminderAt !== null && reminderAt === undefined) {
      throw invalid('reminderAt 必须是 ISO 8601 或毫秒时间戳')
    }
    patch.reminderAt = reminderAt ?? null
  }
  if (input.recurrence !== undefined) {
    if (input.recurrence === null) {
      patch.recurrenceConfig = null
    } else {
      const parsed = parseRecurrenceConfig(input.recurrence)
      if (!parsed) throw invalid('recurrence 无效')
      patch.recurrenceConfig = parsed
    }
  }
  if (input.completed !== undefined && input.completed !== existing.completed) {
    if (input.completed) return completeTask(userId, taskId).task
    patch.completed = false
    patch.completedAt = null
  }
  if (Object.keys(patch).length === 0) return existing
  writeRecords(userId, 'tasks', [patchRecord(taskId, Date.now(), patch)])
  return getTask(userId, taskId)
}

function shiftReminder(reminderAt: number | null, fromDue: string | null, toDue: string): number | null {
  if (reminderAt == null || !fromDue) return reminderAt
  const from = Date.parse(`${fromDue}T00:00:00`)
  const to = Date.parse(`${toDue}T00:00:00`)
  if (!Number.isFinite(from) || !Number.isFinite(to)) return reminderAt
  return reminderAt + (to - from)
}

export function completeTask(userId: string, taskId: string): { task: TaskView; nextTask?: TaskView } {
  const existing = getTask(userId, taskId)
  if (existing.completed) return { task: existing }
  const now = Date.now()
  const recurrence = parseRecurrenceConfig(existing.recurrenceConfig)
  if (!recurrence) {
    writeRecords(userId, 'tasks', [
      patchRecord(taskId, now, { completed: true, completedAt: now })
    ])
    return { task: getTask(userId, taskId) }
  }
  if (recurrence.endsAfterOccurrences != null && recurrence.endsAfterOccurrences <= 1) {
    writeRecords(userId, 'tasks', [
      patchRecord(taskId, now, {
        completed: true,
        completedAt: now,
        recurrenceConfig: null
      })
    ])
    return { task: getTask(userId, taskId) }
  }
  const today = todayYmd(userId)
  const currentDue = existing.dueDate || today
  const nextDue = getNextDateOnOrAfter(currentDue, recurrence, today)
  if (recurrence.endsAt && nextDue > recurrence.endsAt) {
    writeRecords(userId, 'tasks', [
      patchRecord(taskId, now, {
        completed: true,
        completedAt: now,
        recurrenceConfig: null
      })
    ])
    return { task: getTask(userId, taskId) }
  }
  const nextId = `task-${uuidv4()}`
  const nextRecurrence = decrementOccurrences(recurrence)
  const nextReminder = shiftReminder(existing.reminderAt, existing.dueDate, nextDue)
  writeTables(userId, {
    tasks: [
      patchRecord(taskId, now, {
        completed: true,
        completedAt: now,
        recurrenceConfig: null
      }),
      taskRecord(nextId, now, {
        id: nextId,
        listId: existing.listId,
        title: existing.title,
        notes: existing.notes,
        completed: false,
        completedAt: null,
        dueDate: nextDue,
        dueTime: existing.dueTime,
        sortOrder: existing.sortOrder,
        isMyDay: existing.isMyDay,
        myDayAddedAt: existing.myDayAddedAt,
        recurrenceConfig: nextRecurrence,
        expectedMinutes: existing.expectedMinutes,
        isImportant: existing.isImportant,
        reminderAt: nextReminder,
        archived: false,
        archivedAt: null,
        createdAt: now
      })
    ]
  })
  return { task: getTask(userId, taskId), nextTask: getTask(userId, nextId) }
}

export function uncompleteTask(userId: string, taskId: string): TaskView {
  getTask(userId, taskId)
  writeRecords(userId, 'tasks', [
    patchRecord(taskId, Date.now(), { completed: false, completedAt: null })
  ])
  return getTask(userId, taskId)
}

export function deleteTask(userId: string, taskId: string): { id: string; deleted: true } {
  const existing = getRecord(userId, 'tasks', taskId)
  if (!existing) throw notFound(`任务不存在: ${taskId}`)
  writeRecords(userId, 'tasks', [
    {
      id: taskId,
      updatedAt: Date.now(),
      deleted: true,
      data: { ...stripInternal(existing.data), id: taskId }
    }
  ])
  return { id: taskId, deleted: true }
}

export function createList(userId: string, input: { name: string }): ListView {
  const name = input.name?.trim()
  if (!name) throw invalid('清单名称不能为空')
  const existing = findListByName(userId, name)
  if (existing) return existing
  ensureSystemLists(userId)
  const now = Date.now()
  const id = `list-${uuidv4()}`
  const sortOrder = listLists(userId).length
  writeRecords(userId, 'lists', [
    {
      id,
      updatedAt: now,
      deleted: false,
      data: {
        id,
        name,
        isSystem: false,
        sortOrder,
        iconKey: 'list',
        pinned: false,
        topOrder: null,
        hidden: false,
        createdAt: now,
        updatedAt: now,
        archived: false,
        archivedAt: null,
        deleted: false
      }
    }
  ])
  return getList(userId, id)
}

export function renameList(userId: string, listId: string, name: string): ListView {
  const list = getList(userId, listId)
  if (list.isSystem) throw forbidden('不能重命名系统清单')
  const trimmed = name.trim()
  if (!trimmed) throw invalid('清单名称不能为空')
  const now = Date.now()
  writeRecords(userId, 'lists', [
    {
      id: listId,
      updatedAt: now,
      deleted: false,
      data: {
        ...stripInternal(getRecord(userId, 'lists', listId)!.data),
        name: trimmed,
        updatedAt: now
      }
    }
  ])
  return getList(userId, listId)
}

export function archiveList(userId: string, listId: string, archived = true): ListView {
  const list = getList(userId, listId)
  if (list.isSystem) throw forbidden('不能归档系统清单')
  const now = Date.now()
  const listRecord = getRecord(userId, 'lists', listId)!
  const taskPatches: SyncRecord[] = listRecords(userId, 'tasks')
    .filter((task) => asString(task.data.listId) === listId)
    .map((task) =>
      patchRecord(task.id, now, {
        archived,
        archivedAt: archived ? now : null
      })
    )
  writeTables(userId, {
    lists: [
      {
        id: listId,
        updatedAt: now,
        deleted: false,
        data: {
          ...stripInternal(listRecord.data),
          archived,
          archivedAt: archived ? now : null,
          updatedAt: now
        }
      }
    ],
    tasks: taskPatches
  })
  return getList(userId, listId)
}

export function deleteList(userId: string, listId: string): { id: string; deleted: true } {
  const list = getList(userId, listId)
  if (list.isSystem) throw forbidden('不能删除系统清单')
  const now = Date.now()
  const listRecord = getRecord(userId, 'lists', listId)!
  const tasks = listRecords(userId, 'tasks').filter(
    (task) => asString(task.data.listId) === listId
  )
  writeTables(userId, {
    lists: [
      {
        id: listId,
        updatedAt: now,
        deleted: true,
        data: { ...stripInternal(listRecord.data), id: listId, deleted: true, updatedAt: now }
      }
    ],
    tasks: tasks.map((task) => ({
      id: task.id,
      updatedAt: now,
      deleted: true,
      data: { ...stripInternal(task.data), id: task.id, deleted: true }
    }))
  })
  return { id: listId, deleted: true }
}

export function reorderTasks(userId: string, taskIds: string[]): { updated: number } {
  if (!Array.isArray(taskIds) || taskIds.length === 0) {
    throw invalid('taskIds 不能为空')
  }
  const now = Date.now()
  const records: SyncRecord[] = []
  for (let index = 0; index < taskIds.length; index++) {
    const id = taskIds[index]
    getTask(userId, id)
    records.push(patchRecord(id, now, { sortOrder: index }))
  }
  writeRecords(userId, 'tasks', records)
  return { updated: records.length }
}

export function todayOverview(userId: string, timeZone?: string): Record<string, unknown> {
  const tz = userTimeZone(userId, timeZone)
  const today = todayYmd(userId, tz)
  const tasks = listTasks(userId, { limit: 200, timeZone: tz })
  const myDay = tasks.filter((task) => task.isMyDay && !task.completed)
  const dueToday = tasks.filter((task) => task.dueDate === today && !task.completed)
  const overdue = tasks.filter(
    (task) => !task.completed && task.dueDate != null && task.dueDate < today
  )
  const important = tasks.filter((task) => task.isImportant && !task.completed)
  return {
    date: today,
    timeZone: tz,
    myDay,
    dueToday,
    overdue,
    important,
    incompleteCount: tasks.filter((task) => !task.completed).length
  }
}

export function calendarDay(
  userId: string,
  date: string,
  timeZone?: string
): Record<string, unknown> {
  if (!isYmd(date)) throw invalid('date 必须是 YYYY-MM-DD')
  const tz = userTimeZone(userId, timeZone)
  const lists = listMap(userId)
  const tasks: TaskView[] = []
  const seen = new Set<string>()
  const add = (task: TaskView) => {
    if (seen.has(task.id)) return
    seen.add(task.id)
    tasks.push(task)
  }
  for (const record of listRecords(userId, 'tasks')) {
    const task = toTaskView(record, lists)
    if (task.dueDate === date) add(task)
    if (formatCreated(task, tz) === date) add(task)
    if (task.completedAt && formatMs(task.completedAt, tz) === date) add(task)
    const recurrence = parseRecurrenceConfig(task.recurrenceConfig)
    if (recurrence && task.dueDate && recurrenceHitsDate(task.dueDate, recurrence, date)) {
      add(task)
    }
  }
  return { date, timeZone: tz, tasks }
}

function formatCreated(task: TaskView, timeZone: string): string {
  return formatMs(task.createdAt, timeZone)
}

function formatMs(ms: number, timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(new Date(ms))
}


