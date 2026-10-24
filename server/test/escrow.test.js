const test = require('node:test')
const assert = require('node:assert/strict')
const { db, initDatabase } = require('../dist/db/schema')

// 测试可能在空数据库环境运行（如生产部署机），先确保表结构存在
initDatabase()

const { ALL_TABLES } = require('../dist/sync/types')
const { applyClientTables, getServerChanges } = require('../dist/sync/algorithm')
const { getOrCreatePepper } = require('../dist/escrow/pepper')

const USER_ID = 'test-escrow-user'
const USER_ID_2 = 'test-escrow-user-2'

function ensureTestUser (id) {
  db.prepare(
    `INSERT INTO users (id, username, password_hash, created_at, updated_at)
     VALUES (?, ?, 'test-hash', 0, 0)
     ON CONFLICT(id) DO NOTHING`
  ).run(id, id)
}

function clearUserData (userId) {
  db.prepare('DELETE FROM sync_records WHERE user_id = ?').run(userId)
  db.prepare('UPDATE users SET pepper = NULL WHERE id = ?').run(userId)
}

test('sync whitelist contains memo_locks (folder lock table)', () => {
  assert.ok(ALL_TABLES.includes('memo_locks'))
})

test('applyClientTables accepts memo_locks records and serves them back', () => {
  ensureTestUser(USER_ID)
  clearUserData(USER_ID)

  const lockRecord = {
    id: 'memo-lock-test-1',
    updatedAt: 1700000001000,
    deleted: false,
    data: {
      id: 'memo-lock-test-1',
      folderId: 'memo-folder-test-1',
      kdfName: 'argon2id',
      kdfParams: '{"iterations":3,"memoryKiB":65536,"lanes":2,"keyLength":32}',
      salt: 'c2FsdA==',
      wrappedContentKey: 'd3JhcHBlZA==',
      wrapNonce: 'bm9uY2U=',
      recoveryWrappedContentKey: 'cmVjb3Zlcnk=',
      recoveryNonce: 'cmVjb3Zlcnktbm9uY2U=',
      cryptoVersion: 1,
      configRevision: 1,
      createdAt: 1700000000000
    }
  }

  applyClientTables(USER_ID, { memo_locks: [lockRecord] })

  const changes = getServerChanges(USER_ID, 0)
  const lockRows = changes.get('memo_locks') ?? []
  assert.ok(Array.isArray(lockRows))
  const stored = lockRows.find((r) => r.id === 'memo-lock-test-1')
  assert.ok(stored, 'lock record should be downloadable')
  assert.equal(stored.data.folderId, 'memo-folder-test-1')
  assert.equal(stored.data.wrappedContentKey, 'd3JhcHBlZA==')

  // 旧记录（updatedAt 更小）不能覆盖新记录：LWW 语义保持
  const stale = { ...lockRecord, updatedAt: 1699999000000, data: { ...lockRecord.data, wrappedContentKey: 'c3RhbGU=' } }
  applyClientTables(USER_ID, { memo_locks: [stale] })
  const after = (getServerChanges(USER_ID, 0).get('memo_locks') ?? []).find(
    (r) => r.id === 'memo-lock-test-1'
  )
  assert.equal(after.data.wrappedContentKey, 'd3JhcHBlZA==')

  clearUserData(USER_ID)
})

test('pepper is generated once per user and stable across calls', () => {
  ensureTestUser(USER_ID_2)
  clearUserData(USER_ID_2)

  const first = getOrCreatePepper(USER_ID_2)
  assert.ok(first && first.length > 0, 'pepper should be non-empty')
  // 合法 base64
  assert.doesNotThrow(() => Buffer.from(first, 'base64'))
  assert.equal(Buffer.from(first, 'base64').length, 32)

  const second = getOrCreatePepper(USER_ID_2)
  assert.equal(first, second, 'pepper must be stable for the same user')

  // 不同用户的 pepper 互不相同
  ensureTestUser(USER_ID)
  clearUserData(USER_ID)
  const other = getOrCreatePepper(USER_ID)
  assert.notEqual(first, other)

  clearUserData(USER_ID_2)
  clearUserData(USER_ID)
})
