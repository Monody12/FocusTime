export interface SyncRecord {
  id: string
  updatedAt: number
  data: Record<string, unknown>
  deleted?: boolean
}

export interface SyncTables {
  lists: SyncRecord[]
  tasks: SyncRecord[]
  sessions: SyncRecord[]
  task_recurrence_completions: SyncRecord[]
  settings: SyncRecord[]
  memo_folders: SyncRecord[]
  memo_tags: SyncRecord[]
  memos: SyncRecord[]
  memo_tag_links: SyncRecord[]
  memo_versions: SyncRecord[]
  memo_attachments: SyncRecord[]
  memo_shares: SyncRecord[]
  privacy_vault: SyncRecord[]
}

export interface SyncRequest {
  lastSyncTime: number
  tables: SyncTables
}

export interface SyncResponse {
  serverLastSync: number
  tables: SyncTables
}

export interface UserRecord {
  id: number
  user_id: string
  table_name: string
  record_id: string
  data_json: string
  updated_at: number
  server_updated_at?: number
  deleted: number
}

export type TableName =
  | 'lists'
  | 'tasks'
  | 'sessions'
  | 'task_recurrence_completions'
  | 'settings'
  | 'memo_folders'
  | 'memo_tags'
  | 'memos'
  | 'memo_tag_links'
  | 'memo_versions'
  | 'memo_attachments'
  | 'memo_shares'
  | 'privacy_vault'

export const ALL_TABLES: TableName[] = [
  'lists',
  'tasks',
  'sessions',
  'task_recurrence_completions',
  'settings',
  'memo_folders',
  'memo_tags',
  'memos',
  'memo_tag_links',
  'memo_versions',
  'memo_attachments',
  'memo_shares',
  'privacy_vault'
]
