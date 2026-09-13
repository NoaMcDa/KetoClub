# Fixtures

## Wolt

`wolt_vitrina_lilinblum_menu.json` and `wolt_malformed_menu.json` are
**synthetic**, not recorded responses, contrary to the default rule in
architecture.md §18.4 that a fixture is a recorded real response.

Both files say so in their own first key, `_fixture_note`, which
`test/services/menu/wolt/wolt_menu_mapper_test.dart` also asserts is
ignored by the mapper (an unknown top-level key must not change the
result), so the label doubles as a test rather than sitting as a dead
comment.

### Why these are synthetic

`restaurant-api.wolt.com` is blocked from this build environment — the
egress proxy returns a 403 on the CONNECT to that host — so a real
response could not be recorded from here. That is a limit of the
environment, not of the project: see "Re-recording" below for the route
that now exists. `wolt_vitrina_lilinblum_menu.json`
is instead hand-built from the payload documented in `menu_api_research`
(lines 24-36) and `README.md` (lines 85-120), extended with every shape
variation `WoltMenuMapper` needs to survive: a `radio` and a `checkbox`
option group, a dish with `"options": []`, a dish with `description` null
and another with the key absent entirely, `"price": 0`, an item id listed
under two categories (dedupe), an item id absent from `items[]` (skip), an
option id absent from `options[]` (skip), Hebrew dish and category names,
and unknown keys at the top level, and inside a category, an item, an
option group, and an option value.

`wolt_malformed_menu.json` is a plausible 2xx body of the wrong shape (an
error envelope with none of `currency`/`categories`/`items`), used to
exercise the `platformChanged` path in `wolt_adapter_test.dart` and
`wolt_menu_mapper_test.dart`.

### Re-recording before release

Before shipping, replace `wolt_vitrina_lilinblum_menu.json` with a real
recording — from a network environment that can reach Wolt — of:

```bash
curl -s \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
  -H 'Accept: application/json' \
  'https://restaurant-api.wolt.com/v4/venues/slug/vitrina-lilinblum/menu/data'
```

Or, more simply, through the backend, which sets that header itself:

```bash
cd backend && uv run uvicorn app.main:app --reload --port 8000
curl -s 'http://localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data' \
  | python3 -m json.tool
```

The backend relays Wolt's body unchanged, so the two produce the same
recording; the second needs no hand-copied header.

(The `User-Agent` value lives in **three** places that must agree:
`browserUserAgent` in `lib/utils/constants.dart`, the literal above, and
`WOLT_USER_AGENT` in `backend/app/services/wolt.py`. The backend needs its
own copy because a browser forbids a page from setting that header, which
is part of why the proxy exists at all.) Redact only fields that are
personal (there should be none in a public menu). Keep the `_fixture_note`
key, updated to describe the real recording instead, or remove the note
and the assertion in `wolt_menu_mapper_test.dart` that checks it is
ignored — either is fine as long as they change together. Re-check that
the fixture still exercises every shape variation listed above; a real
venue may not happen to have a checkbox option group or a duplicated
item id, in which case keep a couple of hand-added dishes alongside the
real ones rather than losing that coverage.

## LLM response fixtures (`llm_*.json`)

These are **synthetic by design**, not recordings. Each one is a hand-built
OpenRouter reply shaped to exercise exactly one of the eight parser rules in
architecture.md §9.4 — an invented dish, a yellow with no instruction, an
over-cap list, a reply that is not JSON at all, and so on. A recorded response
could not be relied on to contain those cases, so recording them would make the
suite weaker rather than stronger.

`llm_unknown_keys.json` doubles as the parser's unknown-key tolerance test: it
carries a `_fixture_note` key that the parser must ignore.
