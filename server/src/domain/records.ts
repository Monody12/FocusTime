import { db } from '../db/schema'
import { applyClientTables } from '../sync/algorithm'
import { SyncRecord, TableName } from '../sync/types'

export const TASK_SYNC_FIELDS = [
  'listId',
  'title',
  'notes',
  'completed',
  'completedAt',
  'dueDate',
  'dueTime',
  'sortOrder',
  'isMyDay',
  'myDayAddedAt',
  'recurrenceConfig',
  'expectedMinutes',
  'isImportant',
  'reminderAt',
  'archived',
  'archivedAt'
] as const

export type TaskSyncField = (typeof TASK_SYNC_FIELDS)[number]

export interface StoredRecord {
  id: string
  updatedAt: number
  deleted: boolean
  data: Record<string, unknown>
}

export function parseDataJson(dataJson: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(dataJson) as unknown
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>
    }
  } catch {
    // fall through
  }
  return {}
}

export function listRecords(
  userId: string,
  tableName: TableName,
  options: { includeDeleted?: boolean } = {}
): StoredRecord[] {
  const sql = options.includeDeleted
    ? `SELECT record_id, data_json, updated_at, deleted
       FROM sync_records
       WHERE user_id = ? AND table_name = ?`
    : `SELECT record_id, data_json, updated_at, deleted
       FROM sync_records
       WHERE user_id = ? AND table_name = ? AND deleted = 0`
  const rows = db.prepare(sql).all(userId, tableName) as Array<{
    record_id: string
    data_json: string
    updated_at: number
    deleted: number
  }>
  return rows.map((row) => ({
    id: row.record_id,
    updatedAt: row.updated_at,
    deleted: row.deleted === 1,
    data: parseDataJson(row.data_json)
  }))
}

export function getRecord(
  userId: string,
  tableName: TableName,
  recordId: string,
  options: { includeDeleted?: boolean } = {}
): StoredRecord | undefined {
  const row = db.prepare(
    `SELECT record_id, data_json, updated_at, deleted
     FROM sync_records
     WHERE user_id = ? AND table_name = ? AND record_id = ?`
  ).get(userId, tableName, recordId) as
    | {
        record_id: string
        data_json: string
        updated_at: number
        deleted: number
      }
    | undefined
  if (!row) return undefined
  if (!options.includeDeleted && row.deleted === 1) return undefined
  return {
    id: row.record_id,
    updatedAt: row.updated_at,
    deleted: row.deleted === 1,
    data: parseDataJson(row.data_json)
  }
}

export function writeRecords(
  userId: string,
  tableName: TableName,
  records: SyncRecord[]
): void {
  if (records.length === 0) return
  applyClientTables(userId, { [tableName]: records })
}

export function writeTables(
  userId: string,
  tables: Partial<Record<TableName, SyncRecord[]>>
): void {
  applyClientTables(userId, tables)
}

export function asString(value: unknown): string | undefined {
  if (typeof value === 'string') return value
  if (typeof value === 'number' && Number.isFinite(value)) return String(value)
  return undefined
}

export function asNumber(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return undefined
}

export function asBoolean(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') return value
  if (value === 1 || value === '1' || value === 'true') return true
  if (value === 0 || value === '0' || value === 'false') return false
  return undefined
}

export function stripInternal(data: Record<string, unknown>): Record<string, unknown> {
  const { _fieldUpdatedAt: _ignored, ...rest } = data
  return rest
}

export function getSettingValue(userId: string, key: string): string | undefined {
  const record = getRecord(userId, 'settings', key)
  if (!record) return undefined
  const value = record.data.value ?? record.data[key]
  return asString(value)
}
