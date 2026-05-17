import { db } from '../db/schema'
import { SyncRecord, TableName, ALL_TABLES, UserRecord } from './types'

interface ChangeResult {
  sent: number
  received: number
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

  const stmt = db.prepare(`
    INSERT INTO sync_records (user_id, table_name, record_id, data_json, updated_at, deleted)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, table_name, record_id) DO UPDATE SET
      data_json = CASE
        WHEN excluded.updated_at > sync_records.updated_at THEN excluded.data_json
        ELSE sync_records.data_json
      END,
      updated_at = CASE
        WHEN excluded.updated_at > sync_records.updated_at THEN excluded.updated_at
        ELSE sync_records.updated_at
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
    stmt.run(userId, tableName, record.id, dataJson, record.updatedAt, deleted)
    count++
  }

  return count
}

/**
 * Get all records for a user that have been modified since lastSyncTime.
 */
export function getServerChanges(
  userId: string,
  lastSyncTime: number
): Map<TableName, SyncRecord[]> {
  const result = new Map<TableName, SyncRecord[]>()

  for (const tableName of ALL_TABLES) {
    const stmt = db.prepare(`
      SELECT record_id, data_json, updated_at, deleted
      FROM sync_records
      WHERE user_id = ? AND table_name = ? AND (updated_at > ? OR deleted = 1)
      ORDER BY updated_at ASC
    `)

    const rows = stmt.all(userId, tableName, lastSyncTime) as UserRecord[]

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