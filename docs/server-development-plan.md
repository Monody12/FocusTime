# 服务器开发迁移计划

更新时间：2026-08-27

## 目标

将本地 FocusMyTime 工作区迁移到 `root@1.12.46.222:/root/work/FocusTime-master`，在服务器上继续开发已确认的备忘录模块，同时保留本地已开发但尚未提交或推送的全部内容。迁移包只包含源码、配置、测试和文档，不包含构建物、依赖缓存或运行时数据。

## 已迁移范围

- Flutter 客户端现有未提交改动与依赖锁文件。
- 备忘录 SQLite Schema 14、文件夹/标签/正文/版本/附件/分享/隐私保险库数据层。
- 客户端同步协议与服务端 8 张备忘录表白名单。
- Argon2id + AES-256-GCM 隐私加密、主密钥包装、恢复密钥和自动锁定基础服务。
- 备忘录入口、列表、搜索、Markdown 原文/预览、普通/隐私新建和版本快照。
- 附件对象存储基础适配器：按用户隔离对象键、2 GiB 保留线、容量查询、私有下载和可撤销分享。
- README、测试和项目配置。

## 排除内容

- `.git`（保留服务器现有 Git 历史和远端配置）
- `.dart_tool`、`build`、各平台构建目录
- `server/node_modules`、`server/dist`
- SQLite 数据库、日志、环境变量和其他运行时生成文件

## 后续执行顺序

1. 在服务器安装/验证 Flutter、Dart、Node.js、npm 及 `better-sqlite3` 所需构建工具。
2. 运行 `flutter pub get`、`dart analyze`、Flutter 单元测试和数据库迁移测试。
3. 在服务器安装服务端依赖，运行 `npm run build` 与服务端测试。
4. 完善 Markdown GFM 渲染、图片粘贴、离线上传队列、附件管理界面和隐私设置页。
5. 接入 MinIO/S3 生产适配器，配置对象存储目录、容量监控、备份和分享域名。
6. 完成同步冲突、恢复密钥、密码修改、回收站/版本保留和 AI 授权边界测试。
7. 通过真实浏览器桌面/移动视口和生产健康检查后，再按发布流程部署。

## 当前验证记录

- 本地 `dart analyze`：通过。
- 本地 `flutter test`：134 个测试全部通过（17 个备忘录单元测试 + 4 个 Markdown 组件测试 + 其余既有测试；备忘录测试使用独立临时数据库目录避免并发文件争锁）。
- 本地服务端 `npm run build` 与 `npm test`：7 个测试全部通过。`better-sqlite3` 已升级到 11.x，通过 npmmirror 预编译二进制安装；新增存储测试覆盖用户隔离、路径穿越、分享密码/过期/撤销与容量接口。
- Windows 桌面构建环境：已安装 VS Build Tools 2022（C++ 工作负载），修复空 `packageSources` 的 NuGet 配置后 `flutter build windows --debug` 构建成功。
- 开发策略：开发在本地 Windows 工作区进行；远程 `/root/work/FocusTime-master` 仅保留迁移副本，发布时才同步/部署到服务器。
- 尚未完成：编辑器图片粘贴（Ctrl+V）与拖拽、代码块语法高亮、私密附件加密分享页面 UI、MinIO/S3 适配器、附件对象的服务端删除联动清理。
