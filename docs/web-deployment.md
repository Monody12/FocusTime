# Web 构建与部署

## 生产发布

本项目的正式发布包含 GitHub Release、线上 Web 前端和同域同步服务，三者缺一不可。
在 GitHub Release 成功后，从生产服务器的项目根目录执行：

```bash
tool/deploy_production.sh
```

脚本会检查版本一致性和 GitHub Release，运行 Flutter 与服务端测试，按生产参数构建
Web，使用 SQLite 在线备份 API 保存一致的数据快照，备份并更新 `/root/focus-timer-sync`，重启 PM2，然后把静态产物复制到
`/www/wwwroot/focus.dluserver.cn/releases/<timestamp>` 并原子切换 `current`。
部署结束时会再次检查线上版本、PM2、同域 API、Wasm MIME 和 `main.dart.js` 哈希。

只检查当前线上部署是否与仓库版本一致，不执行部署：

```bash
tool/deploy_production.sh --verify-only
```

服务端程序和 `sync-server.db` 一致性快照保存在 `/root/focus-timer-sync/backups/pre-v<version>-<timestamp>`；
旧 Web 版本保留在站点 `releases/` 目录。需要回滚时，恢复服务端备份并将 `current`
原子切回上一个静态目录，然后重新验证 PM2 和 `/api/health`。

## 构建

使用 Flutter 3.44 或更高版本，并在构建前生成 SQLite Web 运行资源：

```bash
flutter pub get
dart run sqflite_common_ffi_web:setup
tool/setup_web_fonts.sh
tool/setup_ui_font.sh
flutter build web --release \
  --no-web-resources-cdn \
  --dart-define=SYNC_SERVER_URL=https://focus.dluserver.cn
```

`sqflite_common_ffi_web:setup` 会生成 `web/sqlite3.wasm` 与
`web/sqflite_sw.js`。这两个文件必须随静态产物一起部署，其中 Wasm 文件需
以 `application/wasm` MIME 类型返回。

`tool/setup_web_fonts.sh` 会把 Flutter 引擎当前版本所需的简体中文、日文汉字、
常用符号和彩色表情回退字体下载到 `web/font-fallback/`。英文系统环境输入中文时，
Flutter 可能选择 Noto Sans JP，因此该字体也必须随包部署。Release 和生产部署脚本
都会在 Web 构建前执行字体清单准备与数量校验。构建时使用
`--no-web-resources-cdn`，并由启动脚本将字体回退指向站点本地目录，生产运行不
依赖 Google CDN。`assets/fonts/FocusNotoSansSC-UI.ttf` 是应用界面常用字形的
内置子集，用于避免冷启动首帧出现缺字方框；完整字库仍负责用户输入等动态文本。
升级 Flutter 后应重新运行回退字体脚本；新增界面文字时运行
`tool/setup_ui_font.sh` 更新内置子集。

## 同步服务

同步服务生产环境需要以下配置：

```dotenv
PORT=6677
HOST=127.0.0.1
JWT_SECRET=<a-long-random-secret>
CORS_ORIGINS=https://focus.dluserver.cn
```

重启 PM2 前先构建服务端：

```bash
cd server
npm run build
pm2 start ecosystem.config.js --only focus-timer-sync
```

生产环境 PM2 配置固定了构建 `better-sqlite3` 原生模块所用的 Node 解释器。
解释器版本发生变化时，必须重建该模块：

```bash
npm rebuild better-sqlite3 --build-from-source --nodedir=<node-installation>
```

## 反向代理

从站点根目录提供 Flutter 静态文件，并将 `/api/` 反向代理到本机同步服务。
Web 应用需要以下规则：

- 将 HTTP 重定向到 HTTPS。
- 使用 `try_files $uri $uri/ /index.html` 支持 Flutter 路由。
- 不缓存 `index.html`、`flutter_bootstrap.js`、`flutter.js`、
  `flutter_service_worker.js`、`main.dart.js`、`sqflite_sw.js`、
  `sqlite3.wasm`、CanvasKit、Flutter 内置字体与 `version.json`。
- 缓存静态资源，并以 `application/wasm` 返回 `.wasm` 文件。
- 将 `Host`、`X-Real-IP`、`X-Forwarded-For` 与
  `X-Forwarded-Proto` 转发给 API。

## 浏览器行为

浏览器数据保存在 WebAssembly SQLite/IndexedDB 中，设置页提供 JSON 备份导入
导出。系统日历和关闭页面后的系统通知只在原生端可用；页面保持打开时，提醒会
使用应用内铃声。

Web SQLite 当前使用无 Worker 模式以兼容无法可靠启动 SharedWorker 的浏览器。
应用启动页会通过 Web Locks API 独占数据库，同一浏览器配置一次只允许一个标签
页运行，避免多个 SQLite 实例同时写入 IndexedDB。第二个标签页会提示先关闭已打开
的页面；不支持 Web Locks API 的旧浏览器不在推荐支持范围内。
