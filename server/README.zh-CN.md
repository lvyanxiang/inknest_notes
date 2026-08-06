# InkNest 服务端

[English](README.md) | [简体中文](README.zh-CN.md)

InkNest 服务端是为账号备份和 local-first（本地优先）同步提供支持的
Python/FastAPI 后端。目前已经包含服务骨架、PostgreSQL、MinIO、健康检查、第一版
账号/会话/设备接口、按用户隔离的资料库元数据持久化、经过大小和 SHA-256 校验的附件
预签名上传与下载流程，以及使用不透明 Cursor 的增量同步变更流；批量同步提交和冲突处理
尚未实现。

## 环境要求

- Docker Desktop 和 Docker Compose，用于运行 PostgreSQL 与 MinIO。
- Python 3.12 和 `uv`，用于在宿主机运行 API。

macOS 尚未安装 `uv` 时执行：

```bash
brew install uv
```

## 推荐的开发启动方式

日常开发推荐只在 Docker 中运行 PostgreSQL 和 MinIO，FastAPI 直接在宿主机运行。这样
可以保留基础设施隔离，同时在修改 Python 文件后自动重载服务。

如果 Compose 中的 API 容器正在运行，只停止 API，不影响数据库和 MinIO：

```bash
docker compose stop api
```

在仓库根目录启动或保持基础设施运行：

```bash
docker compose up -d postgres minio minio-init
```

第一次配置宿主机环境时，从示例创建 `server/.env`：

```bash
cp server/.env.example server/.env
```

把其中的 PostgreSQL、MinIO 配置改成与根目录 `.env` 一致。已有正确的
`server/.env` 时不要重复执行复制命令，以免覆盖本地配置。

还需要在 `server/.env` 中设置至少 32 位的 JWT 密钥。可以生成随机值：

```bash
openssl rand -hex 32
```

把生成结果写入：

```env
INKNEST_JWT_SECRET=你的随机密钥
```

真实密钥只能保存在被 Git 忽略的 `.env` 或生产环境密钥管理服务中，不能提交到仓库。

第一次安装依赖、执行迁移并启动 API：

```bash
cd server
uv sync
uv run alembic upgrade head
uv run uvicorn inknest_server.main:app --reload --host 127.0.0.1 --port 8000
```

后续日常启动一般只需要：

```bash
cd server
uv run uvicorn inknest_server.main:app --reload
```

使用 `Ctrl+C` 停止宿主机 API。

## 使用 Docker 启动完整服务

完整容器方式适合集成测试或验证部署镜像，但不提供宿主机 Python 热重载。

首次配置且根目录 `.env` 不存在时执行：

```bash
cp .env.example .env
```

API 已经提供非敏感默认值。只有 Compose API 容器需要覆盖普通可选配置时，才创建被
Git 忽略的容器配置文件：

```bash
cp server/.env.compose.example server/.env.compose
```

不要为了重复默认值而创建这个文件。容器专属网络地址和服务间凭据映射仍显式保留在
`compose.yaml` 中。

不要用这个命令覆盖已有 `.env`。配置完成后，在仓库根目录执行：

```bash
docker compose up -d --build
```

`.env.example` 中的值只用于本地开发。公开部署前必须使用独立凭据和密钥管理服务。

## 本地访问地址

API 在宿主机运行或使用默认 Compose 端口映射时，以下地址相同。本地开发中
`127.0.0.1` 和 `localhost` 可以互换。

### API 文档与健康检查

| 内容 | 地址 | 说明 |
| --- | --- | --- |
| Swagger UI | `http://127.0.0.1:8000/docs` | 交互式接口文档，可以直接发起请求。 |
| 认证接口分组 | `http://127.0.0.1:8000/docs#/authentication` | Swagger 中的账号和设备接口。 |
| ReDoc | `http://127.0.0.1:8000/redoc` | 只读的另一种接口文档。 |
| OpenAPI JSON | `http://127.0.0.1:8000/openapi.json` | 供程序读取的 API 合同。 |
| 存活检查 | `http://127.0.0.1:8000/api/v1/health/live` | 只验证 API 进程是否运行，不检查数据库和 MinIO。 |
| 就绪检查 | `http://127.0.0.1:8000/api/v1/health/ready` | 验证 PostgreSQL 和私有 MinIO Bucket 是否可用。 |

当前没有为根路径 `/` 配置页面，因此访问 `http://127.0.0.1:8000/` 返回
`404 Not Found` 是正常现象。浏览器入口使用 `/docs`。

### 当前 API 接口

统一基础地址：`http://127.0.0.1:8000/api/v1`。

| 方法 | 路径 | 鉴权方式 | 作用 |
| --- | --- | --- | --- |
| `GET` | `/health/live` | 无 | 检查 API 进程是否存活。 |
| `GET` | `/health/ready` | 无 | 检查 PostgreSQL 和 MinIO 是否就绪。 |
| `POST` | `/auth/register` | 无 | 创建用户、设备和登录会话。 |
| `POST` | `/auth/login` | 无 | 登录并创建一个设备会话。 |
| `POST` | `/auth/refresh` | 请求体中的 Refresh Token | 轮换 Refresh Token，并签发新的 Access Token。 |
| `POST` | `/auth/logout` | 请求体中的 Refresh Token | 撤销提交的 Refresh Token。 |
| `GET` | `/me` | Bearer Access Token | 获取当前用户。 |
| `GET` | `/devices` | Bearer Access Token | 获取当前用户的登录设备。 |
| `DELETE` | `/devices/{device_id}` | Bearer Access Token | 撤销当前用户拥有的指定设备。 |
| `POST` | `/assets/upload-sessions` | Bearer Access Token | 创建或重试附件上传会话，返回 MinIO 预签名 PUT URL。 |
| `POST` | `/assets/upload-sessions/{upload_id}/complete` | Bearer Access Token | 校验暂存对象并创建可用附件元数据。 |
| `DELETE` | `/assets/upload-sessions/{upload_id}` | Bearer Access Token | 取消当前用户拥有的待上传会话。 |
| `GET` | `/assets/{asset_id}/download-url` | Bearer Access Token | 为当前用户拥有的可用附件签发短期下载 URL。 |
| `GET` | `/sync/changes?cursor=...&limit=...` | Bearer Access Token | 按顺序读取当前用户的增量变更，并返回下一个不透明 Cursor。 |

访问 Bearer 鉴权接口时，使用注册、登录或刷新接口返回的 Access Token：

```http
Authorization: Bearer <access-token>
```

失败登录使用 5 分钟滑动窗口。默认情况下，同一客户端 IP 与规范化邮箱组合最多允许
失败 5 次，同一客户端 IP 总计最多失败 25 次。超过限制时返回
`429 Too Many Requests`、结构化错误码 `login_rate_limited` 和 `Retry-After` 响应头。
成功登录会清除当前 IP 与账号组合的失败记录。

### 附件预签名上传

调用上传会话接口前，数据库中必须已有属于当前用户的笔记本。当前还没有公开的笔记本
CRUD API，所以现阶段可使用仓库层、测试数据或数据库工具准备笔记本。

创建上传会话时，App 提交稳定的本地 `assetId`、所属笔记本、文件名、MIME、字节数和
SHA-256：

```bash
curl -X POST http://127.0.0.1:8000/api/v1/assets/upload-sessions \
  -H "Authorization: Bearer <access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "notebookId": "<notebook-id>",
    "assetId": "<stable-local-asset-id>",
    "kind": "image",
    "filename": "note.png",
    "contentType": "image/png",
    "byteSize": 1234,
    "sha256": "<64位十六进制SHA-256>"
  }'
```

响应中的 `uploadUrl` 是短期敏感凭据，不应记录到日志或长期保存。按照响应中的
`method` 和 `requiredHeaders` 把文件直接上传到 MinIO，例如：

```bash
curl -X PUT '<uploadUrl>' -H 'Content-Type: image/png' --data-binary '@note.png'
```

PUT 成功只代表字节已到达暂存区。然后使用创建响应中的 `uploadId` 调用完成接口：

```bash
curl -X POST \
  http://127.0.0.1:8000/api/v1/assets/upload-sessions/<upload-id>/complete \
  -H "Authorization: Bearer <access-token>"
```

服务端先核对 MinIO 中的 MIME 和真实字节数，再把暂存对象条件复制到客户端没有写权限的
最终 Key，并以流式读取计算 SHA-256。全部一致后才返回 `status: ready`、写入 `assets`
表并把 `asset_uploads.status` 改为 `completed`。完成请求可以安全重试，不会重复创建附件。

同一个用户使用相同 `assetId` 和相同元数据重试时，会复用同一个会话并重新签发 URL；
元数据不同会返回 `409`，避免静默覆盖另一个本地文件。只执行 PUT、尚未完成校验时，
`asset_uploads.status` 仍是 `pending`，`assets` 表不会新增记录，这是刻意的安全边界。
大小、MIME 或 SHA-256 不匹配时返回 `422`，最终对象不会成为可用附件，暂存对象保留供
客户端覆盖后重试。
取消会话只阻止服务端后续完成该会话，不能撤销已经签发且尚未过期的 URL；下文的运维
清理命令会在安全宽限期后处理过期和残留的暂存对象。

附件完成后，可以使用稳定的 `assetId` 获取下载 URL：

```bash
curl \
  http://127.0.0.1:8000/api/v1/assets/<asset-id>/download-url \
  -H "Authorization: Bearer <access-token>"
```

服务端只会为当前用户拥有的 `assets` 记录签名，并先确认 MinIO 对象仍存在且大小、MIME
与数据库一致。响应包含 `downloadUrl`、`expiresAt`、`byteSize` 和 `sha256`。App 下载时
应先写入临时文件，核对大小和 SHA-256 后再原子替换正式本地文件。不要记录或长期保存
完整预签名 URL。

### 增量同步变更

`GET /api/v1/sync/changes` 只返回当前登录用户的追加式变更，并按照服务端顺序分页。默认
每页 100 条，允许范围为 1–500：

```bash
curl 'http://127.0.0.1:8000/api/v1/sync/changes?limit=100' \
  -H 'Authorization: Bearer <access-token>'
```

App 应在整页变更安全写入本地后才保存 `nextCursor`，下一次请求必须原样回传：

```bash
curl --get 'http://127.0.0.1:8000/api/v1/sync/changes' \
  -H 'Authorization: Bearer <access-token>' \
  --data-urlencode 'cursor=<next-cursor>' \
  --data-urlencode 'limit=100'
```

事件包含公开变更 ID、资源类型、稳定资源 ID、操作、可选 Revision 和哈希、来源设备、
客户端快照以及服务端时间。内部数字序列不是 API 字段。Cursor 带签名并绑定账号；格式
错误、被修改或跨账号 Cursor 返回 `400 sync_cursor_invalid`。没有新变更时仍会返回供下次
轮询保存的 Cursor。

资料库创建、新内容 Revision 和附件完成会在权威写入的同一个 PostgreSQL 事务中追加
事件；相同内容重试不会重复追加。删除事件、批量 `/sync/commit` 和冲突处理属于后续切片。

### 安全清理附件对象

附件清理是显式执行的运维命令，不会随 API 启动自动运行。在 `server/` 目录先执行默认
预览；该命令不会修改 PostgreSQL 或 MinIO：

```bash
uv run python -m inknest_server.maintenance.cleanup_assets
```

JSON 输出会显示过期会话、符合条件的暂存对象、发现和到期的孤儿对象、受保护对象、删除
数量和失败数量。检查预览后，才显式执行：

```bash
uv run python -m inknest_server.maintenance.cleanup_assets --execute
```

`--execute` 属于日常运维命令，但它确实可能物理删除没有数据库引用的 MinIO 文件。安全
规则如下：

- 待上传会话 24 小时过期，过期后额外保留暂存文件 24 小时。
- 已取消会话和已完成上传的暂存残留等待 1 小时。
- 最终目录中没有任何 `assets.object_key` 引用的对象先写入
  `asset_gc_candidates`，隔离观察 7 天。
- 删除前立刻再次查询数据库；隔离期间重新获得引用的对象改为 `protected`，不会删除。
- 已引用的 ready 附件永远不会入选；对象 Key 必须符合服务端目录规则；每次每类最多处理
  100 条记录。
- `asset_uploads` 和 GC 审计记录不会被清除。失败会记录尝试次数和错误类型，可安全重试。

可在 Navicat/pgAdmin 查看 `asset_uploads.staging_deleted_at`、
`cleanup_attempts`、`last_cleanup_error` 和 `asset_gc_candidates`；可在 MinIO Console
查看剩余文件。遇到失败时不要手工删除 ready 对象，应先修复数据库或 MinIO 连接，再重跑
默认预览和 `--execute`。

### PostgreSQL 与 MinIO

| 服务 | 地址 | 访问方式 |
| --- | --- | --- |
| PostgreSQL | `localhost:5432` | 使用 Navicat、pgAdmin 或 `psql`；数据库名、用户名和密码读取根目录中被忽略的 `.env`。 |
| MinIO Console | `http://localhost:9001` | 浏览器管理界面，使用根目录 `.env` 中的 MinIO 凭据。 |
| MinIO S3 API | `http://localhost:9000` | 后端使用的 S3 兼容接口，不是普通的浏览器文件管理页面。 |

MinIO Bucket 是私有的。上传使用短期签名 URL，最终附件只能通过后端后续签发的下载
URL 访问，不会把 Bucket 设置成公开浏览。

## 验证命令

在 `server/` 目录执行：

```bash
uv run ruff format --check .
uv run ruff check .
uv run mypy
uv run pytest
```

PostgreSQL 和 MinIO 已运行时，可以执行真实依赖集成测试：

```bash
INKNEST_RUN_INTEGRATION=1 uv run pytest -m integration
```

在仓库根目录验证 Compose 配置：

```bash
docker compose config
```

## 数据库迁移

当前迁移历史为：

- `20260805_0001`：空基线。
- `20260805_0002`：创建 `users`、`devices` 和 `refresh_tokens`。
- `20260805_0003`：创建 `folders`、`notebooks`、`pages`、
  `infinite_canvases` 和 `assets` 元数据表。
- `20260805_0004`：为笔记本、页面和无限画布增加当前 JSON、Revision、内容哈希，并
  创建不可变的 `revisions` 历史表。
- `20260805_0005`：创建 `asset_uploads` 上传会话表，记录预期大小、SHA-256、对象 Key、
  状态和有效期。
- `20260806_0006`：将上传对象 Key 明确为暂存 Key，增加完成时间，支持验证后创建正式
  `assets` 附件引用。
- `20260806_0007`：为上传会话增加清理审计字段，并创建带 7 天隔离状态的
  `asset_gc_candidates`，用于可恢复的 MinIO 垃圾回收。
- `20260806_0008`：创建追加式 `sync_changes`，使用 PostgreSQL Identity 顺序、归属字段、
  不可变快照和 Cursor 查询索引。

后续表结构变化必须创建新迁移，不能修改已经应用过的迁移文件。

应用迁移并查看当前版本：

```bash
cd server
uv run alembic upgrade head
uv run alembic current
```

修改 SQLAlchemy Model 后生成新迁移：

```bash
uv run alembic revision --autogenerate -m "描述本次表结构变化"
```

执行前必须检查迁移文件中的 `upgrade()` 和 `downgrade()`，确认字段、索引、外键和回滚
操作正确。

只在确认过的开发环境中回退最后一次迁移：

```bash
uv run alembic downgrade -1
```

这个命令可能删除表、字段及数据，必须先备份，不应作为日常清理命令。

## 资料库元数据持久化

`src/inknest_server/models/library.py` 中的 SQLAlchemy Model 定义文件夹、笔记本、
页面、无限画布和附件元数据；`src/inknest_server/repositories/library.py` 是统一数据库
访问边界。每次读取都必须传入 `user_id`，创建页面、画布或附件前也会校验父级资源归属。
因此“资源不存在”和“资源属于其他用户”都会表现为相同的未找到结果，不会泄露他人数据。

App 生成的 ID 以稳定字符串保存，并与 `user_id` 组成联合主键。因此两个用户都拥有
`page-local-1` 也不会冲突。页面的 `coordinate_space_version` 使用 JSON 保存，服务端
可以原样保留未来或未知格式，不进行危险改写。`assets` 表只保存文件名、类型、大小、
SHA-256 和 MinIO Object Key，PDF、图片、音频等文件本体仍存放在 MinIO。

当前还没有公开的资料库 CRUD 或同步提交接口；只读增量变更流和附件上传会话是目前公开的
资料库相关接口。可以先在 Navicat/pgAdmin 查看这些表，或在
`server/` 目录运行仓库层测试：

```bash
uv run pytest tests/unit/test_library_repository.py
INKNEST_RUN_INTEGRATION=1 uv run pytest tests/integration
```

## 带历史版本的 JSON 内容

`notebooks`、`pages` 和 `infinite_canvases` 现在使用以下三个字段保存当前状态：

- `content`：当前完整 JSON。
- `revision`：服务端生成的单调递增版本号。
- `content_hash`：规范化 JSON 的 SHA-256。

对页面来说，画笔笔迹、文本框、图片位置、图形、PDF 背景引用以及未知字段都包含在
`pages.content` 的完整页面 JSON 中。内容发生变化时，同一个快照还会追加到
`revisions.content`，用于历史恢复。服务端不会把每一笔拆成单独一行数据库记录。

哈希输入采用 UTF-8 JSON：对象 Key 递归排序、移除无意义空格、保持数组顺序和 Unicode，
并拒绝 NaN/Infinity。服务端只规范化、保存和计算哈希，不解释或改写未知的
`coordinateSpaceVersion`。

保存时调用方必须提交当前 `base_revision`。PostgreSQL 会锁定资源行，服务端再生成下一
版本；不同内容使用过期版本会得到明确冲突。相同内容的重复请求即使仍携带旧版本，也会
作为幂等重试返回，不会重复创建历史记录。成功的新 Revision 现在会追加到
`sync_changes` 并通过只读增量变更接口返回；通过 `/sync/commit` 写入仍属于下一切片。

## 认证机制

当前认证使用：

- 邮箱和密码账号。
- Argon2id 密码哈希，不保存明文密码。
- 短期 JWT Access Token，默认有效期 15 分钟。
- 可轮换的随机 Refresh Token，默认有效期 30 天。
- PostgreSQL 只保存 Refresh Token 的 SHA-256 哈希。
- Refresh Token 重复使用时撤销同一个 Token Family。
- 撤销设备时，使该设备的 Access Token 和 Refresh Token 失效。
- 登录失败限流：默认同一 IP+邮箱 5 次、同一 IP 总计 25 次，窗口为 5 分钟。

当前限流记录保存在单个 API 进程内，符合目前单进程开发方式。生产环境扩展为多个 API
实例前，需要把限流存储替换为共享实现，确保所有实例看到同一个尝试窗口。

第一版尚未发送邮箱验证邮件。

## 配置分层

应用配置统一使用 `INKNEST_` 前缀。配置按职责拆分，新增普通可选配置时不需要继续复制
到 `compose.yaml`。

| 文件或来源 | 作用 | 是否跟踪 |
| --- | --- | --- |
| Pydantic `Settings` | 非敏感应用默认值和配置校验。 | 是 |
| `server/.env` | 宿主机 FastAPI 配置，例如使用 `localhost` 的依赖地址。 | 否 |
| 根目录 `.env` | Compose 基础设施、端口、服务凭据和变量替换。 | 否 |
| `server/.env.compose` | Compose API 容器的普通可选覆盖配置。 | 否 |
| `compose.yaml` 的 `environment` | 容器专属地址和显式服务间凭据映射。 | 是 |

对应示例为 `.env.example`、`server/.env.example` 和
`server/.env.compose.example`。当同一个变量同时存在时，`environment` 会覆盖
`env_file`；PostgreSQL 容器主机名 `postgres` 和 MinIO 主机名 `minio` 就使用这个机制。

新增普通可选 API 配置时，应增加 Pydantic 默认值与校验、示例和文档。只有容器必须
使用不同值或需要显式映射密钥时，才修改 `compose.yaml`。

重要配置：

- `INKNEST_DATABASE_URL`：SQLAlchemy PostgreSQL 连接地址。
- `INKNEST_MINIO_ENDPOINT`：不包含 URL Scheme 的 MinIO 主机和端口。
- `INKNEST_MINIO_PUBLIC_ENDPOINT`：写入预签名 URL、供 App 访问的 MinIO 主机和端口；
  Compose 中通常是 `localhost:9000`，而内部地址是 `minio:9000`。
  真机调试时不能使用 `localhost`，应改为手机可访问的电脑局域网地址或 HTTPS 域名。
- `INKNEST_MINIO_ACCESS_KEY`、`INKNEST_MINIO_SECRET_KEY`：仅限服务端使用，不能暴露给
  Flutter。
- `INKNEST_MINIO_BUCKET`：就绪检查使用的私有对象 Bucket。
- `INKNEST_MINIO_SECURE`：非本地环境是否为 MinIO 启用 TLS。
- `INKNEST_MINIO_PUBLIC_SECURE`：客户端访问预签名 URL 时是否使用 HTTPS。
- `INKNEST_ASSET_UPLOAD_URL_MINUTES`：预签名 URL 有效分钟数，默认 15。
- `INKNEST_ASSET_UPLOAD_SESSION_HOURS`：待上传会话有效小时数，默认 24。
- `INKNEST_ASSET_DOWNLOAD_URL_MINUTES`：附件下载 URL 有效分钟数，默认 15。
- `INKNEST_MAX_ASSET_UPLOAD_BYTES`：单个附件允许的最大字节数，默认 512 MiB。
- `INKNEST_ASSET_CLEANUP_PENDING_GRACE_HOURS`：待上传会话过期后额外保留暂存对象的
  小时数，默认 24。
- `INKNEST_ASSET_CLEANUP_STAGING_GRACE_HOURS`：取消或完成上传后清理暂存残留前等待的
  小时数，默认 1。
- `INKNEST_ASSET_CLEANUP_ORPHAN_QUARANTINE_DAYS`：无引用最终对象允许删除前的隔离天数，
  默认 7。
- `INKNEST_ASSET_CLEANUP_BATCH_SIZE`：每次清理中每类最多修改的记录数，默认 100。
- `INKNEST_JWT_SECRET`：至少 32 位的服务端签名密钥，不能暴露给 Flutter 或提交生产值。
- `INKNEST_ACCESS_TOKEN_MINUTES`：Access Token 有效分钟数，默认 15。
- `INKNEST_REFRESH_TOKEN_DAYS`：Refresh Token 有效天数，默认 30。
- `INKNEST_LOGIN_RATE_LIMIT_ACCOUNT_ATTEMPTS`：每个 IP+邮箱组合在窗口内允许的失败次数，
  默认 5。
- `INKNEST_LOGIN_RATE_LIMIT_IP_ATTEMPTS`：每个 IP 在窗口内允许的总失败次数，默认 25。
- `INKNEST_LOGIN_RATE_LIMIT_WINDOW_SECONDS`：登录限流滑动窗口秒数，默认 300。
