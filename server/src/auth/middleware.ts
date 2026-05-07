import { Request, Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { getUserById } from './crypto'

const JWT_SECRET = process.env.JWT_SECRET || 'focus-timer-sync-secret-key-change-in-production'
const JWT_EXPIRY = '7d'

export interface AuthRequest extends Request {
  userId?: string
}

export function generateToken(userId: string): string {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: JWT_EXPIRY })
}

export function verifyToken(token: string): string | null {
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string }
    return decoded.userId
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