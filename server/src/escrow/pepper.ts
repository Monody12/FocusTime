import { randomBytes } from 'crypto'
import { db } from '../db/schema'

/// 取用户 pepper；不存在则生成 32 字节随机值并落库。
///
/// pepper 只下发给通过鉴权的设备：客户端用它 + 账号密码本地派生托管密钥，
/// 服务器端不参与任何密钥派生，仅用于抬高数据库泄露后的离线爆破成本。
export function getOrCreatePepper (userId: string): string {
  const row = db
    .prepare('SELECT pepper FROM users WHERE id = ?')
    .get(userId) as { pepper?: string | null } | undefined
  if (row?.pepper) return row.pepper
  const pepper = randomBytes(32).toString('base64')
  db.prepare('UPDATE users SET pepper = ?, updated_at = ? WHERE id = ?').run(
    pepper,
    Date.now(),
    userId
  )
  return pepper
}
