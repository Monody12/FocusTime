import Database, { type Database as DatabaseType } from 'better-sqlite3'
import { join } from 'path'
import { existsSync, mkdirSync } from 'fs'

const DATA_DIR = join(__dirname, '../../data')
if (!existsSync(DATA_DIR)) {
  mkdirSync(DATA_DIR, { recursive: true })
}

const DB_PATH = join(DATA_DIR, 'sync-server.db')

export const db: DatabaseType = new Database(DB_PATH)

db.pragma('journal_mode = WAL')
db.pragma('foreign_keys = ON')

export function initDatabase(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS sync_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      table_name TEXT NOT NULL,
      record_id TEXT NOT NULL,
      data_json TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      server_updated_at INTEGER NOT NULL DEFAULT 0,
      deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(user_id, table_name, record_id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE INDEX IF NOT EXISTS idx_sync_user_table ON sync_records(user_id, table_name);
    CREATE INDEX IF NOT EXISTS idx_sync_updated ON sync_records(user_id, updated_at);

    CREATE TABLE IF NOT EXISTS sync_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      sync_time INTEGER NOT NULL,
      client_last_sync INTEGER NOT NULL,
      records_sent INTEGER NOT NULL,
      records_received INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE INDEX IF NOT EXISTS idx_sync_log_user_time ON sync_log(user_id, sync_time);

    CREATE TABLE IF NOT EXISTS object_shares (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      object_key TEXT NOT NULL,
      token_hash TEXT UNIQUE NOT NULL,
      expires_at INTEGER,
      password_hash TEXT,
      revoked INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE INDEX IF NOT EXISTS idx_object_shares_token ON object_shares(token_hash, revoked);
    CREATE INDEX IF NOT EXISTS idx_object_shares_user ON object_shares(user_id, created_at);
  `)

  const columns = db.prepare('PRAGMA table_info(sync_records)').all() as Array<{ name: string }>
  if (!columns.some((column) => column.name === 'server_updated_at')) {
    db.exec('ALTER TABLE sync_records ADD COLUMN server_updated_at INTEGER NOT NULL DEFAULT 0')
    db.exec('UPDATE sync_records SET server_updated_at = updated_at WHERE server_updated_at = 0')
  }
  db.exec('CREATE INDEX IF NOT EXISTS idx_sync_server_updated ON sync_records(user_id, server_updated_at)')

  // Keep operational sync logs bounded while retaining enough history for
  // diagnosis. User data in sync_records is not affected.
  const syncLogRetentionMs = 90 * 24 * 60 * 60 * 1000
  db.prepare('DELETE FROM sync_log WHERE sync_time < ?')
    .run(Date.now() - syncLogRetentionMs)
}

export function getDatabase(): Database.Database {
  return db
}
