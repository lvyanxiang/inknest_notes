# InkNest Notes 服务端实施计划

- 状态：实施中（Phase 2）
- 更新时间：2026-08-05
- 产品 Brief：`docs/product/features/inknest-cloud-backend/PRODUCT_BRIEF.md`
- 对应路线图：Milestone 8 / Post-MVP 6 Sync And Backup

## 1. 结论

服务端采用同一 Git 仓库内的渐进式 monorepo 结构：保留现有 Flutter
项目在仓库根目录，新建 `server/` 作为独立 Python 项目。不要为了目录对称性立即把
Flutter 迁移到 `apps/mobile/`。

首版技术栈：

- Python 3.12+、FastAPI、Pydantic、Uvicorn。
- PostgreSQL、SQLAlchemy、Alembic、psycopg 3。
- MinIO，用于 PDF、图片、音频、缩略图、导出文件和备份包。
- JWT Access Token、可撤销 Refresh Token、Argon2 密码哈希。
- Docker Compose，统一启动 API、PostgreSQL 和 MinIO。
- pytest、HTTPX、Testcontainers，覆盖 API、数据库和对象存储集成测试。

首版保持 local-first：无网络时 App 仍可正常写作；云端只增强备份、恢复和跨设备
同步，不成为每次编辑的在线前置条件。

## 2. 为什么放在当前仓库

推荐结构属于 monorepo，但不强制一次性重排所有目录。优势：

- 一个 Codex 工作区可以同时读取 Flutter 模型、Python 数据模型和同步协议。
- 修改序列化字段或 API 时，可以在一个提交中同时修改前端、后端和测试。
- 根级 `compose.yaml` 可以统一拉起本地依赖。
- `docs/` 继续作为跨端产品、协议和迁移记录的单一事实来源。
- 避免把现有 Flutter 的 iOS、Android、Web、测试和工具路径全部迁移。

只有在未来增加 Web 前端、管理后台、桌面端独立工程或共享 SDK 后，再评估迁移为：

```text
apps/mobile/
apps/web/
services/api/
packages/contracts/
```

当前不做该迁移。

## 3. 目标目录结构

```text
inknest_notes/
├── android/ ios/ macos/ linux/ windows/ web/
├── lib/
├── test/
├── assets/
├── docs/
│   ├── development/
│   │   └── BACKEND_IMPLEMENTATION_PLAN.md
│   └── product/features/inknest-cloud-backend/
│       └── PRODUCT_BRIEF.md
├── server/
│   ├── pyproject.toml
│   ├── uv.lock
│   ├── README.md
│   ├── .env.example
│   ├── Dockerfile
│   ├── alembic.ini
│   ├── alembic/
│   │   └── versions/
│   ├── src/inknest_server/
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── api/
│   │   │   ├── dependencies.py
│   │   │   └── v1/
│   │   │       ├── auth.py
│   │   │       ├── devices.py
│   │   │       ├── sync.py
│   │   │       ├── assets.py
│   │   │       └── backups.py
│   │   ├── auth/
│   │   ├── db/
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── services/
│   │   │   ├── sync_service.py
│   │   │   ├── conflict_service.py
│   │   │   ├── storage_service.py
│   │   │   └── backup_service.py
│   │   └── workers/
│   └── tests/
│       ├── unit/
│       ├── integration/
│       └── contract/
├── compose.yaml
├── .env.example
└── pubspec.yaml
```

Python 依赖只写入 `server/pyproject.toml`，不要混入 Flutter 工程。根目录只保留跨项目
的编排、文档和开发命令。

## 4. 服务边界

### Flutter App 负责

- 本地文件仓库和即时编辑。
- 记录本地待同步变更。
- 显示登录、同步、冲突、恢复和离线状态。
- 根据服务端游标进行增量上传和下载。
- 下载完成后以临时文件、哈希校验、原子替换的方式更新本地文件。

### FastAPI 负责

- 账号、会话和设备授权。
- 用户资源归属检查。
- 同步游标、幂等请求和 Revision 校验。
- 冲突副本、软删除和恢复规则。
- MinIO 预签名 URL、上传完成确认和对象元数据。
- 备份任务、历史版本、存储额度和审计记录。

### PostgreSQL 负责

- 用户、设备、文件夹、笔记本和页面权威元数据。
- 页面/画布 JSON 的当前版本与历史版本。
- Revision、同步事件、游标、墓碑和冲突关系。
- 附件路径、大小、MIME、SHA-256 和引用关系。
- 备份状态、恢复任务和存储用量。

### MinIO 负责

- PDF、图片、音频、缩略图、导出和备份包的二进制对象。
- 私有 Bucket、预签名上传和下载。
- 开发与演示环境的 S3 兼容存储。

MinIO 不负责笔记业务关系；PostgreSQL 不保存大文件本体。

## 5. 首版数据模型

至少建立以下表：

```text
users
devices
refresh_tokens
folders
notebooks
pages
infinite_canvases
assets
asset_uploads
revisions
sync_changes
sync_idempotency_keys
tombstones
conflicts
backups
restore_jobs
storage_usages
```

同步对象的公共字段：

```text
id                    UUID/稳定字符串 ID
user_id               所属用户
revision              服务端单调递增版本
content_hash           规范化内容 SHA-256
created_at             服务端 UTC 时间
updated_at             服务端 UTC 时间
deleted_at             软删除时间，可空
last_modified_device_id
conflict_of            冲突来源，可空
```

约束：

- 客户端 ID 一旦生成不得因上传或恢复而重写。
- 同一用户内对象 ID 唯一；任何查询必须包含用户权限过滤。
- `revision` 由服务端生成，客户端不得自行提升。
- 删除先写 tombstone，在保留期结束后才允许物理清理。
- 页面 JSON 保留 `coordinateSpaceVersion`，服务端不得自动改写未知版本。
- 附件对象只有在大小和 SHA-256 验证完成后才进入 `ready` 状态。

## 6. MinIO 对象布局

首版使用私有 Bucket `inknest-private`：

```text
users/{userId}/notebooks/{notebookId}/
├── pdfs/{assetId}/{sanitizedName}
├── images/{assetId}/{sanitizedName}
├── audio/{assetId}/{sanitizedName}
├── thumbnails/{assetId}.webp
└── exports/{assetId}/{sanitizedName}

users/{userId}/backups/{backupId}.inknestbackup
```

规则：

- 对象 Key 由服务端生成，不直接信任用户文件名。
- 客户端不持有 MinIO Root Key。
- API 只签发短期、单对象、指定方法的预签名 URL。
- 上传完成后校验大小、SHA-256、MIME 和资源归属。
- 同一哈希可在同一用户范围内去重；首版不做跨用户去重。
- 删除数据库引用后先进入垃圾回收队列，不立即删除对象。

## 7. API V1

统一前缀：`/api/v1`。

### 健康检查

```text
GET  /health/live
GET  /health/ready
```

### 账号与设备

```text
POST   /auth/register
POST   /auth/login
POST   /auth/refresh
POST   /auth/logout
GET    /me
GET    /devices
DELETE /devices/{deviceId}
```

### 同步

```text
GET  /sync/bootstrap
GET  /sync/changes?cursor=...
POST /sync/commit
POST /sync/conflicts/{conflictId}/resolve
```

`/sync/commit` 接受批量操作，每个请求必须携带：

```text
deviceId
idempotencyKey
baseCursor
operations[]
```

每个更新操作携带 `baseRevision`。Revision 不匹配时不得覆盖当前版本，返回结构化
冲突结果或创建保守的冲突副本。

### 附件

```text
POST   /assets/upload-sessions
POST   /assets/upload-sessions/{uploadId}/complete
DELETE /assets/upload-sessions/{uploadId}
GET    /assets/{assetId}/download-url
DELETE /assets/{assetId}
```

### 备份与恢复

```text
POST /backups
GET  /backups
GET  /backups/{backupId}
GET  /backups/{backupId}/download-url
POST /restores
GET  /restores/{restoreId}
```

## 8. 同步和“不静默覆盖”规则

首次登录默认动作是 Merge：

- 本地有、云端没有：保留本地并上传。
- 云端有、本地没有：下载到本地。
- 标题相同但 ID 不同：两份都保留。
- ID 相同且只有一侧变化：接受变化侧。
- ID 相同且两侧都从共同 Revision 发生变化：创建冲突副本。
- 一侧删除、另一侧编辑：保留编辑版本并记录删除冲突。
- 无法判断共同祖先：保留两份，不猜测覆盖。
- 恢复中断：保留恢复前本地数据并允许重试。

同步粒度首版固定为：文件夹、笔记本元数据、页面、无限画布和附件。笔迹仍包含在页面
JSON 中，不单独进行实时合并。

明确的 Replace Local 不是首版默认流程。未来若实现，必须先生成可恢复备份并二次
确认。

## 9. 备份格式

在接入自动云同步前，先定义版本化 `.inknestbackup`：

```text
manifest.json
library/folders.json
notebooks/{notebookId}/notebook.json
notebooks/{notebookId}/pages/{pageId}.json
notebooks/{notebookId}/canvas.json
notebooks/{notebookId}/assets/...
checksums.sha256
```

`manifest.json` 至少包含：

- `formatVersion`。
- `createdAt`。
- `appVersion`。
- `notebookCount`。
- 文件清单、大小和 SHA-256。
- 可选导出范围：单笔记本或完整资料库。

恢复必须先解压到临时目录、验证 manifest 和全部哈希，再合并到正式资料库。任何校验
失败都不得修改原数据。

## 10. 分阶段实施

### Phase 0：协议与本地备份基础

- [ ] 冻结 V1 JSON 规范和时间、ID、哈希规则。
- [ ] 定义 `.inknestbackup` manifest 与归档结构。
- [ ] 为现有 Flutter 数据实现手动备份和验证式恢复。
- [ ] 定义 API 错误码、同步 Operation 和 Conflict DTO。
- [ ] 增加前后端共享的 OpenAPI/JSON Schema 合同测试样例。

完成标准：不依赖服务端即可安全导出、校验、合并恢复现有笔记。

### Phase 1：Python 服务骨架

- [x] 创建 `server/pyproject.toml` 和 `src` 布局。
- [x] 配置 FastAPI、设置管理、结构化日志和统一错误响应。
- [x] 配置 PostgreSQL、SQLAlchemy、Alembic。
- [x] 配置 MinIO Storage Adapter。
- [x] 创建根级 `compose.yaml`，启动 API、PostgreSQL、MinIO。
- [x] 添加 `/health/live`、`/health/ready`。
- [x] 建立 pytest 单元和集成测试入口。

完成标准：新环境通过一条编排命令启动，健康检查验证数据库和 MinIO 可用。

### Phase 2：账号、会话和设备

- [x] 用户注册、登录、Refresh Token 轮换和退出。
- [x] Argon2 密码哈希。
- [ ] 登录限流。
- [x] 设备注册、设备列表和远程撤销。
- [x] 用户资源归属测试。
- [x] 敏感配置通过环境变量注入。

完成标准：两名用户无法访问彼此的任何元数据和文件地址，被撤销设备无法刷新会话。

### Phase 3：云端资料库与附件

- [ ] 文件夹、笔记本、页面和无限画布表与仓库层。
- [ ] 当前版本、历史 Revision、Content Hash。
- [ ] 创建附件上传会话和预签名 URL。
- [ ] 上传完成校验和附件引用。
- [ ] PDF、图片、音频端到端上传下载测试。
- [ ] 未完成上传和孤儿对象清理规则。

完成标准：服务端能完整保存并恢复一本包含 PDF、图片、音频和富页面内容的笔记。

### Phase 4：增量同步与冲突

- [ ] 同步变更日志和不透明 Cursor。
- [ ] 批量、幂等 `/sync/commit`。
- [ ] Flutter 本地待同步队列和最后成功 Cursor。
- [ ] Revision 乐观锁。
- [ ] 页面级和笔记本级冲突副本。
- [ ] Tombstone、删除-编辑冲突和恢复。
- [ ] 离线编辑、断网重试和重复提交测试。

完成标准：两个设备从同一版本并发修改时，两边内容都可恢复，任何请求重试不会重复
创建内容。

### Phase 5：首次登录合并与新设备恢复

- [ ] 检测设备本地资料库与云端资料库同时存在。
- [ ] 实现默认 Merge，不以标题推断对象身份。
- [ ] 上传本地独有、下载云端独有。
- [ ] 显示同步进度、失败项和重试状态。
- [ ] 新设备全量 bootstrap 后切换至增量同步。
- [ ] 恢复前快照和失败回滚。

完成标准：已有本地笔记的设备登录后不丢数据；新设备能恢复全部支持内容。

### Phase 6：备份、历史与运维

- [ ] 服务端生成单笔记本和完整资料库备份。
- [ ] 历史版本列表和恢复为新 Revision。
- [ ] 存储用量统计和配额拒绝。
- [ ] PostgreSQL 备份与 MinIO 对象备份演练。
- [ ] 审计日志、错误跟踪、指标和告警。
- [ ] 安全扫描、限流、CORS 和上传约束。

完成标准：能从独立备份恢复数据库和对象，且恢复演练有自动化校验记录。

### Phase 7：生产准备（后续）

- [ ] 确定生产区域、域名、TLS、邮件服务和隐私条款。
- [ ] 评估单节点 MinIO 风险以及 OSS/S3 Storage Adapter 切换。
- [ ] 接入订阅权益和存储套餐。
- [ ] 制定版本保留、账号删除和数据导出策略。
- [ ] 进行大 PDF、长音频、弱网和并发压测。

## 11. 测试矩阵

### Python 单元测试

- 密码、Token、Revision、哈希和权限规则。
- 合并决策、冲突生成、Tombstone 和保留期。
- 对象 Key 生成、MIME 和文件大小约束。

### Python 集成测试

- FastAPI + PostgreSQL 真实事务。
- FastAPI + MinIO 预签名上传、下载和删除。
- Alembic 从空数据库升级。
- 重复 idempotency key 和并发 Revision。

### Flutter 测试

- 本地待同步队列持久化。
- Cursor 更新只在整批提交成功后发生。
- 下载使用临时文件、校验和原子替换。
- 登录合并、冲突副本、取消和错误恢复状态。

### 端到端场景

1. 设备 A 创建含 PDF、图片和音频的笔记，设备 B 完整恢复。
2. A、B 离线修改不同页面，联网后无冲突合并。
3. A、B 离线修改同一页面，联网后创建冲突副本。
4. A 删除页面、B 离线编辑页面，联网后保留 B 的编辑。
5. 上传在中途断网，重试后只存在一个完整对象。
6. 恢复包被篡改或截断，原本地资料库保持不变。
7. 旧 `coordinateSpaceVersion` 页面上传并恢复后不被自动改写。

## 12. 安全基线

- 全部生产请求使用 HTTPS。
- Access Token 短期有效，Refresh Token 哈希后存储并支持轮换、撤销。
- 密码使用 Argon2，不记录明文密码、Token 或 MinIO Secret。
- MinIO Bucket 私有；Root 凭证只在服务端环境中存在。
- 对注册、登录、刷新、上传会话和下载签名进行限流。
- 上传限制 MIME、扩展名、文件大小和用户配额。
- 所有时间使用 UTC，所有授权以服务端用户身份为准。
- 日志不得包含笔记正文、JWT、密码或预签名 URL 完整查询参数。
- 账号删除先进入保留期，最终同时清理数据库和 MinIO 对象。

## 13. 暂不引入

- Redis/Celery：先用数据库任务表和进程内开发任务；备份生成影响 API 后再引入。
- Elasticsearch：先使用 PostgreSQL 搜索；OCR/Web 知识库规模明确后再引入。
- Kubernetes：单机 Compose 足够开发与答辩，生产规模证明需要后再评估。
- 实时 WebSocket 协作、CRDT、AI、OCR、转写和团队空间。

## 14. 第一个可执行切片

用户确认开始实施后，第一批代码只完成 Phase 1：

1. 新建 `server/` Python 项目。
2. 增加根级 `compose.yaml`。
3. 启动 FastAPI、PostgreSQL 和 MinIO。
4. 建立配置、数据库 Session、Storage Adapter 和健康检查。
5. 添加 Alembic 空基线和集成测试。
6. 写 `server/README.md`，记录启动、迁移、测试和环境变量。

第一切片不修改 Flutter 用户界面、不增加登录，也不声称已完成同步。完成后再进入账号与
设备阶段。

## 15. 完成定义

服务端 V1 只有同时满足以下条件才算完成：

- 本地 App 在服务离线时仍可写作和保存。
- 账号之间的数据和对象完全隔离。
- 增量同步可断点重试并保持幂等。
- 首次登录默认合并，不静默覆盖本地笔记。
- 冲突、删除和恢复行为可观察、可解释、可回退。
- PDF、图片、音频和备份通过 MinIO 完整恢复。
- 数据库和对象存储均有独立备份及恢复演练。
- API 合同、数据库迁移、Python 测试、Flutter 测试和端到端同步场景通过。
