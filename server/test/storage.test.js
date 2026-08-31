const test = require('node:test')
const assert = require('node:assert/strict')
const { spawn } = require('node:child_process')
const { mkdtempSync, rmSync } = require('node:fs')
const { tmpdir } = require('node:os')
const { join } = require('node:path')
const { setTimeout: sleep } = require('node:timers/promises')

const PORT = 18700 + Math.floor(Math.random() * 500)
const BASE = `http://127.0.0.1:${PORT}`
const objectRoot = mkdtempSync(join(tmpdir(), 'focustime-storage-'))
const child = spawn(process.execPath, ['dist/index.js'], {
  cwd: join(__dirname, '..'),
  env: {
    ...process.env,
    PORT: String(PORT),
    JWT_SECRET: 'storage-test-secret',
    OBJECT_STORAGE_ROOT: objectRoot
  },
  stdio: ['ignore', 'pipe', 'pipe']
})

async function waitForServer () {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`${BASE}/api/health`)
      if (res.ok) return
    } catch (_) { /* not ready yet */ }
    await sleep(200)
  }
  throw new Error('server did not start')
}

async function register (name) {
  const res = await fetch(`${BASE}/api/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: name, password: 'storage-test-pass' })
  })
  assert.ok(res.ok, `register failed: ${res.status}`)
  return res.json()
}

test.before(async () => {
  await waitForServer()
})

test('upload returns a user-isolated object key and download round-trips', async () => {
  const alice = await register(`storagetest-a-${Date.now()}`)
  const content = Buffer.from('hello storage').toString('base64')
  const res = await fetch(`${BASE}/api/storage/upload`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ filename: 'note.txt', mimeType: 'text/plain', contentBase64: content })
  })
  assert.equal(res.status, 201)
  const body = await res.json()
  assert.ok(body.objectKey.startsWith(`${alice.userId}/`), 'object key must be user prefixed')

  const download = await fetch(`${BASE}/api/storage/download/${encodeURIComponent(body.objectKey)}`, {
    headers: { Authorization: `Bearer ${alice.token}` }
  })
  assert.equal(download.status, 200)
  assert.equal(await download.text(), 'hello storage')
})

test('another user cannot download or delete foreign objects', async () => {
  const alice = await register(`storagetest-a2-${Date.now()}`)
  const bob = await register(`storagetest-b-${Date.now()}`)
  const content = Buffer.from('secret').toString('base64')
  const upload = await fetch(`${BASE}/api/storage/upload`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ filename: 'secret.txt', mimeType: 'text/plain', contentBase64: content })
  })
  const { objectKey } = await upload.json()

  const foreignDownload = await fetch(`${BASE}/api/storage/download/${encodeURIComponent(objectKey)}`, {
    headers: { Authorization: `Bearer ${bob.token}` }
  })
  assert.equal(foreignDownload.status, 403)

  const foreignDelete = await fetch(`${BASE}/api/storage/objects/${encodeURIComponent(objectKey)}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${bob.token}` }
  })
  assert.equal(foreignDelete.status, 403)

  const pathTraversal = await fetch(`${BASE}/api/storage/download/${encodeURIComponent(`${alice.userId}/../${bob.userId}/escape.txt`)}`, {
    headers: { Authorization: `Bearer ${alice.token}` }
  })
  assert.notEqual(pathTraversal.status, 200)
})

test('shares support password, expiry and revocation with hashed tokens', async () => {
  const alice = await register(`storagetest-c-${Date.now()}`)
  const content = Buffer.from('shared content').toString('base64')
  const upload = await fetch(`${BASE}/api/storage/upload`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ filename: 'share.txt', mimeType: 'text/plain', contentBase64: content })
  })
  const { objectKey } = await upload.json()

  // 带密码的分享：无密码 401，带密码 200
  const passwordShare = await fetch(`${BASE}/api/storage/shares`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ objectKey, password: 'share-pass-123' })
  })
  assert.equal(passwordShare.status, 201)
  const passwordBody = await passwordShare.json()

  const withoutPassword = await fetch(`${BASE}/share/${passwordBody.token}`)
  assert.equal(withoutPassword.status, 401)
  const withPassword = await fetch(`${BASE}/share/${passwordBody.token}`, {
    headers: { 'X-Share-Password': 'share-pass-123' }
  })
  assert.equal(withPassword.status, 200)
  assert.equal(await withPassword.text(), 'shared content')

  // 已过期的分享必须 404
  const expired = await fetch(`${BASE}/api/storage/shares`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ objectKey, expiresAt: Date.now() - 1000 })
  })
  const expiredBody = await expired.json()
  const expiredFetch = await fetch(`${BASE}/share/${expiredBody.token}`)
  assert.equal(expiredFetch.status, 404)

  // 撤销后必须 404
  const share = await fetch(`${BASE}/api/storage/shares`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ objectKey })
  })
  const shareBody = await share.json()
  const revoke = await fetch(`${BASE}/api/storage/shares/${shareBody.shareId}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${alice.token}` }
  })
  assert.ok(revoke.ok)
  const revokedFetch = await fetch(`${BASE}/share/${shareBody.token}`)
  assert.equal(revokedFetch.status, 404)

  // 不能为其他用户的对象创建分享
  const bob = await register(`storagetest-d-${Date.now()}`)
  const foreignShare = await fetch(`${BASE}/api/storage/shares`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${bob.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ objectKey })
  })
  assert.equal(foreignShare.status, 400)
})

test('deleting an object is idempotent and revokes all existing shares', async () => {
  const alice = await register(`storagetest-delete-${Date.now()}`)
  const upload = await fetch(`${BASE}/api/storage/upload`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      filename: 'delete-me.txt',
      mimeType: 'text/plain',
      contentBase64: Buffer.from('delete me').toString('base64')
    })
  })
  assert.equal(upload.status, 201)
  const { objectKey } = await upload.json()

  const share = await fetch(`${BASE}/api/storage/shares`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${alice.token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ objectKey })
  })
  assert.equal(share.status, 201)
  const { token } = await share.json()

  const remove = () => fetch(
    `${BASE}/api/storage/objects/${encodeURIComponent(objectKey)}`,
    {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${alice.token}` }
    }
  )
  assert.equal((await remove()).status, 200)
  assert.equal((await remove()).status, 200)

  const download = await fetch(
    `${BASE}/api/storage/download/${encodeURIComponent(objectKey)}`,
    { headers: { Authorization: `Bearer ${alice.token}` } }
  )
  assert.equal(download.status, 404)
  assert.equal((await fetch(`${BASE}/share/${token}`)).status, 404)
})

test('usage endpoint reports storage numbers', async () => {
  const alice = await register(`storagetest-e-${Date.now()}`)
  const res = await fetch(`${BASE}/api/storage/usage`, {
    headers: { Authorization: `Bearer ${alice.token}` }
  })
  assert.equal(res.status, 200)
  const body = await res.json()
  assert.ok(typeof body.usage.availableBytes === 'number')
  assert.equal(body.usage.reserveBytes, 2 * 1024 * 1024 * 1024)
})

test.after(async () => {
  child.kill()
  await sleep(200)
  rmSync(objectRoot, { recursive: true, force: true })
})
