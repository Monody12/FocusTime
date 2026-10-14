import { Router, Response } from 'express'
import { z } from 'zod'
import { AuthRequest, authMiddleware } from '../auth/middleware'
import { createToken, listTokens, revokeToken } from './tokens'
import { DomainError } from '../domain/errors'

const router = Router()
router.use(authMiddleware)

const createSchema = z.object({
  name: z.string().trim().min(1).max(64),
  scopes: z.array(z.enum(['tasks:read', 'tasks:write', 'sessions:read'])).optional(),
  expiresInDays: z.number().int().min(1).max(3650).nullable().optional()
}).strict()

router.get('/tokens', (req: AuthRequest, res: Response) => {
  res.json({ success: true, tokens: listTokens(req.userId!) })
})

router.post('/tokens', (req: AuthRequest, res: Response) => {
  const parsed = createSchema.safeParse(req.body)
  if (!parsed.success) {
    res.status(400).json({ error: '令牌名称必填；scopes 可选，默认只读' })
    return
  }
  try {
    const created = createToken(req.userId!, parsed.data)
    res.status(201).json({
      success: true,
      token: created.token,
      info: created.info
    })
  } catch (error) {
    if (error instanceof DomainError) {
      res.status(error.status).json({ error: error.message })
      return
    }
    res.status(500).json({ error: '创建令牌失败' })
  }
})

router.delete('/tokens/:id', (req: AuthRequest, res: Response) => {
  const revoked = revokeToken(req.userId!, req.params.id)
  if (!revoked) {
    res.status(404).json({ error: '令牌不存在或已撤销' })
    return
  }
  res.json({ success: true })
})

export default router
