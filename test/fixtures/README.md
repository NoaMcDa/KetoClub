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
response could not be recorded from here. `wolt_vitrina_lilinblum_menu.json`
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

### Re-recording before release (issue #22)

**`wolt_vitrina_lilinblum_menu.json` is synthetic. It has never been a real
Wolt response, and it proves only that `WoltMenuMapper` handles the shapes
listed above — it proves nothing about what Wolt's real API actually
returns today.** `restaurant-api.wolt.com` is unreachable from every
environment this repository's automation runs in (the egress proxy 403s
the CONNECT), so issue #22 — recording a real fixture — stays open until
someone runs the recorder below from an unblocked machine.

```bash
tool/record_wolt_fixture.sh vitrina-lilinblum
```

This does everything the old hand-typed `curl` command needed doing by
hand: it sends the same `User-Agent` `browserUserAgent` in
`lib/utils/constants.dart` sends (keep the two in sync if it ever
changes), fails loudly with the response body printed if the request
does not come back `200` or the body is not JSON, redacts any field whose
key looks like a token/secret/session/credential and any string value
shaped like a bearer token or JWT, writes
`test/fixtures/wolt_{slug}_menu.json` pretty-printed with a
`_fixture_note` header naming the venue, the recording timestamp, the
endpoint, and exactly what was redacted, and finally runs
`wolt_fixture_shape_test.dart` against it so a schema drift shows up
immediately rather than the next time someone happens to run the suite.
Pass any venue slug as `$1`; `vitrina-lilinblum` is the one already used
throughout this repo's docs and fixtures, so keeping the same slug means
the new file replaces this one directly.

Before committing the result: open the file and skim it for anything the
redaction pass missed (it does not know your account's own data if you
were logged into Wolt while fetching — request the endpoint from a
private/incognito session to avoid that entirely). Keep the
`_fixture_note` key, or remove it and the assertion in
`wolt_menu_mapper_test.dart` that checks an unknown top-level key is
ignored — either is fine as long as they change together. Re-check that
the fixture still exercises every shape variation listed above; a real
venue may not happen to have a checkbox option group or a duplicated
item id, in which case keep a couple of hand-added dishes alongside the
real ones rather than losing that coverage. `wolt_fixture_shape_test.dart`
runs against every `wolt_*_menu.json` fixture automatically (except
`wolt_malformed_menu.json`), so a new file needs no test-file edit to be
covered.

## 10bis

`tenbis_synthetic_menu.json` and `tenbis_malformed_menu.json` are
**synthetic**, not recorded responses, for the same reason as the Wolt
pair above and tracked the same way: issue #44, not #22.

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
