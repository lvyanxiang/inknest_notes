from inknest_server.models import (
    Asset,
    Conflict,
    Folder,
    InfiniteCanvas,
    Notebook,
    Page,
)


def folder_snapshot(folder: Folder) -> dict[str, object]:
    return {"id": folder.id, "name": folder.name}


def notebook_snapshot(notebook: Notebook) -> dict[str, object]:
    return {
        "id": notebook.id,
        "folderId": notebook.folder_id,
        "title": notebook.title,
        "layoutMode": notebook.layout_mode,
        "isArchived": notebook.is_archived,
        "revision": notebook.revision,
        "contentHash": notebook.content_hash,
        "content": notebook.content,
        "conflictOf": notebook.conflict_of,
    }


def page_snapshot(page: Page) -> dict[str, object]:
    return {
        "id": page.id,
        "notebookId": page.notebook_id,
        "position": page.position,
        "width": page.width,
        "height": page.height,
        "coordinateSpaceVersion": page.coordinate_space_version,
        "rotationQuarterTurns": page.rotation_quarter_turns,
        "template": page.template,
        "revision": page.revision,
        "contentHash": page.content_hash,
        "content": page.content,
        "conflictOf": page.conflict_of,
    }


def infinite_canvas_snapshot(canvas: InfiniteCanvas) -> dict[str, object]:
    return {
        "id": canvas.id,
        "notebookId": canvas.notebook_id,
        "background": canvas.background,
        "revision": canvas.revision,
        "contentHash": canvas.content_hash,
        "content": canvas.content,
    }


def asset_snapshot(asset: Asset) -> dict[str, object]:
    return {
        "id": asset.id,
        "notebookId": asset.notebook_id,
        "kind": asset.kind,
        "filename": asset.original_filename,
        "contentType": asset.content_type,
        "byteSize": asset.byte_size,
        "sha256": asset.sha256,
    }


def conflict_snapshot(conflict: Conflict) -> dict[str, object]:
    return {
        "id": str(conflict.id),
        "resourceType": conflict.resource_type,
        "conflictOf": conflict.original_resource_id,
        "copyResourceId": conflict.copy_resource_id,
        "copyDisplayName": conflict.copy_display_name,
        "baseRevision": conflict.base_revision,
        "currentRevision": conflict.current_revision,
        "submittedContentHash": conflict.submitted_content_hash,
        "submittedContent": conflict.submitted_content,
        "currentContentHash": conflict.current_content_hash,
        "currentContent": conflict.current_content,
        "sourceDeviceId": (
            str(conflict.source_device_id)
            if conflict.source_device_id is not None
            else None
        ),
        "status": conflict.status,
        "resolution": conflict.resolution,
        "resolvedByDeviceId": (
            str(conflict.resolved_by_device_id)
            if conflict.resolved_by_device_id is not None
            else None
        ),
        "resolvedAt": (
            conflict.resolved_at.isoformat()
            if conflict.resolved_at is not None
            else None
        ),
        "createdAt": conflict.created_at.isoformat(),
    }
