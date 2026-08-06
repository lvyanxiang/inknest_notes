from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models.auth import User
from inknest_server.repositories.library import (
    InvalidLibraryOperationError,
    LibraryRepository,
    LibraryResourceNotFoundError,
)


async def create_user(session: AsyncSession, *, email: str) -> UUID:
    user = User(email=email, password_hash="test-password-hash")
    session.add(user)
    await session.flush()
    return user.id


@pytest.mark.asyncio
async def test_library_metadata_preserves_client_ids_and_unknown_coordinate_version(
    db_session: AsyncSession,
) -> None:
    user_id = await create_user(db_session, email="owner@example.com")
    repository = LibraryRepository(db_session)

    folder = await repository.create_folder(
        user_id=user_id, folder_id="folder-local-1", name="课程"
    )
    notebook = await repository.create_notebook(
        user_id=user_id,
        notebook_id="notebook-local-1",
        title="高等数学",
        layout_mode="paged",
        folder_id=folder.id,
    )
    future_coordinate_version = {"version": "future-v2", "protected": True}
    page = await repository.create_page(
        user_id=user_id,
        notebook_id=notebook.id,
        page_id="page-local-1",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=future_coordinate_version,
    )
    asset = await repository.create_asset_metadata(
        user_id=user_id,
        notebook_id=notebook.id,
        asset_id="asset-local-1",
        kind="pdf",
        original_filename="教材.pdf",
        relative_path="assets/imported.pdf",
        object_key=(
            f"users/{user_id}/notebooks/{notebook.id}/pdfs/asset-local-1/textbook.pdf"
        ),
        content_type="application/pdf",
        byte_size=2048,
        sha256="a" * 64,
    )

    assert folder.id == "folder-local-1"
    assert notebook.id == "notebook-local-1"
    assert page.id == "page-local-1"
    assert page.coordinate_space_version == future_coordinate_version
    assert asset.notebook_id == notebook.id
    assert [item.id for item in await repository.list_folders(user_id=user_id)] == [
        folder.id
    ]
    assert [item.id for item in await repository.list_notebooks(user_id=user_id)] == [
        notebook.id
    ]
    assert [
        item.id
        for item in await repository.list_pages(
            user_id=user_id, notebook_id=notebook.id
        )
    ] == [page.id]


@pytest.mark.asyncio
async def test_same_client_ids_are_isolated_per_user(
    db_session: AsyncSession,
) -> None:
    first_user_id = await create_user(db_session, email="first@example.com")
    second_user_id = await create_user(db_session, email="second@example.com")
    repository = LibraryRepository(db_session)

    first = await repository.create_notebook(
        user_id=first_user_id,
        notebook_id="notebook-local-1",
        title="First",
        layout_mode="paged",
    )
    second = await repository.create_notebook(
        user_id=second_user_id,
        notebook_id="notebook-local-1",
        title="Second",
        layout_mode="paged",
    )

    assert first.id == second.id
    assert (
        await repository.get_notebook(
            user_id=first_user_id, notebook_id="notebook-local-1"
        )
    ).title == "First"
    assert (
        await repository.get_notebook(
            user_id=second_user_id, notebook_id="notebook-local-1"
        )
    ).title == "Second"


@pytest.mark.asyncio
async def test_cross_user_parent_resources_are_hidden(
    db_session: AsyncSession,
) -> None:
    owner_id = await create_user(db_session, email="owner@example.com")
    other_id = await create_user(db_session, email="other@example.com")
    repository = LibraryRepository(db_session)
    folder = await repository.create_folder(
        user_id=owner_id, folder_id="folder-shared-name", name="Private"
    )
    notebook = await repository.create_notebook(
        user_id=owner_id,
        notebook_id="notebook-private",
        title="Private",
        layout_mode="paged",
        folder_id=folder.id,
    )
    page = await repository.create_page(
        user_id=owner_id,
        notebook_id=notebook.id,
        page_id="page-private",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=1,
    )
    asset = await repository.create_asset_metadata(
        user_id=owner_id,
        notebook_id=notebook.id,
        asset_id="asset-private",
        kind="image",
        original_filename="private.png",
        relative_path="assets/images/private.png",
        object_key=f"users/{owner_id}/notebooks/{notebook.id}/images/private.png",
        content_type="image/png",
        byte_size=128,
        sha256="b" * 64,
    )
    infinite_notebook = await repository.create_notebook(
        user_id=owner_id,
        notebook_id="infinite-private",
        title="Private canvas",
        layout_mode="infiniteCanvas",
    )
    canvas = await repository.create_infinite_canvas(
        user_id=owner_id,
        notebook_id=infinite_notebook.id,
        canvas_id="canvas-private",
    )

    with pytest.raises(LibraryResourceNotFoundError):
        await repository.get_folder(user_id=other_id, folder_id=folder.id)
    with pytest.raises(LibraryResourceNotFoundError):
        await repository.get_notebook(user_id=other_id, notebook_id=notebook.id)
    with pytest.raises(LibraryResourceNotFoundError):
        await repository.get_page(user_id=other_id, page_id=page.id)
    with pytest.raises(LibraryResourceNotFoundError):
        await repository.get_asset(user_id=other_id, asset_id=asset.id)
    with pytest.raises(LibraryResourceNotFoundError):
        await repository.get_infinite_canvas(user_id=other_id, canvas_id=canvas.id)
    with pytest.raises(LibraryResourceNotFoundError):
        await repository.create_notebook(
            user_id=other_id,
            notebook_id="notebook-other",
            title="Other",
            layout_mode="paged",
            folder_id=folder.id,
        )
    with pytest.raises(LibraryResourceNotFoundError):
        await repository.create_page(
            user_id=other_id,
            notebook_id=notebook.id,
            page_id="page-other",
            position=0,
            width=768,
            height=1024,
            coordinate_space_version=1,
        )


@pytest.mark.asyncio
async def test_layout_specific_children_are_enforced(
    db_session: AsyncSession,
) -> None:
    user_id = await create_user(db_session, email="owner@example.com")
    repository = LibraryRepository(db_session)
    paged = await repository.create_notebook(
        user_id=user_id,
        notebook_id="paged-notebook",
        title="Paged",
        layout_mode="paged",
    )
    infinite = await repository.create_notebook(
        user_id=user_id,
        notebook_id="infinite-notebook",
        title="Infinite",
        layout_mode="infiniteCanvas",
    )

    with pytest.raises(InvalidLibraryOperationError):
        await repository.create_infinite_canvas(
            user_id=user_id,
            notebook_id=paged.id,
            canvas_id="wrong-canvas",
        )
    with pytest.raises(InvalidLibraryOperationError):
        await repository.create_page(
            user_id=user_id,
            notebook_id=infinite.id,
            page_id="wrong-page",
            position=0,
            width=768,
            height=1024,
            coordinate_space_version=1,
        )

    canvas = await repository.create_infinite_canvas(
        user_id=user_id,
        notebook_id=infinite.id,
        canvas_id="canvas-local-1",
    )
    assert (
        await repository.get_infinite_canvas(user_id=user_id, canvas_id=canvas.id)
    ).notebook_id == infinite.id
