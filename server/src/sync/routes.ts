import { Router, Response } from 'express'
import { z } from 'zod'
import { AuthRequest, authMiddleware } from '../auth/middleware'
import {
  applyClientTables,
  getCurrentServerCursor,
  getServerChanges,
  logSync,
  resetUserData
} from './algorithm'
import { TableName, ALL_TABLES, SyncRecord, SyncTables } from './types'

const router = Router()
const maxRecordsPerRequest = 50_000
const syncRecordSchema = z.object({
  id: z.string().min(1).max(256),
  updatedAt: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
  data: z.record(z.unknown()),
  deleted: z.boolean().optional()
}).strict()

// Apply auth middleware to all sync routes
router.use(authMiddleware)

// POST /api/sync - Main sync endpoint
router.post('/', (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!
    const lastSyncTime = req.body?.lastSyncTime
    const tables = req.body?.tables

    if (!Number.isSafeInteger(lastSyncTime) || lastSyncTime < 0) {
      res.status(400).json({ error: 'lastSyncTime 必须是非负整数' })
      return
    }

    if (!tables || typeof tables !== 'object' || Array.isArray(tables)) {
      res.status(400).json({ error: 'tables 必须是对象' })
      return
    }

    const validatedTables: Partial<SyncTables> = {}
    let totalRecords = 0
    const clientTables = Object.keys(tables)
    for (const tableName of clientTables) {
      if (!ALL_TABLES.includes(tableName as TableName)) {
        res.status(400).json({ error: `无效的数据表: ${tableName}` })
        return
      }
      const records = tables[tableName]
      if (!Array.isArray(records)) {
        res.status(400).json({ error: `${tableName} 必须是记录数组` })
        return
      }
      totalRecords += records.length
      if (totalRecords > maxRecordsPerRequest) {
        res.status(413).json({ error: '单次同步记录过多，请缩小同步批次' })
        return
      }
      const parsedRecords = z.array(syncRecordSchema).safeParse(records)
      if (!parsedRecords.success) {
        res.status(400).json({ error: `${tableName} 包含无效记录` })
        return
      }
      validatedTables[tableName as TableName] = parsedRecords.data as SyncRecord[]
    }

    // Apply incoming records from client in a single transaction.
    const recordsReceived = applyClientTables(userId, validatedTables)

    // Get changes from server using the server-side change cursor. Client
    // edit timestamps are still used inside each record for conflict handling.
    const serverChanges = getServerChanges(userId, lastSyncTime)
    const serverLastSync = getCurrentServerCursor()

    // Build response
    const responseTables: SyncTables = {} as SyncTables
    for (const tableName of ALL_TABLES) {
      responseTables[tableName as TableName] = serverChanges.get(tableName as TableName) || []
    }

    // Log sync operation (wrapped in try-catch: logging failure must not break the sync response)
    try {
      const recordsSent = ALL_TABLES.reduce(
        (total, tableName) => total + (responseTables[tableName]?.length || 0),
        0
      )
      logSync(userId, serverLastSync, lastSyncTime, recordsSent, recordsReceived)
    } catch (logErr) {
      console.error('logSync failed (non-fatal):', logErr)
    }

    res.json({
      serverLastSync,
      tables: responseTables
    })
  } catch (error) {
    console.error('Sync error:', error)
    res.status(500).json({ error: 'Sync failed' })
  }
})

// DELETE /api/sync/reset - Reset all user data
router.delete('/reset', (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!
    const confirm = req.body?.confirm

    if (confirm !== true) {
      res.status(400).json({ error: 'confirm must be true' })
      return
    }

    resetUserData(userId)
    res.json({ success: true })
  } catch (error) {
    console.error('Reset error:', error)
    res.status(500).json({ error: 'Reset failed' })
  }
})

export default router
