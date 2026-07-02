import { db } from '../db/schema'
import { SyncRecord, TableName, ALL_TABLES, UserRecord } from './types'

let lastIssuedServerTime = 0

const TASK_SYNC_FIELDS = [
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

type FieldVersions = Record<(typeof TASK_SYNC_FIELDS)[number], number>

function nextServerChangeTime(): number {
  if (lastIssuedServerTime === 0) {
    const row = db
      .prepare('SELECT COALESCE(MAX(server_updated_at), 0) as value FROM sync_records')
      .get() as { value: number }
    lastIssuedServerTime = row.value || 0
  }

  lastIssuedServerTime = Math.max(Date.now(), lastIssuedServerTime + 1)
  return lastIssuedServerTime
}

function parseDataJson(dataJson: string): Record<string, unknown> {
  const parsed = JSON.parse(dataJson) as unknown
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
    return parsed as Record<string, unknown>
  }
  return {}
}

function readTimestamp(value: unknown, fallback: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string') {
    const parsed = Number.parseInt(value, 10)
    if (Number.isFinite(parsed)) return parsed
  }
  return fallback
}

function readTaskFieldVersions(
  data: Record<string, unknown>,
  fallbackUpdatedAt: number
): FieldVersions {
  const rawVersions = data._fieldUpdatedAt
  const versions = {} as FieldVersions

  for (const fieldName of TASK_SYNC_FIELDS) {
    if (rawVersions && typeof rawVersions === 'object' && !Array.isArray(rawVersions)) {
      versions[fieldName] = readTimestamp(
        (rawVersions as Record<string, unknown>)[fieldName],
        fallbackUpdatedAt
      )
    } else {
      versions[fieldName] = fallbackUpdatedAt
    }
  }

  return versions
}

function withTaskFieldVersions(
  data: Record<string, unknown>,
  versions: FieldVersions,
  updatedAt: number,
  deleted: boolean
): Record<string, unknown> {
  return {
    ...data,
    updatedAt,
    deleted,
    _fieldUpdatedAt: versions
  }
}

export function getCurrentServerCursor(): number {
  if (lastIssuedServerTime > 0) return lastIssuedServerTime
  const row = db
    .prepare('SELECT COALESCE(MAX(server_updated_at), 0) as value FROM sync_records')
    .get() as { value: number }
  lastIssuedServerTime = row.value || 0
  return lastIssuedServerTime
}

/**
 * Apply incoming records from client using Last-Write-Wins (LWW) conflict resolution.
 * Returns the number of records processed.
 */
export function applyClientRecords(
  userId: string,
  tableName: TableName,
  records: SyncRecord[]
): number {
  if (records.length === 0) return 0
  if (tableName === 'tasks') {
    return applyClientTaskRecords(userId, records)
  }

  const stmt = db.prepare(`
    INSERT INTO sync_records (
      user_id,
      table_name,
      record_id,
      data_json,
      updated_at,
      server_updated_at,
      deleted
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, table_name, record_id) DO UPDATE SET
      data_json = CASE
        WHEN excluded.updated_at > sync_records.updated_at THEN excluded.data_json
        ELSE sync_records.data_json
      END,
      updated_at = CASE
        WHEN excluded.updated_at > sync_records.updated_at THEN excluded.updated_at
        ELSE sync_records.updated_at
      END,
      server_updated_at = CASE
        WHEN excluded.updated_at > sync_records.updated_at THEN excluded.server_updated_at
        ELSE sync_records.server_updated_at
      END,
      deleted = CASE
        WHEN excluded.updated_at > sync_records.updated_at THEN excluded.deleted
        ELSE sync_records.deleted
      END
  `)

  let count = 0
  for (const record of records) {
    const dataJson = JSON.stringify(record.data)
    const deleted = record.deleted ? 1 : 0
    stmt.run(
      userId,
      tableName,
      record.id,
      dataJson,
      record.updatedAt,
      nextServerChangeTime(),
      deleted
    )
    count++
  }

  return count
}

function applyClientTaskRecords(userId: string, records: SyncRecord[]): number {
  const selectStmt = db.prepare(`
    SELECT record_id, data_json, updated_at, deleted, server_updated_at
    FROM sync_records
    WHERE user_id = ? AND table_name = 'tasks' AND record_id = ?
  `)

  const insertStmt = db.prepare(`
    INSERT INTO sync_records (
      user_id,
      table_name,
      record_id,
      data_json,
      updated_at,
      server_updated_at,
      deleted
    )
    VALUES (?, 'tasks', ?, ?, ?, ?, ?)
  `)

  const updateStmt = db.prepare(`
    UPDATE sync_records
    SET data_json = ?,
        updated_at = ?,
        server_updated_at = ?,
        deleted = ?
    WHERE user_id = ? AND table_name = 'tasks' AND record_id = ?
  `)

  let count = 0
  for (const record of records) {
    const existing = selectStmt.get(userId, record.id) as UserRecord | undefined
    const incomingDeleted = record.deleted === true
    const incomingVersions = readTaskFieldVersions(record.data, record.updatedAt)

    if (!existing) {
      const normalizedData = withTaskFieldVersions(
        record.data,
        incomingVersions,
        record.updatedAt,
        incomingDeleted
      )
      insertStmt.run(
        userId,
        record.id,
        JSON.stringify(normalizedData),
        record.updatedAt,
        nextServerChangeTime(),
        incomingDeleted ? 1 : 0
      )
      count++
      continue
    }

    if (incomingDeleted) {
      if (record.updatedAt > existing.updated_at) {
        const normalizedData = withTaskFieldVersions(
          record.data,
          incomingVersions,
          record.updatedAt,
          true
        )
        updateStmt.run(
          JSON.stringify(normalizedData),
          record.updatedAt,
          nextServerChangeTime(),
          1,
          userId,
          record.id
        )
      }
      count++
      continue
    }

    if (existing.deleted === 1) {
      if (record.updatedAt > existing.updated_at) {
        const normalizedData = withTaskFieldVersions(
          record.data,
          incomingVersions,
          record.updatedAt,
          false
        )
        updateStmt.run(
          JSON.stringify(normalizedData),
          record.updatedAt,
          nextServerChangeTime(),
          0,
          userId,
          record.id
        )
      }
      count++
      continue
    }

    const existingData = parseDataJson(existing.data_json)
    const existingVersions = readTaskFieldVersions(existingData, existing.updated_at)
    const mergedData: Record<string, unknown> = { ...existingData }
    const mergedVersions: FieldVersions = { ...existingVersions }
    let changed = false

    for (const fieldName of TASK_SYNC_FIELDS) {
      if (
        Object.prototype.hasOwnProperty.call(record.data, fieldName) &&
        incomingVersions[fieldName] > existingVersions[fieldName]
      ) {
        mergedData[fieldName] = record.data[fieldName]
        mergedVersions[fieldName] = incomingVersions[fieldName]
        changed = true
      }
    }

    if (changed) {
      const mergedUpdatedAt = Math.max(
        existing.updated_at,
        record.updatedAt,
        ...Object.values(mergedVersions)
      )
      const normalizedData = withTaskFieldVersions(
        mergedData,
        mergedVersions,
        mergedUpdatedAt,
        false
      )
      updateStmt.run(
        JSON.stringify(normalizedData),
        mergedUpdatedAt,
        nextServerChangeTime(),
        0,
        userId,
        record.id
      )
    }
    count++
  }

  return count
}

/**
 * Get all records for a user that have changed on the server since cursor.
 * Client edit time (updated_at) is still returned for LWW conflict checks.
 */
export function getServerChanges(
  userId: string,
  serverCursor: number
): Map<TableName, SyncRecord[]> {
  const result = new Map<TableName, SyncRecord[]>()

  for (const tableName of ALL_TABLES) {
    const stmt = db.prepare(`
      SELECT record_id, data_json, updated_at, deleted
      FROM sync_records
      WHERE user_id = ? AND table_name = ? AND server_updated_at > ?
      ORDER BY server_updated_at ASC
    `)

    const rows = stmt.all(userId, tableName, serverCursor) as UserRecord[]

    const records: SyncRecord[] = rows.map((row) => ({
      id: row.record_id,
      updatedAt: row.updated_at,
      data: JSON.parse(row.data_json),
      deleted: row.deleted === 1
    }))

    result.set(tableName, records)
  }

  return result
}

/**
 * Log a sync operation for audit purposes.
 */
export function logSync(
  userId: string,
  syncTime: number,
  clientLastSync: number,
  recordsSent: number,
  recordsReceived: number
): void {
  const stmt = db.prepare(`
    INSERT INTO sync_log (user_id, sync_time, client_last_sync, records_sent, records_received)
    VALUES (?, ?, ?, ?, ?)
  `)
  stmt.run(userId, syncTime, clientLastSync, recordsSent, recordsReceived)
}

/**
 * Reset all user data (for testing or account deletion).
 */
export function resetUserData(userId: string): void {
  const deleteSyncRecords = db.prepare('DELETE FROM sync_records WHERE user_id = ?')
  deleteSyncRecords.run(userId)
}

/**
 * Delete user account and all associated data.
 */
export function deleteUser(userId: string): void {
  resetUserData(userId)
  const deleteUser = db.prepare('DELETE FROM users WHERE id = ?')
  deleteUser.run(userId)
}
