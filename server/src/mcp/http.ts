import { Router, Request, Response, NextFunction } from 'express'
import { verifyToken } from '../auth/middleware'
import { getUserById } from '../auth/crypto'
import { authenticateMcpToken, jwtAuthContext, AuthContext } from './tokens'
import { handleJsonRpc } from './protocol'
import { executeTool } from './tools'

const router = Router()
const serverVersion = process.env.npm_package_version || '1.10.0'

const defaultAllowedHosts = [
  'focus.dluserver.cn',
  'localhost',
  '127.0.0.1',
  '::1'
]

function parseHost(hostHeader: string): string {
  const trimmed = hostHeader.trim().toLowerCase()
  if (trimmed.startsWith('[')) {
    const end = trimmed.indexOf(']')
    if (end > 0) return trimmed.slice(1, end)
  }
  return trimmed.split(':')[0]
}

function allowedHosts(): Set<string> {
  const extra = (process.env.MCP_ALLOWED_HOSTS || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
  return new Set([...defaultAllowedHosts, ...extra])
}

export function mcpCors(req: Request, res: Response, next: NextFunction): void {
  const origin = req.headers.origin
  if (origin) {
    res.setHeader('Access-Control-Allow-Origin', origin)
    res.setHeader('Vary', 'Origin')
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type, Accept, MCP-Protocol-Version, Mcp-Session-Id'
  )
  res.setHeader('Access-Control-Expose-Headers', 'MCP-Protocol-Version, Mcp-Session-Id')
  if (req.method === 'OPTIONS') {
    res.status(204).end()
    return
  }
  next()
}

export function mcpHostGuard(req: Request, res: Response, next: NextFunction): void {
  const hostHeader = req.headers.host
  if (!hostHeader) {
    next()
    return
  }
  const host = parseHost(hostHeader)
  if (!allowedHosts().has(host)) {
    res.status(403).json({ error: 'Host is not allowed' })
    return
  }
  next()
}

function readBearer(req: Request): string | undefined {
  const header = req.headers.authorization
  if (!header || !header.startsWith('Bearer ')) return undefined
  return header.slice(7).trim()
}

export function authenticateMcpRequest(req: Request): AuthContext | undefined {
  const token = readBearer(req)
  if (!token) return undefined
  const mcp = authenticateMcpToken(token)
  if (mcp) return mcp
  const userId = verifyToken(token)
  if (!userId) return undefined
  const user = getUserById(userId)
  if (!user) return undefined
  return jwtAuthContext(userId)
}

router.post('/', (req, res) => {
  const auth = authenticateMcpRequest(req)
  if (!auth) {
    res.status(401).json({
      jsonrpc: '2.0',
      error: { code: -32001, message: 'Unauthorized' },
      id: null
    })
    return
  }
  const accept = String(req.headers.accept || '')
  if (accept.includes('text/event-stream') && !accept.includes('application/json')) {
    res.setHeader('Content-Type', 'text/event-stream')
    res.setHeader('Cache-Control', 'no-cache')
    const handled = handleJsonRpc(auth, req.body, serverVersion)
    if (handled.status === 202 || handled.payload == null) {
      res.status(202).end()
      return
    }
    res.status(200)
    res.write(`event: message\ndata: ${JSON.stringify(handled.payload)}\n\n`)
    res.end()
    return
  }
  const handled = handleJsonRpc(auth, req.body, serverVersion)
  if (handled.status === 202 || handled.payload == null) {
    res.status(202).end()
    return
  }
  res.setHeader('MCP-Protocol-Version', '2025-03-26')
  res.setHeader('Cache-Control', 'no-store')
  res.status(handled.status).json(handled.payload)
})

router.get('/', (_req, res) => {
  res.setHeader('Allow', 'POST, OPTIONS')
  res.status(405).json({ error: 'MCP 使用 POST JSON-RPC。SSE 流式会话未启用。' })
})

router.delete('/', (_req, res) => {
  res.status(204).end()
})

export function mcpToolInvokeRouter(): Router {
  const invoke = Router()
  invoke.post('/tools/:name', (req, res) => {
    const auth = authenticateMcpRequest(req)
    if (!auth) {
      res.status(401).json({ error: 'Unauthorized' })
      return
    }
    try {
      const result = executeTool(auth, req.params.name, req.body?.arguments ?? req.body)
      res.json({ success: true, result })
    } catch (error) {
      const status = (error as { status?: number }).status || 400
      const message = error instanceof Error ? error.message : '调用失败'
      res.status(status).json({ error: message })
    }
  })
  return invoke
}

export default router
