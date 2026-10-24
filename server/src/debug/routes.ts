import { Router, Response } from 'express'
import { appendFileSync, existsSync, mkdirSync } from 'fs'
import { join } from 'path'

const router = Router()

const LOG_DIR = join(__dirname, '../../logs')
if (!existsSync(LOG_DIR)) mkdirSync(LOG_DIR, { recursive: true })
const LOG_FILE = join(LOG_DIR, 'debug-breadcrumbs.log')

// POST /api/debug/breadcrumb - 调试构建的面包屑收集（--dart-define=DEBUG_BREADCRUMBS）
// 仅自部署排障用：不带鉴权、只追加日志、单条限长 2KB。
router.post('/breadcrumb', (req, res) => {
  try {
    const entries = req.body?.entries
    if (!Array.isArray(entries)) {
      res.status(400).json({ error: 'entries 必须是数组' })
      return
    }
    const ip =
      (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.ip
    const lines = entries
      .slice(0, 200)
      .map((e) => {
        const text = typeof e === 'string' ? e : JSON.stringify(e)
        return `${new Date().toISOString()} ip=${ip} ${String(text).slice(0, 2048)}`
      })
    appendFileSync(LOG_FILE, lines.join('\n') + '\n')
    res.json({ ok: true, count: lines.length })
  } catch (error) {
    res
      .status(500)
      .json({ error: error instanceof Error ? error.message : '写日志失败' })
  }
})

export default router
