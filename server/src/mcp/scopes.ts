export const MCP_SCOPES = ['tasks:read', 'tasks:write', 'sessions:read'] as const
export type McpScope = (typeof MCP_SCOPES)[number]

export const DEFAULT_SCOPES: McpScope[] = ['tasks:read', 'sessions:read']
export const ALL_SCOPES: McpScope[] = [...MCP_SCOPES]

export function parseScopes(value: unknown): McpScope[] {
  const raw = Array.isArray(value) ? value : typeof value === 'string' ? value.split(',') : []
  const scopes = raw
    .map((item) => String(item).trim())
    .filter((item): item is McpScope => (MCP_SCOPES as readonly string[]).includes(item))
  return [...new Set(scopes)]
}

export function hasScope(scopes: readonly string[], required: McpScope): boolean {
  return scopes.includes(required)
}
