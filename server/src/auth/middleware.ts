import { Request, Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { getUserById } from './crypto'

function readJwtSecret(): string {
  const secret = process.env.JWT_SECRET
  if (!secret) {
    throw new Error('JWT_SECRET must be configured for the sync service')
  }
  return secret
}

const JWT_SECRET = readJwtSecret()
const JWT_EXPIRY = '7d'

export interface AuthRequest extends Request {
  userId?: string
}

export function generateToken(userId: string): string {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: JWT_EXPIRY })
}

export function verifyToken(token: string): string | null {
  try {
    const decoded = jwt.verify(token, JWT_SECRET)
    if (
      typeof decoded === 'object' &&
      decoded != null &&
      'userId' in decoded &&
      typeof decoded.userId === 'string'
    ) {
      return decoded.userId
    }
    return null
  } catch {
    return null
  }
}

export function authMiddleware(req: AuthRequest, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized' })
    return
  }

  const token = authHeader.substring(7)
  const userId = verifyToken(token)

  if (!userId) {
    res.status(401).json({ error: 'Invalid or expired token' })
    return
  }

  const user = getUserById(userId)
  if (!user) {
    res.status(401).json({ error: 'User not found' })
    return
  }

  req.userId = userId
  next()
}

export { JWT_SECRET }
