# FocusMyTime MCP 服务器

FocusMyTime 的同步服务可以同时作为 MCP（Model Context Protocol）服务器，让 Claude、Cursor、ChatGPT 等客户端读写已同步的任务、清单和专注记录。

MCP **不是**应用内 DeepSeek 助手的替代。应用内助手仍在客户端直连 DeepSeek；MCP 把云端账号数据暴露给外部 Agent。

当前版本覆盖任务与专注记录。隐私备忘录明文无法在服务端解密，因此不进入 MCP。

## 公共站点

- MCP 端点：`https://focus.dluserver.cn/mcp`
- 令牌管理：登录 Web / 客户端后，在设置 → 同步服务器 → **MCP 访问令牌**
- 健康检查：`GET https://focus.dluserver.cn/api/health` 含 `"mcp": true`

默认新建的令牌只有 `tasks:read` 和 `sessions:read`。需要改任务时请勾选「允许写入任务」。

## Claude Desktop / Cursor（stdio 代理）

先构建服务端：

```bash
cd server
npm install
npm run build
```

在 MCP 客户端配置：

```json
{
  "mcpServers": {
    "focustime": {
      "command": "node",
      "args": ["/绝对路径/FocusTime/server/dist/mcp/stdio.js"],
      "env": {
        "FOCUSMYTIME_URL": "https://focus.dluserver.cn",
        "FOCUSMYTIME_TOKEN": "fmcp_你的令牌"
      }
    }
  }
}
```

自建同步服务时，把 `FOCUSMYTIME_URL` 改成自己的源站（不要带尾斜杠；带 `/mcp` 后缀也可以，代理会去掉）。

## 远程 HTTP MCP

支持 Streamable HTTP 的客户端可以直接连接：

```json
{
  "mcpServers": {
    "focustime": {
      "url": "https://focus.dluserver.cn/mcp",
      "headers": {
        "Authorization": "Bearer fmcp_你的令牌"
      }
    }
  }
}
```

传输为 JSON-RPC 2.0，`POST /mcp`。鉴权使用 `Authorization: Bearer`。MCP 个人令牌以 `fmcp_` 开头；登录 JWT 也可调用（拥有全部范围，仅建议调试）。

## 自建

仓库 `server/` 已包含 MCP。按 README 启动同步服务后即提供 `/mcp` 与 `/api/mcp/tokens`。

环境变量：

| 变量 | 说明 |
|------|------|
| `JWT_SECRET` | 同步登录 JWT，必填 |
| `CORS_ORIGINS` | Web 前端来源。MCP 端点单独放行 Origin |
| `MCP_ALLOWED_HOSTS` | 额外允许的 Host，逗号分隔。默认包含 `focus.dluserver.cn`、`localhost`、`127.0.0.1` |
| `FOCUSMYTIME_DATA_DIR` | SQLite 数据目录，测试请用隔离目录 |

Nginx 需把 `/mcp` 反代到 Node，不能落到 Flutter `index.html`：

```
location ^~ /mcp {
    proxy_pass http://127.0.0.1:6677;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Authorization $http_authorization;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 300s;
}
```

生产机使用 aaPanel 的 `/www/server/nginx/sbin/nginx -t` 与 `-s reload`。

## 工具范围

只读：`list_lists`、`get_list`、`list_tasks`、`get_task`、`search_tasks`、`get_today_overview`、`get_calendar_day`、`list_focus_sessions`、`get_focus_stats`。

写入（需 `tasks:write`）：创建/修改/完成/删除任务，提醒与重复，我的一天与重要，移动与排序，创建/重命名/归档/删除清单。

完成带重复规则的任务时，服务端会按与客户端相同的策略生成下一周期任务。

明确不做：开始/暂停计时器、系统日历、本地通知、DeepSeek 对话、隐私备忘录正文、清空账号。

## 安全

- 令牌以 SHA-256 哈希存储，明文只在创建时显示一次，可随时撤销。
- 写操作走现有 LWW / 字段版本 / 软删除，结果会同步到所有设备。
- 跨用户隔离；系统清单不能删除。
- 不要把令牌提交到 Git 或发到群聊。
