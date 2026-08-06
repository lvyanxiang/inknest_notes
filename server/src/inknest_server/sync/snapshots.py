from inknest_server.models import Asset, Folder, InfiniteCanvas, Notebook, Page


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
