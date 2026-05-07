import { db } from '../db/schema'
import bcrypt from 'bcrypt'
import { v4 as uuidv4 } from 'uuid'

const SALT_ROUNDS = 12

export interface User {
  id: string
  username: string
  password_hash: string
  created_at: number
  updated_at: number
}

export async function createUser(username: string, password: string): Promise<User> {
  const id = uuidv4()
  const password_hash = await bcrypt.hash(password, SALT_ROUNDS)
  const now = Date.now()

  const stmt = db.prepare(`
    INSERT INTO users (id, username, password_hash, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?)
  `)

  stmt.run(id, username, password_hash, now, now)

  return { id, username, password_hash, created_at: now, updated_at: now }
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash)
}

export function getUserByUsername(username: string): User | undefined {
  const stmt = db.prepare('SELECT * FROM users WHERE username = ?')
  return stmt.get(username) as User | undefined
}

export function getUserById(id: string): User | undefined {
  const stmt = db.prepare('SELECT * FROM users WHERE id = ?')
  return stmt.get(id) as User | undefined
}

export function isUsernameTaken(username: string): boolean {
  const stmt = db.prepare('SELECT 1 FROM users WHERE username = ?')
  return !!stmt.get(username)
}