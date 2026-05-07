import { Router, Response } from 'express'
import { AuthRequest, authMiddleware } from '../auth/middleware'
import { applyClientRecords, getServerChanges, logSync, resetUserData } from './algorithm'
import { TableName, ALL_TABLES, SyncTables } from './types'

const router = Router()

// Apply auth middleware to all sync routes
router.use(authMiddleware)

// POST /api/sync - Main sync endpoint
router.post('/', (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!
    const { lastSyncTime, tables } = req.body

    if (typeof lastSyncTime !== 'number') {
      res.status(400).json({ error: 'lastSyncTime must be a number' })
      return
    }

    if (!tables || typeof tables !== 'object') {
      res.status(400).json({ error: 'tables must be an object' })
      return
    }

    // Validate table names
    const clientTables = Object.keys(tables)
    for (const tableName of clientTables) {
      if (!ALL_TABLES.includes(tableName as TableName)) {
        res.status(400).json({ error: `Invalid table name: ${tableName}` })
        return
      }
    }

    // Apply incoming records from client
    let recordsReceived = 0
    for (const tableName of ALL_TABLES) {
      const records = tables[tableName]
      if (Array.isArray(records)) {
        recordsReceived += applyClientRecords(userId, tableName as TableName, records)
      }
    }

    // Get changes from server
    const serverChanges = getServerChanges(userId, lastSyncTime)
    const serverLastSync = Date.now()

    // Build response
    const responseTables: SyncTables = {} as SyncTables
    for (const tableName of ALL_TABLES) {
      responseTables[tableName as TableName] = serverChanges.get(tableName as TableName) || []
    }

    // Log sync operation (wrapped in try-catch: logging failure must not break the sync response)
    try {
      logSync(userId, serverLastSync, lastSyncTime, responseTables.lists?.length || 0, recordsReceived)
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
    const { confirm } = req.body

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
