#!/usr/bin/env bash
# The backend gate. Mirrors tool/check.sh on the Flutter side and runs exactly
# what the `backend` CI job runs (architecture.md §18.5). Run it before pushing.
set -euo pipefail
cd "$(dirname "$0")"

echo "== uv sync"
uv sync --frozen

echo "== ruff check"
uv run ruff check .

echo "== ruff format"
uv run ruff format --check .

echo "== mypy"
uv run mypy app

echo "== pytest with coverage"
uv run pytest --cov=app --cov-report=term-missing --cov-fail-under=80

echo "All backend checks passed."
