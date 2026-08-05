# InkNest 服务端

[English](README.md) | [简体中文](README.zh-CN.md)

InkNest 服务端是为账号备份和 local-first（本地优先）同步提供支持的
Python/FastAPI 后端。目前已经包含服务骨架、PostgreSQL、MinIO、健康检查以及第一版
账号、会话和设备接口；笔记同步尚未实现。

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

访问 Bearer 鉴权接口时，使用注册、登录或刷新接口返回的 Access Token：

```http
Authorization: Bearer <access-token>
```

### PostgreSQL 与 MinIO

| 服务 | 地址 | 访问方式 |
| --- | --- | --- |
| PostgreSQL | `localhost:5432` | 使用 Navicat、pgAdmin 或 `psql`；数据库名、用户名和密码读取根目录中被忽略的 `.env`。 |
| MinIO Console | `http://localhost:9001` | 浏览器管理界面，使用根目录 `.env` 中的 MinIO 凭据。 |
| MinIO S3 API | `http://localhost:9000` | 后端使用的 S3 兼容接口，不是普通的浏览器文件管理页面。 |

MinIO Bucket 是私有的。附件 API 实现后，文件通过后端控制的操作或有时限的签名 URL
访问，不会把 Bucket 设置成公开浏览。

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

`20260805_0001` 是空基线，`20260805_0002` 创建了 `users`、`devices` 和
`refresh_tokens`。后续表结构变化必须创建新迁移，不能修改已经应用过的迁移文件。

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

## 认证机制

当前认证使用：

- 邮箱和密码账号。
- Argon2id 密码哈希，不保存明文密码。
- 短期 JWT Access Token，默认有效期 15 分钟。
- 可轮换的随机 Refresh Token，默认有效期 30 天。
- PostgreSQL 只保存 Refresh Token 的 SHA-256 哈希。
- Refresh Token 重复使用时撤销同一个 Token Family。
- 撤销设备时，使该设备的 Access Token 和 Refresh Token 失效。

第一版尚未发送邮箱验证邮件，也尚未实现登录限流。

## 环境变量

应用配置统一使用 `INKNEST_` 前缀。本地宿主机配置参考 `server/.env.example`，Compose
配置参考根目录 `.env.example`。

重要配置：

- `INKNEST_DATABASE_URL`：SQLAlchemy PostgreSQL 连接地址。
- `INKNEST_MINIO_ENDPOINT`：不包含 URL Scheme 的 MinIO 主机和端口。
- `INKNEST_MINIO_ACCESS_KEY`、`INKNEST_MINIO_SECRET_KEY`：仅限服务端使用，不能暴露给
  Flutter。
- `INKNEST_MINIO_BUCKET`：就绪检查使用的私有对象 Bucket。
- `INKNEST_MINIO_SECURE`：非本地环境是否为 MinIO 启用 TLS。
- `INKNEST_JWT_SECRET`：至少 32 位的服务端签名密钥，不能暴露给 Flutter 或提交生产值。
- `INKNEST_ACCESS_TOKEN_MINUTES`：Access Token 有效分钟数，默认 15。
- `INKNEST_REFRESH_TOKEN_DAYS`：Refresh Token 有效天数，默认 30。
