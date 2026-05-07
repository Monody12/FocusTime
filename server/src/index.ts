import express from 'express'
import cors from 'cors'
import { initDatabase } from './db/schema'
import authRoutes from './auth/routes'
import syncRoutes from './sync/routes'

const PORT = process.env.PORT || 6677

// Initialize database
initDatabase()

const app = express()

// Middleware
app.use(cors())
app.use(express.json({ limit: '10mb' }))

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: Date.now() })
})

// Auth routes
app.use('/api/auth', authRoutes)

// Sync routes
app.use('/api/sync', syncRoutes)

// 404 handler
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' })
})

// Error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err)
  res.status(500).json({ error: 'Internal server error' })
})

app.listen(PORT, () => {
  console.log(`Focus Timer Sync Server running on port ${PORT}`)
  console.log(`Health check: http://localhost:${PORT}/api/health`)
})

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down...')
  process.exit(0)
})

process.on('SIGTERM', () => {
  console.log('Shutting down...')
  process.exit(0)
})