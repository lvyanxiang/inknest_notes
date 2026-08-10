import pytest
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import text

from inknest_server.db import Database
from inknest_server.db.schema_version import (
    AlembicSchemaVersionChecker,
    MissingSchemaHeadError,
    MultipleSchemaHeadsError,
    SchemaVersionMismatchError,
    validate_schema_heads,
)


def test_schema_version_accepts_the_single_applied_head() -> None:
    validate_schema_heads(
        current_heads=("revision-2",),
        expected_heads=("revision-2",),
    )


@pytest.mark.parametrize("current_heads", [(), ("revision-1",), ("revision-3",)])
def test_schema_version_rejects_missing_older_or_newer_database(
    current_heads: tuple[str, ...],
) -> None:
    with pytest.raises(SchemaVersionMismatchError) as raised:
        validate_schema_heads(
            current_heads=current_heads,
            expected_heads=("revision-2",),
        )

    assert raised.value.current_heads == current_heads
    assert raised.value.expected_head == "revision-2"
    assert "uv run alembic upgrade head" in str(raised.value)


def test_schema_version_rejects_multiple_code_heads() -> None:
    with pytest.raises(MultipleSchemaHeadsError) as raised:
        validate_schema_heads(
            current_heads=("revision-a", "revision-b"),
            expected_heads=("revision-a", "revision-b"),
        )

    assert raised.value.expected_heads == ("revision-a", "revision-b")
    assert "merge revision" in str(raised.value)


def test_schema_version_rejects_missing_code_head() -> None:
    with pytest.raises(MissingSchemaHeadError, match="no Alembic head"):
        validate_schema_heads(current_heads=(), expected_heads=())


async def test_alembic_checker_reads_the_database_and_repository_heads() -> None:
    database = Database("sqlite+aiosqlite:///:memory:")
    config = Config("alembic.ini")
    expected_head = ScriptDirectory.from_config(config).get_current_head()
    assert expected_head is not None

    try:
        async with database.engine.begin() as connection:
            await connection.execute(
                text("CREATE TABLE alembic_version (version_num VARCHAR(32) NOT NULL)")
            )
            await connection.execute(
                text("INSERT INTO alembic_version (version_num) VALUES (:revision)"),
                {"revision": expected_head},
            )

        await AlembicSchemaVersionChecker(database).check()
    finally:
        await database.close()
