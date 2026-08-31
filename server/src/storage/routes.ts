import { Router, Response } from 'express'
import { createHash, randomBytes } from 'crypto'
import { z } from 'zod'
import { AuthRequest, authMiddleware } from '../auth/middleware'
import { db } from '../db/schema'
import {
  createUserObjectKey,
  deleteObject,
  getObject,
  getStorageUsage,
  putObject,
  sha256,
} from './object_storage'

const router = Router()
router.use(authMiddleware)

const uploadSchema = z.object({
  filename: z.string().min(1).max(255),
  mimeType: z.string().min(1).max(120),
  contentBase64: z.string().min(1).max(15 * 1024 * 1024),
  private: z.boolean().optional().default(false),
}).strict()

router.get('/usage', (req: AuthRequest, res: Response) => {
  try {
    res.json({ success: true, usage: getStorageUsage() })
  } catch (error) {
    console.error('Storage usage error:', error)
    res.status(500).json({ error: '无法读取存储空间' })
  }
})

router.post('/upload', (req: AuthRequest, res: Response) => {
  try {
    const parsed = uploadSchema.safeParse(req.body)
    if (!parsed.success) {
      res.status(400).json({ error: '上传参数无效' })
      return
    }
    const content = Buffer.from(parsed.data.contentBase64, 'base64')
    const objectKey = createUserObjectKey(req.userId!, parsed.data.filename)
    putObject(objectKey, content)
    res.status(201).json({
      success: true,
      objectKey,
      sizeBytes: content.byteLength,
      sha256: sha256(content),
      mimeType: parsed.data.mimeType,
      isPrivate: parsed.data.private,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : '上传失败'
    res.status(message.includes('存储空间') ? 507 : 400).json({ error: message })
  }
})

router.get('/download/:objectKey(*)', (req: AuthRequest, res: Response) => {
  try {
    const objectKey = req.params.objectKey
    if (!objectKey.startsWith(`${req.userId}/`)) {
      res.status(403).json({ error: '无权访问该附件' })
      return
    }
    const content = getObject(objectKey)
    res.setHeader('Cache-Control', 'private, max-age=300')
    res.send(content)
  } catch (_) {
    res.status(404).json({ error: '附件不存在' })
  }
})

router.post('/shares', (req: AuthRequest, res: Response) => {
  const schema = z.object({
    objectKey: z.string().min(1).max(512),
    expiresAt: z.number().int().positive().nullable().optional(),
    password: z.string().min(8).max(200).nullable().optional(),
  }).strict()
  try {
    const parsed = schema.safeParse(req.body)
    if (!parsed.success || !parsed.data.objectKey.startsWith(`${req.userId}/`)) {
      res.status(400).json({ error: '分享参数无效' })
      return
    }
    const token = randomBytes(24).toString('base64url')
    const tokenHash = createHash('sha256').update(token).digest('hex')
    const id = randomBytes(16).toString('hex')
    db.prepare(`
      INSERT INTO object_shares (id, user_id, object_key, token_hash, expires_at, password_hash, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      req.userId,
      parsed.data.objectKey,
      tokenHash,
      parsed.data.expiresAt ?? null,
      parsed.data.password ? createHash('sha256').update(parsed.data.password).digest('hex') : null,
      Date.now(),
    )
    res.status(201).json({ success: true, token, shareId: id })
  } catch (error) {
    console.error('Create share error:', error)
    res.status(500).json({ error: '创建分享失败' })
  }
})

router.delete('/shares/:id', (req: AuthRequest, res: Response) => {
  const result = db.prepare('UPDATE object_shares SET revoked = 1 WHERE id = ? AND user_id = ?').run(req.params.id, req.userId)
  res.json({ success: result.changes > 0 })
})

export const publicStorageRouter = Router()
publicStorageRouter.get('/:token', (req, res) => {
  try {
    const tokenHash = createHash('sha256').update(req.params.token).digest('hex')
    const share = db.prepare('SELECT * FROM object_shares WHERE token_hash = ? AND revoked = 0').get(tokenHash) as {
      object_key: string
      expires_at: number | null
      password_hash: string | null
    } | undefined
    if (!share || (share.expires_at !== null && share.expires_at < Date.now())) {
      res.status(404).json({ error: '分享已失效' })
      return
    }
    if (share.password_hash) {
      const supplied = req.header('X-Share-Password') || ''
      const hash = createHash('sha256').update(supplied).digest('hex')
      if (hash !== share.password_hash) {
        res.status(401).json({ error: '需要分享密码' })
        return
      }
    }
    res.send(getObject(share.object_key))
  } catch (_) {
    res.status(404).json({ error: '分享已失效' })
  }
})

router.delete('/objects/:objectKey(*)', (req: AuthRequest, res: Response) => {
  try {
    const objectKey = req.params.objectKey
    if (!objectKey.startsWith(`${req.userId}/`)) {
      res.status(403).json({ error: '无权删除该附件' })
      return
    }
    deleteObject(objectKey)
    db.prepare(
      'UPDATE object_shares SET revoked = 1 WHERE object_key = ? AND user_id = ? AND revoked = 0',
    ).run(objectKey, req.userId)
    res.json({ success: true })
  } catch (_) {
    res.status(404).json({ error: '附件不存在' })
  }
})

export default router
