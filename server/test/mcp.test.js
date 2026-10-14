const test = require('node:test')
const assert = require('node:assert/strict')
const { spawn } = require('node:child_process')
const http = require('node:http')
const { mkdtempSync, rmSync } = require('node:fs')
const { tmpdir } = require('node:os')
const { join } = require('node:path')
const { setTimeout: sleep } = require('node:timers/promises')

const PORT = 19100 + Math.floor(Math.random() * 400)
const BASE = `http://127.0.0.1:${PORT}`
const dataDir = mkdtempSync(join(tmpdir(), 'focustime-mcp-'))
const logs = { stdout: '', stderr: '' }
const child = spawn(process.execPath, ['dist/index.js'], {
  cwd: join(__dirname, '..'),
  env: {
    ...process.env,
    PORT: String(PORT),
    HOST: '127.0.0.1',
    JWT_SECRET: 'mcp-test-secret',
    FOCUSMYTIME_DATA_DIR: dataDir,
    OBJECT_STORAGE_ROOT: join(dataDir, 'objects'),
    CORS_ORIGINS: 'https://focus.dluserver.cn'
  },
  stdio: ['ignore', 'pipe', 'pipe']
})
child.stdout.on('data', (chunk) => { logs.stdout += chunk.toString() })
child.stderr.on('data', (chunk) => { logs.stderr += chunk.toString() })

async function waitForServer () {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`${BASE}/api/health`)
      if (res.ok) return
    } catch (_) { /* not ready */ }
    if (child.exitCode != null) {
      throw new Error(`server exited ${child.exitCode}\n${logs.stderr}\n${logs.stdout}`)
    }
    await sleep(200)
  }
  throw new Error(`server did not start\n${logs.stderr}\n${logs.stdout}`)
}

async function register (name) {
  const res = await fetch(`${BASE}/api/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: name, password: 'mcp-test-pass' })
  })
  const text = await res.text()
  assert.ok(res.ok, `register failed: ${res.status} ${text}`)
  return JSON.parse(text)
}

async function jsonRpc (token, method, params, id = 1) {
  const res = await fetch(`${BASE}/mcp`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/json'
    },
    body: JSON.stringify({ jsonrpc: '2.0', id, method, params })
  })
  return { status: res.status, body: await res.json() }
}

async function createMcpToken (jwt, body) {
  const res = await fetch(`${BASE}/api/mcp/tokens`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  })
  const text = await res.text()
  assert.equal(res.status, 201, `create token failed: ${res.status} ${text}`)
  return JSON.parse(text)
}

function toolPayload (rpc) {
  assert.equal(rpc.status, 200)
  assert.equal(rpc.body.result.isError, false, JSON.stringify(rpc.body))
  return JSON.parse(rpc.body.result.content[0].text)
}

function rawPost (headers, body) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: '127.0.0.1',
      port: PORT,
      path: '/mcp',
      method: 'POST',
      headers
    }, (res) => {
      let data = ''
      res.on('data', (chunk) => { data += chunk })
      res.on('end', () => resolve({ status: res.statusCode, body: data }))
    })
    req.on('error', reject)
    req.end(body)
  })
}

test.after(() => {
  child.kill('SIGTERM')
  try {
    rmSync(dataDir, { recursive: true, force: true })
  } catch (_) { /* ignore */ }
})

test.before(async () => {
  await waitForServer()
})

test('health reports mcp capability', async () => {
  const res = await fetch(`${BASE}/api/health`)
  const body = await res.json()
  assert.equal(body.status, 'ok')
  assert.equal(body.mcp, true)
  assert.equal(body.mcpPath, '/mcp')
  assert.equal(body.memoSync, true)
})

test('unauthenticated mcp is rejected', async () => {
  const res = await fetch(`${BASE}/mcp`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} })
  })
  assert.equal(res.status, 401)
})

test('unknown Host is rejected', async () => {
  const result = await rawPost({
    Host: 'evil.example',
    'Content-Type': 'application/json',
    Authorization: 'Bearer skip',
    'Content-Length': '2'
  }, '{}')
  assert.equal(result.status, 403)
})

test('default MCP token is read-only and can create then list tasks with write scope', async () => {
  const user = await register(`mcp-a-${Date.now()}`)
  const readToken = await createMcpToken(user.token, { name: 'reader' })
  assert.match(readToken.token, /^fmcp_/)
  assert.deepEqual(readToken.info.scopes, ['tasks:read', 'sessions:read'])

  const listedTools = await jsonRpc(readToken.token, 'tools/list')
  const toolNames = listedTools.body.result.tools.map((tool) => tool.name)
  assert.equal(toolNames.includes('create_task'), false)
  assert.ok(toolNames.includes('list_tasks'))

  const denied = await jsonRpc(readToken.token, 'tools/call', {
    name: 'create_task',
    arguments: { title: 'should fail' }
  })
  assert.equal(denied.status, 200)
  assert.equal(denied.body.result.isError, true)

  const writeToken = await createMcpToken(user.token, {
    name: 'writer',
    scopes: ['tasks:read', 'tasks:write', 'sessions:read']
  })
  const created = await jsonRpc(writeToken.token, 'tools/call', {
    name: 'create_task',
    arguments: { title: '写周报', dueDate: '2099-01-02', isMyDay: true }
  })
  const task = toolPayload(created)
  assert.equal(task.title, '写周报')
  assert.equal(task.isMyDay, true)

  const listed = await jsonRpc(readToken.token, 'tools/call', {
    name: 'list_tasks',
    arguments: { myDay: true }
  })
  const tasks = toolPayload(listed)
  assert.equal(tasks.some((item) => item.id === task.id), true)

  const byName = await jsonRpc(readToken.token, 'tools/call', {
    name: 'list_tasks',
    arguments: { listId: '我的一天' }
  })
  const named = toolPayload(byName)
  assert.equal(named.some((item) => item.id === task.id), true)

  const other = await register(`mcp-b-${Date.now()}`)
  const otherToken = await createMcpToken(other.token, {
    name: 'other',
    scopes: ['tasks:read', 'tasks:write']
  })
  const foreign = await jsonRpc(otherToken.token, 'tools/call', {
    name: 'get_task',
    arguments: { taskId: task.id }
  })
  assert.equal(foreign.body.result.isError, true)
})

test('initialize lists tools and JWT can call write tools', async () => {
  const user = await register(`mcp-c-${Date.now()}`)
  const init = await jsonRpc(user.token, 'initialize', {
    protocolVersion: '2025-03-26',
    capabilities: {},
    clientInfo: { name: 'test', version: '1' }
  })
  assert.equal(init.body.result.protocolVersion, '2025-03-26')
  assert.ok(init.body.result.capabilities.tools)

  const tools = await jsonRpc(user.token, 'tools/list')
  const names = tools.body.result.tools.map((tool) => tool.name)
  assert.ok(names.includes('create_task'))
  assert.ok(names.includes('complete_task'))
  assert.ok(names.includes('get_calendar_day'))

  const created = await jsonRpc(user.token, 'tools/call', {
    name: 'create_task',
    arguments: { title: '重复任务', recurrence: { frequency: 'daily', interval: 1 } }
  })
  const task = toolPayload(created)
  const completed = await jsonRpc(user.token, 'tools/call', {
    name: 'complete_task',
    arguments: { taskId: task.id }
  })
  const payload = toolPayload(completed)
  assert.equal(payload.task.completed, true)
  assert.ok(payload.nextTask)
  assert.equal(payload.nextTask.completed, false)
})

test('resources and prompts work; sessions tools respect scope', async () => {
  const user = await register(`mcp-f-${Date.now()}`)
  const readOnly = await createMcpToken(user.token, {
    name: 'tasks-only',
    scopes: ['tasks:read']
  })
  const listed = await jsonRpc(readOnly.token, 'resources/list')
  const uris = listed.body.result.resources.map((item) => item.uri)
  assert.ok(uris.includes('focustime://overview'))

  const overview = await jsonRpc(readOnly.token, 'resources/read', {
    uri: 'focustime://overview'
  })
  assert.ok(overview.body.result.contents[0].text.includes('"date"'))

  const prompts = await jsonRpc(readOnly.token, 'prompts/list')
  assert.ok(prompts.body.result.prompts.some((item) => item.name === 'plan_today'))

  const sessionsDenied = await jsonRpc(readOnly.token, 'tools/call', {
    name: 'list_focus_sessions',
    arguments: {}
  })
  assert.equal(sessionsDenied.body.result.isError, true)

  const calendar = await jsonRpc(readOnly.token, 'tools/call', {
    name: 'get_calendar_day',
    arguments: { date: '2099-01-02' }
  })
  const day = toolPayload(calendar)
  assert.equal(day.date, '2099-01-02')
  assert.equal(day.sessions, undefined)
})

test('REST tool invoke and task update round-trip', async () => {
  const user = await register(`mcp-g-${Date.now()}`)
  const created = await fetch(`${BASE}/api/mcp/tools/create_task`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${user.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ title: 'REST 任务', notes: 'via invoke' })
  })
  assert.equal(created.status, 200)
  const body = await created.json()
  assert.equal(body.success, true)
  assert.equal(body.result.title, 'REST 任务')

  const updated = await jsonRpc(user.token, 'tools/call', {
    name: 'update_task',
    arguments: { taskId: body.result.id, isImportant: true, notes: 'updated' }
  })
  const task = toolPayload(updated)
  assert.equal(task.isImportant, true)
  assert.equal(task.notes, 'updated')
})

test('revoked token is rejected', async () => {
  const user = await register(`mcp-d-${Date.now()}`)
  const created = await createMcpToken(user.token, { name: 'temp' })
  const revoked = await fetch(`${BASE}/api/mcp/tokens/${created.info.id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${user.token}` }
  })
  assert.equal(revoked.status, 200)
  const res = await fetch(`${BASE}/mcp`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${created.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} })
  })
  assert.equal(res.status, 401)
})

test('cannot delete system lists', async () => {
  const user = await register(`mcp-e-${Date.now()}`)
  const result = await jsonRpc(user.token, 'tools/call', {
    name: 'delete_list',
    arguments: { listId: 'system-all-tasks' }
  })
  assert.equal(result.body.result.isError, true)
})
