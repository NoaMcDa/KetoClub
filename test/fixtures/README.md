# Fixtures

## Wolt

### `wolt_hamosad_menu.json` — recorded, real

A real recording of Wolt's consumer-assortment endpoint (`GET consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/hamosad/assortment`), captured 2026-09-25 with the headers its `_fixture_note` lists (`User-Agent` as `browserUserAgent`, `Accept`, `platform: Web`, `app-language: en`). It is the payload of a real Tel Aviv venue on Wolt and carries only public menu data — the redaction pass found no key or string value shaped like a token, session id, JWT or credential. 12 categories, 56 items, 48 option groups, 0 variant groups.

It is **the** fixture `WoltMenuMapper` is tested against (`wolt_menu_mapper_test.dart`), the one `wolt_fixture_shape_test.dart` checks field by field, and a decode + map row in `test/tool/perf_menu_test.dart`. It was checked in by #185 as `wolt_hamosad_assortment.json`, ahead of the port, and renamed to the `wolt_*_menu.json` pattern by the port (#168) so the shape test auto-picks it up; only the note's `purpose` line was edited. Its `_fixture_note` first key doubles as the mapper's unknown-top-level-key test.

Why this endpoint: the previously-shipped `/v4/venues/slug/{slug}/menu/data` endpoint answers `HTTP 200` with a zero-byte body for every anonymous caller (measured against `hamosad` and `vitrina-lilinblum` on 2026-09-25, with and without the full web-client header set). The synthetic `/v4`-shaped `wolt_vitrina_lilinblum_menu.json` that used to stand in here was removed with the port.

What the real payload does **not** exercise, so `wolt_menu_mapper_test.dart` builds small synthetic, assortment-shaped maps inline for it rather than keeping a second fixture: a dish id listed under two categories, an `item_id` absent from `items[]`, a null or absent `description`, a populated `subcategories` list, a non-null `disabled_info`, a top-level `currency`, and malformed images. What it does exercise: Hebrew names, `"price": 0`, items with an empty `images` list, two `option_id`s with no matching group, and one item-level option `name` that differs from its group's.

`wolt_fixture_shape_test.dart` also pins this file's counts (12/56/48, no top-level `currency`, every listed `item_id` present), so a re-record that quietly loses half the menu fails loudly until those numbers are updated on purpose.

### `wolt_malformed_menu.json` — synthetic

A plausible 2xx body of the wrong shape (an error envelope with none of `categories`/`items`), used to exercise the `platformChanged` path in `wolt_menu_mapper_test.dart`. It says so in its own `_fixture_note`.

### Re-recording

```bash
tool/record_wolt_fixture.sh hamosad
```

From any machine that can reach `consumer-api.wolt.com` (this repository's sandbox and CI cannot — the egress proxy 403s the CONNECT). It sends the web-client header set `lib/utils/wolt_headers.dart` sends (keep the two in sync), fails loudly on a non-200, an **empty body** (the symptom that retired `/v4`) or a non-JSON body, redacts any field whose key looks like a token/secret/session/credential and any string value shaped like a bearer token or JWT, writes `test/fixtures/wolt_{slug}_menu.json` pretty-printed with a `_fixture_note` object (venue, UTC time, endpoint, headers, redactions), and runs `wolt_fixture_shape_test.dart` against it. Any venue slug works; a new slug is a new file the shape test covers with no edit.

Before committing: skim the file for anything the redaction pass missed (request from a private/incognito session so no account data can leak in), and if you re-recorded `hamosad`, update the counts the shape test and `wolt_menu_mapper_test.dart` pin.

## Wolt discovery

`wolt_pages_restaurants.json` (the `GET pages/restaurants` "near me" list)
and `wolt_pages_search.json` (the `POST pages/search` by-name result) are
**synthetic**, not recorded responses: neither `consumer-api.wolt.com` nor
`restaurant-api.wolt.com` is reachable from this build environment. Both
say so in their own first key, `_fixture_note`, which
`test/services/venue/wolt/wolt_venue_mapper_test.dart` asserts is ignored.

They are hand-built from the venue object `phase2_discovery_research.md`
§2.1 documents (the union of what 2026 clients read), extended with every
shape variation `WoltVenueMapper` must survive: two sections, a venue
listed in both (dedupe, first wins), an item with no `venue` at all (a
promo tile, a dish result), a venue with no `location`, one with
`online: false`, one with neither an item `image` nor a `brand_image`, an
integer `rating.score`, Hebrew and English names, and unknown keys at the
top level and inside a section, an item, a venue and a rating.

**Neither file has ever been a real Wolt response.** Re-record both per
`phase2_discovery_research.md` §2.4 (steps 1, 2 and 5: copy the two
requests' JSON responses from wolt.com's own traffic in DevTools, redact
with `tool/record_wolt_fixture.sh`'s rules, keep a `_fixture_note` first
key) before release. `wolt_venue_fixture_shape_test.dart` then checks the
recorded shape against every field the mapper reads. A real response may
not contain every variation above; keep a few hand-added items alongside
the real ones rather than losing that coverage.

## 10bis

`tenbis_synthetic_menu.json` and `tenbis_malformed_menu.json` are
**synthetic**, not recorded responses, tracked by issue #44.

Both files say so in their own first key, `_synthetic` (10bis's
equivalent of the Wolt fixtures' `_fixture_note`), which
`test/services/menu/tenbis/tenbis_menu_mapper_test.dart` also asserts is
ignored by the mapper.

### Why these are synthetic

`www.10bis.co.il` is blocked from this build environment the same way
`restaurant-api.wolt.com` is, so a real response could not be recorded
from here. `tenbis_synthetic_menu.json` is hand-built from the payload
`menu_api_research` §3.2 documents and issue #44's own body text (which
names `categoriesList → dishList`, decimal prices, kosher flags,
`dishOptionsList`, and image fields), extended with every shape
variation `TenBisMenuMapper` needs to survive: a numeric `dishId` and a
string one, a dish with no `dishOptionsList` at all, a dish with no
`dishDescription` key, `"price": 0`, a dish id listed under two
categories (dedupe, first category wins), an empty category (`Coming
Soon`), Hebrew category and dish names, and unknown keys at the top
level, inside a category, and inside a dish.

`tenbis_malformed_menu.json` is a plausible 2xx body of the wrong shape
(an error envelope with no `categoriesList`), used to exercise the
`platformChanged` path in `tenbis_menu_mapper_test.dart`.

**Neither file has ever been a real 10bis response, and neither proves
anything about what 10bis's real API actually returns.** Issue #44
tracks recording one — through the backend's 10bis proxy route
(`phase2_plan.md` §5 B1) once it lands:

```bash
curl -sS localhost:8000/v1/proxy/tenbis/api/v1.0/Restaurants/{id}/Menu \
  -o test/fixtures/tenbis_{id}_menu.json
```

or directly, from any machine that can reach `www.10bis.co.il`:

```bash
curl -sS -H 'Accept: application/json' \
  'https://www.10bis.co.il/api/v1.0/Restaurants/{id}/Menu' \
  -o test/fixtures/tenbis_{id}_menu.json
```

Before committing the result: skim it for anything worth redacting,
check whether `TenBisMenuMapper`'s assumed field names
(`categoriesList`, `categoryName`, `dishList`, `dishId`, `dishName`,
`dishDescription`, `price`, `dishOptionsList`, `dishImageUrl`,
`restaurantName`) match the real payload — if they do not, this is the
schema-drift signal architecture.md §15 asks for, and the mapper (and
its tests) need updating to match before the fixture replaces the
synthetic one — and re-check that the fixture still exercises every
shape variation listed above; a real venue may not happen to have a
duplicated dish id or an empty category, so keep a couple of
hand-added dishes alongside the real ones rather than losing that
coverage. Keep the `_synthetic` key, or remove it and the assertion in
`tenbis_menu_mapper_test.dart` that checks an unknown top-level key is
ignored — either is fine as long as they change together.

## LLM response fixtures (`llm_*.json`)

These are **synthetic by design**, not recordings. Each one is a hand-built
model reply shaped to exercise exactly one of the eight parser rules in
architecture.md §9.4 — an invented dish, a yellow with no instruction, an
over-cap list, a reply that is not JSON at all, and so on. A recorded response
could not be relied on to contain those cases, so recording them would make the
suite weaker rather than stronger.

`llm_unknown_keys.json` doubles as the parser's unknown-key tolerance test: it
carries a `_fixture_note` key that the parser must ignore.
