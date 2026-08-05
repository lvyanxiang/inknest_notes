import hashlib
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content import CanonicalJsonError, content_hash
from inknest_server.models.auth import Device, User
from inknest_server.repositories import (
    ContentRepository,
    LibraryRepository,
    LibraryResourceNotFoundError,
    RevisionConflictError,
)


async def create_user_and_device(
    session: AsyncSession, *, email: str
) -> tuple[UUID, UUID]:
    user = User(email=email, password_hash="test-password-hash")
    session.add(user)
    await session.flush()
    device = Device(user_id=user.id, name="Test iPad", platform="ios")
    session.add(device)
    await session.flush()
    return user.id, device.id


@pytest.mark.asyncio
async def test_page_content_creates_immutable_revisions_and_deduplicates_retry(
    db_session: AsyncSession,
) -> None:
    user_id, device_id = await create_user_and_device(
        db_session, email="owner@example.com"
    )
    library = LibraryRepository(db_session)
    content_repository = ContentRepository(db_session)
    notebook = await library.create_notebook(
        user_id=user_id,
        notebook_id="notebook-local-1",
        title="Math",
        layout_mode="paged",
    )
    page = await library.create_page(
        user_id=user_id,
        notebook_id=notebook.id,
        page_id="page-local-1",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version={"future": 2},
    )
    first_content: dict[str, object] = {
        "strokes": [{"id": "stroke-1", "points": [{"y": 2.0, "x": 1.0}]}],
        "coordinateSpaceVersion": {"future": 2},
        "id": page.id,
    }

    first = await content_repository.save_page_content(
        user_id=user_id,
        page_id=page.id,
        base_revision=0,
        content=first_content,
        device_id=device_id,
    )
    retry = await content_repository.save_page_content(
        user_id=user_id,
        page_id=page.id,
        base_revision=0,
        content={
            "id": page.id,
            "coordinateSpaceVersion": {"future": 2},
            "strokes": [{"points": [{"x": 1.0, "y": 2.0}], "id": "stroke-1"}],
        },
        device_id=device_id,
    )

    assert first.revision == 1
    assert first.created_revision is True
    assert retry == type(retry)(
        revision=1,
        content_hash=first.content_hash,
        created_revision=False,
    )
    assert page.revision == 1
    assert page.content_hash == content_hash(first_content)
    assert page.content == first_content

    second_content: dict[str, object] = {
        **first_content,
        "strokes": [
            {"id": "stroke-1", "points": [{"y": 2.0, "x": 1.0}]},
            {},
        ],
    }
    with pytest.raises(RevisionConflictError) as conflict:
        await content_repository.save_page_content(
            user_id=user_id,
            page_id=page.id,
            base_revision=0,
            content=second_content,
            device_id=device_id,
        )
    assert conflict.value.current_revision == 1

    second = await content_repository.save_page_content(
        user_id=user_id,
        page_id=page.id,
        base_revision=1,
        content=second_content,
        device_id=device_id,
    )
    history = await content_repository.list_revisions(
        user_id=user_id, resource_type="page", resource_id=page.id
    )

    assert second.revision == 2
    assert [item.revision for item in history] == [2, 1]
    assert history[0].content == second_content
    assert history[1].content == first_content
    assert history[0].device_id == device_id


@pytest.mark.asyncio
async def test_notebook_and_infinite_canvas_content_are_revisioned(
    db_session: AsyncSession,
) -> None:
    user_id, _ = await create_user_and_device(db_session, email="owner@example.com")
    library = LibraryRepository(db_session)
    content_repository = ContentRepository(db_session)
    paged = await library.create_notebook(
        user_id=user_id,
        notebook_id="paged",
        title="Paged",
        layout_mode="paged",
    )
    infinite = await library.create_notebook(
        user_id=user_id,
        notebook_id="infinite",
        title="Infinite",
        layout_mode="infiniteCanvas",
    )
    canvas = await library.create_infinite_canvas(
        user_id=user_id,
        notebook_id=infinite.id,
        canvas_id="canvas-local-1",
    )

    notebook_result = await content_repository.save_notebook_content(
        user_id=user_id,
        notebook_id=paged.id,
        base_revision=0,
        content={"id": paged.id, "pageIds": ["page-1"]},
    )
    canvas_result = await content_repository.save_infinite_canvas_content(
        user_id=user_id,
        canvas_id=canvas.id,
        base_revision=0,
        content={"strokes": [], "viewportScale": 1.0},
    )

    assert notebook_result.revision == 1
    assert paged.content == {"id": paged.id, "pageIds": ["page-1"]}
    assert canvas_result.revision == 1
    assert canvas.content == {"strokes": [], "viewportScale": 1.0}


@pytest.mark.asyncio
async def test_content_and_revision_history_are_user_scoped(
    db_session: AsyncSession,
) -> None:
    owner_id, _ = await create_user_and_device(db_session, email="owner@example.com")
    other_id, other_device_id = await create_user_and_device(
        db_session, email="other@example.com"
    )
    library = LibraryRepository(db_session)
    content_repository = ContentRepository(db_session)
    notebook = await library.create_notebook(
        user_id=owner_id,
        notebook_id="private-notebook",
        title="Private",
        layout_mode="paged",
    )

    with pytest.raises(LibraryResourceNotFoundError):
        await content_repository.save_notebook_content(
            user_id=other_id,
            notebook_id=notebook.id,
            base_revision=0,
            content={"id": notebook.id},
        )
    with pytest.raises(LibraryResourceNotFoundError):
        await content_repository.save_notebook_content(
            user_id=owner_id,
            notebook_id=notebook.id,
            base_revision=0,
            content={"id": notebook.id},
            device_id=other_device_id,
        )
    with pytest.raises(LibraryResourceNotFoundError):
        await content_repository.list_revisions(
            user_id=other_id,
            resource_type="notebook",
            resource_id=notebook.id,
        )


def test_canonical_hash_is_order_independent_and_rejects_non_finite_numbers() -> None:
    first = {"标题": "数学", "nested": {"b": 2, "a": 1}}
    second = {"nested": {"a": 1, "b": 2}, "标题": "数学"}
    expected = hashlib.sha256(
        '{"nested":{"a":1,"b":2},"标题":"数学"}'.encode()
    ).hexdigest()

    assert content_hash(first) == expected
    assert content_hash(second) == expected
    with pytest.raises(CanonicalJsonError):
        content_hash({"invalid": float("nan")})
