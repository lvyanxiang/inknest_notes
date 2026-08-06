from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class SyncApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        from_attributes=True,
        populate_by_name=True,
    )


class SyncChangeResponse(SyncApiModel):
    change_id: UUID
    resource_type: Literal["folder", "notebook", "page", "infinite_canvas", "asset"]
    resource_id: str
    operation: Literal["upsert", "delete"]
    revision: int | None
    content_hash: str | None
    payload: dict[str, object] | None
    device_id: UUID | None
    created_at: datetime


class SyncChangesResponse(SyncApiModel):
    changes: list[SyncChangeResponse]
    next_cursor: str
    has_more: bool
