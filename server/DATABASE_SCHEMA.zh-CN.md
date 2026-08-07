# InkNest 服务端数据库表说明

本文档按当前 SQLAlchemy 模型整理 PostgreSQL 中的业务表、字段用途和它们对应的 App 功能。数据库模型的实际定义位于：

- `src/inknest_server/models/auth.py`
- `src/inknest_server/models/library.py`

当前共有 15 张业务表，以及 1 张由 Alembic 自动管理的结构版本表。

本文档对应的当前 Alembic 迁移头为 `20260807_0014`。其中：

- `20260807_0013` 为 `folders` 增加同步所需的 `revision` 和
  `content_hash`。
- `20260807_0014` 为 `tombstones` 增加 `structure_metadata`，并把页面
  位置唯一约束调整为只约束未删除页面的部分唯一索引。

## 核心关系

```text
用户 users
├── 设备 devices
│   └── 刷新凭证 refresh_tokens
└── 文件夹 folders
    └── 笔记本 notebooks
        ├── 普通页面 pages
        ├── 无限画布 infinite_canvases
        └── 附件元数据 assets ── 实际文件存放在 MinIO
```

需要特别注意：用户在页面上画的一笔不会单独生成一行数据，而是保存在 `pages.content` JSON 中。PostgreSQL 保存业务信息和同步状态，MinIO 保存 PDF、图片和音频的实际文件字节。

## 账号与设备

### `users`：用户

一行代表一个注册账号。

| 字段 | 作用 |
| --- | --- |
| `id` | 用户唯一 ID。 |
| `email` | 登录邮箱，不允许重复。 |
| `password_hash` | 经过哈希处理的密码，不保存明文密码。 |
| `is_active` | 账号是否可用。 |
| `created_at` | 注册时间。 |
| `updated_at` | 用户信息最后更新时间。 |

### `devices`：登录设备

一行代表某个账号登记的一台设备。

| 字段 | 作用 |
| --- | --- |
| `id` | 服务端设备 ID。 |
| `user_id` | 设备所属用户。 |
| `name` | 设备名称，例如 iPad Pro。 |
| `platform` | 平台，例如 `ios`、`android`。 |
| `created_at` | 首次登记时间。 |
| `last_seen_at` | 最近访问服务端的时间。 |
| `revoked_at` | 设备被撤销的时间；为空表示仍有效。 |

设备记录用于区分修改来源、设备管理、多设备同步和冲突处理。

### `refresh_tokens`：刷新凭证

Access Token 过期后，App 使用 Refresh Token 换取新的 Access Token。

| 字段 | 作用 |
| --- | --- |
| `id` | Refresh Token 记录 ID。 |
| `user_id` | Token 所属用户。 |
| `device_id` | Token 所属设备。 |
| `family_id` | 同一条 Token 轮换链的 ID，用于检测旧 Token 重放。 |
| `token_hash` | Refresh Token 的哈希值，不保存原始 Token。 |
| `expires_at` | 过期时间。 |
| `created_at` | 创建时间。 |
| `revoked_at` | 撤销时间；为空表示未撤销。 |
| `replaced_by_token_id` | 刷新后替代当前 Token 的新记录 ID。 |

## 书架与笔记内容

### `folders`：文件夹

一行代表书架上的一个文件夹。

| 字段 | 作用 |
| --- | --- |
| `id` | App 生成的稳定文件夹 ID。 |
| `user_id` | 文件夹所属用户。 |
| `name` | 文件夹名称。 |
| `revision` | 文件夹当前服务端版本号；创建、改名等有效同步变更会递增。 |
| `content_hash` | 文件夹同步元数据的 SHA-256，用于幂等判断和并发修改校验。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最后更新时间。 |

`id + user_id` 是联合主键，保证不同账号的数据隔离。
`revision = 0` 时 `content_hash` 为空；进入版本化同步后，`revision > 0`
且 `content_hash` 必须是 64 位 SHA-256 字符串。

### `notebooks`：笔记本

一行代表书架上的一本笔记。

| 字段 | 作用 |
| --- | --- |
| `id` | App 生成的稳定笔记本 ID。 |
| `user_id` | 笔记本所属用户。 |
| `folder_id` | 所在文件夹；为空表示书架根目录。 |
| `title` | 笔记本标题。 |
| `layout_mode` | `paged` 普通分页笔记或 `infiniteCanvas` 无限画布。 |
| `is_archived` | 是否归档。 |
| `revision` | 当前服务端版本号，每次有效内容修改递增。 |
| `content_hash` | 当前 `content` 的 SHA-256，用于判断内容是否相同。 |
| `content` | 扩展 JSON，例如书签、PDF 大纲和录音列表。 |
| `conflict_of` | 如果是冲突副本，记录原笔记本 ID。 |
| `deleted_at` | 软删除时间；为空表示未删除。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最后更新时间。 |

`content` 目前主要承载 `bookmarkedPageIds`、`pdfOutlines` 和 `audioRecordings`。页面上的笔迹不保存在这里。

### `pages`：普通页面

一行代表普通笔记本中的一页纸。

| 字段 | 作用 |
| --- | --- |
| `id` | 云端页面稳定 ID。 |
| `user_id` | 页面所属用户。 |
| `notebook_id` | 页面所属笔记本。 |
| `position` | 页面顺序，从 0 开始。 |
| `width` | 页面原始宽度。 |
| `height` | 页面原始高度。 |
| `coordinate_space_version` | 坐标系统版本，用于保护不同版本的笔迹坐标。 |
| `rotation_quarter_turns` | 顺时针旋转次数，范围 0～3，每次 90°。 |
| `template` | 页面模板，例如空白、横线或方格。 |
| `revision` | 页面当前版本号。 |
| `content_hash` | 页面内容的 SHA-256。 |
| `content` | 笔迹、文本框、图片引用、图形和 PDF 背景等 JSON 内容。 |
| `conflict_of` | 如果是冲突副本，记录原页面 ID。 |
| `deleted_at` | 软删除时间；为空表示未删除。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最后更新时间。 |

用户画一笔并完成同步后，主要变化的是 `content`、`content_hash`、`revision` 和 `updated_at`。

同一本笔记中，只有 `deleted_at IS NULL` 的活动页面要求 `position` 唯一，
对应部分唯一索引 `uq_pages_active_notebook_owner_position`。软删除页面可以保留
删除前的位置；删除中间页时，后续活动页会在同一事务中向前压紧，恢复时再根据墓碑
记录的位置插回。这样既能保持活动页序连续，也不会因为软删除历史记录占用旧位置而
阻止新增或恢复页面。

### `infinite_canvases`：无限画布

普通分页笔记使用 `pages`，无限画布笔记使用本表。一本无限画布笔记只能对应一条画布记录。

| 字段 | 作用 |
| --- | --- |
| `id` | 无限画布稳定 ID。 |
| `user_id` | 画布所属用户。 |
| `notebook_id` | 画布所属笔记本。 |
| `background` | 画布背景样式。 |
| `revision` | 当前版本号。 |
| `content_hash` | 画布内容的 SHA-256。 |
| `content` | 笔迹、文本、图片、图形和视口等 JSON 内容。 |
| `deleted_at` | 软删除时间。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最后更新时间。 |

## 附件与 MinIO

### `assets`：已完成附件

本表只保存附件元数据，文件内容实际存放在 MinIO。

| 字段 | 作用 |
| --- | --- |
| `id` | App 生成的稳定附件 ID。 |
| `user_id` | 附件所属用户。 |
| `notebook_id` | 附件所属笔记本。 |
| `kind` | 文件类型，例如 `pdf`、`image`、`audio`。 |
| `original_filename` | 原始文件名。 |
| `relative_path` | 文件在本地笔记本目录中的相对路径。 |
| `object_key` | 文件在 MinIO 中的对象路径。 |
| `content_type` | MIME 类型，例如 `image/png`。 |
| `byte_size` | 文件字节大小。 |
| `sha256` | 文件内容校验值。 |
| `created_at` | 创建时间。 |
| `updated_at` | 更新时间。 |

### `asset_uploads`：附件上传任务

记录一次文件从 App 上传至 MinIO，并经过服务端校验和最终确认的过程。

| 字段 | 作用 |
| --- | --- |
| `id` | 上传任务 ID。 |
| `user_id` | 发起上传的用户。 |
| `device_id` | 发起上传的设备。 |
| `notebook_id` | 文件所属笔记本。 |
| `asset_id` | 上传完成后对应的附件 ID。 |
| `kind` | PDF、图片或音频。 |
| `original_filename` | 原始文件名。 |
| `relative_path` | App 本地相对路径。 |
| `staging_object_key` | 上传期间在 MinIO 中的临时对象路径。 |
| `content_type` | 文件 MIME 类型。 |
| `expected_byte_size` | App 声明的文件大小。 |
| `expected_sha256` | App 声明的文件 SHA-256。 |
| `status` | `pending`、`completed`、`cancelled` 或 `expired`。 |
| `expires_at` | 整个上传任务的过期时间。 |
| `upload_url_expires_at` | 预签名上传链接的过期时间。 |
| `cancelled_at` | 取消时间。 |
| `completed_at` | 完成时间。 |
| `staging_deleted_at` | MinIO 临时对象清理时间。 |
| `cleanup_attempts` | 临时对象清理尝试次数。 |
| `last_cleanup_error` | 最近一次清理错误。 |
| `created_at` | 创建时间。 |
| `updated_at` | 更新时间。 |

### `asset_gc_candidates`：MinIO 垃圾对象候选

用于延迟处理“MinIO 中存在、数据库中却没有正式附件记录”的孤立对象，防止立即删除造成数据损失。

| 字段 | 作用 |
| --- | --- |
| `id` | 候选记录 ID。 |
| `object_key` | MinIO 对象路径。 |
| `reason` | 进入清理候选的原因。 |
| `status` | `pending`、`protected` 或 `deleted`。 |
| `first_seen_at` | 第一次发现时间。 |
| `eligible_after` | 允许实际删除的最早时间。 |
| `last_checked_at` | 最近检查时间。 |
| `delete_attempts` | 删除尝试次数。 |
| `last_error` | 最近一次删除错误。 |
| `deleted_at` | 实际删除时间。 |
| `created_at` | 创建时间。 |
| `updated_at` | 更新时间。 |

## 增量同步

### `sync_changes`：云端变更流水

服务端每发生一次有效变化，就追加一条记录。客户端通过 Cursor 拉取上次同步之后的变化。

| 字段 | 作用 |
| --- | --- |
| `sequence` | 自增流水号，也是同步 Cursor 的基础。 |
| `change_id` | 变更的唯一 UUID。 |
| `user_id` | 变更所属用户。 |
| `device_id` | 产生变更的设备。 |
| `resource_type` | 文件夹、笔记本、页面、画布、附件、冲突或墓碑。 |
| `resource_id` | 被修改资源的 ID。 |
| `operation` | `upsert` 新增/更新，或 `delete` 删除。 |
| `revision` | 变化后的资源版本号。 |
| `content_hash` | 变化后的内容校验值。 |
| `payload` | 客户端应用这次变化所需的数据；删除时为空。 |
| `created_at` | 变更发生时间。 |

### `sync_commits`：同步提交防重复

避免断网重试导致同一批修改执行两次。

| 字段 | 作用 |
| --- | --- |
| `id` | 提交记录 ID。 |
| `user_id` | 提交用户。 |
| `device_id` | 提交设备。 |
| `idempotency_key` | 客户端生成的幂等键。 |
| `request_hash` | 请求内容的 SHA-256。 |
| `response_payload` | 第一次成功时的响应结果，用于安全返回相同结果。 |
| `created_at` | 提交时间。 |

### `revisions`：历史版本

保存笔记本、页面和无限画布的历史内容快照，用于追踪版本及判断冲突。

| 字段 | 作用 |
| --- | --- |
| `id` | 历史版本记录 ID。 |
| `user_id` | 所属用户。 |
| `resource_type` | `notebook`、`page` 或 `infinite_canvas`。 |
| `resource_id` | 对应资源 ID。 |
| `revision` | 该资源的版本号。 |
| `content_hash` | 当时内容的 SHA-256。 |
| `content` | 当时的完整内容快照。 |
| `device_id` | 产生该版本的设备。 |
| `created_at` | 版本创建时间。 |

## 冲突与删除保护

### `conflicts`：编辑冲突

两台设备从同一个旧版本分别修改同一页面或笔记本时，服务端保留冲突副本，而不是静默覆盖内容。

| 字段 | 作用 |
| --- | --- |
| `id` | 冲突记录 ID。 |
| `user_id` | 所属用户。 |
| `resource_type` | 冲突对象：笔记本或页面。 |
| `original_resource_id` | 原资源 ID。 |
| `copy_resource_id` | 自动创建的冲突副本 ID。 |
| `copy_display_name` | 冲突副本显示名称。 |
| `base_revision` | 客户端开始编辑时基于的版本。 |
| `current_revision` | 服务端发现冲突时的当前版本。 |
| `submitted_content_hash` | 客户端提交内容的 SHA-256。 |
| `submitted_content` | 客户端提交的内容。 |
| `current_content_hash` | 云端当前内容的 SHA-256。 |
| `current_content` | 云端当前内容。 |
| `source_device_id` | 产生冲突提交的设备。 |
| `status` | `pending` 或 `resolved`。 |
| `resolution` | 保留原版、采用冲突版或同时保留。 |
| `resolved_by_device_id` | 处理冲突的设备。 |
| `resolved_at` | 冲突解决时间。 |
| `created_at` | 冲突产生时间。 |

### `tombstones`：删除墓碑

记录资源曾被删除以及删除前的快照，使离线设备能够识别删除操作，并保护“删除与编辑同时发生”时的内容。

| 字段 | 作用 |
| --- | --- |
| `id` | 墓碑记录 ID。 |
| `user_id` | 所属用户。 |
| `resource_type` | 被删除的笔记本、页面或无限画布。 |
| `resource_id` | 被删除资源 ID。 |
| `base_revision` | 发起删除时客户端基于的版本。 |
| `resource_revision` | 删除前资源版本。 |
| `deleted_revision` | 删除动作对应的服务端版本号。 |
| `content_hash` | 删除前内容的 SHA-256。 |
| `content` | 删除前的完整内容快照。 |
| `structure_metadata` | 删除前的结构位置 JSON。页面保存 `notebookId` 和从 0 开始的 `position`；当前其他资源保存空对象。 |
| `deleted_by_device_id` | 执行删除的设备。 |
| `deleted_at` | 删除时间。 |
| `state` | `active` 表示仍处于删除状态，`restored` 表示已经恢复。 |
| `conflict_kind` | 删除与编辑冲突的类型。 |
| `resolution` | 最终采用恢复快照或保留编辑。 |
| `conflicting_device_id` | 与删除发生冲突的设备。 |
| `restored_by_device_id` | 执行恢复的设备。 |
| `restored_at` | 恢复时间。 |
| `created_at` | 墓碑创建时间。 |

## Alembic 管理表

### `alembic_version`

这不是业务表，由 Alembic 自动维护。

| 字段 | 作用 |
| --- | --- |
| `version_num` | 当前数据库已经执行到的迁移版本。 |

它只表示数据库结构版本，不记录用户笔记的内容变化。

当前完成迁移后，`version_num` 应为 `20260807_0014`。

## App 操作与数据位置速查

| App 操作 | 主要数据位置 |
| --- | --- |
| 注册、登录 | `users`、`devices`、`refresh_tokens` |
| 创建文件夹 | `folders` |
| 创建笔记本 | `notebooks` |
| 画笔、文本、图片引用、图形 | `pages.content` |
| 编辑无限画布 | `infinite_canvases.content` |
| 上传 PDF、图片、录音 | PostgreSQL `assets` + MinIO 文件 |
| 保存历史版本 | `revisions` |
| 记录同步变化 | `sync_changes` |
| 防止重复提交 | `sync_commits` |
| 保护并解决编辑冲突 | `conflicts` |
| 记录删除并支持恢复 | `tombstones` |

## 查看数据库结构

可以使用 Navicat、DBeaver 或 pgAdmin 连接 PostgreSQL 查看表结构和数据。数据库结构发生变化时，需要通过 SQLAlchemy 模型和 Alembic 迁移维护，不能只在可视化工具里手工修改表。

SQLAlchemy 模型只描述代码期望的结构，修改模型不会自动更新 PostgreSQL。实际结构
变更必须通过 Alembic revision 落地，并检查其中的 `upgrade()`、`downgrade()`、索引、
约束和默认值。

本次操作只是让说明文档追平已经存在的 `0013`、`0014` 迁移，没有再创建新的迁移。
尚未升级的开发数据库需要在 `server/` 目录执行：

```bash
uv run alembic upgrade head
uv run alembic current
uv run alembic check
```

预期 `alembic current` 显示 `20260807_0014 (head)`，`alembic check` 显示没有新的升级
操作。不要把 `alembic downgrade -1` 当作日常清理命令；本次 `0014` 的 downgrade 会
删除 `structure_metadata`，而恢复旧的全表页面位置唯一约束时，如果已有软删除页与活动页
占用相同位置，还可能执行失败。生产环境应优先备份并通过新的向前迁移修正问题。
