#!/usr/bin/env bash
# Runs locally exactly what the CI `backend` job runs.
set -euo pipefail
cd "$(dirname "$0")"

echo "== uv sync"
uv sync --frozen

echo "== ruff check"
uv run ruff check .

echo "== ruff format --check"
uv run ruff format --check .

echo "== mypy"
uv run mypy app

echo "== pytest (coverage floor 80%)"
uv run pytest --cov=app --cov-fail-under=80

echo "All backend checks passed."
