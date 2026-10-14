import { DomainError } from '../domain/errors'
import { AuthContext } from './tokens'
import { executeTool, toolsForScopes } from './tools'
import { readResource, resourcesForScopes } from './resources'
import { getPrompt, PROMPTS } from './prompts'

export const SERVER_NAME = 'focusmytime'
export const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'] as const
export const DEFAULT_PROTOCOL = '2025-03-26'

interface JsonRpcRequest {
  jsonrpc?: string
  id?: string | number | null
  method?: string
  params?: Record<string, unknown>
}

export interface JsonRpcResponse {
  jsonrpc: '2.0'
  id: string | number | null
  result?: unknown
  error?: { code: number; message: string; data?: unknown }
}

function isNotification(message: JsonRpcRequest): boolean {
  return message.id === undefined
}

function ok(id: string | number | null, result: unknown): JsonRpcResponse {
  return { jsonrpc: '2.0', id, result }
}

function fail(
  id: string | number | null,
  code: number,
  message: string,
  data?: unknown
): JsonRpcResponse {
  return { jsonrpc: '2.0', id, error: { code, message, data } }
}

function toolResult(data: unknown, isError = false) {
  return {
    content: [{ type: 'text', text: typeof data === 'string' ? data : JSON.stringify(data, null, 2) }],
    structuredContent: typeof data === 'string' ? { text: data } : data,
    isError
  }
}

export function handleJsonRpc(
  auth: AuthContext,
  body: unknown,
  serverVersion: string
): { status: number; payload: JsonRpcResponse | null } {
  if (Array.isArray(body)) {
    return {
      status: 400,
      payload: fail(null, -32600, '不支持批量 JSON-RPC，请逐条发送')
    }
  }
  if (!body || typeof body !== 'object') {
    return { status: 400, payload: fail(null, -32600, '请求必须是 JSON 对象') }
  }
  const message = body as JsonRpcRequest
  if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    return { status: 400, payload: fail(message.id ?? null, -32600, '无效的 JSON-RPC 请求') }
  }
  if (isNotification(message)) {
    return { status: 202, payload: null }
  }
  const id = message.id ?? null
  const params = message.params || {}
  try {
    switch (message.method) {
      case 'initialize': {
        const requested = typeof params.protocolVersion === 'string' ? params.protocolVersion : ''
        const protocolVersion = PROTOCOL_VERSIONS.includes(
          requested as (typeof PROTOCOL_VERSIONS)[number]
        )
          ? requested
          : DEFAULT_PROTOCOL
        return {
          status: 200,
          payload: ok(id, {
            protocolVersion,
            capabilities: {
              tools: { listChanged: false },
              resources: { subscribe: false, listChanged: false },
              prompts: { listChanged: false }
            },
            serverInfo: { name: SERVER_NAME, version: serverVersion },
            instructions:
              'FocusMyTime MCP：读取和修改已同步的任务、清单与专注记录。写操作会通过 LWW 同步到用户所有设备。默认令牌只读。不要读取或猜测隐私备忘录明文。'
          })
        }
      }
      case 'ping':
      case 'notifications/initialized':
        return { status: 200, payload: ok(id, {}) }
      case 'tools/list':
        return {
          status: 200,
          payload: ok(id, {
            tools: toolsForScopes(auth.scopes).map((tool) => ({
              name: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema,
              annotations: tool.annotations
            }))
          })
        }
      case 'tools/call': {
        const name = typeof params.name === 'string' ? params.name : ''
        const result = executeTool(auth, name, params.arguments)
        return { status: 200, payload: ok(id, toolResult(result)) }
      }
      case 'resources/list':
        return { status: 200, payload: ok(id, { resources: resourcesForScopes(auth.scopes) }) }
      case 'resources/read': {
        const uri = typeof params.uri === 'string' ? params.uri : ''
        const resource = readResource(auth, uri)
        return {
          status: 200,
          payload: ok(id, {
            contents: [
              { uri: resource.uri, mimeType: resource.mimeType, text: resource.text }
            ]
          })
        }
      }
      case 'resources/templates/list':
        return {
          status: 200,
          payload: ok(id, {
            resourceTemplates: [
              {
                uriTemplate: 'focustime://lists/{listId}',
                name: '清单任务',
                mimeType: 'application/json'
              },
              {
                uriTemplate: 'focustime://tasks/{taskId}',
                name: '任务详情',
                mimeType: 'application/json'
              },
              {
                uriTemplate: 'focustime://calendar/{date}',
                name: '某日日历',
                mimeType: 'application/json'
              }
            ]
          })
        }
      case 'prompts/list':
        return { status: 200, payload: ok(id, { prompts: PROMPTS }) }
      case 'prompts/get': {
        const name = typeof params.name === 'string' ? params.name : ''
        const rawArgs = params.arguments
        const args: Record<string, string> = {}
        if (rawArgs && typeof rawArgs === 'object' && !Array.isArray(rawArgs)) {
          for (const [key, value] of Object.entries(rawArgs)) {
            if (typeof value === 'string') args[key] = value
          }
        }
        return { status: 200, payload: ok(id, getPrompt(auth, name, args)) }
      }
      default:
        return { status: 200, payload: fail(id, -32601, `未知方法: ${message.method}`) }
    }
  } catch (error) {
    if (error instanceof DomainError) {
      if (message.method === 'tools/call') {
        return { status: 200, payload: ok(id, toolResult({ error: error.message, code: error.code }, true)) }
      }
      const rpcCode = error.status === 404 ? -32004 : error.status === 403 ? -32003 : -32602
      return { status: 200, payload: fail(id, rpcCode, error.message, { code: error.code }) }
    }
    const messageText = error instanceof Error ? error.message : '内部错误'
    return { status: 200, payload: fail(id, -32603, messageText) }
  }
}
