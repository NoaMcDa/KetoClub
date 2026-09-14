# KetoClub backend

A small FastAPI service that makes live Wolt menus work in the web build.
`restaurant-api.wolt.com` sends no CORS headers, so a browser refuses the
request before it leaves; this service forwards it (`backend_plan.md` §1).

**The backend is an accelerator, never a dependency.** With no backend URL
configured, the app behaves exactly as it does without one, including the
web build's paste-a-link path.

Currently ships `GET /v1/health` only (#94). The menu proxy, hosted
classification and community routes are later issues (`backend_plan.md` §5).

## Running locally

```bash
cd backend
uv sync
uv run uvicorn app.main:app --reload --port 8000
curl http://localhost:8000/v1/health
# {"status":"ok","version":"0.1.0","llm_configured":false}
```

Point the Flutter web build at it:

```bash
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

From an **Android emulator**, `localhost` on the host machine is not
reachable from the guest; use the emulator's host alias instead:

```bash
flutter run --dart-define=KETOCLUB_BACKEND_URL=http://10.0.2.2:8000
```

iOS simulators and physical devices are unaffected — see `backend_plan.md`
§4 for the client-side wiring once the proxy route lands.

## Configuration

Copy `.env.example` to `.env` and fill in values; every variable has a safe
default except `OPENROUTER_API_KEY` and `ADMIN_TOKEN`, which gate the routes
that need them (`/v1/chat` and `/v1/admin/*`, both later issues). See
`.env.example` for the full list with defaults and descriptions.

## The gate

```bash
backend/check.sh
```

Runs exactly what the CI `backend` job runs: `uv sync --frozen`, `ruff
check`, `ruff format --check`, `mypy app` (strict), then `pytest
--cov=app --cov-fail-under=80`. It is a required check on every pull
request, independent of whether the PR touches `backend/` — see
`architecture.md` §18.5 for why a path-filtered required check is worse than
an always-green one.

## Tests

`uv run pytest` runs the suite over an in-memory SQLite database
(`sqlite:///:memory:`, `StaticPool`) with respx blocking any real network
call — no test in this suite ever reaches the network
(`architecture.md` constraint 12).
