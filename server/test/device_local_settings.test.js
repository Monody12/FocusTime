const test = require('node:test')
const assert = require('node:assert/strict')
const { db, initDatabase } = require('../dist/db/schema')

// 测试可能在空数据库环境运行（如生产部署机），先确保表结构存在
initDatabase()

const {
  applyClientTables,
  purgeDeviceLocalSettingRecords,
  DEVICE_LOCAL_SETTING_KEYS
} = require('../dist/sync/algorithm')

const USER_ID = 'test-device-local-user'

function ensureTestUser () {
  db.prepare(
    `INSERT INTO users (id, username, password_hash, created_at, updated_at)
     VALUES (?, 'test-device-local-user', 'test-hash', 0, 0)
     ON CONFLICT(id) DO NOTHING`
  ).run(USER_ID)
}

function settingsRows (userId) {
  return db
    .prepare(
      "SELECT record_id FROM sync_records WHERE user_id = ? AND table_name = 'settings'"
    )
    .all(userId)
    .map((row) => row.record_id)
}

test('device-local setting keys exist in the deny-list', () => {
  assert.ok(DEVICE_LOCAL_SETTING_KEYS.includes('serverSupportsMemoSync'))
})

test('rejects device-local setting keys on ingest but keeps normal settings', () => {
  ensureTestUser()
  applyClientTables(USER_ID, {
    settings: [
      {
        id: 'serverSupportsMemoSync',
        updatedAt: 1000,
        deleted: false,
        data: { key: 'serverSupportsMemoSync', value: 'false' }
      },
      {
        id: 'memoLastSyncTime',
        updatedAt: 1000,
        deleted: false,
        data: { key: 'memoLastSyncTime', value: '123' }
      },
      {
        id: 'themeMode',
        updatedAt: 1000,
        deleted: false,
        data: { key: 'themeMode', value: 'dark' }
      }
    ]
  })

  const rows = settingsRows(USER_ID)
  for (const key of DEVICE_LOCAL_SETTING_KEYS) {
    assert.ok(!rows.includes(key), `${key} must not be ingested`)
  }
  assert.ok(rows.includes('themeMode'))
})

test('startup purge removes historically polluted device-local records', () => {
  ensureTestUser()
  db.prepare(
    `INSERT INTO sync_records
      (user_id, table_name, record_id, data_json, updated_at, server_updated_at, deleted)
     VALUES (?, 'settings', 'memoLastSyncTime', '{}', 1, 1, 0)`
  ).run(USER_ID)
  db.prepare(
    `INSERT INTO sync_records
      (user_id, table_name, record_id, data_json, updated_at, server_updated_at, deleted)
     VALUES (?, 'settings', 'purgeKeepKey', '{}', 1, 1, 0)`
  ).run(USER_ID)

  const purged = purgeDeviceLocalSettingRecords()
  assert.ok(purged >= 1)

  const rows = settingsRows(USER_ID)
  assert.ok(!rows.includes('memoLastSyncTime'))
  assert.ok(rows.includes('purgeKeepKey'))
})

test('cleans up the test user records', () => {
  db.prepare('DELETE FROM sync_records WHERE user_id = ?').run(USER_ID)
  db.prepare('DELETE FROM users WHERE id = ?').run(USER_ID)
  assert.equal(settingsRows(USER_ID).length, 0)
})
