import express from 'express'
import cors from 'cors'
import { db, initDatabase } from './db/schema'
import authRoutes from './auth/routes'
import syncRoutes from './sync/routes'
import { repairAllMisappliedTaskArchives } from './sync/algorithm'

const PORT = Number.parseInt(process.env.PORT || '6677', 10)
const HOST = process.env.HOST?.trim() || '127.0.0.1'
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65_535) {
  throw new Error('PORT must be an integer between 1 and 65535')
}
const allowedOrigins = new Set(
  (process.env.CORS_ORIGINS || 'https://focus.dluserver.cn')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
)

type HttpError = Error & { status?: number }

const authAttempts = new Map<string, { count: number; resetAt: number }>()
const authWindowMs = 15 * 60 * 1000
const authAttemptLimit = 20
let lastAuthCleanup = 0

function cleanupExpiredAuthAttempts(now: number): void {
  if (now - lastAuthCleanup < 60_000) return
  lastAuthCleanup = now
  for (const [key, attempt] of authAttempts) {
    if (attempt.resetAt <= now) authAttempts.delete(key)
  }
}

function authRateLimit(
  req: express.Request,
  res: express.Response,
  next: express.NextFunction,
): void {
  const now = Date.now()
  cleanupExpiredAuthAttempts(now)
  const remoteAddress = req.socket.remoteAddress || ''
  const fromLocalProxy = remoteAddress === '127.0.0.1' ||
    remoteAddress === '::1' ||
    remoteAddress === '::ffff:127.0.0.1'
  // Trust X-Forwarded-For only when the TCP peer is the local Nginx proxy.
  // Direct clients must not be able to rotate the rate-limit key themselves.
  const key = fromLocalProxy ? (req.ip || remoteAddress) : (remoteAddress || 'unknown')
  const current = authAttempts.get(key)
  const attempt = current && current.resetAt > now
    ? current
    : { count: 0, resetAt: now + authWindowMs }
  attempt.count += 1
  authAttempts.set(key, attempt)

  if (attempt.count > authAttemptLimit) {
    const retryAfter = Math.max(1, Math.ceil((attempt.resetAt - now) / 1000))
    res.setHeader('Retry-After', retryAfter.toString())
    res.status(429).json({ error: '登录尝试过多，请稍后再试' })
    return
  }
  next()
}

// Initialize database
initDatabase()
const repairedTasks = repairAllMisappliedTaskArchives()
if (repairedTasks > 0) {
  console.log(`Repaired ${repairedTasks} task archive sync record(s)`)
}

const app = express()

// Middleware
app.disable('x-powered-by')
app.set('trust proxy', 1)
app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.has(origin)) {
      callback(null, true)
      return
    }
    const error: HttpError = new Error('Origin is not allowed by CORS policy')
    error.status = 403
    callback(error)
  },
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  maxAge: 86400,
}))
app.use(express.json({ limit: '10mb' }))

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: Date.now() })
})

// Auth routes
app.use('/api/auth', authRateLimit, authRoutes)

// Sync routes
app.use('/api/sync', syncRoutes)

// 404 handler
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' })
})

// Error handler
app.use((err: HttpError, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (!err.status || err.status >= 500) {
    console.error('Unhandled error:', err)
  }
  res.status(err.status || 500).json({ error: err.status ? err.message : 'Internal server error' })
})

const server = app.listen(PORT, HOST, () => {
  console.log(`Focus Timer Sync Server running on ${HOST}:${PORT}`)
  console.log(`Health check: http://${HOST}:${PORT}/api/health`)
})

let shuttingDown = false
function shutdown(signal: string): void {
  if (shuttingDown) return
  shuttingDown = true
  console.log(`Received ${signal}, shutting down...`)
  const forceExit = setTimeout(() => process.exit(1), 5_000)
  forceExit.unref()
  server.close(() => {
    db.close()
    clearTimeout(forceExit)
    process.exit(0)
  })
}

process.on('SIGINT', () => shutdown('SIGINT'))
process.on('SIGTERM', () => shutdown('SIGTERM'))
