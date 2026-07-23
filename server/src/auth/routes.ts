import { Router, Request, Response } from 'express'
import { z } from 'zod'
import { createUser, verifyPassword, isUsernameTaken, getUserByUsername } from './crypto'
import { generateToken } from './middleware'

const router = Router()
const usernameSchema = z.string().trim().min(3).max(32)
const registerSchema = z.object({
  username: usernameSchema,
  password: z.string()
    .min(6)
    .refine((value) => Buffer.byteLength(value, 'utf8') <= 72)
}).strict()
const loginSchema = z.object({
  username: usernameSchema,
  password: z.string().min(1).max(1024)
}).strict()

router.post('/register', async (req: Request, res: Response) => {
  try {
    const parsed = registerSchema.safeParse(req.body)
    if (!parsed.success) {
      res.status(400).json({ error: '用户名需为 3-32 个字符，密码需为 6-72 字节' })
      return
    }
    const { username, password } = parsed.data

    if (isUsernameTaken(username)) {
      res.status(409).json({ error: 'Username already exists' })
      return
    }

    const user = await createUser(username, password)
    const token = generateToken(user.id)

    res.json({ success: true, userId: user.id, token })
  } catch (error) {
    if ((error as { code?: string }).code?.startsWith('SQLITE_CONSTRAINT')) {
      res.status(409).json({ error: '用户名已存在' })
      return
    }
    console.error('Register error:', error)
    res.status(500).json({ error: 'Registration failed' })
  }
})

router.post('/login', async (req: Request, res: Response) => {
  try {
    const parsed = loginSchema.safeParse(req.body)
    if (!parsed.success) {
      res.status(400).json({ error: '请输入有效的用户名和密码' })
      return
    }
    const { username, password } = parsed.data

    const user = getUserByUsername(username)
    if (!user) {
      res.status(401).json({ error: '用户名或密码错误' })
      return
    }

    const valid = await verifyPassword(password, user.password_hash)
    if (!valid) {
      res.status(401).json({ error: '用户名或密码错误' })
      return
    }

    const token = generateToken(user.id)

    res.json({ success: true, userId: user.id, token })
  } catch (error) {
    console.error('Login error:', error)
    res.status(500).json({ error: 'Login failed' })
  }
})

export default router
