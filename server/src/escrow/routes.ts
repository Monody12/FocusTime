import { Router, Response } from 'express'
import { AuthRequest, authMiddleware } from '../auth/middleware'
import { getOrCreatePepper } from './pepper'

const router = Router()
router.use(authMiddleware)

// GET /api/escrow/pepper - 返回当前用户的托管 pepper（不存在则生成）
router.get('/pepper', (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!
    const pepper = getOrCreatePepper(userId)
    res.json({ pepper })
  } catch (error) {
    res.status(500).json({
      error: error instanceof Error ? error.message : '获取托管 pepper 失败',
    })
  }
})

export default router
