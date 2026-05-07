import { Router, Request, Response } from 'express'
import { createUser, verifyPassword, isUsernameTaken, getUserByUsername } from './crypto'
import { generateToken } from './middleware'

const router = Router()

router.post('/register', async (req: Request, res: Response) => {
  try {
    const { username, password } = req.body

    if (!username || !password) {
      res.status(400).json({ error: 'Username and password are required' })
      return
    }

    if (username.length < 3 || username.length > 32) {
      res.status(400).json({ error: 'Username must be 3-32 characters' })
      return
    }

    if (password.length < 6) {
      res.status(400).json({ error: 'Password must be at least 6 characters' })
      return
    }

    if (isUsernameTaken(username)) {
      res.status(409).json({ error: 'Username already exists' })
      return
    }

    const user = await createUser(username, password)
    const token = generateToken(user.id)

    res.json({ success: true, userId: user.id, token })
  } catch (error) {
    console.error('Register error:', error)
    res.status(500).json({ error: 'Registration failed' })
  }
})

router.post('/login', async (req: Request, res: Response) => {
  try {
    const { username, password } = req.body

    if (!username || !password) {
      res.status(400).json({ error: 'Username and password are required' })
      return
    }

    const user = getUserByUsername(username)
    if (!user) {
      res.status(401).json({ error: 'Invalid credentials' })
      return
    }

    const valid = await verifyPassword(password, user.password_hash)
    if (!valid) {
      res.status(401).json({ error: 'Invalid credentials' })
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