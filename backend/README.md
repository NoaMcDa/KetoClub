# KetoClub backend

A small FastAPI service that makes live Wolt menus work in the web build.
`restaurant-api.wolt.com` sends no CORS headers, so a browser refuses the
request before it leaves; this service forwards it (`backend_plan.md` §1).

**The backend is an accelerator, never a dependency.** With no backend URL
configured, the app behaves exactly as it does without one, including the
web build's paste-a-link path.

Routes shipped so far:

| Route | Issue | What it does |
|---|---|---|
| `GET /v1/health` | #94 | `{status, version, llm_configured}` |
| `POST /v1/chat` | #100 | Hosted classification: forwards one completion to Gemini `generateContent` with the server's key |

The menu proxy and community routes are later issues (`backend_plan.md` §5).

### `POST /v1/chat`

Body `{system_prompt, user_prompt, response_schema?, schema_name?}`, the
Dart `LlmChatClient.complete` parameters one to one; `200` answers
`{content, model}`. Every request needs `X-KetoClub-Install-Id` (32 lowercase
hex characters) and must **not** carry `Authorization`: the server holds the
key. `response_schema` is a strict JSON schema; the backend converts it to
Gemini's `responseSchema` subset (no `additionalProperties`, `nullable`
instead of `["T", "null"]`). A 400 on a schema-carrying request is re-sent
once without the schema, unless it is an invalid key.

Every error the route originates is `{reason, status_code}`:

| Status | `reason` | When |
|---|---|---|
| 400 | `badResponse` | Missing or malformed install id, or an inbound `Authorization` header |
| 429 | `rateLimited` | Over `RATE_LIMIT_PER_MINUTE` / `RATE_LIMIT_PER_DAY` for this install, or Gemini answered 429 |
| 502 | `offline` | Gemini unreachable |
| 502 | `badResponse` | Any other upstream status, or a reply with no usable text (`finishReason` not `STOP`, no candidates, not JSON) |
| 503 | `notConfigured` | No `GEMINI_API_KEY`, or Gemini rejected it (400 `API_KEY_INVALID`, 401, 403) |
| 504 | `timeout` | Gemini did not answer within 110 s |

A body that fails validation (empty prompt, prompt over its bound) is
FastAPI's own 422. Logs carry the install id's first 8 characters and
upstream status codes only: never the key, prompt text or an upstream body.

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
default except `GEMINI_API_KEY` and `ADMIN_TOKEN`, which gate the routes
that need them (`/v1/chat`, and `/v1/admin/*` in a later issue). See
`.env.example` for the full list with defaults and descriptions.

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | unset | The server's key, sent only as `x-goog-api-key`. Unset → `/v1/chat` answers `notConfigured` |
| `GEMINI_MODEL` | `gemini-2.5-flash` | Model in the `generateContent` path |
| `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com` | Upstream host; never taken from a request |
| `GEMINI_MAX_OUTPUT_TOKENS` | `8192` | `generationConfig.maxOutputTokens` |
| `GEMINI_THINKING_BUDGET` | `0` | Thinking tokens count against the output budget, and this is a classification task |
| `RATE_LIMIT_PER_MINUTE`, `RATE_LIMIT_PER_DAY` | `5`, `40` | Per install id on `/v1/chat`, in memory |

## Smoke test against the real API

`generativelanguage.googleapis.com` is unreachable from the sandbox and CI,
so every test mocks it; this is the one way to see a real completion. With
`GEMINI_API_KEY` set in `.env` and the server running:

```bash
curl -sS localhost:8000/v1/chat \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{
    "system_prompt": "You are a keto-diet menu analyst. Classify every dish as orderAsIs, modifiable or nonKeto. A modifiable dish names the swap in modification; otherwise modification is null.",
    "user_prompt": "1 | Mains | Entrecote | 300g steak with fries\n2 | Mains | Pasta | Spaghetti with tomato sauce",
    "response_schema": {
      "type": "object",
      "additionalProperties": false,
      "required": ["dishes"],
      "properties": {
        "dishes": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "verdict", "modification"],
            "properties": {
              "id": {"type": "string"},
              "verdict": {"type": "string", "enum": ["orderAsIs", "modifiable", "nonKeto"]},
              "modification": {"type": ["string", "null"]}
            }
          }
        }
      }
    },
    "schema_name": "menu_analysis"
  }'
# {"content":"{\"dishes\": [...]}","model":"gemini-2.5-flash"}
```

The default limit is 5 requests a minute per install id; change the id to
keep going, or raise `RATE_LIMIT_PER_MINUTE`.

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
