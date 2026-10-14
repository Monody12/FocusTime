#!/usr/bin/env node
import { createInterface } from 'node:readline'

const rawUrl = process.env.FOCUSMYTIME_URL?.trim().replace(/\/+$/, '') || ''
const baseUrl = rawUrl.replace(/\/mcp$/i, '')
const token = process.env.FOCUSMYTIME_TOKEN?.trim()

if (!baseUrl || !token) {
  console.error('请设置环境变量 FOCUSMYTIME_URL 和 FOCUSMYTIME_TOKEN')
  console.error('示例：FOCUSMYTIME_URL=https://focus.dluserver.cn FOCUSMYTIME_TOKEN=fmcp_...')
  process.exit(1)
}

const mcpUrl = `${baseUrl}/mcp`

async function forward(message: unknown): Promise<unknown | null> {
  const response = await fetch(mcpUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2025-03-26'
    },
    body: JSON.stringify(message)
  })
  if (response.status === 202) return null
  const contentType = response.headers.get('content-type') || ''
  const text = await response.text()
  if (contentType.includes('text/event-stream')) {
    const dataLine = text
      .split('\n')
      .map((line) => line.trim())
      .find((line) => line.startsWith('data: '))
    if (!dataLine) return null
    return JSON.parse(dataLine.slice(6))
  }
  if (!text) return null
  return JSON.parse(text)
}

function requestId(raw: string): string | number | null {
  try {
    const parsed = JSON.parse(raw) as { id?: string | number | null }
    return parsed.id ?? null
  } catch {
    return null
  }
}

async function handleLine(line: string): Promise<void> {
  const trimmed = line.trim()
  if (!trimmed) return
  try {
    const message = JSON.parse(trimmed) as unknown
    const result = await forward(message)
    if (result != null) {
      process.stdout.write(`${JSON.stringify(result)}\n`)
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'MCP 代理失败'
    process.stdout.write(
      `${JSON.stringify({
        jsonrpc: '2.0',
        id: requestId(trimmed),
        error: { code: -32002, message }
      })}\n`
    )
  }
}

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity })
let queue = Promise.resolve()

rl.on('line', (line) => {
  queue = queue.then(() => handleLine(line))
})

rl.on('close', () => {
  queue.finally(() => process.exit(0))
})
