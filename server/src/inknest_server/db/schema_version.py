from collections.abc import Collection
from pathlib import Path
from typing import Protocol

from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy.engine import Connection

from inknest_server.db.connection import Database


class SchemaVersionError(RuntimeError):
    """Raised when the database cannot safely serve the checked-out code."""


class MultipleSchemaHeadsError(SchemaVersionError):
    def __init__(self, expected_heads: Collection[str]) -> None:
        self.expected_heads = tuple(sorted(expected_heads))
        super().__init__(
            "multiple Alembic heads are present in the checked-out code: "
            f"{', '.join(self.expected_heads)}; create and review a merge revision"
        )


class MissingSchemaHeadError(SchemaVersionError):
    def __init__(self) -> None:
        super().__init__(
            "no Alembic head is present in the checked-out code; "
            "restore the migration history before starting the API"
        )


class SchemaVersionMismatchError(SchemaVersionError):
    def __init__(
        self,
        *,
        current_heads: Collection[str],
        expected_head: str,
    ) -> None:
        self.current_heads = tuple(sorted(current_heads))
        self.expected_head = expected_head
        current = ", ".join(self.current_heads) if self.current_heads else "<none>"
        super().__init__(
            "database schema revision does not match the checked-out code: "
            f"database={current}, expected={expected_head}; "
            "run `uv run alembic upgrade head` before starting the API"
        )


class SchemaVersionChecker(Protocol):
    async def check(self) -> None: ...


class AlembicSchemaVersionChecker:
    def __init__(
        self,
        database: Database,
        *,
        config_path: Path | None = None,
    ) -> None:
        self._database = database
        self._config_path = config_path or _default_alembic_config_path()

    async def check(self) -> None:
        config = _load_alembic_config(self._config_path)
        scripts = ScriptDirectory.from_config(config)
        expected_heads = scripts.get_heads()
        async with self._database.engine.connect() as connection:
            current_heads = await connection.run_sync(_database_heads)
        validate_schema_heads(
            current_heads=current_heads,
            expected_heads=expected_heads,
        )


def validate_schema_heads(
    *,
    current_heads: Collection[str],
    expected_heads: Collection[str],
) -> None:
    if not expected_heads:
        raise MissingSchemaHeadError()
    if len(expected_heads) > 1:
        raise MultipleSchemaHeadsError(expected_heads)
    expected_head = next(iter(expected_heads))
    if set(current_heads) != {expected_head}:
        raise SchemaVersionMismatchError(
            current_heads=current_heads,
            expected_head=expected_head,
        )


def _database_heads(connection: Connection) -> tuple[str, ...]:
    context = MigrationContext.configure(connection)
    return tuple(context.get_current_heads())


def _default_alembic_config_path() -> Path:
    return Path(__file__).resolve().parents[3] / "alembic.ini"


def _load_alembic_config(config_path: Path) -> Config:
    config = Config(str(config_path))
    configured_location = config.get_main_option("script_location")
    if configured_location is None:
        raise SchemaVersionError(
            f"Alembic config has no script_location: {config_path}"
        )
    script_location = Path(configured_location)
    if not script_location.is_absolute():
        config.set_main_option(
            "script_location",
            str(config_path.parent / script_location),
        )
    return config
