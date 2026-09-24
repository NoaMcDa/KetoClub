# Accessibility checklist

Issue #64's own checklist: what architecture.md §6.6's accessibility rule
("every verdict is icon **and** colour") and the RTL/large-text/screen-reader
half of the audit actually cover, and which test pins each claim. The
contrast half of this issue landed first, in PR #148; this document is the
remainder — semantics, large text, RTL, and the icon-plus-colour sweep.

This is a checklist, not a design document; see `architecture.md` §6.6 and
§8.3 for the design and `phase2_discovery_research.md` §8.3 for the audit
plan this was built from.

## 1. Contrast on tints (#148, landed already)

Measured against `lib/theme/app_tokens.dart`, WCAG 2.x relative luminance,
AA at 4.5:1 for normal text:

| Pair | Where | Ratio before | Ratio now | Fix |
|---|---|---|---|---|
| `lightGreenOn` on `lightGreen` | `StatusBadge` green pill text | 4.08:1 (fail) | 4.97:1 | Darkened the pill fill |
| `lightInk3` on `lightBg` | small labels (unused on `main` at the time) | 2.78:1 (fail) | 4.57:1 | Darkened the token |
| `darkInk3` on `darkBg` | small labels, dark mode | 4.02:1 (fail) | 5.08:1 | Lightened the token |
| every other `on`/`pill` and `ink`/background pair `VerdictColors` produces | pills, chips, counters, rails | ≥ 4.5:1 | unchanged | none |

Pinned by `test/theme/contrast_test.dart`: it computes the ratio for every
pair `StatusBadge` and the counter tiles actually draw — the red pill's
`ink`-on-tint, not the `on`-on-tint that would fail at 1.04:1 — in both
`VerdictColors.light()` and `.dark()`, so a future colour change that
regresses any of them fails a test, not a screenshot review.

## 2. Icon-plus-colour

Architecture.md §6.6: every verdict is icon **and** colour, never colour
alone, so a colour-blind user can read the same verdict a sighted user
reads from tint. Swept across every verdict-carrying widget:

| Widget | Icon | Colour | Test |
|---|---|---|---|
| `StatusBadge` (the pill) | `check_circle` / `edit_note` / `cancel` per verdict | `VerdictTone.pill`/`on` (or `ink` for red — see its own doc comment) | `test/widgets/status_badge_test.dart`: "renders an icon alongside the label for every verdict" |
| `VerdictCounterTiles` | same three icons, added in this pass — previously a colour-only dot | `VerdictTone.rail` | `test/widgets/verdict_counter_tiles_test.dart`: "every tile shows an icon beside its colour, never colour alone" |
| `VenueCard`'s green pill | `check_circle` | `VerdictColors.green` | pre-existing (issue #40) |
| `VenueCard`'s yellow count | `edit_note`, added in this pass — previously a colour-only dot | `VerdictColors.amber.rail` | covered by `venue_card_test.dart`'s existing render tests (the dot's replacement changes no expected text) |

The one place colour was previously the only signal — the counter tiles'
dot and the venue card's yellow dot — now carries the matching verdict icon
too, matching `StatusBadge`'s own icon per verdict.

## 3. Semantics (screen readers)

Every verdict- or engine-carrying widget wraps its visual children in one
`Semantics` node with `excludeSemantics: true`, so a screen reader announces
one clean phrase instead of an icon and a text node read as two disjoint
things:

| Widget | Announces | Test |
|---|---|---|
| `StatusBadge` | The verdict word ("Order as-is" / "Order with a change" / "Not keto") — never the colour | `status_badge_test.dart` |
| `EngineChip` | "AI engine, model {model}" or "Rules engine, not AI-verified: {reason}" | `engine_chip_test.dart` |
| `VerdictCounterTiles` | "{verdict}: {count}", `selected` when the tile is the active filter, and — added in this pass — a hint: "Double tap to filter" (inactive) or "Double tap to clear the filter" (active) | `verdict_counter_tiles_test.dart` |
| `KetoScoreBadge` | "Keto score: {score} out of 10" | `keto_score_badge_test.dart` |
| `_NetCarbsChip` (DishCard) | "Estimated net carbs, not confirmed: {grams} grams" | `dish_card_test.dart` |
| `_ScriptDisclosure` / note row (DishCard) | The disclosure label with Flutter's own `expanded` flag; the note text or "Add a note" | `dish_card_test.dart` |
| `VenueCard` | Name, open/closed state, and the score and counts as one label (issue #40) | `venue_card_test.dart` |
| `WaiterScriptWidget` (the waiter card's script) | The whole script's lines as one block — added in this pass, so a screen reader no longer reads each numbered circle and line as its own node | `waiter_script_widget_test.dart`: "announces the whole script as one block, not one node per numbered line" |

Every widget above has an English `matchesSemantics`/`bySemanticsLabel`
test and at least one Hebrew-locale case.

## 4. Large text

Widget tests pump `MediaQuery(textScaler: TextScaler.linear(2.0))` — the
test binding reports a `RenderFlex` overflow as a thrown exception, so
`tester.takeException()` catches it directly — over a narrow (320-360px)
surface, the tightest real phone width, rather than the wide default test
surface:

| Widget | Test | Fix applied |
|---|---|---|
| `StatusBadge` | `status_badge_test.dart` | Wrapped the icon+label row in a `FittedBox(fit: scaleDown)` — the pill shrinks rather than overflowing |
| `VerdictCounterTiles` | `verdict_counter_tiles_test.dart` (three-digit counts) | Same `FittedBox` fix on the icon+count row |
| `DishCard` | `dish_card_test.dart` | Changed the price/net-carb-chip `Row` to a `Wrap`, so the chip drops to its own line instead of overflowing |
| `VenueCard` | `venue_card_test.dart` | Already safe — its name is `Expanded` and its meta line already a `Wrap` |
| `WaiterScriptWidget` / the Waiter Card | `waiter_script_widget_test.dart`, `waiter_card_sheet_test.dart` | Already safe — every text line sits in an `Expanded` |

No widget in this table throws under a 2x scale on a 320-360px surface any
more.

## 5. Right-to-left

`Locale('he')` alone already renders the app under RTL directionality —
Flutter resolves it from the locale, with no `Directionality` override
needed in a test — so every RTL test below pumps `locale: const
Locale('he')` and asserts real layout mirroring (which side an element
sits on), not only that Hebrew strings appear:

| Screen/widget | Mirrors | Test |
|---|---|---|
| Discovery (`VenueSearchScreen`) | (issue #40) | existing |
| `VenueCard` | the score sits left of the name | `venue_card_test.dart` |
| Waiter Card (`WaiterCardSheet`) | the first tab sits at the trailing edge, not the leading one | `waiter_card_sheet_test.dart` |
| `MenuScreen` | the keto score sits left of the venue name — added in this pass | `menu_screen_test.dart`, group "right-to-left" |
| `SettingsScreen` | the net-carb stepper's minus button sits right of plus — added in this pass | `settings_screen_test.dart`, group "right-to-left" |

Two genuine hard-coded-direction bugs turned up in this sweep and were
fixed, both in widgets an RTL screen renders:

- `RulesReasonBanner`'s Settings/Retry actions used `EdgeInsets.only(left:
  8)` — the wrong side under RTL, where the actions sit at the trailing
  (visually left) edge, not the leading one. Changed to
  `EdgeInsetsDirectional.only(start: 8)`.
- `NoteEditorSheet`'s sheet padding used `EdgeInsets.only(left: 24, right:
  24, …)`. Numerically symmetric so it never actually mis-rendered, but
  changed to `EdgeInsetsDirectional.only(start: 24, end: 24, …)` for the
  same reason every other directional inset in this codebase is directional
  rather than physical.

No other `EdgeInsets.only(left:`/`right:` or `Alignment.centerLeft`/
`centerRight` remains under `lib/screens` or `lib/widgets` outside a
purely decorative gradient (`VenueCard`'s and `PhotoTile`'s placeholder
gradients, whose diagonal direction carries no reading-order meaning).

## 6. What this audit did not touch

- `venue_search_screen.dart` and `venue_search_controller.dart` beyond
  reading them — issue #40 already added Discovery's own RTL test and
  directional insets, and this pass was scoped to leave that file to
  whoever owns it concurrently.
- Large-text tests for `SettingsScreen` and `MenuScreen` as whole screens —
  both are built from ordinary Material list tiles and switches
  (`RadioListTile`, `SwitchListTile`, `SegmentedButton`), which wrap their
  own labels; the per-widget large-text tests in §4 cover the
  purpose-built widgets these screens compose.
- VoiceOver/TalkBack on a real device — every claim above is evidenced by
  `flutter test`'s semantics tree, not a physical accessibility-service
  run (see the "What is NOT verified yet" section of `CLAUDE.md`).
