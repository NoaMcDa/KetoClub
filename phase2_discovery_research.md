# Phase 2 Discovery chain: research and completion plan

Written 2026-09-23, after Phase 2 run 1 merged everything except the
Discovery chain. That chain — #37, #38, #39, #40, #41, #42, #43, #50, #63,
#64 and #123 — was deferred because #38 (find Wolt's venue-search endpoint)
was believed to need a browser capture only the user can make. This
document is the research that unblocks as much of it as can be unblocked
from here, and says exactly what still needs the user's machine.

Nothing below was verified by a live call: `restaurant-api.wolt.com`,
`consumer-api.wolt.com`, `wolt.com`, `docs.flutter.dev` and `api.flutter.dev`
are all egress-blocked in the sandbox and in CI. Every endpoint claim is
third-party evidence (open-source clients, DevTools captures committed to
GitHub, package metadata) dated and confidence-rated in §2. Treat this as a
map for the capture, not a substitute for it.

Sections: 1 summary · 2 Wolt endpoints (#38) · 3 the proxy route (#123) ·
4 `LocationService` (#37) · 5 `WoltVenueSearchService` (#39) · 6 the
Discovery screen (#40) · 7 pre-scoring, D13 (#41, #42) · 8 flows, skeletons,
accessibility, photos (#43, #63, #64, #50) · 9 order of work · 10 what only
the user can do · 11 sources.

## 1. Summary

| Finding | Effect on the plan |
|---|---|
| Wolt's web client uses two anonymous, unofficial "pages" endpoints: `GET consumer-api.wolt.com/v1/pages/restaurants?lat=&lon=` (every venue near a point, ~2000 nearest) and `POST restaurant-api.wolt.com/v1/pages/search` with `{"q","target":"venues","lat","lon"}` (by name). Both return `{"sections":[{"items":[{"venue":{…}}]}]}` | #39 can be written now against a synthetic fixture built from the documented shape, the way #45 was for 10bis; the user re-records later. #38 shrinks from "discover" to "confirm and record" |
| Every browser capture on record shows `access-control-allow-origin: https://wolt.com` (origin-locked, credentials allowed) | The web build must go through the backend (#123), exactly as menus do. No change to the D11 rule |
| Requests need the web client's header set (`platform: Web`, `client-version`, `app-language`, `x-wolt-web-clientid`, `w-wolt-session-id`); a bare request to the search POST is reported to get `410` "update the Wolt app" | The proxy route and the native adapter both send that set; the User-Agent alone is not enough, unlike the menu proxy |
| Two 2025–2026 sources report `GET /v4/venues/slug/{slug}/menu/data` — the endpoint the shipped Wolt adapter uses — returning `200` with an **empty body** without a user token, and moved to `consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/{slug}/assortment` | Issue #22's fixture recording is now urgent: it either refutes this or tells us the menu adapter needs the assortment endpoint. Flagged in §2.5 |
| Wolt's ToS forbid "systematic retrieval … any robot, spider, web crawler" | Pre-scoring (#42) that fetches N menus per list is the feature most exposed to this. §7 recommends the option that fetches nothing the user did not ask to open |
| `geolocator` 14.x builds on Flutter 3.47; the repo pins `^11.0.0`. Web is HTTPS-only and `getLastKnownPosition`/`openAppSettings` throw there | #37 is unblocked and needs no capture; it bumps the pin and wraps the plugin behind a sealed `LocationResult` |
| `cached_network_image` cannot draw a no-CORS image on web; `Image.network` with `webHtmlElementStrategy: fallback` can, at the cost of caching | #50 ships without a caching package on web (§8.4) |

The chain is therefore **not blocked on the capture any more** except for
two claims that only a real call can settle: which section index holds the
full venue list, and whether the search POST needs the two UUID headers. Both
are absorbed by writing the mapper to iterate every section and by always
sending the headers. What the capture still buys is the recorded fixture
(architecture.md §18.4 says a fixture is a recorded response) and the answer
to the `/v4 … menu/data` question.

## 2. Wolt discovery endpoints (#38)

### 2.1 What the current web client calls

Confidence: **H** = several independent 2026 clients with code; **M** = one
2026 source or only 2025; **L** = nothing after 2023. Sources in §11.

| Endpoint | Request | What comes back | Conf |
|---|---|---|---|
| `GET https://consumer-api.wolt.com/v1/pages/restaurants?lat={lat}&lon={lon}` (also works on `restaurant-api.wolt.com`, which Wolt's own 2023–2025 internship assignments use) | `platform: Web` needed for `promotions`/`badges_v2`; no auth. `limit` is ignored; one client passes `radius`, effect unverified | `sections[].items[]`, each `{title, image.url, link.target, template, track_id, venue{…}}`. Which section holds "all restaurants" varies by source (`sections[0]`, `sections[1]`, or the one titled `All restaurants`) — **iterate all sections and dedupe by `venue.slug`** | H |
| `POST https://restaurant-api.wolt.com/v1/pages/search` body `{"q":"pizza","target":"venues","lat":32.07,"lon":34.77}` (`target: "items"` searches dishes; `null` mixes both — what wolt.com sends) | JSON body; web header set below. ~100 venues per query, ranked by proximity | `sections[0].items[].venue{…}` (venues) or `.menu_item{id,name,price,currency,venue_name,venue_id}` (items) | H |
| `GET https://consumer-api.wolt.com/v1/pages/front?lat=&lon=` | city front page: category and promo carousels, some items carry `venue` | mixed sections | H |
| `GET https://consumer-api.wolt.com/order-xp/web/v1/pages/venue/slug/{slug}/static` | web header set | `venue{id,name,slug,address,post_code,city,country,currency,description,rating{rating,score_raw,volume},timezone,tags[],website,phone,share_url,delivery_methods[]}` — no coordinates read by any client; take them from the list | H |
| `GET https://consumer-api.wolt.com/order-xp/web/v1/venue/slug/{slug}/dynamic/?lat=&lon=&selected_delivery_method=homedelivery` | `platform: Web` required | live `venue.online`, delivery estimate and fee, banners | H |
| `GET https://restaurant-api.wolt.com/v1/cities` | none | `results[]{id,name,slug,timezone,country_code_alpha2,location.coordinates:[lon,lat]}` — a seed position for "search a city" without GPS | H |
| `GET restaurant-api.wolt.com/v1/pages/delivery`, `/v1/pages/front/{city}`, `/v3/venues/slug/{slug}`, the Google autocomplete/geocode proxies | — | 2021–2023 only; two 2026 sources say `/v3` is 410/404 | L / dead |
| Any "delivers-to" or delivery-area lookup | — | **no source at all**; clients read `venue.delivers` from the list instead | — |

The `venue` object in the list endpoints (union of what clients read):

```
id, name, slug, address, city, country (alpha-3), currency, delivers (bool),
delivery_price, delivery_price_int, estimate (min), estimate_range ("15-25"),
location: [lng, lat]            ← GeoJSON order; one scraper reads it backwards
online (bool), price_range (1–4), product_line ("restaurant" | "retail" …),
rating: {rating (0–5?), score (0–10), volume}, short_description,
tags: ["ice cream", "sweets"], badges[], promotions[], brand_image{url,blurhash}
```

and the list item around it carries `image.url` (an `imageproxy.wolt.com` or
`wolt-menu-images-cdn.wolt.com` URL). This answers #38's fourth acceptance
criterion — name, address, coordinates, cuisine (`tags`), opening state
(`online`) and image are all present in the one list call. Opening *hours*
are not; `online` is the live state, which is what the Discovery artboard's
"Open now" chip needs.

### 2.2 The request wolt.com itself sends

Captured in Chrome DevTools on 2026-02-09 and committed to a public repo
(analisto/wolt_com), cookies elided:

```
GET https://consumer-api.wolt.com/v1/pages/restaurants?lat=…&lon=…
accept: application/json, text/plain, */*
app-language: en
client-version: 1.16.75-PR20787
clientversionnumber: 1.16.75-PR20787
origin: https://wolt.com
platform: Web
referer: https://wolt.com/
user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36
w-wolt-session-id: no-analytics-consent
x-wolt-web-clientid: 40fac410-9825-4611-ba68-60cae2260415
```

Response headers on the same call:

```
access-control-allow-credentials: true
access-control-allow-origin: https://wolt.com
vary: Accept-Encoding,Origin
via: 1.1 …cloudfront.net (CloudFront)
```

The search POST carried the same header set and no `Authorization`. The
header values that matter, per the clients that probed them:

- `platform: Web` — without it `venue-list/promotions-near-you` returns
  `200` with a `no-content` section and `dynamic` misbehaves. Send it always.
- `client-version` / `clientversionnumber` — values seen in 2026 run from
  `1.16.75` (Feb) to `1.16.125` (Sep). HTTP `430` is Wolt's "update the app"
  code; a `410` with `error_code 430` on the search POST is the reported
  symptom of a missing web-client identity. Pin one value in one place
  (`constants.dart` for the phone adapter, `config.py` for the proxy) and
  expect to bump it.
- `x-wolt-web-clientid` (uuid4, one per install) and
  `w-wolt-session-id: no-analytics-consent` — one June 2026 source says the
  search POST needs them; two September 2026 clients omit them and still
  report success. Unresolved; send them, they cost nothing. The install id
  KetoClub already keeps (`InstallIdStore`) must **not** be reused here — it
  is sent to KetoClub's backend only, by D12's privacy rule; generate a
  separate random UUID.
- `app-language: he` selects Hebrew venue names and descriptions. KetoClub
  should pass the UI locale, and the mapper must not assume Latin text.
- `User-Agent` — one client says the default headless UA gets an altered
  layout, another says none is needed. A browser cannot set it anyway; the
  proxy sends the same `browserUserAgent` the menu proxy does.

### 2.3 CORS, auth, rate limits, terms — the #38 acceptance criteria

- **CORS**: origin-locked to `https://wolt.com` with credentials, so it
  cannot be `*`. No browser page on another origin has ever been seen
  calling these successfully. Same rule as menus (architecture.md §13, D11):
  phones call Wolt directly, web goes through the backend. Expected by #38;
  confirmed by the captures.
- **Auth**: none for discovery, search, cities, venue static/dynamic and
  assortment, in every 2026 client. Favourites, basket and checkout need a
  bearer JWT from `authentication.wolt.com` — out of scope.
- **Rate limits and blocking**: `429` on bursts (clients throttle at
  0.35–1 s between calls and honour `Retry-After`); "fewer/empty" results
  after ~45 rapid list calls; datacenter IPs are sometimes blocked
  (CloudFront in front, Ravelin device cookies on the web session, an Apify
  actor says residential proxies are needed). One May 2026 source reports
  every `v1` endpoint returning `410 Gone` from US residential IPs — it is
  contradicted by every June–September 2026 client, and is most likely the
  missing-header symptom. **For #123: the endpoint is cheap per call but
  bursty callers get throttled, so the proxy needs its 5-minute cache and a
  modest per-install limit (§3), and the app must never fan out list calls
  (§7).**
- **Terms**: Wolt's user terms (2 May 2024 text) forbid "use of any kind of
  systematic retrieval, such as use of any robot, spider, web crawler,
  extraction software, automated process and/or device to scrape, copy
  and/or monitor any portion of the Wolt-Service". One call per user action
  (a search, a "near me") is the same exposure the shipped menu fetch
  already carries; background fan-out over N venues is a different category
  and §7 avoids it. `restaurant-api.wolt.com` is in Wolt's HackerOne scope,
  so probing beyond normal client behaviour is their bug-bounty programme's
  business, not ours.

### 2.4 What the capture still has to settle

Only the user can do these, from a browser on wolt.com with DevTools open
(the protocol is `README.md`'s reverse-engineering section; the redaction
rules are `tool/record_wolt_fixture.sh`'s):

1. Open `https://wolt.com/en/isr/tel-aviv/restaurants`, allow or set a
   location, and copy the `pages/restaurants` request URL, its request
   headers and the full JSON response. Note which section index holds the
   complete venue list and how many venues came back.
2. Type a name in the site search (e.g. "vitrina"), copy the `pages/search`
   request (method, URL, headers, JSON body) and response.
3. Reissue both from a terminal with `curl` **outside the browser**, once
   with the full header set from §2.2 and once with only `platform: Web`
   and a browser UA, and record which succeed. That answers the UUID-header
   question and gives the proxy its minimal header set.
4. Run `tool/record_wolt_fixture.sh vitrina-lilinblum`. If it fails with an
   empty `200` body, §2.5 applies and #22 becomes a code change, not a
   recording.
5. Redact (`ravelinDeviceId`, cookies, any `session`/`token` key; the
   script's `redact_key_pattern` is the list) and check the two responses
   in as `test/fixtures/wolt_pages_restaurants.json` and
   `test/fixtures/wolt_pages_search.json` with a `_fixture_note` first key,
   the convention `test/fixtures/README.md` documents.

Until step 5 happens, #39 runs on a synthetic fixture built from §2.1 whose
`_fixture_note` says so — the same decision run 1 took for 10bis (#45).

### 2.5 A side finding about the shipped menu adapter

> **Settled 2026-09-25: empty body confirmed, ported in #168.** `/v4 … menu/data`
> answered `200` with a zero-byte body for `hamosad` and `vitrina-lilinblum`,
> with and without the §2.2 header set; the assortment endpoint answered with a
> real menu (`test/fixtures/wolt_hamosad_menu.json`), which `WoltMenuAdapter`,
> `WoltMenuMapper` and the backend proxy now read. The text below is the
> pre-recording analysis, kept as written.

`WoltMenuAdapter` fetched `GET restaurant-api.wolt.com/v4/venues/slug/{slug}/menu/data`
with a browser User-Agent and nothing else. Two sources (OzTamir/wolt-api,
2025-12-20: "the verified curl returned HTTP 200 with an empty body";
r1nnegann/wolt-easy, 2026-09-06: the same, "without user token") say that
endpoint no longer answers anonymously, and both moved to
`GET consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/{slug}/assortment`,
which the current web app uses (`categories[]`, `items[]` with prices in
minor units and `images[].url`). A third client keeps `/v4/venues/slug/{slug}/menu`
as a fallback that "still works for some venues". Neither source shows the
headers it sent, so this may be the same missing-`platform: Web` symptom as
the search POST.

What to do with it: nothing until `tool/record_wolt_fixture.sh` has been
run once (step 4 above). If it returns a real menu, the adapter is fine. If
it returns an empty body, retry with the §2.2 header set; if that also
fails, #22 turns into "port `WoltMenuAdapter` and `WoltMenuMapper` to the
assortment endpoint", which touches one file each by design (architecture
.md §6.3) plus the proxy route's path. `MenuFetchFailureReason.platformChanged`
already covers a `200` whose body is not a menu, so the app degrades
correctly either way; it just cannot show a menu.

## 3. The venue-search proxy route (#123)

The findings fix the route shape #123 left open:

| Route | Upstream | Forwarded parameters |
|---|---|---|
| `GET /v1/proxy/wolt/pages/restaurants?lat=&lon=&lang=` | `GET {WOLT_CONSUMER_BASE_URL}/v1/pages/restaurants?lat=&lon=` | `lat` ∈ [-90, 90], `lon` ∈ [-180, 180], 4-decimal rounding for the cache key (≈11 m); `lang` ∈ {en, he} → `app-language` |
| `POST /v1/proxy/wolt/pages/search` body `{"q","lat","lon","lang"}` | `POST {WOLT_BASE_URL}/v1/pages/search` body `{"q","target":"venues","lat","lon"}` | `q` trimmed, 1–80 chars; the target is fixed server-side, never client-chosen |

Design points, each following an existing decision:

- **Second upstream host.** `consumer-api.wolt.com` joins `config.py` as
  `WOLT_CONSUMER_BASE_URL`, never taken from a request, like `WOLT_BASE_URL`
  and `TENBIS_BASE_URL`. Both routes are literal allow-list entries; no
  wildcard.
- **Header set built from scratch** in `services/wolt.py` as
  `WOLT_DISCOVERY_HEADERS`: `platform: Web`, `client-version` and
  `clientversionnumber` (one `WOLT_CLIENT_VERSION` setting), `app-language`
  from the validated `lang`, `x-wolt-web-clientid` (one uuid4 generated at
  backend start, held in `app.state`, never persisted), `w-wolt-session-id:
  no-analytics-consent`, `Accept`, and the existing `WOLT_USER_AGENT`.
  Nothing from the inbound request (`Origin`, cookies, the KetoClub install
  id) reaches Wolt — the rule `_proxy_menu` already enforces.
- **Cache**: reuse `menu_cache` with `source = "wolt-restaurants"` /
  `"wolt-search"` and the canonical query as the key (`{lat4},{lon4},{lang}`
  or `{q lowercased},{lat4},{lon4},{lang}`), TTL a new
  `DISCOVERY_CACHE_TTL_SECONDS = 300`, `X-KetoClub-Cache: hit|miss` as today.
  The composite `(source, slug)` primary key from #122 already makes this
  collision-free; the column is called `slug` but holds any id.
- **Rate limit**: yes, per install, because §2.3 says bursty callers get
  throttled by Wolt and a throttled backend IP would take every web user
  down at once. Reuse `/v1/chat`'s limiter (#101) with its own bucket:
  20/minute per install is generous for a human typing and stops a loop.
  Cache hits bypass it, as chat-cache hits do.
- **Status mapping**: pass Wolt's status and body through unchanged, as the
  menu proxy does; `502 offline` / `504 timeout` for proxy-originated
  failures. A Wolt `410`/`430` passes through too, so the Dart side can map
  it to `platformChanged` and the UI can say "search stopped working" rather
  than "offline".
- **Tests**: respx-faked upstream for 200, 4xx, 5xx, `ConnectError`,
  timeout; parameter validation (out-of-range lat, 81-char query, unknown
  lang); cache hit within TTL and miss after; the limiter; and a test that
  the forwarded request carries exactly `WOLT_DISCOVERY_HEADERS` and no
  inbound header — the same shape as `tests/test_proxy_wolt.py`.

`backend/README.md` gets the two curl lines, and the manual end-to-end check
gains "search for a venue on the web build".

## 4. `LocationService` (#37)

Unblocked; nothing here needs the capture.

- **Package**: `geolocator` 14.0.3 (latest at the time of writing) builds on
  Flutter 3.47.4 / Dart 3.13. The repo's `^11.0.0` pin must be bumped; the
  API changed at 13 (`LocationSettings(accuracy:, timeLimit:)` replaces the
  `desiredAccuracy`/`timeLimit` named arguments on `getCurrentPosition`).
  Android uses `geolocator_android` 5.x (FusedLocationProvider by default;
  `forceLocationManager: true` is available for devices without Play
  Services); iOS `geolocator_apple`; web `geolocator_web` over the browser
  Geolocation API.
- **Web constraints**: the Geolocation API needs a secure context —
  `https://` or `localhost`; a plain `http://` origin returns
  `LocationPermission.denied` without a prompt. `getLastKnownPosition`,
  `openAppSettings` and `openLocationSettings` throw
  `UnimplementedError`/`PlatformException` on web, so the service must not
  call them there; `runsInBrowser` (the constant the Wolt adapter already
  uses) gates it.
- **Permission model**: `checkPermission()` → `requestPermission()` →
  `getCurrentPosition(locationSettings: LocationSettings(accuracy:
  LocationAccuracy.medium, timeLimit: Duration(seconds: 10)))`. Android 12+
  can grant *approximate* only, which arrives as `whileInUse` with a
  coarse fix — fine for "within a few hundred metres" and the service should
  request `medium`, not `best`, so the approximate grant is honoured rather
  than re-prompted. `deniedForever` (iOS "Never", Android "Don't ask
  again") is its own outcome so the UI can send the user to Settings instead
  of re-asking. `isLocationServiceEnabled()` false (GPS off) is the third
  distinct outcome.
- **Manifests**: `android/app/src/main/AndroidManifest.xml` declares both
  `ACCESS_COARSE_LOCATION` and `ACCESS_FINE_LOCATION` (declaring only fine
  makes Android 12+ deny the approximate option); `ios/Runner/Info.plist`
  gets `NSLocationWhenInUseUsageDescription` only — no "always", no
  background. The strings are user-facing and go through the platform's own
  localisation (`InfoPlist.strings` per language, `strings.xml` per locale),
  not ARB; both languages say the position is used once to list nearby
  restaurants and never leaves the device except as a search parameter.
  #66's platform-setup PR already touched both manifests; this is an
  addition, not a conflict, now that #66 is merged.
- **Shape in `lib/`**: `services/location/location_service.dart` with
  `abstract interface class LocationService { Future<LocationResult>
  current(); }` and `sealed class LocationResult` with `LocationFound(lat,
  lon, accuracyMetres)`, `LocationDenied(permanently: bool)`,
  `LocationUnavailable(reason: servicesOff | insecureContext | timeout |
  unsupported)`. `GeolocatorLocationService` is the only file importing
  `package:geolocator`, and it is a rank-0 service like `connectivity.dart`
  — it may not import `flutter/services.dart` (the architecture test), so
  `PlatformException` is caught as `Exception` and folded into
  `unavailable`. `di.dart` constructs it; the constructor does no plugin I/O
  (the `di_test` rule). `FakeLocationService` in `test/fakes/` and
  `FlowFakeLocationService` in `flow_support.dart` script each result.
- **Privacy copy**: `settingsConsentBody` currently says "Nothing about you,
  your location or your history is sent". Once a position is sent to Wolt
  (and, on web, through KetoClub's backend), that sentence is false and the
  ARB text must change in the same PR — "your position is sent to Wolt only
  when you search nearby, and is not stored".

## 5. `WoltVenueSearchService` (#39)

- **Model**: `Venue` today has `ref, name, address, latitude, longitude,
  sourceUrl` and is constructed nowhere in `lib/`. Add the fields the card
  needs and the feed provides: `cuisineTags: List<String>`, `isOnline:
  bool?`, `imageUrl: String?`, `shortDescription: String?`, `platformRating:
  double?` (Wolt's 0–10 `rating.score`, not a keto score — name it so
  nobody confuses the two), `estimateMinutes: int?`. Distance is not a
  field; it is computed from the search position at render time so a
  cached list stays valid when the user moves.
- **Interface**: `abstract interface class VenueSearchService { Future<VenueSearchResult>
  nearby(double lat, double lon, {required String language}); Future<VenueSearchResult>
  byName(String query, {double? lat, double? lon, required String language}); }`
  with `sealed VenueSearchResult` → `VenuesFound(List<Venue>)` and
  `VenueSearchFailed(reason)`, reasons `offline, timeout, rateLimited,
  platformChanged, blockedByBrowser, backendUnreachable` — distinct from
  `MenuFetchFailureReason` as the issue asks, and `failure_copy.dart`'s
  uniqueness test extends to them.
- **Two files, like the menu adapter**: `wolt_venue_search_service.dart`
  does HTTP with the same `proxyBase`/`runsInBrowser` routing as
  `WoltMenuAdapter` (§2.2's header set on the direct path, minus
  `User-Agent` in a browser); `wolt_venue_mapper.dart` is a pure
  `Map<String, Object?>` → `List<Venue>` function that walks every section,
  takes `location[1]` as latitude and `location[0]` as longitude, dedupes by
  slug, skips any item without `venue.slug` and `venue.name`, and tolerates
  every field being absent — the same never-throws contract
  `WoltMenuMapper` has.
- **Sorting**: nearest first by haversine distance (a `utils/geo.dart` with
  a pure function and a test against two known points); the "minutes"
  figure on the card is Wolt's own `estimate` when present, else
  `ceil(distanceKm / 5 * 60)` walking, labelled as such.
- **Boundary test**: `consumer-api.wolt.com` and `/v1/pages/` join
  `import_rules_test.dart`'s `_Boundary` list, allowed only in
  `wolt_venue_search_service.dart`; `restaurant-api.wolt.com`'s allow-list
  gains the same file. `services/venue` is rank 0 and may not import
  `services/menu`, so the search service shares nothing with the adapter
  except `constants.dart` — the header set and client version live there.
- **Tests**: mapper over the fixture (synthetic until §2.4 step 5) plus
  the shape test pattern from `wolt_fixture_shape_test.dart`; service over
  `MockClient` for 200, 4xx, 410 → `platformChanged`, 429 → `rateLimited`,
  5xx, `ClientException` with and without a proxy, timeout, browser vs
  native; the contract suite runs the fake and the implementation.
- **`AppDependencies`** gains `venueSearchService` and `locationService`;
  every fake bundle (`fake_app_dependencies.dart`, `flow_support.dart`,
  `di_test.dart`) updates in the same PR, the lesson from #144/#145.

## 6. The Discovery screen (#40)

The artboard (`.design/Discovery.dc.html`) shows: a "Looking around
Rothschild 22" header with a location affordance, the "Where to eat" title,
chips *Nearby · Keto 8+ · Open now · Grill*, and cards with a photo tile,
name, keto score, blurb, "Cuisine · N min" meta and green/yellow counts.
What is already on `main` after run 1: `VenueSearchScreen` with the paste
field, the offline banner, "Continue with {venue}" (#55) and the
`discoveryEmpty*` placeholder copy that says search is not available yet.

- **State**: `VenueSearchController` keeps its paste path untouched and
  gains `locate()` (→ `LocationService`, then `nearby`), `search(q)`
  (debounced 400 ms; a pasted link still resolves as today and wins over a
  search), `results`, `activeChip` (one at a time; tap again clears), a
  `LoadPhase` like `MenuController`'s, and a `VenueSearchFailed` reason for
  `failure_copy.dart`. Position, results and chip are in-memory only; the
  last search string could join `AppSettings` later, not now.
- **Header copy**: the artboard's street name needs reverse geocoding,
  which no Wolt endpoint provides anonymously (§2.1's Google proxies are
  2021-era). Ship "Looking around you" / "Looking around {venue-city}" from
  the nearest result's `city` field and leave the street for a later
  `geocoding`-package decision — recorded as an open question, not
  silently dropped.
- **Chips**: *Nearby* is the default state (sorted by distance); *Keto 8+*
  filters on the card score and is therefore empty until #42 lands (hide the
  chip until then rather than show an always-empty list); *Open now* is
  `isOnline == true`; the cuisine chip is the most common `cuisineTags`
  entry among the results, one chip, so it is never a wall of chips.
- **Cards**: `widgets/venue_card.dart` with the photo tile from #50, name,
  the `KetoScoreBadge` that already exists (only when a score exists, §7),
  `shortDescription`, `{cuisine} · {minutes} min`, and the green/yellow
  counts only when a cached analysis exists — the issue already says so.
  Tapping pushes `/venue/wolt/{slug}`, the existing route. RTL: the meta
  line uses `Directionality`-aware separators and the card's leading photo
  flips with the text direction; the widget test pumps both directions.
- **ARB**: `discoveryEmptyTitle`/`discoveryEmptyBody` are rewritten (they
  say search does not exist), `venueSearchHint` becomes "Search by name, or
  paste a Wolt link", and new keys cover the location header, the four
  chips, the denied/unavailable states with their actions ("Use my
  location", "Open Settings", "Type a name instead"), and the six failure
  reasons in both languages.

## 7. Pre-scoring: what the card shows before a menu is opened (#41 → D13)

The issue asks for a comparison; here it is, with a recommendation.

| Option | Cost | Accuracy | Latency | Privacy / terms | Verdict |
|---|---|---|---|---|---|
| **A. Rules-engine pre-analysis** of every visible venue's menu (#42 as written): fetch up to N menus in the background, run `HeuristicMenuClassifier`, show score and counts marked "estimate" | Phones: N direct Wolt menu calls per list. Web: N proxied calls, each 1 h-cached server-side. Zero `/v1/chat` spend | Rules only — the same coarse verdicts the "rules" banner apologises for; a card would promise a score the menu screen then revises | A list of 20 cards means 20 fetches before the numbers settle; with concurrency 3 that is many seconds of numbers popping in | This is the "systematic retrieval" pattern §2.3 quotes, and the one that gets an IP throttled — every scroll fans out to Wolt for menus nobody asked to see | **No** as the default behaviour |
| **B. Server-cached AI analyses only**: the backend exposes which venue slugs have a fresh completion-cache entry (from anyone's analysis, #103), and cards show the AI score for those | One cheap backend call per list on web and on phones (the phone would need the backend for this, a first) | AI-grade, and identical to what the menu screen will show | One call, no popping | No Wolt traffic. Needs a new backend route that maps slug → cached counts, which the completion cache keyed by prompt hash does not have today (a slug column is a small schema change) | Good second step |
| **C. No numbers until opened**, plus numbers for venues whose analysis is in the device cache (`MenuRepository.cached(ref)`) — the counts and `ketoScore` already exist for those | Zero | Exact for what it shows; shows nothing it cannot back | None | None | **Ship this first** |

**Recommendation for D13**: C now, B when the backend is hosted (#109)
so that "someone analysed it" has a population behind it, and A never as a
background fan-out — at most as an explicit "Estimate this list" action
that fetches the visible venues once, so the retrieval is something the
user asked for. The score formula stays `utils/keto_score.dart`'s
`10 × (green + 0.5 × yellow) / (green + yellow + red)`; `keto_score.dart`'s
own doc comment calls the 0.5 weight invented product logic, and #41 is
where it was supposed to get a basis. It does not get one here — no
nutrition source says a dish needing one swap is worth half a safe one —
so D13 should record it as a UI ranking heuristic, never a health claim,
with the card labelled "estimate" whenever the numbers come from rules
(C shows rules numbers only if the cached analysis was rules-only, in
which case the existing `EngineChip` label carries over).

Consequences for #42: rescope from "fetch menus for the visible venues in
the background" to "read cached analyses for the visible venues, and offer
an explicit estimate action bounded by the concurrency constant". The
tests the issue lists (scheduler with fakes, cancellation on a new query,
the LLM fake never called, the estimate marker) all still apply to the
explicit action.

*Recorded as D13 in `architecture.md` §14 on 2026-09-24 (PR #147, closing
#41), exactly as recommended above; #42 was rescoped to match.*

## 8. Flows, skeletons, accessibility, photos

### 8.1 Discovery flow tests (#43)

Three flows under `integration_test/flows/`, each faking
`LocationService`, `VenueSearchService` and the menu repository through
`flow_support.dart` (same-directory import rule): *locate → list → open
venue → menu* (asserts the menu route with the tapped slug), *permission
denied → "Type a name instead" → search → list* and *chip filter narrows
the list* (Open now hides the offline venue). All three run on the
existing headless-Chrome integration job; `FlowFakeLocationService`
returns a scripted `LocationResult` so no flow ever touches the plugin.

### 8.2 Skeletons and empty states (#63)

`widgets/skeletons.dart` with `VenueCardSkeleton`, `DishCardSkeleton` and
`SavedEntrySkeleton`, shaped like the real cards (photo tile, two text
bars, a meta bar) and drawn from `AppTokens` surfaces so both themes work
without a new colour. The Menu screen's `LoadPhase.fetching` and the Saved
tab's `isLoading` already exist as the hooks; Discovery's `LoadPhase` from
§6 is the third. Empty states each carry the one next action the issue
asks for (Discovery: "Use my location" or "Paste a link"; Menu: "Retry";
Saved: "Find a restaurant" → tab switch). Widget tests pump each screen in
the loading and the empty state, once per theme. A shimmer animation is
optional and not worth a dependency; a static two-tone skeleton reads
fine.

### 8.3 RTL and accessibility audit (#64) — including the known contrast defects

Measured against `lib/theme/app_tokens.dart` on `main` (WCAG 2.x relative
luminance; AA is 4.5:1 for normal text, 3:1 for large/bold ≥ 14 pt bold):

| Pair | Where it is drawn | Ratio | Verdict | Fix |
|---|---|---|---|---|
| `lightGreenOn` `#FAF7F0` on `lightGreen` `#338946` | `StatusBadge` green pill text (10 px, w800) — `tone.on` on `tone.pill` | 4.08:1 | fails AA for 10 px text | Darken the pill fill to `#2A7A3B` (4.97:1 with the same `on`), or draw the green pill the way the red one already is — `tone.ink` `#115629` on `lightGreenTint` (the ink reads 8.2:1 on `lightBg`). The badge is icon-plus-colour already, so the text is not the only signal, but it must still be legible |
| `lightInk3` `#A09484` on `lightBg` `#FAF7F0` | declared for small labels; **not used by any widget on `main`** | 2.78:1 | fails | Darken to `#7C6F5F` (4.57:1) before anything uses it, or delete the token |
| `darkInk3` `#7D7364` on `darkBg` `#14120E` | small labels in dark mode | 4.02:1 | fails AA by a hair | Lighten to `#8E8474` (5.08:1) |
| every other pair `VerdictColors` produces: amber `on`/pill 7.18 and 9.98, red `on`/pill 4.74 and 5.74, the three `ink`-on-background pairs 6.85–13.36, `ink2` on background 5.21 and 7.09 (light, dark) | pills, chips, counters, rails | ≥ 4.5:1 | pass | none. The red pill draws `tone.ink` on `lightRedTint`, not `on` on the tint (which would be 1.04:1) — `StatusBadge` special-cases it, and the contrast test must assert the pair the widget actually draws |

No test pins the token values, so the fix PR adds one: a
`test/theme/contrast_test.dart` that computes the ratio for every
`on`/surface pair `VerdictColors` produces in both themes and asserts
≥ 4.5 — then the regression is impossible, not just noted. The rest of the
audit is mechanical: a `Semantics` label on `StatusBadge` (verdict word,
not colour), `EngineChip`, `VerdictCounterTiles` (count + verdict + "tap to
filter") and the Waiter Card (script read as one block); `MediaQuery
.textScaler` at 2.0 in the widget tests of every card to catch clipping;
and `Directionality.rtl` pumps for Discovery, Menu and Settings. The
checklist lands in `docs/ACCESSIBILITY.md` next to `docs/RELEASE.md`.

### 8.4 Photos from the feeds (#50)

- Wolt images are served from `imageproxy.wolt.com` and
  `wolt-menu-images-cdn.wolt.com`. Whether either sends CORS headers is
  unconfirmed (blocked here). On web, an `<img>` element does not need
  CORS to display, but decoding into a canvas or a byte cache does — which
  is why `cached_network_image` cannot render a no-CORS image in a Flutter
  web build (it fetches bytes with `http`).
- **Recommendation**: `Image.network(url, webHtmlElementStrategy:
  WebHtmlElementStrategy.fallback, …)` (Flutter ≥ 3.27) inside a fixed-size
  container, with `errorBuilder` and `loadingBuilder` returning the
  placeholder gradient — the fixed size is what prevents layout shift. On
  web the fallback strategy draws an `<img>` platform view when the CORS
  fetch fails, so the tile shows either way; on iOS/Android the framework's
  own in-memory `ImageCache` covers a session. No caching package: on the
  web there is nothing to cache without CORS, and on phones the menu is
  already re-fetched at most daily. `extended_image` is the second choice
  if disk caching on phones is ever wanted; it is BSD-licensed and does not
  break the web path when its cache is disabled there.
- `Dish.imageUrl` and `Venue.imageUrl` come from the mappers (`items[].image`
  in the menu payload, `image.url` on the list item); both nullable, both
  ignored by the classifier.
- Widget tests: null URL → placeholder; a `MockClient` 404 → placeholder;
  no size change between the two.

## 9. Order of work

Same process as run 1: one PR per issue, workers in isolated worktrees,
CI judges, merge on green.

| Wave | Issues | Depends on | Notes |
|---|---|---|---|
| 0 | Docs: this document; #41 → D13 in `architecture.md` §14 and #42 rescoped; §17.2 answered "documented, awaiting recording" | — | Opus for the D13 write-up |
| 1 | #37 `LocationService`; #123 proxy route; #39 service + synthetic fixture; #64 contrast fixes and the contrast test (independent of Discovery) | none | #37 and #39 both add an `AppDependencies` field — merge #37 first, #39 merges main. #123 and #39 agree on the route paths in §3 up front |
| 2 | #40 Discovery screen; #50 photos (`Image.network` in `DishCard` now, `VenueCard` when #40 lands) | #37, #39 | #40 is the `venue_search_screen.dart` hotspot; nothing else touches it this wave |
| 3 | #42 (rescoped: cached-analysis counts + explicit estimate action); #43 flows; #63 skeletons; #64 remainder (semantics, RTL, large text) | #40 | #63 and #64 both touch every screen — one at a time |
| user | #38 recording (§2.4), #22 menu fixture, the `/v4 … menu/data` check (§2.5) | a machine that reaches Wolt | When the recording lands, the synthetic fixtures are replaced in one PR and the shape tests say whether the mappers survive |

Wave 1 can start now. Everything in it is independent of the capture.

## 10. What only the user can do

1. **The capture and the fixture recording** (§2.4). Without it the chain
   ships against a synthetic fixture, which is acceptable for a first PR
   and not for a release.
2. **The `/v4 … menu/data` check** (§2.5): one run of
   `tool/record_wolt_fixture.sh vitrina-lilinblum`. If the body is empty,
   the shipped menu path is broken for real users today and that outranks
   every Discovery issue. *(Done 2026-09-25: empty; ported in #168, §2.5.)*
3. **A phone run of the permission prompt** (#37): the approximate/precise
   choice on Android 12+ and the "Never" path on iOS are only evidenced by
   fakes until then (`docs/RELEASE.md`'s device matrix has the row).
4. **A decision on D13** if the recommendation in §7 is not wanted — in
   particular whether an explicit "estimate this list" action is worth
   building at all, given the terms exposure.

## 11. Sources

Wolt endpoints, all read as raw GitHub source or package metadata between
2026-09-23 20:30 and 21:00 UTC (dates are each repo's last commit or the
package's release date): mekedron/wolt-cli (Go, 2026-09-20), skorokithakis/
woltapi (PyPI 0.5.0, 2026-09-06), erlaufer/wolt-mcp (npm 0.1.3, 2026-08-05),
ttamkivi/wolt-mcp (2026-08-23), Bl0ck154/wolt-discount-monitor (`FINDINGS.md`,
2026-06-20; repo active 2026-09-23), r1nnegann/wolt-easy (`docs/ARCHITECTURE.md`,
2026-09-06), gkvasnikov/nutrition-app-2 (2026-06-01), analisto/wolt_com
(DevTools captures of 2026-02-09/10), funkekaiser/wolt-google-reviews
(2026-09-20), selfish/ha-wait-for-wolt (2026-08-10), Michaelliv/runline wolt
plugin (2026-09-17), kalifs/availability-checker (2026-08-17),
maxreith/openclaw_showcase (2026-06-03), OzTamir/wolt-api and its
`docs/WOLT_API.md` (npm 1.4.0, 2025-12-20), jonzarecki/wolt-sdk (2025-08-02),
woltapp/mobile-internship-2025 and the 2023/2024 internship READMEs (Wolt's
own, `restaurant-api.wolt.com/v1/pages/restaurants`), PerVillalva/wolt-api-
scraper (2024-01-16), Valaraucoo/what-to-eat (2023-11-11), Tomer Chaim,
"Exploring Wolt's web API" (Medium, 2021-01-16, via the apachecn mirror),
washingtoneimae-dot/agent browse-sh skill (the "all v1 is 410" claim,
2026-05-19), Apify crawlerbros/wolt-scraper listing (residential-proxy
note), Wolt user terms (explore.wolt.com, Hungary and Germany, 2 May 2024
text, via search snippets), HackerOne Wolt scope via bountyindex.

Flutter packages: pub.dev pages for `geolocator` 14.0.3, `geolocator_web`,
`geolocator_android`, `cached_network_image`, `extended_image`; the Flutter
3.27 release notes for `webHtmlElementStrategy`. `docs.flutter.dev` and
`api.flutter.dev` were unreachable, so the `Image.network` behaviour is from
the framework source on GitHub and the pub.dev changelogs.

Repository facts (`main` at `de74638`): `lib/models/venue.dart`,
`lib/utils/keto_score.dart`, `lib/services/menu/wolt/wolt_adapter.dart`,
`lib/state/app_dependencies.dart`, `lib/screens/venue_search_screen.dart`,
`lib/theme/app_tokens.dart`, `test/architecture/import_rules_test.dart`,
`backend/app/routers/proxy.py`, `backend/app/services/wolt.py`,
`backend/app/config.py`, `test/fixtures/README.md`, `.design/Discovery.dc.html`,
`architecture.md` §6.5, §13, §17.2.
