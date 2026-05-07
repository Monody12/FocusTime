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
      deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(user_id, table_name, record_id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE INDEX IF NOT EXISTS idx_sync_user_table ON sync_records(user_id, table_name);
    CREATE INDEX IF NOT EXISTS idx_sync_updated ON sync_records(user_id, updated_at);
  `)
}

export function getDatabase(): Database.Database {
  return db
}