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
| `GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data` | #95 | The Wolt menu proxy for the web build, see below |
| `POST /v1/chat` | #100 | Hosted classification: forwards one completion to Gemini `generateContent` with the server's key |

Community routes are later issues (`backend_plan.md` §5).

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
FastAPI's own 422. Logs carry the install id's first 8 characters, the
`cache=hit|miss` outcome and upstream status codes only: never the key,
prompt text or an upstream body.

#### The shared completion cache (#103)

Identical menus produce identical prompts, so a completion is cached
server-side by request hash and served to every caller who asks the same
question — the free-tier quota (D6, 50 requests a day in the app's own
router) goes much further this way.

- **Key**: sha256 of the canonical JSON (sorted keys, no whitespace) of
  `{model, system_prompt, user_prompt, response_schema, schema_name}`,
  using the server's own `GEMINI_MODEL`. The key is stable across dict key
  order, including inside a nested `response_schema`.
- **Lookup order**: the cache is checked first — before the Authorization
  rejection's sibling checks have any cost, before the rate limiter and
  before the "no key configured" check. A hit answers directly and spends
  no install quota; a miss falls through to the limiter and then Gemini as
  before.
- **TTL**: `CHAT_CACHE_TTL_SECONDS` (default 86400, matching the app's own
  `menuCacheTtl`). A row older than the TTL is a miss and is replaced.
- **What is cached**: only a successful (200) completion — `content` and
  `model`, exactly what `ChatResponse` holds. A `BackendError` (any failure
  reason) is never cached. The stored row holds no install id and no
  install-identifying data at all; the cache serves every install
  identically once warm.
- **Header**: every `/v1/chat` response carries `X-KetoClub-Cache: hit` or
  `miss`, exposed to browser JS via CORS `expose_headers`.

## The Wolt menu proxy

`GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data` forwards to
`{WOLT_BASE_URL}/v4/venues/slug/{slug}/menu/data` and returns Wolt's status,
body and `Content-Type` unchanged, 404 included — the Dart adapter's status
mapping needs no change whether it talks to Wolt directly or through this
proxy. It is the **only** proxy route: the upstream host always comes from
`WOLT_BASE_URL` in config, never from the request.

- `slug` is validated against `^[a-z0-9][a-z0-9-]{0,99}$`; anything else is
  422 before any upstream call is made.
- Upstream request headers are built from scratch (`User-Agent`, `Accept`)
  — nothing from the inbound request (`Origin`, `Cookie`, `Authorization`,
  the install id) is forwarded.
- A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses are cached per slug for `MENU_CACHE_TTL_SECONDS`; the
  response carries `X-KetoClub-Cache: hit` or `miss`. Failures are never
  cached.

The synthetic Wolt fixture used in `lib/` tests has never been recorded from
a real venue (issue #22); this proxy can do that from a machine that can
reach `restaurant-api.wolt.com` (the sandbox this backend was built in
cannot):

```bash
curl -sS localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data \
  -o test/fixtures/wolt_vitrina_lilinblum_menu.json
```

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
