import { db } from '../db/schema'
import { SyncRecord, SyncTables, TableName, ALL_TABLES, UserRecord } from './types'
import {
  ArchiveRepairContext,
  getMisappliedArchiveRepairTime
} from './archive_repair'

let lastIssuedServerTime = 0

// 设备本地状态键：曾被旧版客户端当普通设置上传，把某台设备缓存的
// 'false' 能力标志下发到所有设备，导致备忘录同步被整体剔除。
// 服务端拒绝摄入这些键，并在启动时清掉历史污染记录，旧客户端未升级也能自愈。
export const DEVICE_LOCAL_SETTING_KEYS = [
  'serverSupportsMemoSync',
  'memoLastSyncTime',
  'memoServerSyncCursor'
] as const

export function purgeDeviceLocalSettingRecords(): number {
  const placeholders = DEVICE_LOCAL_SETTING_KEYS.map(() => '?').join(', ')
  const info = db
    .prepare(
      `DELETE FROM sync_records WHERE table_name = 'settings' AND record_id IN (${placeholders})`
    )
    .run(...DEVICE_LOCAL_SETTING_KEYS)
  return info.changes
}

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
 * Apply incoming records from client. Deleted records are terminal tombstones;
 * ordinary updates cannot resurrect them.
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
  if (tableName === 'settings') {
    return applyClientSettingsRecords(userId, records)
  }

  const selectStmt = db.prepare(`
    SELECT record_id, data_json, updated_at, deleted, server_updated_at
    FROM sync_records
    WHERE user_id = ? AND table_name = ? AND record_id = ?
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
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `)

  const updateStmt = db.prepare(`
    UPDATE sync_records
    SET data_json = ?,
        updated_at = ?,
        server_updated_at = ?,
        deleted = ?
    WHERE user_id = ? AND table_name = ? AND record_id = ?
  `)

  let count = 0
  for (const record of records) {
    const existing = selectStmt.get(userId, tableName, record.id) as UserRecord | undefined
    const incomingDeleted = record.deleted === true

    if (!existing) {
      insertStmt.run(
        userId,
        tableName,
        record.id,
        JSON.stringify({ ...record.data, updatedAt: record.updatedAt, deleted: incomingDeleted }),
        record.updatedAt,
        nextServerChangeTime(),
        incomingDeleted ? 1 : 0
      )
      count++
      continue
    }

    if (incomingDeleted) {
      if (existing.deleted === 1 && record.updatedAt <= existing.updated_at) {
        count++
        continue
      }
      const tombstoneUpdatedAt = Math.max(existing.updated_at, record.updatedAt)
      updateStmt.run(
        JSON.stringify({ ...record.data, updatedAt: tombstoneUpdatedAt, deleted: true }),
        tombstoneUpdatedAt,
        nextServerChangeTime(),
        1,
        userId,
        tableName,
        record.id
      )
      count++
      continue
    }

    if (existing.deleted === 1) {
      count++
      continue
    }

    if (record.updatedAt > existing.updated_at) {
      updateStmt.run(
        JSON.stringify({ ...record.data, updatedAt: record.updatedAt, deleted: false }),
        record.updatedAt,
        nextServerChangeTime(),
        0,
        userId,
        tableName,
        record.id
      )
    }
    count++
  }

  return count
}

function applyClientSettingsRecords(userId: string, records: SyncRecord[]): number {
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
    VALUES (?, 'settings', ?, ?, ?, ?, ?)
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
    if ((DEVICE_LOCAL_SETTING_KEYS as readonly string[]).includes(record.id)) {
      continue
    }
    stmt.run(
      userId,
      record.id,
      JSON.stringify(record.data),
      record.updatedAt,
      nextServerChangeTime(),
      record.deleted ? 1 : 0
    )
    count++
  }

  return count
}

export function applyClientTables(userId: string, tables: Partial<SyncTables>): number {
  const applyTables = db.transaction(() => {
    let recordsReceived = 0
    for (const tableName of ALL_TABLES) {
      const records = tables[tableName]
      if (Array.isArray(records)) {
        recordsReceived += applyClientRecords(userId, tableName, records)
      }
    }
    repairMisappliedTaskArchives(userId)
    return recordsReceived
  })

  return applyTables()
}

interface ArchiveRepairRow {
  user_id: string
  record_id: string
  data_json: string
  updated_at: number
  deleted: number
}

function repairMisappliedTaskArchives(userId?: string): number {
  const userClause = userId ? ' AND user_id = ?' : ''
  const queryArgs = userId ? [userId] : []
  const listRows = db.prepare(`
    SELECT user_id, record_id, data_json, updated_at, deleted
    FROM sync_records
    WHERE table_name = 'lists'${userClause}
  `).all(...queryArgs) as ArchiveRepairRow[]

  const contexts = new Map<string, ArchiveRepairContext>()
  for (const row of listRows) {
    const data = parseDataJson(row.data_json)
    const context = contexts.get(row.user_id) || {
      activeListIds: new Set<string>(),
      archivedListTimes: new Set<number>()
    }
    if (row.deleted === 0 && data.archived !== true) {
      context.activeListIds.add(row.record_id)
    }
    if (
      data.archived === true &&
      typeof data.archivedAt === 'number' &&
      Number.isSafeInteger(data.archivedAt)
    ) {
      context.archivedListTimes.add(data.archivedAt)
    }
    contexts.set(row.user_id, context)
  }

  if (contexts.size === 0) return 0
  const taskRows = db.prepare(`
    SELECT user_id, record_id, data_json, updated_at, deleted
    FROM sync_records
    WHERE table_name = 'tasks' AND deleted = 0${userClause}
  `).all(...queryArgs) as ArchiveRepairRow[]
  const updateStmt = db.prepare(`
    UPDATE sync_records
    SET data_json = ?, updated_at = ?, server_updated_at = ?, deleted = 0
    WHERE user_id = ? AND table_name = 'tasks' AND record_id = ? AND deleted = 0
  `)

  let repaired = 0
  for (const row of taskRows) {
    const context = contexts.get(row.user_id)
    if (!context) continue
    const data = parseDataJson(row.data_json)
    const versions = readTaskFieldVersions(data, row.updated_at)
    const repairUpdatedAt = getMisappliedArchiveRepairTime(
      data,
      row.updated_at,
      {
        listId: versions.listId,
        archived: versions.archived,
        archivedAt: versions.archivedAt
      },
      context
    )
    if (repairUpdatedAt === null) continue

    versions.archived = repairUpdatedAt
    versions.archivedAt = repairUpdatedAt
    const repairedData = withTaskFieldVersions(
      {...data, archived: false, archivedAt: null},
      versions,
      repairUpdatedAt,
      false
    )
    updateStmt.run(
      JSON.stringify(repairedData),
      repairUpdatedAt,
      nextServerChangeTime(),
      row.user_id,
      row.record_id
    )
    repaired++
  }
  return repaired
}

export function repairAllMisappliedTaskArchives(): number {
  return db.transaction(() => repairMisappliedTaskArchives())()
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
      if (existing.deleted === 1 && record.updatedAt <= existing.updated_at) {
        count++
        continue
      }
      const tombstoneUpdatedAt = Math.max(existing.updated_at, record.updatedAt)
      const normalizedData = withTaskFieldVersions(
        record.data,
        incomingVersions,
        tombstoneUpdatedAt,
        true
      )
      updateStmt.run(
        JSON.stringify(normalizedData),
        tombstoneUpdatedAt,
        nextServerChangeTime(),
        1,
        userId,
        record.id
      )
      count++
      continue
    }

    if (existing.deleted === 1) {
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
