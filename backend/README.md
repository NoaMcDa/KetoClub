# KetoClub backend

A small FastAPI service that makes live Wolt menus work in the web build.
Wolt's APIs send no CORS headers for foreign origins, so a browser refuses the
request before it leaves; this service forwards it (`backend_plan.md` §1).

**The backend is an accelerator, never a dependency.** With no backend URL
configured, the app behaves exactly as it does without one, including the
web build's paste-a-link path.

**It serves the web build only** (`architecture.md` D17, issue #194). iOS and
Android call Wolt and Google's Gemini API themselves, with a key the user
pastes into the app's Settings, and never call this service even when
`KETOCLUB_BACKEND_URL` is compiled into a phone build. `/v1/chat` is the web
build's only path to a model.

Routes shipped so far:

| Route | Issue | Install id? | Limiter? | What it does |
|---|---|---|---|---|
| `GET /v1/health` | #94 | no | no | `{status, version, llm_configured}` |
| `GET /v1/proxy/wolt/venues/slug/{slug}/assortment` | #95, #168 | no | no | The Wolt menu proxy for the web build, see below |
| `GET /v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu` | #122 | no | no | The 10bis menu proxy for the web build, see below |
| `POST /v1/chat` | #100 | **yes** | **yes** (`RATE_LIMIT_*`) | Hosted classification for the web build: forwards one completion to Gemini `generateContent` with the server's key |
| `GET /v1/proxy/wolt/pages/restaurants` | #123 | **yes** | **yes** (`DISCOVERY_RATE_LIMIT_PER_MINUTE`) | Nearby-venue search for the web build, see below |
| `POST /v1/proxy/wolt/pages/search` | #123 | **yes** | **yes** (`DISCOVERY_RATE_LIMIT_PER_MINUTE`) | By-name venue search for the web build, see below |
| `POST /v1/website/fetch` | #181 | **yes** | **yes** (`WEBSITE_RATE_LIMIT_PER_MINUTE`, and per host) | One restaurant page or PDF for the web build, fetched politely (D19), see below |
| `POST /v1/menus` | #310 | **yes** (rate limiting only) | **yes** (`RATE_LIMIT_*`, shared with `/v1/chat`) | Stores one opened menu in the anonymous shared store, see below |
| `GET /v1/menus/{source}/{platform_id}` | #310 | no | no | Reads one stored menu back, see below |
| `POST /v1/classify` | #333 | **yes** | **yes** (`ANALYSIS_RATE_LIMIT_*`, only for a Gemini call) | A complete analysis of a menu the client holds (D25), see below |
| `GET /v1/venue-menus/{source}/{platform_id}` | #333 | **yes** | **yes** (`ANALYSIS_RATE_LIMIT_*`, only for a Gemini call) | One Wolt or 10bis menu, mapped and optionally analysed (D25), see below |
| `POST /v1/text-menu` | #333 | **yes** | **yes** (`ANALYSIS_RATE_LIMIT_*`, only for a Gemini call) | A pasted menu, read and analysed (D18, D25), see below |

Menu proxies are one fetch per user action and have no per-install
identity; `/v1/chat`, the two discovery routes, the website route,
`POST /v1/menus` and the three D25 analysis routes require
`X-KetoClub-Install-Id` and enforce a per-install limit. A missing or
malformed install id is answered `400 {"reason":"badResponse"}` — a
client that misses the header sees the same shape as a bad prompt.

The other community routes are later issues (`backend_plan.md` §5).

### `POST /v1/chat`

Body `{system_prompt, user_prompt, response_schema?, schema_name?, images?}`,
the Dart `LlmChatClient.complete` parameters one to one; `200` answers
`{content, model}`. Every request needs `X-KetoClub-Install-Id` (32 lowercase
hex characters) and must **not** carry `Authorization`: the server holds the
key. `response_schema` is a strict JSON schema; the backend converts it to
Gemini's `responseSchema` subset (no `additionalProperties`, `nullable`
instead of `["T", "null"]`). A 400 on a schema-carrying request is re-sent
once without the schema, unless it is an invalid key.

#### Menu pages: `images` (D15, #170)

`images` is an optional list of `{mime_type, data}`: menu photographs or a
PDF for Gemini to read with its own vision (`architecture.md` D15). `data` is
standard, padded base64; `mime_type` is one of `image/jpeg`, `image/png`,
`image/webp` or `application/pdf`. Each part is forwarded to Gemini as an
`inline_data` part after the user prompt's text part, in the order sent, and
the schema retry re-sends them unchanged. Omitted or empty, the request is
exactly the text-only one it always was.

- **Bounds**: at most `VISION_MAX_IMAGES` parts (default 6), each at most
  `VISION_MAX_IMAGE_BYTES` once decoded (default 3 MiB). Over either, a
  malformed base64 string or any other `mime_type` (`image/gif`,
  `image/heic`) is FastAPI's 422 before any upstream call and before the
  rate limiter; the app reads 422 as `badResponse`.
- **Never cached**: a request with images neither reads nor writes the
  shared completion cache below, and answers `X-KetoClub-Cache: bypass`.
  Images never enter the cache key.
- **Never stored or logged**: pages are forwarded and dropped. The log line
  carries `images=<count>` and nothing else about them: never bytes, a mime
  type or base64.
- **Same gates**: the install id is still required, `Authorization` is still
  rejected, and the per-install limiter counts an image request exactly like
  a text one.

Phones do not use this route (`architecture.md` D17): `GeminiChatClient`
sends the same `inline_data` parts straight to Google.

A one-pixel PNG, for trying the route by hand:

```bash
curl -sS -i localhost:8000/v1/chat \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{
    "system_prompt": "Describe the image in one word, as JSON {\"word\": ...}.",
    "user_prompt": "What is in this image?",
    "images": [{
      "mime_type": "image/png",
      "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    }]
  }'
# HTTP/1.1 200 OK ... x-ketoclub-cache: bypass
```

For real menu pages, `tools/vision_smoke.py` (issue #88) base64-encodes the
files, posts one request and prints the status, latency, `X-KetoClub-Cache`
and the reply. It makes a real call, so it is not a test and not in the
coverage measurement:

```bash
uv run python tools/vision_smoke.py \
  --backend http://localhost:8000 \
  --install-id 0123456789abcdef0123456789abcdef \
  --schema-file tests/fixtures/menu_analysis_schema.json \
  page1.jpg page2.jpg menu.pdf
```

Its default prompts are short placeholders; pass `--system-prompt-file` and
`--user-prompt-file` with the app's own `MenuAnalysisPrompt` text to test the
real thing.

Every error the route originates is `{reason, status_code}`:

| Status | `reason` | When |
|---|---|---|
| 400 | `badResponse` | Missing or malformed install id, or an inbound `Authorization` header |
| 429 | `rateLimited` | Over `RATE_LIMIT_PER_MINUTE` / `RATE_LIMIT_PER_DAY` for this install, or Gemini answered 429 |
| 502 | `offline` | Gemini unreachable |
| 502 | `badResponse` | Any other upstream status, or a reply with no usable text (`finishReason` not `STOP`, no candidates, not JSON) |
| 503 | `notConfigured` | No `GEMINI_API_KEY`, or Gemini rejected it (400 `API_KEY_INVALID`, 401, 403) |
| 504 | `timeout` | Gemini did not answer within 110 s |

A body that fails validation (empty prompt, prompt over its bound, an
image out of bounds) is FastAPI's own 422. The `user_prompt` bound is 400,000 characters (#188) — an
abuse guard, not a model limit, and not a promise: a menu that large is bound
first by `GEMINI_MAX_OUTPUT_TOKENS` and the 110 s read timeout, so past a
couple of hundred dishes the honest answer is #188's batching, not this cap.

When the terminal shows `gemini upstream_status=404`, the configured
`GEMINI_MODEL` is not served for this key or API version (a retired id, see
#179): the log also prints `error_status=NOT_FOUND` and a one-line hint. List
what the key can use and set `GEMINI_MODEL` in `.env`:

```bash
curl -sS https://generativelanguage.googleapis.com/v1beta/models \
  -H "x-goog-api-key: $GEMINI_API_KEY" | grep '"name"'
```

Logs carry the install id's first 8 characters, an image count, the
`cache=hit|miss|bypass` outcome, upstream status codes and, on an error, Google's `error.status`
enum only: never the key, prompt text or an upstream body.

### Reading a `/v1/chat` exchange in the log

Every upstream call prints its shape, so a failure can be read against the
menu's size without anything quoting the menu (logger `ketoclub.chat`):

```
gemini request attempt=1 model=gemini-3.5-flash schema=yes system_chars=4210 user_chars=3880 user_lines=56 images=0 image_bytes=0 max_output_tokens=65536 thinking_budget=0
gemini upstream_status=200
gemini response status=200 latency_ms=33512.4 body_bytes=18340
gemini reply finish_reason=STOP content_chars=17902 prompt_tokens=2970 output_tokens=6120 thoughts_tokens=none total_tokens=9090
```

- `user_lines` is the dish count for the menu prompt (one dish per line);
  `attempt=2 … schema=no` is the one schema-less re-send after a 400.
- `gemini reply unusable reason=…` names why a 200 was thrown away:
  `finish_reason=MAX_TOKENS` (the output cap, #188; the `output_tokens`
  beside it is how far it got), `finish_reason=SAFETY`, `no_candidates`,
  `no_text_part`, `not_json`.
- An error reply prints `error_status=UNAVAILABLE error_code=503` (Google's
  enum and code). Set `GEMINI_LOG_UPSTREAM_ERRORS=true` in `.env` to also
  print its `error_message` (key redacted, capped at 500 characters) and
  `details[].reason` entries while diagnosing.

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
- **Header**: every successful `/v1/chat` response carries
  `X-KetoClub-Cache: hit`, `miss` or, for a request with images (#170),
  `bypass`, exposed to browser JS via CORS `expose_headers`.
- **Images**: a request carrying any is never looked up and never stored;
  see "Menu pages" above.

## The Wolt menu proxy

`GET /v1/proxy/wolt/venues/slug/{slug}/assortment` forwards to
`{WOLT_CONSUMER_BASE_URL}/consumer-api/consumer-assortment/v1/venues/slug/{slug}/assortment`
— the endpoint wolt.com's own web app reads a menu from — and returns Wolt's
status, body and `Content-Type` unchanged, 404 included — the Dart adapter's
status mapping needs no change whether it talks to Wolt directly or through
this proxy. The upstream host always comes from `WOLT_CONSUMER_BASE_URL` in
config, never from the request.

Until #168 this route was `GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data`,
forwarding to `{WOLT_BASE_URL}/v4/…/menu/data`. That upstream now answers every
anonymous caller with `200` and a zero-byte body (measured 2026-09-25, with and
without the web-client headers), so the old route was **removed**, not kept
alongside: nothing calls it, and keeping it would only serve empty menus. Its
cache rows were written under `source = "wolt"`; the new route writes
`"wolt-assortment"`, so a cached empty `/v4` body can never be served.

- `slug` is validated against `^[a-z0-9][a-z0-9-]{0,99}$`; anything else is
  422 before any upstream call is made.
- Upstream request headers are built from scratch — the same web-client
  set the discovery routes send (`platform: Web`, `app-language: en`,
  `client-version`/`clientversionnumber` from `WOLT_CLIENT_VERSION`, the
  per-process `x-wolt-web-clientid`, `w-wolt-session-id`, `User-Agent`,
  `Accept`) — and nothing from the inbound request (`Origin`, `Cookie`,
  `Authorization`, the install id) is forwarded.
- A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses with a non-empty body are cached per slug for
  `MENU_CACHE_TTL_SECONDS`; the response carries `X-KetoClub-Cache: hit` or
  `miss`. Failures, and an empty 2xx body (passed through, so the app reports
  `platformChanged`), are never cached. This applies to the 10bis proxy too.

The Wolt menu fixture the Dart tests run against,
`test/fixtures/wolt_hamosad_menu.json`, is a real recording of this upstream
(issue #168). This proxy can re-record it from a machine that can reach
`consumer-api.wolt.com` (the sandbox this backend was built in cannot); add a
`_fixture_note` first key by hand, or use `tool/record_wolt_fixture.sh`, which
writes one:

```bash
curl -sS localhost:8000/v1/proxy/wolt/venues/slug/hamosad/assortment \
  -o test/fixtures/wolt_hamosad_menu.json
```

## The 10bis menu proxy

`GET /v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu` forwards to
`{TENBIS_BASE_URL}/api/v1.0/Restaurants/{restaurantId}/Menu` and returns
10bis's status, body and `Content-Type` unchanged, 404 included — shaped
like the Wolt proxy above (issue #122). The upstream host always
comes from `TENBIS_BASE_URL` in config, never from the request.

- `restaurantId` is validated against `^[0-9]{1,12}$`; anything else is 422
  before any upstream call is made.
- Upstream request headers are built from scratch (`User-Agent`, `Accept`)
  — nothing from the inbound request is forwarded, the same rule as Wolt's.
- A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses are cached per restaurant id for `MENU_CACHE_TTL_SECONDS`;
  the response carries `X-KetoClub-Cache: hit` or `miss`. Failures are
  never cached. The cache table is shared with the Wolt proxy but keyed by
  `(source, id)`, so a Wolt slug and a 10bis id that happen to be the same
  string never collide.

The synthetic 10bis fixture used in `lib/` tests has never been recorded
from a real restaurant (issue #44); this proxy can do that from a machine
that can reach `www.10bis.co.il` (the sandbox this backend was built in
cannot):

```bash
curl -sS localhost:8000/v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu \
  -o test/fixtures/tenbis_{id}_menu.json
```

## The Wolt venue-discovery proxies

`GET /v1/proxy/wolt/pages/restaurants?lat=&lon=&lang=` and
`POST /v1/proxy/wolt/pages/search` are the two routes the Discovery screen
uses on the web build (#123): Wolt's "pages" endpoints are unofficial,
origin-locked to `https://wolt.com` and are reported to answer 410 without
the full web-client header set
(`phase2_discovery_research.md` §2.2, §2.3). Both are literal allow-list
entries, forwarding only the parameters below — no wildcard passthrough.

- `GET` forwards to `{WOLT_CONSUMER_BASE_URL}/v1/pages/restaurants?lat=&lon=`.
  `lat` (`-90..90`) and `lon` (`-180..180`) are required floats; `lang` is
  `en` or `he` (default `en`). Any value outside those bounds is 422 before
  any upstream call is made.
- `POST` takes `{"q", "lat", "lon", "lang"}` and forwards to
  `{WOLT_BASE_URL}/v1/pages/search` as `{"q", "target": "venues", "lat",
  "lon"}` — `target` is fixed here, never taken from the client. `q` is
  trimmed and must be 1–80 characters after trimming; `lat`/`lon`/`lang`
  share the `GET` route's bounds.
- Upstream request headers are the Wolt web-client identity, built from
  scratch every call (`platform: Web`, `client-version` and
  `clientversionnumber` from `WOLT_CLIENT_VERSION`, `app-language` from
  `lang`, a per-process `x-wolt-web-clientid` uuid4 generated once at
  startup — never the KetoClub install id — `w-wolt-session-id:
  no-analytics-consent`, `Accept`, `User-Agent`). Nothing from the inbound
  request (`Origin`, `Cookie`, `Authorization`, the install id) is
  forwarded, the same rule as the menu proxies.
- Wolt's status, body and `Content-Type` come back unchanged, 410 included.
  A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses are cached for `DISCOVERY_CACHE_TTL_SECONDS` (default 300 s,
  shorter than the menu proxy's), keyed on the canonical query
  (`{lat},{lon},{lang}` or `{q lowercased},{lat},{lon},{lang}`); the
  response carries `X-KetoClub-Cache: hit|miss`. Failures are never cached.
- Every request needs `X-KetoClub-Install-Id`, the same rule as `/v1/chat`;
  missing or malformed is 400 `badResponse`. Each install is limited to
  `DISCOVERY_RATE_LIMIT_PER_MINUTE` (default 20, no daily cap) across both
  routes — a cache hit never spends the quota.

```bash
curl -sS 'localhost:8000/v1/proxy/wolt/pages/restaurants?lat=32.07&lon=34.77&lang=en' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef'

curl -sS localhost:8000/v1/proxy/wolt/pages/search \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{"q": "vitrina", "lat": 32.07, "lon": 34.77, "lang": "en"}'
```

## The website fetch route

`POST /v1/website/fetch` (#181, `architecture.md` D19) fetches **one**
restaurant page or PDF for the web build, which cannot read another site
itself (no CORS). Finding the menu on the page — JSON-LD, a `/menu` /
`תפריט` / `.pdf` link, or the page's own text — is the app's job, on every
platform (`lib/services/menu/website/`); this route only fetches, politely.
Phones fetch sites directly under the same rules (D17), so the two must be
kept in step.

- **Request:** `{"url": "https://…"}` (at most 2048 characters) with the
  `X-KetoClub-Install-Id` header. The URL travels in the body so the request
  log, which records the route path, never holds it.
- **Success:** `200 {"kind": "html" | "pdf", "content_type", "body",
  "final_url"}` — `body` is the decoded page for `html` (by its `charset`,
  UTF-8 by default and whenever the declared one is unknown or wrong) and
  standard base64 for `pdf`; `final_url` is the URL
  after redirects, the base the app resolves relative links against.
- **Failures,** each `{"reason", "status_code"}` with its own reason, which
  the app maps one to one (`BackendWebsiteFetcher.reasonFor`):

  | Status | `reason` | When |
  |---|---|---|
  | 400 | `invalidUrl` | not `http`/`https`, user info in the URL, a port other than 80/443, or a host that resolves to a non-public address (checked again on every redirect) |
  | 400 | `badResponse` | missing or malformed install id |
  | 403 | `disallowedByRobots` | the site's `robots.txt` disallows `ketoclubbot` (or `*`) for the path |
  | 403 | `aiReserved` | `X-Robots-Tag: noai`, `tdm-reservation: 1`, or their `<meta>` forms |
  | 404 | `notFound` | the site answered 404 or 410 |
  | 413 | `tooLarge` | over `WEBSITE_MAX_HTML_BYTES` or `WEBSITE_MAX_PDF_BYTES` (declared or streamed) |
  | 415 | `unsupportedContent` | neither HTML nor a PDF |
  | 422 | `jsOnlyPage` | a page that renders only with JavaScript: almost no text beside an executable script, or a `<noscript>` asking for JavaScript (a page carrying JSON-LD is left to the app) |
  | 429 | `rateLimited` | the per-host or per-install limit |
  | 502 | `offline` | the site (or its `robots.txt`) could not be reached, answered 5xx on `robots.txt`, or its host did not resolve |
  | 502 | `upstreamStatus` | any other non-2xx from the site, or more than five redirects |
  | 504 | `timeout` | the site did not answer in time |

**Crawl hygiene** (the research's §4.4 and §6 posture):

- **Logged out and named.** Nothing of the inbound request is forwarded —
  no cookie, no credential, no install id. Every request sends
  `WEBSITE_USER_AGENT`, which names the fetcher and a contact URL, plus
  `Accept` and `Accept-Language: he,en`.
- **Public hosts only.** The host must resolve only to globally routable
  addresses; loopback, private, link-local, multicast and reserved addresses
  are refused before any request, on the first URL and on every redirect.
- **`robots.txt` first,** per scheme and host, cached in memory for
  `WEBSITE_ROBOTS_TTL_SECONDS`: the groups naming `ketoclubbot`, else `*`;
  longest match wins, a tie goes to `Allow` (RFC 9309). A 4xx (or a 3xx,
  which is not followed) means no rules; a 5xx or no answer means the site is
  not fetched at all.
- **AI opt-outs are honoured** as refusals, not warnings.
- **Rate limits,** in memory: `WEBSITE_HOST_RATE_LIMIT_PER_MINUTE` fetches per
  site across every install (a paste costs at most two), and
  `WEBSITE_RATE_LIMIT_PER_MINUTE` per install, so the route is no open proxy.
- **Size caps** before and while reading the body.
- **Nothing is kept or republished.** No page is cached server-side; the one
  log line per fetch (logger `ketoclub.website`) carries the host and the
  outcome only — never the path, the query or the body.
- **No Wix `_api` calls** and no headless browser (#180 decides the first).

```bash
curl -sS localhost:8000/v1/website/fetch \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{"url": "https://example.com/"}'
```

## The D25 analysis routes (#333)

`POST /v1/classify`, `GET /v1/venue-menus/{source}/{platform_id}` and
`POST /v1/text-menu` answer with complete results: the Dart `Menu` and
`MenuAnalysed` JSON (camelCase, `app.keto.models`), made on the server by
the ported rule engine, prompt and parser (`app/keto/`, `app/platforms/`).
`backend_plan.md` §3.3 is the contract; in short:

- **Options** are `{netCarbLimitGrams: 1..50, dietaryConstraints: [...]}`,
  each constraint one of the three Dart prompt fragments verbatim, at most
  once (422 otherwise). `/v1/venue-menus` takes them as `netCarbLimitGrams`
  and one repeated `constraints` query parameter per fragment.
- **The analysis** carries the request's options and `schemaVersion: 1`.
  Its engine is `{"kind": "llm", "model": …}`, or the rule engine's
  `{"kind": "rules", "reason": …}` when Gemini failed (`notConfigured`,
  `offline`, `timeout`, `rateLimited`, `badResponse`): a Gemini failure is
  never an error here, as the client's `RoutingMenuClassifier` falls back.
- **Analysis cache** (`analysis_cache`, `ANALYSIS_CACHE_TTL_SECONDS`): keyed
  by `sha256(fingerprint|model|schemaVersion|netCarbLimitGrams|constraints)`.
  A hit is free; only an `llm` analysis is written. A hit whose dish ids do
  not match the menu's (the same dishes under other ids) is a miss.
- **Analysis bucket** (`ANALYSIS_RATE_LIMIT_*`): spent only just before a
  Gemini call. Empty: `/v1/classify` and `/v1/text-menu` answer 429
  `rateLimited`; `/v1/venue-menus` keeps the menu and answers the rules
  stamped `rateLimited`.
- `/v1/venue-menus` reads the menu proxies' own `menu_cache` rows
  (`X-KetoClub-Cache` reports that cache), maps the payload, and with
  `classify=true` analyses it and upserts `stored_menus` (without the
  analysis's `options`). Errors: 404 `notFound`, 502 `platformChanged`,
  502 `offline`, 504 `timeout`. `/v1/classify` (body ≤
  `CLASSIFY_MAX_BODY_BYTES`, else 413 `payloadTooLarge`) and
  `/v1/text-menu` never write `stored_menus`; a menu or text with no dish is
  422 `noDishesFound`.
- The install id keys the analysis bucket only: it is never stored and
  never logged on these routes.

```bash
curl -sS 'localhost:8000/v1/venue-menus/wolt/hamosad?classify=true&netCarbLimitGrams=6' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef'
curl -sS localhost:8000/v1/text-menu \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{"text": "Steak\nPasta carbonara", "options": {"netCarbLimitGrams": 6, "dietaryConstraints": []}}'
```

## The menu store (#310)

An anonymous, shared store of the menus people open: one row per
`(source, platform_id)` in the `stored_menus` table. **Rows are keyed by
venue, never by install id.** `POST /v1/menus` requires
`X-KetoClub-Install-Id` only to spend the per-install rate limiter (the
`RATE_LIMIT_*` bucket `/v1/chat` uses); the id is then dropped. It is never
stored, never passed to the store's service and never logged, not even
truncated (D12, #164).

`POST /v1/menus` body:

| Field | Type | Notes |
|---|---|---|
| `source` | `"wolt"`, `"tenbis"`, `"tabit"`, `"ontopo"`, `"scan"` or `"website"` | Anything else is 422 |
| `platform_id` | string, 1–512 chars after trimming | The platform's own id for the menu (a Wolt slug, a 10bis restaurant id, …) |
| `venue_name`, `city` | string ≤ 200, or null | Optional |
| `menu` | object | The client's normalised menu, stored as-is; `dish_count` counts `categories[*].dishes` (0 if the shape is off) |
| `analysis` | object or null | Optional; a top-level numeric `score` in it becomes the row's `score`, which is otherwise null. The backend computes no verdicts and no score |

The first upload of a venue answers **201** `{"created": true,
"submission_count": 1}`; a later one answers **200** `{"created": false,
"submission_count": n}`, keeps `first_seen_at`, moves `last_seen_at` and
always replaces the menu. A null (or omitted) `venue_name`, `city` or
`analysis` never erases what an earlier upload stored.
`submission_count` counts uploads, not distinct installs.

`GET /v1/menus/{source}/{platform_id}` answers 200 with `{source,
platform_id, venue_name, city, menu, analysis, dish_count, score,
first_seen_at, last_seen_at, submission_count}` (UTC timestamps).
`platform_id` may contain `/`. It needs no install id and spends no quota.

| Status | `reason` | When |
|---|---|---|
| 400 | `badResponse` | `POST`: missing or malformed install id; either route: an inbound `Authorization` header |
| 404 | `menuNotFound` | `GET`: no row for that pair |
| 404 | (FastAPI's own) | Either route when `MENU_STORE_ENABLED=false`: the router is not mounted |
| 413 | `payloadTooLarge` | `POST`: `Content-Length` or the bytes read over `MENU_STORE_MAX_BODY_BYTES` (1 MiB) |
| 422 | (FastAPI's `detail`) | A body or path that does not validate, or a `NaN`/`Infinity` in the JSON; spends no quota |
| 429 | `rateLimited` | `POST`: over `RATE_LIMIT_PER_MINUTE` / `RATE_LIMIT_PER_DAY` for this install |

```bash
curl -sS localhost:8000/v1/menus \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{"source":"wolt","platform_id":"hamosad","venue_name":"Hamosad",
       "menu":{"categories":[{"name":"Mains","dishes":[{"name":"Steak"}]}]}}'
# {"created":true,"submission_count":1}
curl -sS localhost:8000/v1/menus/wolt/hamosad
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

An iOS or Android build ignores the define (D17): phones reach Wolt and
Gemini directly, so there is no reason to point one at this service.

## Configuration

Copy `.env.example` to `.env` and fill in values; every variable has a safe
default except `GEMINI_API_KEY` and `ADMIN_TOKEN`, which gate the routes
that need them (`/v1/chat`, and `/v1/admin/*` in a later issue). See
`.env.example` for the full list with defaults and descriptions.

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | unset | The server's key, sent only as `x-goog-api-key`. Unset → `/v1/chat` answers `notConfigured` |
| `GEMINI_MODEL` | `gemini-3.5-flash` | Model in the `generateContent` path. `gemini-2.5-flash` was retired for new users September 2026 (404 NOT_FOUND); see `.env.example` for why 3.5-flash was picked over `gemini-flash-latest` / `-lite-latest` / `-3.8-flash`. |
| `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com` | Upstream host; never taken from a request |
| `GEMINI_MAX_OUTPUT_TOKENS` | `65536` | `generationConfig.maxOutputTokens`; must exceed a full menu's verdicts (#188) |
| `GEMINI_THINKING_BUDGET` | `0` | Thinking tokens count against the output budget, and this is a classification task |
| `GEMINI_LOG_UPSTREAM_ERRORS` | `false` | Also log an upstream error reply's `error.message` (key redacted) and `details[].reason`; the shape lines above are always on |
| `VISION_MAX_IMAGES` | `6` | Most `images` parts one `/v1/chat` request may carry (#170) |
| `VISION_MAX_IMAGE_BYTES` | `3145728` | Largest `images` part once decoded, in bytes (3 MiB) |
| `RATE_LIMIT_PER_MINUTE`, `RATE_LIMIT_PER_DAY` | `5`, `40` | Per install id on `/v1/chat` and `POST /v1/menus` (one shared bucket), in memory |
| `MENU_STORE_ENABLED` | `true` | `false` → the menu store's router is not mounted and both `/v1/menus` routes answer 404 (#310) |
| `MENU_STORE_MAX_BODY_BYTES` | `1048576` | Largest `POST /v1/menus` body (1 MiB); over it → 413 `payloadTooLarge` |
| `WOLT_BASE_URL` | `https://restaurant-api.wolt.com` | Upstream host for the by-name discovery route (the menu proxy left it in #168); never taken from a request |
| `TENBIS_BASE_URL` | `https://www.10bis.co.il` | Upstream host for the 10bis proxy; never taken from a request |
| `WOLT_CONSUMER_BASE_URL` | `https://consumer-api.wolt.com` | Upstream host for the Wolt menu proxy (#168) and the nearby-venue discovery route; never taken from a request |
| `WOLT_CLIENT_VERSION` | `1.16.125` | Wolt web-client version sent on menu and discovery requests |
| `DISCOVERY_CACHE_TTL_SECONDS` | `300` | Discovery response cache TTL |
| `DISCOVERY_RATE_LIMIT_PER_MINUTE` | `20` | Per install id, across both discovery routes; no daily cap |
| `ANALYSIS_RATE_LIMIT_PER_MINUTE`, `ANALYSIS_RATE_LIMIT_PER_DAY` | `10`, `60` | Per install id, the D25 analysis bucket: spent only just before a Gemini call (#333) |
| `ANALYSIS_CACHE_TTL_SECONDS` | `604800` | The D25 analysis cache's TTL (7 days, #333) |
| `CLASSIFY_MAX_BODY_BYTES` | `786432` | Largest `POST /v1/classify` body (768 KiB); over it → 413 `payloadTooLarge` |
| `WEBSITE_USER_AGENT` | `KetoClubBot/1.0 (+https://github.com/NoaMcDa/KetoClub; menu reader)` | Sent on every website fetch; names the fetcher and a contact URL (D19) |
| `WEBSITE_MAX_HTML_BYTES`, `WEBSITE_MAX_PDF_BYTES` | `2097152`, `3145728` | Size caps for a fetched page and PDF; the PDF cap matches `VISION_MAX_IMAGE_BYTES` |
| `WEBSITE_MAX_ROBOTS_BYTES`, `WEBSITE_ROBOTS_TTL_SECONDS` | `524288`, `3600` | How much of `robots.txt` is read, and how long it is cached per host |
| `WEBSITE_HOST_RATE_LIMIT_PER_MINUTE` | `6` | Website fetches per site across every install |
| `WEBSITE_RATE_LIMIT_PER_MINUTE` | `10` | Website fetches per install id |

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
# {"content":"{\"dishes\": [...]}","model":"gemini-3.5-flash"}
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

## Manual end-to-end check

Every automated test above mocks Wolt and Gemini, because neither is reachable
from this repository's build environment. This is the one way to confirm the
whole path really works, from a machine that has a real network: linked from
`README.md` and `HANDOFF.md` as *the* place this check lives, so it is written
once.

1. **Set a real key.** `cp .env.example .env` (if not already done) and set
   `GEMINI_API_KEY` to a real Google Gemini API key.
2. **Start the backend.**
   ```bash
   cd backend
   uv sync
   uv run uvicorn app.main:app --reload --port 8000
   ```
3. **Health check.**
   ```bash
   curl -sS localhost:8000/v1/health
   # {"status":"ok","version":"0.1.0","llm_configured":true}
   ```
   `llm_configured` must read `true` — if it reads `false`, `GEMINI_API_KEY`
   was not picked up (check `.env` is in `backend/`, not the repository root).
4. **Proxy check**, against a real Wolt venue slug:
   ```bash
   curl -sS localhost:8000/v1/proxy/wolt/venues/slug/hamosad/assortment \
     -D - -o /dev/null
   # HTTP/1.1 200 OK
   # x-ketoclub-cache: miss
   ```
   Run it again: the second response carries `x-ketoclub-cache: hit`.
5. **Chat smoke test.** Use the curl in "Smoke test against the real API"
   above. A real completion comes back as `{"content":"{\"dishes\": [...]}",
   "model":"gemini-3.5-flash"}` (or whatever `GEMINI_MODEL` names).
5a. **Search for a venue on the web build**, against real Wolt discovery
   endpoints: use the two curls in "The Wolt venue-discovery proxies" above,
   or run the Flutter app and search by name or "near me" once #40 lands.
   A real response carries a `sections` list of venues; run either curl
   twice to see `x-ketoclub-cache` flip from `miss` to `hit`.
6. **The Flutter app, end to end:**
   ```bash
   flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
   ```
   Paste a real Wolt venue link. The menu loads live (not from the checked-in
   fixture) and is classified with the engine chip showing the Gemini model
   name — with no key entered anywhere in the app, because there is nowhere
   to enter one (D12).
7. **The unreachable-backend path.** Stop the `uvicorn` process (Ctrl-C) and
   retry the same paste in the still-running Flutter app: the fetch fails with
   "KetoClub's server could not be reached, so the menu could not be read.",
   and a fresh classification attempt falls back to the rule engine with the
   `backendUnreachable` reason shown on the engine chip — never a bare "no
   internet" message, per `architecture.md` constraint 10.

Nobody has run this checklist from inside this repository's build
environment: `consumer-api.wolt.com` and `generativelanguage.googleapis.com`
are both unreachable through its egress proxy (`HANDOFF.md`, `architecture.md`
§17 open question 1). It is written here, once, for whoever next has a network
path to both.
