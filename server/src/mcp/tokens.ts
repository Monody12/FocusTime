import { createHash, randomBytes } from 'crypto'
import { db } from '../db/schema'
import { ALL_SCOPES, DEFAULT_SCOPES, McpScope, parseScopes } from './scopes'
import { invalid } from '../domain/errors'

export interface McpTokenRow {
  id: string
  user_id: string
  token_hash: string
  token_prefix: string
  name: string
  scopes: string
  expires_at: number | null
  revoked: number
  last_used_at: number | null
  created_at: number
}

export interface McpTokenInfo {
  id: string
  name: string
  tokenPrefix: string
  scopes: McpScope[]
  expiresAt: number | null
  lastUsedAt: number | null
  createdAt: number
  revoked: boolean
}

export interface AuthContext {
  userId: string
  scopes: McpScope[]
  tokenId?: string
  via: 'mcp' | 'jwt'
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

function toInfo(row: McpTokenRow): McpTokenInfo {
  return {
    id: row.id,
    name: row.name,
    tokenPrefix: row.token_prefix,
    scopes: parseScopes(JSON.parse(row.scopes)),
    expiresAt: row.expires_at,
    lastUsedAt: row.last_used_at,
    createdAt: row.created_at,
    revoked: row.revoked === 1
  }
}

export function listTokens(userId: string): McpTokenInfo[] {
  const rows = db.prepare(
    `SELECT * FROM mcp_tokens WHERE user_id = ? AND revoked = 0 ORDER BY created_at DESC`
  ).all(userId) as McpTokenRow[]
  return rows.map(toInfo)
}

export function createToken(
  userId: string,
  input: { name: string; scopes?: unknown; expiresInDays?: number | null }
): { token: string; info: McpTokenInfo } {
  const name = input.name.trim()
  if (!name || name.length > 64) throw invalid('令牌名称需为 1-64 个字符')
  const scopes = parseScopes(input.scopes)
  const resolved = scopes.length > 0 ? scopes : DEFAULT_SCOPES
  const now = Date.now()
  let expiresAt: number | null = null
  if (input.expiresInDays != null) {
    if (!Number.isInteger(input.expiresInDays) || input.expiresInDays < 1 || input.expiresInDays > 3650) {
      throw invalid('expiresInDays 必须是 1-3650 的整数')
    }
    expiresAt = now + input.expiresInDays * 24 * 60 * 60 * 1000
  }
  const secret = randomBytes(32).toString('base64url')
  const token = `fmcp_${secret}`
  const id = randomBytes(16).toString('hex')
  db.prepare(
    `INSERT INTO mcp_tokens
      (id, user_id, token_hash, token_prefix, name, scopes, expires_at, revoked, last_used_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL, ?)`
  ).run(
    id,
    userId,
    hashToken(token),
    token.slice(0, 12),
    name,
    JSON.stringify(resolved),
    expiresAt,
    now
  )
  const row = db.prepare('SELECT * FROM mcp_tokens WHERE id = ?').get(id) as McpTokenRow
  return { token, info: toInfo(row) }
}

export function revokeToken(userId: string, tokenId: string): boolean {
  const result = db.prepare(
    `UPDATE mcp_tokens SET revoked = 1 WHERE id = ? AND user_id = ? AND revoked = 0`
  ).run(tokenId, userId)
  return result.changes > 0
}

export function authenticateMcpToken(token: string): AuthContext | undefined {
  if (!token.startsWith('fmcp_')) return undefined
  const row = db.prepare(
    `SELECT * FROM mcp_tokens WHERE token_hash = ?`
  ).get(hashToken(token)) as McpTokenRow | undefined
  if (!row || row.revoked === 1) return undefined
  if (row.expires_at != null && row.expires_at < Date.now()) return undefined
  db.prepare('UPDATE mcp_tokens SET last_used_at = ? WHERE id = ?').run(Date.now(), row.id)
  return {
    userId: row.user_id,
    scopes: parseScopes(JSON.parse(row.scopes)),
    tokenId: row.id,
    via: 'mcp'
  }
}

export function jwtAuthContext(userId: string): AuthContext {
  return { userId, scopes: ALL_SCOPES, via: 'jwt' }
}
