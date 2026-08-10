.PHONY: run migrate check-schema

run: migrate
	uv run uvicorn inknest_server.main:app --reload --host 0.0.0.0 --port 8000

migrate:
	uv sync
	uv run alembic upgrade head

check-schema:
	uv run alembic current
	uv run alembic heads
	uv run alembic check
