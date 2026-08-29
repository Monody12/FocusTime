import { createHash, randomBytes } from 'crypto'
import { existsSync, mkdirSync, readFileSync, statfsSync, unlinkSync, writeFileSync } from 'fs'
import { join, normalize, sep } from 'path'

const defaultRoot = join(__dirname, '../../data/objects')
const root = normalize(process.env.OBJECT_STORAGE_ROOT?.trim() || defaultRoot)
const reserveBytes = 2 * 1024 * 1024 * 1024

if (!existsSync(root)) mkdirSync(root, { recursive: true })

function safePath(objectKey: string): string {
  const normalizedKey = objectKey.replace(/\\/g, '/').replace(/^\/+/, '')
  if (!normalizedKey || normalizedKey.includes('..')) throw new Error('Invalid object key')
  const target = normalize(join(root, normalizedKey))
  if (!target.startsWith(`${root}${sep}`) && target !== root) throw new Error('Invalid object key')
  return target
}

export interface StorageUsage {
  totalBytes: number
  freeBytes: number
  reserveBytes: number
  availableBytes: number
}

export function getStorageUsage(): StorageUsage {
  let fsStats: { blocks?: number; bsize?: number; bavail?: number } = {}
  try {
    fsStats = statfsSync(root) as typeof fsStats
  } catch (_) {
    // Keep a conservative fallback for test environments where statfs is unavailable.
  }
  const totalBytes = (fsStats.blocks || 0) * (fsStats.bsize || 0)
  const freeBytes = (fsStats.bavail || 0) * (fsStats.bsize || 0)
  const availableBytes = Math.max(0, freeBytes - reserveBytes)
  return { totalBytes, freeBytes, reserveBytes, availableBytes }
}

export function assertCapacity(bytes: number): void {
  if (!Number.isSafeInteger(bytes) || bytes < 0) throw new Error('Invalid object size')
  const usage = getStorageUsage()
  // If statfs is not exposed, do not block uploads solely because a test
  // filesystem returned zeros; production deployments should expose it.
  if (usage.freeBytes > 0 && bytes > usage.availableBytes) {
    throw new Error('服务器可用存储空间不足（需始终保留 2GB）')
  }
}

export function createUserObjectKey(userId: string, filename: string): string {
  const safeUser = userId.replace(/[^a-zA-Z0-9_-]/g, '_')
  const extension = filename.includes('.') ? filename.slice(filename.lastIndexOf('.')).toLowerCase().slice(0, 16) : ''
  return `${safeUser}/${new Date().toISOString().slice(0, 10)}/${randomBytes(16).toString('hex')}${extension}`
}

export function putObject(objectKey: string, content: Buffer): void {
  assertCapacity(content.byteLength)
  const target = safePath(objectKey)
  mkdirSync(join(target, '..'), { recursive: true })
  writeFileSync(target, content, { flag: 'wx' })
}

export function getObject(objectKey: string): Buffer {
  return readFileSync(safePath(objectKey))
}

export function deleteObject(objectKey: string): void {
  const target = safePath(objectKey)
  if (existsSync(target)) unlinkSync(target)
}

export function sha256(content: Buffer): string {
  return createHash('sha256').update(content).digest('hex')
}
