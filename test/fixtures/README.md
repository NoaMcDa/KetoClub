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

`tenbis_19156_menu.json` is a **real recording** (#468, closing #44) of
`GET https://www.10bis.co.il/NextApi/GetRestaurantMenu?culture=he-IL&uiCulture=he&restaurantId=19156&deliveryMethod=delivery`,
the endpoint 10bis's own web app reads, taken 2026-11-13. The older
`api/v1.0/Restaurants/{id}/Menu` answers 404 for every id. Its
`_fixture_note` key (the Wolt fixtures' convention) records the request,
the redaction (`ShoppingCartGuid`, a per-request id, zeroed) and the trim:
each of the 19 categories keeps 2 of its dishes, 38 of 247, so the goldens
built from it stay small. Every kept dish is byte-for-byte what 10bis
sent. The shape test (`tenbis_fixture_shape_test.dart`) covers every
`tenbis_*_menu.json` but the malformed one automatically.

The variations a real menu does not happen to show (a string `dishId`, a
decimal `dishPrice`, a duplicated dish id, a category without a numeric
`categoryID`, 10bis's two "no such restaurant" answers) are inline
payloads in `tenbis_menu_mapper_test.dart` and the golden corpus
(`tool/golden/golden_corpus.dart`, `tenBisSyntheticPayloads`). The two
not-found shapes were observed live: `Success: false` with an
`InvalidParameters` error for a non-numeric id, and
`Data.categoriesList: null` for an id no restaurant has, both with a 200.

`tenbis_malformed_menu.json` is **synthetic**: a plausible 2xx body of the
wrong shape (no `Success`, no `Data`), for the `platformChanged` path.

To re-record, from any machine that can reach `www.10bis.co.il`:

```bash
curl -sS -A 'Mozilla/5.0' -H 'Accept: application/json'   'https://www.10bis.co.il/NextApi/GetRestaurantMenu?culture=he-IL&uiCulture=he&restaurantId={id}&deliveryMethod=delivery'   -o test/fixtures/tenbis_{id}_menu.json
```

or through a local backend:
`curl -sS localhost:8000/v1/proxy/tenbis/restaurants/{id}/menu`. Zero the
`ShoppingCartGuid`, then regenerate the goldens (D25).

## LLM response fixtures (`llm_*.json`)

These are **synthetic by design**, not recordings. Each one is a hand-built
model reply shaped to exercise exactly one of the eight parser rules in
architecture.md §9.4 — an invented dish, a yellow with no instruction, an
over-cap list, a reply that is not JSON at all, and so on. A recorded response
could not be relied on to contain those cases, so recording them would make the
suite weaker rather than stronger.

`llm_unknown_keys.json` doubles as the parser's unknown-key tolerance test: it
carries a `_fixture_note` key that the parser must ignore.

### Scanned-menu replies (`llm/llm_scanned_*.json`)

Also synthetic by design, for `MenuResponseParser.parseScanned` (the vision
path, issue #89). A scan has no source menu, so §9.4's provenance rule is
replaced by "a nameless element is dropped; duplicate normalised names keep
the first"; one fixture per replaced rule (`nameless_element`,
`duplicate_names`), plus a valid reply, an empty one (`noDishesFound`) and
`over_cap` — 1001 generated dishes, one past `maxAnalysedDishes`. Every other
§9.4 rule is proven by running the text path's own `llm_*.json` fixtures above
through `parseScanned` unchanged, so the two parsers are held to the same
files. No vision reply has been recorded yet (#88).

## Restaurant websites (`website/*.html`)

**Synthetic**, hand-written for issue #181 (`architecture.md` D19); each says so
in a leading HTML comment. No real restaurant site has been recorded: they pin
the locator's cases, not any real site's markup. `jsonld_menu.html` carries a
schema.org `Menu` (sections, a nested section, a nameless item, a malformed
block); `menu_link.html` links its menu page from the nav (and a Wolt link that
must not be followed); `hebrew_menu_link.html` says `תפריט` only in a link's
text; `legacy_encoded_menu_link.html` links it only as `תפריט`
percent-encoded in `windows-1255` (`%FA%F4%F8%E9%E8`), which is not UTF-8;
`pdf_link.html` links a menu PDF on a file host beside a wine-list PDF;
`no_menu.html` has none of these; `menu_page_separate_prices.html` (Hebrew) and
`menu_page_inline_prices.html` (English) are the two price layouts
`WebsiteMenuLocator.menuText` reads. Replace or supplement them with real,
redacted pages once a machine can fetch some, and record which sites they came
from.

## Photon street search (`photon/*.json`)

**Recorded, real**, for issue #449 (`architecture.md` D28): two replies from
Photon's public instance (`https://photon.komoot.io/api/`), recorded
2026-11-12 from a laptop with the exact request the app sends (`limit=15`,
`bbox=34.2,29.4,35.9,33.4`, `layer=house`, `layer=street`), stored as
returned (pretty-printed, nothing redacted; they are public OpenStreetMap
data and carry no user data).

- `photon_herzl_tel_aviv_default.json`: `q=` the Hebrew for "Herzl 10 Tel
  Aviv", `lang=default`. Nine `house` features; it shows Photon returning one
  address under three spellings of the city, which the mapper's dedupe step
  merges.
- `photon_dizengoff_en.json`: `q=dizengoff`, `lang=en`. Eight segments of one
  `street` plus three other features.

Photon sends `Content-Type: application/json` with no charset, which is why
both clients decode `bodyBytes` as UTF-8. These were recorded with Python's
own `User-Agent`; Photon answers `403` to Dart's default one, which is why
`PhotonPlaceSearchService` sends a KetoClub `User-Agent` on phones (a
fixture cannot show that: a mocked client never sees Photon's check). To re-record, send the same `GET`
with any HTTP client and save the body; keep to a handful of requests (the
public instance is fair-use).
