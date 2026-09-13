# M16 — AI Menu Scanner: research, pre-flight, and the milestone plan

**Source:** the product owner's M16 request, quoted verbatim in §1 → rewritten as the
**M16 Epic, #351** (milestone #19, label `epic:m16-menu-scanner`, issues #352–#366,
#372, #373, #405–#408)
**Status:** all three input modes — pasted text, photographed pages, and now PDF
(#405–#408) — are implemented and merged onto the working branch, completing the
milestone's code. #405 added the extraction seam and Hebrew legibility guard, #406 the
rasteriser for pages with no usable text layer, #407 the file picker, #408 the third
`MenuInputMode` and its e2e flow. Two platforms (web, Linux) are build-and-smoke-test
verified for the new `pdfrx`/`file_selector` dependencies; Android, iOS, macOS and
Windows are unbuilt in this environment and remain to be watched on the real CI run.
**#373 was closed as completed by the owner** after PR #410, on one photographed menu
rather than the three it asked for — so the corpus gap it names is real but is no longer
tracked by an open issue, and no real Hebrew menu **PDF** has been obtained at all. The
milestone's product-owner decisions (§11) remain open. See §12.

The honest verified/not-verified line: the pasted-text and photo-page paths have both been
driven end to end in the headless e2e suite (#366's `menu_text_flow.dart` and
`menu_photo_flow.dart`), against a real `MenuAnalyzer`, `MenuPageReader`, prompt and parser
on the photo side. **One real restaurant menu has now been photographed and read** — and it
produced the finding that should govern the rest of the milestone: **the dish names survive
and the prices do not**, 9 of 23 names character-perfect against 2 of 23 prices, the rest
losing their leading digit (`28` → `8`). Hence the hard rule in §10: **M16 must never
present a scanned price as fact.** #373 asked for three deliberately differing menus and was
closed on one, so the remaining two are an unclosed gap without an issue behind them.
§5 and §10 have the full picture.
**Read before:** picking up any M16 issue. **M12 (#267, #121, #122) is closed as
superseded** — the owner took that decision on 2026-09-12 and milestone #14 is retired,
so there is nothing left there to pick up; §1.1 records why.

---

## 0. Verdict, in one paragraph

The request describes a capability the repository **already has a milestone for**:
M12 Menu Analyzer (Epic #267, issues #121 and #122) is *"menu OCR → per-dish keto
verdicts and modification tips"*. M12 cannot ship what M16 asks for, and the reason is
structural rather than a matter of polish: it classifies a dish by running its *name*
through `IngredientClassifier`, whose entire vocabulary is six seed oils, five sweeteners
and a list of clean fats. **That rule set has no word for bread, rice, pasta, potato,
flour or sugar** — `grep` it — so a margherita pizza matches nothing, earns `cleanKeto`
with `recognisedNothing`, and is shown as "we do not know". M12 also has one input (a
single camera frame), reuses Keto Lens's three badges (whose amber means *quantity
dependent*, not *modifiable*), and explicitly rejected an LLM in a sentence written
before M15 settled that question for the project. What M16 actually needs is: text as the
one input shape (pasted, or OCR'd locally from one or more photos), **a cloud model over
M15's `LlmChatClient` seam** to extract and classify dishes, a three-state verdict of its
own with a modification instruction attached to every yellow, and a deterministic parser
that refuses to let the model invent a dish or leave a yellow without its instruction.
This document records what was measured, the decision taken, and the fourteen issues
that follow from it.

---

## 1. What the request says, and the five things the codebase says back

> **Milestone 16: AI Menu Scanner & Keto Compatibility Classifier**
> Enable users to submit restaurant menus via image upload or text input to
> automatically extract, categorize, and explain dish compatibility based on ketogenic
> guidelines.
> 1. Input Handling — Multi-Image Upload (one or more photos, processed through OCR);
>    Direct Text Input.
> 2. Classification Logic — Green (Keto-Friendly, order as-is: ribeye, grilled salmon in
>    butter, leafy salad with oil dressing); Yellow (Modifiable: fish with potato purée,
>    burger with bun and fries, salad with sugary dressing); Red / Hidden (Non-Keto:
>    pizza, pasta, breaded cutlets, risotto).
> 3. UI & Output — a scanned-menu list with green and yellow badges, non-keto grouped at
>    the bottom or filtered out by default; an expandable card with **Why** and
>    **Modification Instructions** ("Ask to swap the potato purée for double green beans
>    or a side salad").
> 4. Acceptance — OCR extraction from clear multi-page photos; correct categorisation
>    (low net carbs, healthy fats/proteins, hidden sugars/starches flagged); instant
>    expansion showing exact substitutions for every yellow item.

### 1.1 A milestone for this already exists, and it is the wrong shape

`design/v1_1_split.md` §6 created **M12 — Menu Analyzer** as GitHub milestone #14, with
Epic #267 and two issues, #121 (`MenuAnalyzerService`) and #122 (`MenuAnalyzerScreen`).
Both were rewritten against Tesseract on 2026-09-09; neither has a PR, a branch or a
closed sub-task. `milestone_conventions.md` §1.1 says every issue belongs to exactly one
milestone and a milestone is a single cohesive delivery — two open milestones for one
capability is the state `epic:post-mvp` was retired for.

The table below is why M16 is not "M12 with better copy". Every row is a design choice
M12's text makes and M16's request contradicts:

| | M12 (#121/#122, as written) | M16 (the request) |
|---|---|---|
| Input | One camera frame | **One or more** photos, **or pasted text** |
| Engine | `IngredientClassifier` over dish-name tokens; *"an LLM or any network call was rejected"* | An AI classifier that can explain *why* and say *what to change* |
| Verdict | Keto Lens's `VerdictBadge` — amber means "quantity dependent" | Green / **Modifiable** / Red — amber means "fixable with an instruction" |
| Explanation | None — the flagged token *is* the explanation | A "Why" per dish |
| Modification | A rule table keyed on the flagged token (bun → "בלי הלחמנייה") | A dish-specific instruction for every yellow item |
| Placement | Inside `lib/features/keto_lens/` | Its own feature |

The right relationship is **supersession**: M16 replaces M12, and #267, #121 and #122
should be closed as superseded the way Epic #13 was, with milestone #14 retired. M12 has
no merged PR and no closed issue, so this is a scoping decision taken before the
milestone started — the one point at which `milestone_conventions.md` §1.3 allows it
(the same argument #312 made for widening M15 to "add and correct").

**Decided: the owner closed M12 on 2026-09-12**, after M16 shipped in #423. #121, #122
and Epic #267 are closed as superseded, GitHub milestone #14 is retired, and the
`epic:m12-menu-analyzer` label is kept on all three as history. §11 decision 1 is
therefore taken, not open.

### 1.2 M12's engine cannot produce the three states, and the reason is measurable

`IngredientClassifierImpl.classify` flags a token only if it matches a rule in
`lib/core/constants/ingredient_rules.dart`. Those rules are the label-scanner's rules —
`CLAUDE.md` § OCR & ML lists them: forbidden seed oils, insulin-spiking sweeteners, clean
approvals. Searching the file for `לחם`, `אורז`, `פסטה`, `סוכר`, `קמח`, `bread`, `rice`,
`pasta`, `flour`, `potato` finds one hit, and it is a doc comment explaining that coconut
sugar is clean.

So under M12, `פיצה מרגריטה`, `פסטה ברוטב עגבניות`, `שניצל עם פירה` and `ריזוטו פטריות`
all classify as `cleanKeto` with `recognisedNothing == true`, which #121 correctly says
must be *presented* as caution — "we do not know". Four of the request's own examples of
**red** dishes come out as **"unknown"**, and the only way to fix that inside M12 is to
write a Hebrew-and-English dish vocabulary with a carb model behind it — a food table,
which `design/m15_meal_entry_research.md` §5 already researched, could not download, and
shelved on licence grounds. M12 was designed for the ingredient list on the back of a
packet. A menu is a different text.

### 1.3 The three states are not Keto Lens's three badges

Epic #267 makes it an invariant that the analyser uses exactly `Clean Keto` /
`Caution / Quantity Dependent` / `Non-Keto`, and that *"a fourth badge, or different copy
for the same verdict, is a scope violation"*. That was right for M12, whose verdict *was*
an ingredient verdict. It is wrong for M16: a burger with a bun is not "quantity
dependent" — one bun is one bun — it is **removable**, and the whole value of the yellow
state is the instruction that comes with it. Rendering "זהירות — תלוי כמות" on it would be
false copy. M16 therefore declares its own `DishVerdict` (§6.3) and keeps only the three
**colour tokens** in common with Keto Lens, because those already exist in `AppTheme` and
`ui_ux_design.md` and a fourth green would be a design-system violation of a different
kind.

### 1.4 "Plain-English guidance for the server" means the menu's language

The user reads the instruction to a waiter in an Israeli restaurant. The instruction has
to be in the language the menu is printed in — Hebrew for a Hebrew menu, English for an
English one — and the dish **name** has to be exactly as printed, so it can be matched
against the physical menu. Both are prompt rules (§6.6) and test assertions, not
preferences.

### 1.5 It is a milestone

Filed as one issue it fails `issue_conventions.md` §1 on all four atomicity tests. It
needs a domain model, a prompt, a parser, a multi-page OCR reader, an analyser composed
from three interfaces, a picker change, two input modes, a grouped result list, an
expandable card, a consent-copy change, fixtures that nobody has collected, and e2e
coverage of two flows. That is fourteen issues (§9).

---

## 2. What the codebase already gives M16

Read this before planning anything. The expensive parts are built, and most of them were
built by M6 and M15 for exactly this reuse.

| Asset | Where | M16 use |
|---|---|---|
| **On-device Hebrew OCR, six targets, no network** | `TextRecognitionService` interface; Tesseract behind `text_recognizer_factory.dart` | Reads each menu page **locally**. `recognise(String path) → String`, so no plugin type reaches `application/` |
| `isAvailable` on the recogniser | same | Asked *before* a camera is offered — the M6 convention #122 also inherits |
| Live viewfinder + torch | `CameraSession` (`keto_lens/presentation/camera/`), fake-able | Page capture, one frame at a time |
| Gallery import | `PhotoPicker.pickFromGallery()` over `image_picker` | Extended with `pickMultiple()` — `image_picker` already ships `pickMultiImage` on every target (§4.2) |
| **The LLM transport seam** | `LlmChatClient` / `ChatResult` / `ChatFailureReason` / `EstimationCredentials` — #318, PR #350 | The round trip. `OpenRouterClient` is named in two files and M16 adds a third consumer, not a third name |
| BYOK key + consent | `EstimationSettings`, `estimation_settings` store (#317, **merged**), settings section (#321) | Same key, same opt-in. M16 adds one sentence to the disclosure and no second switch (§4.3) |
| The "never throws, sealed result" shape | `MacroEstimator` / `MealEstimate` (#316, merged); `ScanOrchestrator` / `ScanResult` | Copied for `MenuAnalyzer` / `MenuAnalysis`. A `switch` that does not compile until the failure case is handled is the project's answer to "what if it cannot tell" |
| Response-parser discipline | `EstimateResponseParser` (#319): strip fences, `jsonDecode` in a `try`, caps, nothing evaluated | The template for `MenuResponseParser`, plus the menu-specific rules in §6.6 |
| Hebrew normalisation | `HebrewTextNormaliser` | Used by the provenance check — never a second normaliser |
| Colour tokens and the badge shape | `AppTheme.success/caution/danger`, `VerdictBadgeWidget` (icon + colour, never colour alone) | `DishVerdictBadge` follows the same accessibility rule with its own copy |
| Failure-copy-per-reason | `ScanFailureReason`, `EstimateFailureReason`, #323's table | `MenuAnalysisFailureReason` gets the same treatment |
| Tab shell prefix matching | `AppShell.activeIndexForLocation` — `/lens/...` keeps the lens tab lit | The menu route is a child of `/lens` and needs no tab change |
| The e2e harness | `integration_test/helpers/app_harness.dart` | Two new flows, both with the model faked at an interface |

**The one thing nobody has is a corpus.** There is no real Israeli menu here — not a
photo, not a transcript, not one line of what Tesseract makes of a two-column menu in a
decorative font. `design/m6_platform_research.md` called a label corpus *"the
prerequisite for all of it"*, M6 shipped without one, and `design/user_bugs_handoff.md`
records that the scan then read nothing for the first real user. Issue 1 (§9) collects
the corpus first, and it needs no app and no device.

---

## 3. The bar: a menu verdict is advice, not a number

M15's safety argument was numeric: an estimate reaches `DailyLog` and the streak, so it
must be editable. **M16 logs nothing.** No number from this feature reaches a repository,
`MealLoggingService`, or `AdaptationPhaseService`. That removes the streak from the risk
picture entirely and puts something else in its place: the user is standing at a table,
about to order, and the app is about to tell them a dish is fine.

The failure that matters is therefore **a wrong green**, and its close cousin, **a red
that was hidden so well the user never learned the dish was seen**. Four rules follow,
and every M16 issue inherits them:

1. **Never invent a dish.** Every dish in the result must be traceable to the menu text
   that was analysed. A dish the model names that the text does not contain is not
   shown as a verdict (§6.6, the provenance check). The mirror rule from #121 also
   stands: a line the extractor cannot place is reported, not dropped.
2. **A yellow without an instruction does not exist.** The acceptance criterion is
   *"exact ordering substitutions for every yellow-coded item"*. The parser enforces it:
   a `modifiable` dish whose `modification` is empty is demoted to *unclassified*, never
   promoted to green and never left yellow with a blank card.
3. **Unclassified is not a verdict.** A dish the model could not place, or one that
   failed a parser rule, is listed under `לא ניתן לקבוע` with no colour. `ScanResult`
   is sealed for the same reason; `EstimateSucceeded.unidentified` is visible for the
   same reason. The neutral chip `VerdictBadgeWidget` renders for a null badge is the
   precedent.
4. **Red is grouped, not deleted.** The request offers "grouped at the bottom or filtered
   out by default". Grouped, collapsed, with a count — because "the pizza was seen and
   is red" and "the pizza was not read" must not look alike. `design/m5_handoff.md`'s
   convention that a failed read and an empty day must not look alike is the same rule.

None of the figures anywhere in this document measures the classifier M16 builds. §10 is
explicit that no accuracy claim is made.

---

## 4. The engine: what was evaluated, and the decision taken

Four options were assessed.

| | M12's rule classifier | **Cloud LLM over locally-OCR'd text** | Cloud vision model over the photos | Offline dish table |
|---|---|---|---|---|
| Can say *why* and *what to change* | No — a token, not a sentence | **Yes** | Yes | Only for dishes in the table |
| Reads a dish it has never seen (`מלאווח`, `סביח`) | No | **Yes** | Yes | No |
| Handles pasted text | Yes | **Yes — it is the only input shape** | Needs a separate text path | Yes |
| Handles multi-page | Trivially | **Yes — one request per menu** | One request, N image parts; fewer free models qualify | Trivially |
| What leaves the device | Nothing | **Recognised text** | The photographs | Nothing |
| Works offline | Yes | No | No | Yes |
| Deterministic / fixture-testable | Yes | Prompt no; **parser yes** | No | Yes |
| Marginal cost | Zero | One free-tier request per menu | One request, image tokens | Zero |
| Depends on a corpus nobody has | No | For accuracy, yes | For accuracy, yes | For coverage, yes |

> ### Decision taken: a cloud LLM over locally-recognised text, through M15's seam
>
> **Text is the one input shape.** A pasted menu *is* text; a photographed menu becomes
> text on the device through the Tesseract pipeline that already runs on all six
> targets. Both then take the identical path — one prompt, one parser, one fake in every
> test — which is what makes the whole feature testable without a camera, and what makes
> the pasted-text mode the first thing to ship and the first e2e flow to write.
>
> The engine question was **already settled at the project level by M15**: Epic #312
> records that the app calls a hosted model through `LlmChatClient`, that the user brings
> their own OpenRouter key today and the app calls our own backend later, and that this is
> *not* a relaxation of Keto Lens's no-network invariant — which is scoped to a **scan**.
> M12's "an LLM was rejected" predates that decision and cites `technology.md` §6, whose
> own v2 line was *"optional Claude API analysis for ambiguous dishes when network is
> available"*. M16 is that v2, with the seam M15 built.
>
> The rule classifier is not deleted as an idea; it is simply not the engine. If a
> deterministic pre-classifier ever earns its place — say, to answer without a network
> for the 20 dishes every Israeli menu has — it is a second `MenuAnalyzer` behind the same
> interface, exactly as the offline food table sits behind `MacroEstimator`.

### 4.1 Why text, and not the photos

The request itself says *"processed through Optical Character Recognition"*, and the
project has the engine. But the deciding argument is what it does for the boundaries:

- **The photograph never leaves the device.** Only the recognised text is sent. That is
  a smaller payload, a smaller privacy surface, and a sentence the disclosure can say
  plainly. It is also an invariant (§8) — a vision-direct implementation would change
  it and would have to change the disclosure with it.
- **Every `:free` text model qualifies.** Free vision models are a rotating subset of a
  rotating list; text-only requests can use the pinned model #318 chose and its fallback
  list without a second capability check.
- **One prompt for both modes.** Pasted text and OCR'd text differ only in noise, and
  the model is told the text may be OCR output with the errors OCR makes.

The cost is that OCR quality bounds classification quality — §5 — and the mitigation is
the swap the interface allows: `VisionMenuAnalyzer` is a second implementation, not an
edit, and `LlmChatClient.complete` already carries an image part.

### 4.2 Multi-image is a picker change, not a camera change

`PhotoPicker` exposes one method, `pickFromGallery()`, returning one path. `image_picker`
ships `pickMultiImage` with a web implementation (`image_picker_for_web`) and desktop
support through `file_selector`; its `limit` argument is **not honoured on every
platform** (an open Flutter issue on Android), so the page cap is enforced in Dart after
the pick rather than trusted to the plugin. Camera capture reuses
`CameraSession.capturePhoto()` one frame at a time; "add another page" is a loop over a
call that exists, and the screen accumulates paths. No new plugin, no new permission.

### 4.3 Consequences of reusing M15's transport — the same three, restated

- **Bring your own key.** OpenRouter's free tier is **20 requests/minute and 50
  requests/day per key** on an unfunded account, and 1,000/day once the account has ever
  bought $10 of credits (the "200/day" figure in older guides is out of date). A menu is
  **one request**, all pages in one call — so the quota that worries M15 (a meal at a
  time) is comfortable here, and a second `analyse` for the same menu is the thing to
  avoid, not the thing to retry.
- **Opt-in, one switch.** Menu text is not health data the way a meal description is,
  but it is sent with the same key to the same provider, and the disclosure #321 writes
  says what is sent and to whom. M16 adds one sentence to that disclosure (issue 13) and
  does **not** add a second consent, a second key, or a second store. A user who has not
  enabled estimation gets `notConfigured` copy that names Profile, exactly as #323 does.
- **Offline is a designed state.** `MenuAnalysisFailureReason.offline` has its own copy
  and its own way out (keep the pages, retry). The pasted text and the captured pages
  survive every failure on screen; nothing the user typed or photographed is discarded.

### 4.4 The model's answer is untrusted input, and the parser is where that is paid for

The response is JSON from a third party, shaped by text a restaurant printed and OCR
mangled. `EstimateResponseParser` set the pattern; `MenuResponseParser` (§6.6) adds the
menu-specific rules from §3. The structured-output request (`response_format` with a
JSON schema) is sent as a *strong hint* — OpenRouter enforces it on providers that
support it and passes it through as guidance elsewhere — and **the parser never relies on
it**. Nothing in the response is interpreted as an instruction; a dish named `ignore
previous instructions` is a dish with an odd name and fails the provenance check like
any other invention.

### 4.5 What was rejected and why

- **Vision-direct as the first implementation** — costs image tokens against a 50/day
  quota, narrows the model choice, sends photographs, and makes the text mode a second
  prompt. Kept as the documented swap (§5).
- **Keeping M12's extractor as a stage in front of the model** — the LLM is better than
  a line-based heuristic at "is this a dish or a wrapped description", and a
  deterministic extractor in front of a non-deterministic classifier buys no
  testability the parser does not already provide. Its *rules* — drop section headers,
  strip prices, never invent a dish — survive as prompt instructions and as fixture
  cases, and the "never invent" rule became the parser's provenance check.
- **A separate consent for menus** — a second checkbox for the same key going to the same
  place is friction without a privacy gain; the disclosure sentence is the honest fix.
- **Logging a dish to the diary** (`ui_ux_design.md` §7's "הוסף לסל") — a verdict is not
  a macro. The natural bridge is M15's description mode with the dish name prefilled,
  and it is filed as a follow-up in §11, not built here.

---

## 5. Tesseract on menus: what is known, what is not, and what the fallback is

Everything the project knows about its OCR engine was learned on nutrition panels — a
bordered two-column table in a plain font. A menu is none of that: often two or three
columns, decorative type, coloured backgrounds, prices in a different script, and a page
that curls. Three facts and one non-fact:

- **The engine settings are pinned for a label.** `psm 4` ("a single column of text of
  variable sizes") was chosen because `psm 6` flattened a bordered table
  (`design/m6_platform_handoff.md`). `psm 3` (automatic layout) is what Tesseract's own
  documentation points at for columns instead, but `TextRecognitionService.recognise` has
  no segmentation parameter, and adding one touches all three adapters.
- **The prompt is told the text may be interleaved.** A model that is told "this is OCR
  output of a possibly multi-column menu; lines from neighbouring columns may alternate;
  prices may be separated from their dish" recovers most of what `psm` would have kept.
  This is the cheap mitigation and it costs nothing to try first.
- **`heb+eng` is already loaded**, which a bilingual Israeli menu needs and which M6 paid
  3.92 MB for.
- **It has now been measured once, and the interleaving guess above was wrong.**
  Issue #372 rendered a two-section grill menu — each dish right-aligned, its price
  left-aligned, on the same baseline, the shape a real Israeli menu prints — and ran it
  through the app's exact `psm 4` / `heb+eng` / `user_defined_dpi=300` pipeline
  (`test/fixtures/rendered_menu_ocr_fixture.dart`). **`psm 4` did not interleave the two
  columns**: every price stayed on its own dish's output line, in the right reading
  order, confirmed with `tesseract … tsv` word-box output. What it did instead is corrupt
  the price digits themselves, on every row (`₪28`→`₪588`, `₪32`→`2`, `64 ש"ח`→`4 ש"ח`,
  `58 ש"ח`→`8 ש"ח`) — not a new defect, but the already-known "the Hebrew model cannot
  read an isolated column of Latin digits" (`design/m6_platform_handoff.md`) reappearing
  on a menu's much wider price-margin gap.

  **One dish name was corrupted too, and it is the more useful finding of the two.**
  `סלט ירוק עם רוטב שמן זית ולימון` came back with `שמן` replaced by the Latin
  token `Pow` — the `heb+eng` trade-off `CLAUDE.md` already documents, landing on a dish
  name rather than on a macro row. The other four dish names and the wrapped description
  came through unharmed. A corrupted price never reaches the parser's output at all
  (`MenuResponseParser` has no price field), but a corrupted *word inside a dish name*
  does — and this is the first evidence that the provenance rule survives one:
  `nameOccursIn` needs a single qualifying word of the model's name to occur in the
  source, and `סלט`, `ירוק`, `רוטב`, `זית` and `ולימון` all still do. #357
  documented that rule as loose enough to survive one OCR-corrupted letter and could not
  prove it; this capture proves it against a whole corrupted word. Because of that,
  **this capture does not show OCR as the bottleneck for a dish/price row, and the
  "columns may be interleaved" prompt mitigation is not shown insufficient by it** — it
  stays in as a cheap safety net rather than becoming an urgent fix. It also does not clear the layout the mitigation's wording was actually written
  for: a **side-by-side two-section menu** (two independent lists printed next to each
  other, the shape `HebrewMenuFixture.twoColumn` types by hand), which #372 did not build
  and which stays unmeasured.

**If a corpus of that untested layout shows OCR is the bottleneck there, the fix is the
vision swap, not `psm` tuning.** A `VisionMenuAnalyzer` sends the page images through the
`imageBase64` part `LlmChatClient` already has, needs no change to any adapter, and is
selected in one provider — the OCP shape #312 made an invariant. It changes what leaves
the device, so it changes the disclosure; §8's invariant says so. **Nothing measured so
far requires filing it.**


### The photographed menu measured the same questions on a real page (#373)

> Captured by #373 / PR #410 on `main`, from a real Israeli restaurant menu
> photographed off a table (480x640, 40 KB — a phone photo after a messaging
> app). It **corroborates and extends** the rendered-menu capture above: the
> columns hold, and the prices are what break.

### 5.2 The answer: the columns held

**`psm 4` kept the rows whole.** On the photographed menu, dish text and its
price land on the same output line; there is no line anywhere in the transcript
that is a run of bare prices with the dishes elsewhere. `real_menu_pipeline_test.dart`
pins that as an assertion rather than leaving it as prose.

So **the column risk this section was opened to investigate is not what goes
wrong on a real menu.** The prompt's planned "columns may be interleaved"
instruction is not load-bearing for this layout, and the vision swap does not
need to be filed on account of column interleaving. Something else goes wrong
instead — see §10.

### 5.3 But `psm 4` is not obviously the right mode for a menu

Measured on the same photograph, same models, same DPI, varying only the page
segmentation mode:

| psm | chars | lines | Hebrew lines | dish rows keeping a number | prices correct |
|---|---|---|---|---|---|
| 3 | 842 | 22 | 21 | 12 | 2 |
| **4 (shipped)** | **843** | **22** | **21** | **12** | **2** |
| **6** | **1022** | **27** | **24** | **20** | **1** |
| 11 | 926 | 50 | 34 | 8 | 1 |
| 12 | 915 | 48 | 33 | 9 | 1 |

`psm 6` returned **21% more text** than the shipped `psm 4` and kept **20 of
the 23 dish rows** against `psm 4`'s 12 — recovering most of a third menu
section that `psm 4` dropped from its output entirely. It degrades into noise
at the very bottom of the frame, where the restaurant's logo is, which `psm 4`
avoids by stopping early.

Neither mode reads the prices (§10).

**This is a finding, not yet a recommendation.** It is one photograph. Changing
the shipped constant would change Keto Lens too, where `psm 4` was chosen for a
measured reason on the failure that produced it, so a menu scanner wanting
`psm 6` should pass its own mode rather than re-pin the shared one. Filing that
decision needs the other two menus #373 asks for.

### 5.4 Resolution is not the lever

Also measured, so that nobody spends the effort: re-running the same photograph
at 1600 (the app's own `targetWidth`), 2400, 3200, 4000 and 4500 px wide, on
the app's own greyscale-then-linear kernel:

| output width | numbers returned | distinct prices correct (of 19) |
|---|---|---|
| 1600 (shipped) | 12 | 2 |
| 2400 | 12 | 1 |
| 3200 | 14 | 1 |
| 4000 | 20 | 3 |
| 4500 | 19 | 3 |

Upscaling cannot invent strokes a 480 px source never recorded. The app's own
`OcrImagePrep.targetWidth` is as good as any larger number here, and its
`maxUpscale` cap of 4 is not what costs the digits. `OcrImagePrep`'s own
docstring guessed the other way — *"a real camera photo has several times the
detail and none of this brittleness is expected to apply to it"* — and flagged
itself as unverified. It is now verified, and it was optimistic for a
photograph that has been through a messaging app.

---

---

## 6. Architecture

No new plugin, no new permission, no new store, and no change to either
conditional-export firewall. One new feature directory. `http` arrives with #318, not
here.

### 6.1 The pipeline

```
Lens tab → "תפריט" ─┬─ paste text ────────────────────────────────┐
                    │                                              │
                    └─ photos: CameraSession.capturePhoto()  ×N   │
                               PhotoPicker.pickMultiple()          │
                                 → MenuPageReader                  │   (application)
                                     → TextRecognitionService      │   Tesseract, on-device, per page
                                     → text with page markers ─────┤   + list of unread pages
                                                                   ▼
                                                     MenuAnalyzer.analyse(text: ...)
                                                       RemoteMenuAnalyzer            (application)
                                                         → MenuAnalysisPrompt        (data)   system + user + schema
                                                         → LlmChatClient             (core, lifted from #318)
                                                         → MenuResponseParser        (data)   §6.6
                                                         → MenuAnalysis (sealed)     (domain)
                                                             → MenuResultView        (presentation)
                                                                 green · yellow · [red, collapsed] · [unclassified]
                                                                 DishCard: why + modification
```

Nothing is written to the database. Nothing in `keto_lens/` changes except one additive
method on `PhotoPicker` (§4.2).

### 6.2 Where it lives

**`lib/features/menu/`**, with the four standard layers. Not `keto_lens/` (M12's choice,
made when the analyser shared M6's classifier — it no longer does), and not
`restaurant/`, whose placeholder belongs to M11's directory. `architecture.md`'s tree
puts `MenuAnalyzerService` under `restaurant/` and names an `MlKitMenuAnalyzer`; both
lines are updated by issue 14. `CLAUDE.md`'s feature table gains a row.

### 6.3 The domain surface

```dart
// domain/models/dish_verdict.dart
/// Green / yellow / red. Its own enum, not `VerdictBadge`: Keto Lens's amber
/// means "quantity dependent"; this amber means "order it with a change".
enum DishVerdict { orderAsIs, modifiable, nonKeto }

// domain/models/analysed_dish.dart
@immutable
class AnalysedDish {
  final String name;            // exactly as printed — the user matches it to the menu
  final String? description;    // the menu's own line, if any
  final DishVerdict verdict;
  final String why;             // never empty — the parser enforces it
  final String? modification;   // non-null iff verdict == modifiable — the parser enforces it
}

// domain/models/menu_analysis.dart — sealed, for the reason ScanResult is
sealed class MenuAnalysis {}

final class MenuAnalysed extends MenuAnalysis {
  final List<AnalysedDish> dishes;     // never empty
  final List<String> unclassified;     // names the model listed but could not place, or that failed a parser rule — shown, never silent
  final int pageCount;                 // 0 for pasted text
  final List<int> unreadPages;         // 1-based; OCR ran and produced nothing on these
}

final class MenuAnalysisFailed extends MenuAnalysis {
  final MenuAnalysisFailureReason reason;
}

enum MenuAnalysisFailureReason {
  emptyInput, ocrUnavailable, noTextFound,
  notConfigured, offline, rateLimited, unauthorised, badResponse,
  noDishesFound,
}

// domain/services/menu_analyzer.dart
abstract interface class MenuAnalyzer {
  /// Never throws. Text, photos, or both; both empty is `emptyInput`.
  Future<MenuAnalysis> analyse({String? text, List<String> imagePaths = const []});
}
```

The `{text, imagePaths}` signature mirrors `MacroEstimator.estimate({description,
imagePath})` deliberately: it is what lets a vision implementation take the photos and
the text implementation take the text, behind one method, with the choice made in one
provider.

`MenuPageReader` (application) is the multi-page half, separately testable:

```dart
class MenuPageReader {
  const MenuPageReader({required TextRecognitionService recognizer});
  /// OCRs each page in order, on the device. Never throws: a page that fails
  /// or reads empty is listed in `unreadPages`, and the others still count.
  Future<MenuPagesText> read(List<String> imagePaths);
}

@immutable
class MenuPagesText {
  final String text;              // pages joined with a `--- עמוד N ---` marker
  final int pageCount;
  final List<int> unreadPages;    // 1-based
  final bool ocrUnavailable;      // `recognizer.isAvailable` was false; nothing was read
}
```

### 6.4 The LLM seam is lifted to `lib/core/`

#318 places `LlmChatClient`, `ChatResult`, `ChatFailureReason`, `EstimationCredentials`
and `OpenRouterClient` under `lib/features/diary/data/estimation/`. A second feature's
`application/` layer importing a first feature's `data/` folder is the cross-layer arrow
`issue_conventions.md` §3 forbids. Issue 2 moves the transport — the interfaces, the
result types and the client — to `lib/core/services/llm/`, leaves the diary-specific
`UserApiKeyCredentials` and the `llmChatClientProvider` wiring where #318 put them, and
makes **two additive changes** to `complete` while it is there, both needed by a menu and
harmless to a meal:

- `int? maxOutputTokens` — a 60-dish menu is several thousand output tokens, and a
  provider default that truncates the JSON mid-array is a `badResponse` the user cannot
  fix by retrying.
- `Map<String, Object?>? responseSchema` — sent as `response_format: {type:
  'json_schema', json_schema: {name, strict: true, schema}}` where the provider supports
  it; the `json_object` request stays the fallback. The parser trusts neither.

The invariant #312 wrote — *"`grep -rn "OpenRouter" lib/` returns hits in exactly two
files"* — still holds after the move: the client and the one provider that constructs
it. Issue 2 is blocked on #318 merging and is a `refactor` with no behaviour change to
M15's estimator, which is asserted by M15's own suite passing unchanged.

### 6.5 Layer rules

`domain/` holds the four types above and the interface — pure Dart. `data/` holds the
prompt, the schema and the parser. `application/` holds `MenuPageReader` and
`RemoteMenuAnalyzer`, composed from three interfaces (`TextRecognitionService`,
`LlmChatClient`, and the parser's static surface) and never a plugin. `presentation/`
renders. `lib/features/menu/data/providers.dart` is the only file that may name a
concrete analyser — the composition root, and the one place a vision swap shows.

### 6.6 The parser rules

`MenuResponseParser.parse(String content, {required String sourceText})` — static, pure,
never throws. In order:

1. Strip a markdown fence. `jsonDecode` inside a `try`; anything thrown → `badResponse`.
2. Not a `Map`, or `dishes` absent or not a `List` → `badResponse`.
3. Per element: `name` a non-empty `String` ≤ 120 chars; `verdict` one of the three
   names (matched by string, never ordinal); `why` a non-empty `String`. Any of these
   failing moves the element's `name` (if it had one) to `unclassified`.
4. **Yellow requires its instruction.** `verdict == modifiable` with an absent, blank,
   or over-length `modification` → the name goes to `unclassified`. A green or red
   carrying a `modification` keeps the verdict and drops the field.
5. **Provenance.** After `HebrewTextNormaliser` on both sides, at least one word of the
   dish name (≥ 3 characters, digits excluded) must occur in `sourceText`. A name that
   shares nothing with the menu is an invention and goes to `unclassified`. The check is
   deliberately loose enough to survive one OCR-corrupted letter in a three-word name
   and strict enough to catch a dish the menu never mentioned.
6. Caps: `> 150` dishes → `badResponse`; `why` and `modification` truncated at 300
   characters, never rejected for length alone.
7. `dishes` empty after all of the above → `MenuAnalysisFailed(noDishesFound)` —
   *unless* `unclassified` is non-empty, in which case it is a `MenuAnalysed` with an
   empty `dishes` list, because "the model saw dishes and could place none" is a result
   the user should see, not a failure they should retry.
8. Otherwise `MenuAnalysed(dishes, unclassified, ...)`, with page metadata from the
   reader.

All caps and the verdict names live in `lib/core/constants/menu_verdict_rules.dart`,
which also holds the Hebrew definitions of the three states the **prompt** sends and the
**legend** shows — one source of truth, so the model and the user are told the same
thing.

---

## 7. UX

- **Entry point: a second mode on the lens tab.** A two-chip selector at the top of
  `CameraScreen` — `תווית` (default, unchanged) · `תפריט` — pushes `/lens/menu`.
  `AppShell` matches by prefix, so the lens tab stays lit. `ui_ux_design.md` §7's
  "FAB → מסעדה" predates the FAB being the add-meal affordance
  (`design/user_bugs_handoff.md`); the FAB is not touched.
- **Input screen, two tabs, text first.** `הדביקו טקסט` is a multi-line field with an
  analyse button; `צלמו עמודים` is the viewfinder with a thumbnail strip beneath it —
  `עמוד נוסף`, a gallery button that adds several, a remove control per thumbnail, and
  `נתחו` once there is at least one page. Page cap 8, enforced in Dart.
- **Progress is per page.** `קורא עמוד 2 מתוך 5…` during OCR, then `מנתח את התפריט…`.
  Never an indeterminate spinner alone (`design/m6_handoff.md`).
- **Results: three groups and a legend.** Green rows, then yellow rows, then a collapsed
  `לא מתאים לקטו (7)` header that expands to the red rows, then `לא ניתן לקבוע (2)` for
  the unclassified names. A `pageCount` and any `unreadPages` are stated in one line at
  the top (`עמוד 3 לא נקרא — נסו לצלם שוב`). The legend is three chips with the
  `MenuVerdictRules` definitions.
- **The card.** Collapsed: name, badge (icon + colour, never colour alone), and for
  yellow the first line of the instruction. Expanded: `למה` and, for yellow, `מה לבקש`
  with a copy button (`Clipboard` — Flutter SDK, no plugin). Tap anywhere to toggle;
  44×44 pt minimum.
- **Failure copy, one per reason, each with its own way out:**

  | Reason | Headline | Action |
  |---|---|---|
  | `emptyInput` | — | Unreachable: the button is disabled |
  | `ocrUnavailable` | `הסורק לא זמין במכשיר הזה` | Paste text instead; no retry (the M6 rule) |
  | `noTextFound` | `לא זוהה טקסט בתמונות` | Retake, or paste |
  | `notConfigured` | `ניתוח תפריטים לא מופעל` | Open Profile — the same copy shape as #323 |
  | `offline` | `אין חיבור לאינטרנט` | Retry; pages and text kept |
  | `rateLimited` | `חרגתם ממכסת הבקשות היומית` | The quota line #321 already shows |
  | `unauthorised` | `המפתח נדחה` | Check the key in Profile |
  | `badResponse` | `הניתוח נכשל` | Retry |
  | `noDishesFound` | `לא זוהו מנות בתפריט` | Retake / edit text |

- **RTL throughout**, digit runs and prices `TextDirection.ltr`, `EdgeInsetsDirectional`,
  Hebrew copy in `lib/core/constants/` next to `phase_copy.dart` and `profile_copy.dart`.

---

## 8. The milestone

### North Star

A user hands the app a restaurant menu — pasted, or photographed page by page — and gets
every dish back as green, yellow-with-an-instruction, or red, with a reason they can
read and an instruction they can say to the waiter, and the app never shows a dish it
did not find or a yellow it cannot explain.

### Explicitly out of scope

- **M12's two issues** (#121, #122) — superseded, not extended. Not to be picked up
- **Logging a dish to the diary** — a verdict is not a macro; a hand-off to M15's
  description mode is a follow-up (§11)
- **Per-dish macro numbers** — the verdict is qualitative, as #267 also ruled
- **Saving or sharing an analysed menu**, attaching one to an M11 venue
- **A vision-direct analyser** — the documented swap, filed if the corpus demands it
- **A second consent, key, or store** — one switch, one key
- **Changing Keto Lens's scan** — `ScanOrchestrator`, the parsers, the adapters and the
  label sheet are untouched; `PhotoPicker` gains one method
- **Tuning the OCR engine's `psm`** — the prompt absorbs interleaving first (§5)

### Architectural invariants

1. **The photograph never leaves the device.** Only recognised text is sent. Any
   implementation that sends an image must change the disclosure in the same PR.
2. **Nothing M16 produces is persisted.** No repository, no store, no `DailyLog`, no
   streak path.
3. **A yellow verdict carries a non-empty modification instruction**, enforced in the
   parser, not in the prompt alone.
4. **No dish is shown that the source text does not contain** — the provenance check.
5. **Unclassified is rendered, never dropped; red is grouped, never hidden.**
6. `DishVerdict` is its own enum. `VerdictBadge` is not reused for a dish, and
   `AppTheme.success / caution / danger` are the only colours.
7. **Open/closed about the engine.** `lib/features/menu/data/providers.dart` is the
   only file that names a concrete `MenuAnalyzer`; `OpenRouter` stays named in exactly
   two files repo-wide.
8. **Keto Lens's no-network invariant is untouched** — a *scan* still makes no network
   call. A menu analysis is a different feature, and every document that records this
   says so.
9. Estimation's opt-in gates menus too: off until a key is entered and the disclosure
   accepted. No API key is logged, printed or included in any failure value.
10. No new plugin, no new permission, no new store, no change to either firewall; no
    test, unit or e2e, makes a network call.
11. No sembast types in `domain/` or `presentation/`; no Flutter in `domain/` or
    `application/`; all providers `@riverpod`, returning interfaces.

### Definition of Done

`milestone_conventions.md` §3's standard list, plus:

- [ ] Both input modes reachable from the lens tab; the pasted-text mode works with no
      camera and no OCR
- [ ] Two e2e flows in `integration_test/` — pasted text with `MenuAnalyzer` faked;
      photo pages with `PhotoPicker`, `TextRecognitionService` and `LlmChatClient`
      faked, asserting the client received text and **no image part**
- [ ] `test/fixtures/hebrew_menu_fixture.dart` holds at least five real Israeli menu
      transcripts and one verbatim OCR transcript of a photographed menu, and the parser
      and analyser suites run against them
- [ ] `grep -rn "OpenRouter" lib/` reports exactly two files
- [ ] The disclosure names menu text; `design/technology.md` §6, `design/ui_ux_design.md`
      §7, `design/architecture.md`'s tree and route table, and `CLAUDE.md` describe what
      shipped
- [x] M12's Epic #267 carries a closure or supersession comment (§11, decision 1) —
      done 2026-09-12: #267, #121 and #122 closed as superseded, milestone #14 retired

---

## 9. The fourteen issues, in build order

Dependencies point backwards only. Every issue leaves `main` green on its own.

| # | Issue | Type · Layer | Depends on |
|---|---|---|---|
| 1 · #352 | **Hebrew menu corpus** — ≥ 5 real Israeli menu transcripts and one verbatim Tesseract transcript of a photographed menu, as `test/fixtures/hebrew_menu_fixture.dart` + `test/fixtures/images/`; a fixtures test that pins their shape | test · test | — |
| 2 · #355 | **Lift the LLM transport to `lib/core/services/llm/`** — move `LlmChatClient`, `ChatResult`, `ChatFailureReason`, `EstimationCredentials`, `OpenRouterClient`; add `maxOutputTokens` and `responseSchema`; M15's suite unchanged | refactor · core | #318 (M15) |
| 3 · #353 | **Menu domain** — `DishVerdict`, `AnalysedDish`, `MenuAnalysis` (sealed), `MenuAnalysisFailureReason`, `MenuPagesText`, the `MenuAnalyzer` interface, fixtures | feat · domain | — |
| 4 · #356 | **`MenuVerdictRules` + `MenuAnalysisPrompt`** — the three-state definitions (Hebrew, one source for prompt and legend), the caps, the system prompt, the user-turn builder, the JSON schema map | feat · data | 3 |
| 5 · #357 | **`MenuResponseParser`** — §6.6, run against the corpus | feat · data | 1, 3 |
| 6 · #358 | **`MenuPageReader`** — sequential per-page OCR through `TextRecognitionService`, page markers, unread pages, `isAvailable` first | feat · application | 3 |
| 7 · #361 | **`RemoteMenuAnalyzer`** + `menuAnalyzerProvider` — composes 4, 5, 6 and `LlmChatClient`; failure mapping; never throws | feat · application | 2, 4, 5, 6 |
| 8 · #354 | **`PhotoPicker.pickMultiple()`** — additive method on the interface and the `image_picker` adapter; cap enforced in Dart | feat · presentation | — |
| 9 · #359 | **`DishCard`** — expandable; why; modification with copy; badge with icon + colour | feat · presentation | 3 |
| 10 · #362 | **`MenuResultView`** — three groups, collapsed red with count, unclassified section, unread-pages line, legend | feat · presentation | 9 |
| 11 · #364 | **`MenuScannerScreen`, text mode, route and entry point** — `/lens/menu`, the `תפריט` chip on `CameraScreen`, paste → analyse → results, every failure reason's copy | feat · presentation | 7, 10 |
| 12 · #365 | **Photo pages mode** — capture loop over `CameraSession`, multi-pick, thumbnail strip, per-page progress | feat · presentation | 8, 11 |
| 13 · #360 | **Disclosure sentence** — `EstimationSettingsSection` names menu text as something sent; the photo-stays-local sentence | feat · presentation | #321 (M15) |
| 14 · #366 | **Two e2e flows + docs close-out** — `menu_text_flow.dart`, `menu_photo_flow.dart`; `CLAUDE.md`, `technology.md` §6, `ui_ux_design.md` §7, `architecture.md`, `tasks.md`, this file's status line | test · test | 11, 12, 13 |

Issues 1, 3 and 8 (#352, #353, #354) have no dependency and can start today; #363 is not an M16 issue. **Issue 1 is the cheapest
useful thing in the milestone and the one this project has most often skipped** — it
needs a phone, five menus and an afternoon, and it is what stops issue 5's tests from
being "a human imagined this OCR output".

---

## 10. Risks, and what has not been verified

| Risk | Reality |
|---|---|
| **OCR on real menus** | **Nobody has measured it.** The engine is pinned for a two-column label; a three-column menu in a display face may interleave badly. Issue 1 finds out; §5 has the fallback |
| **Classification accuracy** | Unmeasured, and there is no benchmark for "keto verdict on an Israeli menu" to borrow one from. The parser rules bound the damage of an invented dish and a blank yellow; they cannot bound a wrong green. A reviewing user is the last defence, and the `why` text is what lets them review |
| **The wrong green** | The one failure that matters (§3). Mitigated by the `why` being mandatory and visible, not eliminated |
| **A dish the menu never mentioned** | The provenance check (§6.6 rule 5) catches an invention; it cannot catch a real dish assigned the wrong description |
| **Truncated JSON** | A long menu can exceed a provider's default output length. `maxOutputTokens` is set per request (issue 2), and the parser reports a truncated array as `badResponse` rather than showing half a menu as the whole |
| **The free tier runs out** | 50 requests/day per key; one per menu. A user who re-analyses the same menu five times spends five. `rateLimited` copy names the quota |
| **A free model is deprecated upstream** | #318's pin and fallback list; a dead model is `badResponse`, never a crash |
| **The photo mode regresses Keto Lens** | `PhotoPicker` gains a method; nothing else in `keto_lens/` changes. Asserted by M6's and M15's suites passing unchanged |
| ~~**M12 is picked up in parallel**~~ | Retired. The owner closed #267, #121 and #122 as superseded on 2026-09-12 and milestone #14 with them, so there is no second feature to pick up |
| **OpenRouter's own docs were unreachable from this session** | `openrouter.ai` is blocked by this environment's egress policy, as `data.gov.il` was for M15. The rate limits and the multi-image and structured-output facts above are from secondary sources that agree with one another and with `design/m15_meal_entry_research.md`; issue 4 should re-read the primary page before pinning the schema shape |

**No accuracy number is claimed anywhere in this document for the classifier this
milestone builds.** None has been measured.

### What #366 verified, and the one gap it did not close

#366 closed the milestone with two end-to-end flows, driven headless through the real
router, the real screens and — on the photo side — the real analyser:

- **`menu_text_flow.dart`** drives the lens tab's `תפריט` chip → `/lens/menu` → paste →
  analyse, against a fake `MenuAnalyzer`, and asserts the grouped result (green before
  yellow, a collapsed red group with its count, an unclassified name reported) and every
  reachable failure copy, including the offline retry and the notConfigured → Profile
  path.
- **`menu_photo_flow.dart`** is the stronger claim: `MenuAnalyzer` is **real**
  (`RemoteMenuAnalyzer`), so the real `MenuPageReader`, the real `MenuAnalysisPrompt` and
  the real `MenuResponseParser` all run. Only `PhotoPicker`, the camera (which fails on
  its own, headless, the same way `keto_lens_flow.dart` relies on), `TextRecognitionService`
  and `LlmChatClient` are faked. It asserts Epic #351's first invariant directly: the
  recorded client call carries the page-1 recognised text, `imageBase64` is `null`, and
  both `maxOutputTokens` and `responseSchema` are set.

**What that does not close: no real restaurant menu has ever been photographed or
OCR'd.** `HebrewMenuFixture.grill`, which the photo flow's fake `TextRecognitionService`
returns for page 1, is a hand-typed transcript — the same distinction
`design/m6_platform_handoff.md` draws for Keto Lens's own fixtures. #372 (a rendered-menu
OCR capture, needing no camera) and #373 (a photographed real menu, needing a human with
a phone) are the still-open work that would close it, and neither is built. Until one of
them lands, "the photo path works" means "proven against fakes and a hand-typed
transcript," not "proven against an engine reading a real, curled, glare-lit menu photo."


### The photographed-menu corpus (#373 / PR #410)

> Merged from `main`. This is the first real menu in the repository, and it
> changes what M16 may show the user.

### 10.1 What the corpus now has, and what it still lacks

M16's corpus has three provenance tiers, mirroring the three the repo keeps for
labels:

| Tier | Artefact | State |
|---|---|---|
| Hand-typed menu text | `HebrewMenuFixture` (#352) | **Not collected** |
| Rendered menu → real engine output | `RenderedMenuOcrFixture` (#372) | **Not collected** |
| **Photographed menu → real engine output** | `PhotographedMenuOcrFixture` (#373) | **One menu of the three** |

`test/fixtures/images/vivie_restaurant_menu.jpg` is a real Israeli restaurant
menu photographed off a table, supplied by the owner. It is the first menu of
any kind in this repository.

**It is one menu, and #373 asks for three deliberately differing ones** — a
multi-column layout, a laminated sheet with glare, and a bilingual
Hebrew/English card. This is none of those three on purpose; it is simply the
menu somebody had. **#373 was nevertheless closed as completed by the owner**
after PR #410, so the other two menus are a gap in the corpus with no open
issue tracking them.

The photograph arrived at **480×640, 40 KB** — a phone photo after a messaging
app had had it. Nothing here downscaled it further. That is not a defect of the
corpus, it is the normal path by which a photograph reaches an app that accepts
one from the gallery, and §5.4 shows it is the binding constraint.

### 10.2 The finding: the dish names read, the prices do not

The two halves point in opposite directions, and the split is the most useful
thing M16 has learned about its own input.

**Dish names survive.** Scored by edit distance against the printed menu, of
the 23 dish names:

- **9 came back character-perfect** — `צלחת חריפים`, `ריזוטו, פטריות בלו אויסטר`,
  `פילה דג ים, אורז אסור, ביסק סרטנים`.
- **17 scored 0.75 or better**, the band where a name is plainly recognisable
  through one or two corrupted letters (`ברוסקטה סרדינים כבושיט` for
  `...כבושים`).
- **19 scored 0.70 or better.**
- The **4 that failed** (0.33–0.55) are the last four dishes on the page,
  nearest the foot of the photograph where the frame falls off. That is a
  property of where they sat in the shot, not of the dishes.

**Prices do not survive, and they fail in the dangerous direction.** The menu
prints 23 prices, 19 of them distinct. The pipeline returned **12 numbers**.
**Two were right.** The other ten match nothing printed anywhere on the menu,
and they are wrong in one consistent way: the left-hand digit is gone and the
right-hand one survives.

| printed | returned |
|---|---|
| 28 | 8 |
| 18 | 8 |
| 52 | 2 |
| 74 | 4 |
| 63 | 3 |
| 58 | 8 |
| 72 | **72** |
| 79 | **79** |

The nine dishes of the third section returned no number at all.

### 10.3 Why that asymmetry is good news, with one hard rule attached

**A keto classifier reads ingredients, not prices.** The payload M16 needs is
the payload that survives. This is the exact inverse of Keto Lens, where the
numbers are the whole point and the Hebrew is scaffolding — and it means the
menu scanner's core function is viable on real photographs in a way the label
scanner's was not until `psm 4` + `heb+eng` + `user_defined_dpi` were found.

The rule that follows is not optional:

> **M16 must never present a scanned price as fact.**

A price that comes back as nothing is a safe failure. A 28 shekel dish
displayed as 8 shekels is not — it is a *plausible wrong number*, the failure
#257 was, and the user has no way to tell it from a correct one by looking at
it. If prices are surfaced at all they must be shown as the user's to confirm,
exactly as `ScanResultSheet` treats an unknown `ServingBasis`. The safest
reading of this measurement is that M16 should not extract prices at all in its
first version.

`real_menu_pipeline_test.dart` pins the deficiency, in the same spirit as
`real_ocr_pipeline_test.dart` pinning the lost carbohydrate row of the pointed
wafer. **If that test fails because the engine started reading prices, that is
good news and the fix is to rewrite this section — not to loosen the test.**

### 10.4 A menu is not a nutrition label, and the shipped scanner agrees

Worth stating because it was never checked before and M16 makes it reachable:
once a second scanner exists in the same tab shell with the same camera, the
most likely wrong thing for a user to point Keto Lens at is a menu.

Fed this transcript, `ScanOrchestrator` returns `ScanFailed(notALabel)` and
carries the raw text through for the user to see. No macro parses out of it —
not from `שמן זית` in a dish description, not from anything. That is #83's rule
holding on an input class it was never tested against, and it is now a test.

### 10.5 What is still unverified

- **No menu has been read through the app's own camera.** There is no camera in
  this repository. This is a photograph handed to the gallery path.
- **One menu is not an accuracy figure.** Nothing here claims a percentage for
  menus in general, and the 9-of-23-perfect result is one page, one restaurant,
  one typeface, one light.
- **No laminated menu, no glare, no bilingual card.** The three shapes #373
  names as the point of the exercise are all still missing.
- **`psm 6` is a measurement, not a decision** (§5.3).
- **No real Hebrew menu PDF has been obtained or opened.** #405–#408 (§12) shipped
  against fixtures built with `reportlab`, `pikepdf` and `img2pdf`, not against the real
  menu attached to #373 (undownloadable from this environment — proxy 403 on GitHub
  user-attachments). #408's DoD calls for a real Hebrew menu PDF of each kind — text-layer,
  scanned, mixed — opened by hand in `flutter run -d chrome`; that has not been done, and
  cannot be done headlessly since no picker dialog can be driven without a human.
- **Android, iOS, macOS and Windows have never built the PDF adapter.** §12 records web
  and Linux as build-and-smoke-test green; the other four platforms could not be built at
  all in this environment (no SDK, no Apple or Windows hardware) and are unproven until
  watched on the real CI run.

---

## 11. Decisions for the product owner

1. ~~**Close M12 as superseded?**~~ **DECIDED 2026-09-12 — closed.** The owner's words
   were "Close M12, it's redundant". #121, #122 and Epic #267 are closed as superseded
   by M16 (the way Epic #13 was), GitHub milestone #14 is retired, and the
   `epic:m12-menu-analyzer` label stays on all three as history. The alternative —
   keeping M12 as a deterministic, offline first cut — would have meant writing the dish
   vocabulary §1.2 shows it lacks, which is the offline food table M15 shelved.
2. **One consent switch, or two?** M16 reuses estimation's key and consent and adds a
   sentence to the disclosure. A user who wants menus but not meal estimates has no way
   to say so. *Recommendation: one switch now; split only if someone asks.*
3. **Text-first, or vision-first?** Text keeps the photo on the device and every free
   model in play; vision may read a decorative menu better. *Recommendation: text
   first, decide on the corpus, and the swap is one provider line.*
4. **Should a dish be loggable?** `ui_ux_design.md` §7 has "הוסף לסל". The honest bridge
   is "estimate this dish" → M15's description sheet prefilled with the dish name and
   its modification. *Recommendation: a follow-up issue after both milestones ship, not
   M16 scope.*
5. **Where does the entry point live long-term?** A chip on the lens tab is the smallest
   change. If M11's directory ships, "analyse this venue's menu" from a venue card is the
   better door and `/restaurants/:id/menu` (already in `architecture.md`'s route table)
   becomes a second route to the same screen. *Recommendation: lens chip now.*

---

## 12. PDF input (#405–#408), added after the first fourteen shipped

The owner asked for PDF menus once the text and photo modes were working. A menu arrives as a
PDF at least as often as it arrives as a photograph — emailed by the venue, downloaded from its
site, forwarded in a message — and the app could not take one: `grep -rni "pdf"` over `lib/`,
`test/` and `pubspec.yaml` returned zero matches.

**A PDF is two problems wearing one file extension.**

| Kind | What it is | How it becomes text |
|---|---|---|
| **Text-layer** | A designed export; the characters are really in the file | Extracted directly. No OCR, no recognition error, and it works on a build with **no OCR engine at all** |
| **Scanned** | A photograph wrapped in a PDF; no characters exist | Rasterised per page, then read by the **existing** Tesseract pipeline |

A user cannot tell which kind they hold, so both must work. That is why this is four issues
rather than one: #405 the seam and the text layer, #406 the rasteriser, #407 the picker,
#408 the third input mode.

### The engine decision

**`pdfrx` ^2.6.1 (MIT)** for reading, **`file_selector` ^1.0.3 (BSD-3-Clause, flutter.dev)** for
picking. `pdfrx` is the only maintained package that does *both* extraction and rasterising
across all six targets, so one dependency serves both halves. `file_selector` is close to free:
three of its five platform implementations were already in `pubspec.lock` as transitive
dependencies of `image_picker`.

**`syncfusion_flutter_pdf` was evaluated and rejected.** It is pure Dart — no native binaries,
no firewall, zero platform risk, which was genuinely attractive. It cannot rasterise, so it
could not serve a scanned menu without a second engine beside it, and it is proprietary: the
Syncfusion Community License requires gross revenue under $1M *and* fewer than five developers.
MIT with one dependency beats a licence that lapses as the product grows.

**Both packages were added in one commit, not one per issue** — so the lockfile is written
once rather than rewritten in parallel across #405–#408, and the six platform workflows are
triggered once instead of four times. Resolution pulled **19 packages**, more than this
section originally anticipated: `pdfrx` brings `pdfrx_engine`, `pdfium_flutter` and `rxdart`
along with it, and — unpredicted here — the seven `url_launcher` platform packages, because
`pdfrx`'s own dependency chain uses `url_launcher` as a native plugin on all six targets.

### The risk this carried, and how far it resolved

`pdfrx` → `pdfrx_engine` → `pdfium_dart`, whose README says PDFium is *"downloaded and bundled
at build time"* through **Dart native assets** (`hooks`, `code_assets`). That is a build-time
network fetch plus a young Dart feature, landing on six pinned CI runners.
`design/m6_platform_handoff.md` records that **every one of those runners has previously caught
a defect that compiled cleanly on all the others**. #405 was deliberately first and deliberately
small so this would be discovered cheaply.

**Resolved on two of six platforms, unproven on the other four:**

- **Web:** `flutter build web --release --no-web-resources-cdn` is green with the pdfrx
  adapter in the tree.
- **Linux:** `flutter build linux` is green; the pdfium build hook fetches `libpdfium.so`
  and bundles it into the app directory; `tool/linux_smoke_test.sh` **passes** — the built
  binary launches under Xvfb, creates its database file, and logs no fatal line.
- **Android, iOS, macOS, Windows: not verified.** This environment has no Android SDK, no
  Apple hardware and no Windows machine, so none of the four could be built here at all —
  not "built and untested", genuinely never compiled. They must be watched on the real CI
  run before the milestone can be called platform-proven; §12's original stopping condition
  ("if the six builds cannot be made green, the milestone stops there") is not yet fully
  discharged, only two-sixths of it.

### The Hebrew trap, and the guard for it

Israeli menu PDFs are frequently produced by design tools that embed **subset fonts with no
usable `ToUnicode` map**. Extraction from those yields mojibake — plausible-looking character
soup, not Hebrew — and mojibake is *worse* than no text at all: it reaches the model, spends one
of the 50 daily free requests, and returns invented dishes that `MenuResponseParser`'s
provenance rule then silently discards, leaving the user with an empty result and no reason.

So #405 carries a **legibility guard**, applied per page in this order: trim-empty first,
then fewer than `MenuVerdictRules.minExtractedLetters` (20) letters, then a Hebrew-letter
share below `MenuVerdictRules.minHebrewLetterRatio` (0.5) — any one of the three routes the
page to `pagesWithoutTextLayer` with **no partial text kept**. Failing safe into the
slower, proven pipeline is the right direction; sending garbage to a paid model is not.
#406's rasteriser then renders exactly those pages, sequentially, to PNG in a temporary
directory, at `MenuVerdictRules.pdfRenderWidthPx` — which is *derived from*
`OcrImagePrep.targetWidth` rather than restating the 1600px figure a second time, so the
two pipelines cannot drift apart. Aspect ratio is preserved; a page that fails to render is
omitted rather than failing the whole batch. Nothing under `lib/features/keto_lens/` was
touched and no OCR setting changed.

**Every PDF fixture behind this guard is constructed, not a real-world artefact, and must
stay labelled that way.** The real Israeli menu PDF the owner attached to issue #373 could
not be downloaded into this environment — the proxy is scoped to repository APIs and
returns 403 for GitHub user-attachments. The fixtures used instead:
`hebrew_menu_textlayer.pdf` (built with `reportlab`, real embedded Hebrew, letter/Hebrew
ratios 1.00/1.00/0.83 across its pages), `hebrew_menu_mojibake.pdf` (**constructed** with
`pikepdf` by rewriting `/ToUnicode` `bfchar` entries — a real corruption mechanism, but not
a real design-tool export), `hebrew_menu_scanned.pdf` (`img2pdf` over the existing
`vivie_restaurant_menu.jpg`), plus `hebrew_menu_mixed.pdf`, `hebrew_menu_encrypted.pdf` and
`zero_page.pdf`. The guard's thresholds are therefore validated against a simulated
mojibake sample, not a menu a Tel Aviv print shop actually exported.

### What is unchanged

`MenuAnalyzer`'s interface does not change — `RemoteMenuAnalyzer` already accepts `text` and
`imagePaths` together and joins them into one `source` for one request, which is exactly what a
mixed PDF needs. The prompt, the parser, `MenuResultView` and every failure state are reused
untouched. **The PDF never leaves the device**, on the same terms as the photograph: only
extracted or locally-recognised text is sent, and `menu_pdf_flow.dart` asserts it. Keto Lens's
no-network invariant is untouched — a *scan* still makes no request.

**Epic #351's "no new plugin, no new store, no change to either conditional-export firewall"
invariant was amended, not waived**, to permit exactly these two packages and — only if
`flutter build web` proved it necessary — a third firewall.

**The firewall question is answered: no third firewall was needed.** `flutter build web
--release --no-web-resources-cdn` succeeds with `PdfrxPageExtractor` — the one file in
`lib/` that imports `pdfrx` — in the tree. CLAUDE.md's "there are two" firewall sentence
stands unchanged.

### Two real defects found during the work

**A silent no-op on web, the shape of bug this project has shipped before.**
`DocumentPicker.pickPdf()` originally returned `null` both when the user cancelled the
picker and when the platform handed back a file with no filesystem path — the case on
web, where a picked file is a blob rather than a path. That made a web user's PDF pick
indistinguishable from backing out: nothing happened, and nothing said why. The no-path
case now throws `DocumentPickerException`, which `MenuPdfTab` renders as a real message;
cancellation still returns `null`. See `design/user_bugs_handoff.md` for the pattern this
matches.

**A gap in the test gate itself, not the app.** `pdfrx` reaches PDFium as a Dart *native
asset*, and only `flutter build` writes the `.dart_tool/native_assets.yaml` manifest the
VM needs to find it — not `flutter pub get`, not a prior build in the same checkout, and
not `--enable-native-assets` on `flutter test`. Every test that opened a real PDF was
therefore skipping itself (measured: 15 skips against the project's baseline of 5) while
`flutter test` still printed "All tests passed!". The tests were right to skip loudly —
the same precedent `tesseract_ffi_recognizer_test.dart` set for a missing native
dependency — but nothing failed the *build* when they did, which is the actual gap.
Fixed by `tool/pdfium_test_assets.sh`, which writes the manifest pointing at the library
the Linux build hook already produced and exits 1 if that library is absent, plus a new
step in `.github/workflows/build-linux.yml` that runs the PDF test suite after the Linux
build and fails the job if the skip banner reappears. `verify` is deliberately left
unchanged — running these tests there would mean building Linux inside it.

### Final measured state of the merged branch

`flutter analyze` clean, `dart format` clean, **2558 tests passing / 5 skipped** (5 is
the project's long-standing baseline skip count, so nothing from #405–#408 is silently
sitting out), the e2e suite at **40 flows green** (including the new
`menu_pdf_flow.dart`), gated coverage **1022/1057 = 96.69%**, and the web release build
green. This is the code-complete state described at the top of §12; the platform and
real-fixture gaps above are what remain.

---

## 13. The structured-output refusal, found after §12 shipped

The first user report after PDF input merged was that **every** input mode failed while
Daily Intake's description mode worked, and that a two-minute timeout changed nothing.
§4.4 and §6.4 above describe the `json_schema` request as a strong hint with
`json_object` as the fallback; the fallback was never implemented, and the schema as
pinned (from secondary sources — §10 records that `openrouter.ai` was unreachable) was
not valid under strict mode either. The gateway refuses such a request before any model
sees it, and `OpenRouterClient` read that 4xx as `badResponse`. `OpenRouterClient.complete`
now falls back once to `json_object` on 400/404/422, and `MenuAnalysisPrompt.schema` is
strict-mode valid. The full account, the comparison table that located it, and what
remains unverified are in `design/m16_structured_output_fix.md`.

---

## Sources

Primary OpenRouter documentation (`openrouter.ai/docs/...`) was **unreachable from this
session** — blocked by the environment's egress policy — so the OpenRouter facts are from
the secondary sources below, which agree with each other and with M15's research.

- OpenRouter free tier 2026 — rate limits, models, BYOK — <https://klymentiev.com/blog/openrouter-free-tier>
- OpenRouter API key free: limits, free routes, paid access, BYOK — <https://www.datastudios.org/post/openrouter-api-key-free-limits-free-routes-paid-access-and-byok>
- How to get free AI model APIs with "unlimited" tokens (OpenRouter limits) — <https://pinggy.io/blog/free_ai_model_apis_unlimited_tokens_openrouter/>
- OpenRouter structured outputs (docs; unreachable, cited for the field names) — <https://openrouter.ai/docs/guides/features/structured-outputs>
- How to send an image to an LLM via API — multiple `image_url` parts per message — <https://openrouter.ai/blog/tutorials/send-image-to-llm/>
- Free models router (`openrouter/free`) filters by capability — <https://openrouter.ai/openrouter/free>
- Tesseract page segmentation modes explained — <https://pyimagesearch.com/2021/11/15/tesseract-page-segmentation-modes-psms-explained-how-to-improve-your-ocr-accuracy/>
- Tesseract PSM and OEM modes: configuration and tuning — <https://www.nutrient.io/blog/tesseract-python-guide/>
- `image_picker` — `pickMultiImage`, web and desktop support — <https://pub.dev/packages/image_picker>
- `[image_picker]` `limit` is not always supported — <https://github.com/flutter/flutter/issues/147773>
- Keto restaurant ordering scripts (the swap vocabulary the prompt encodes) — <https://www.mysweetketo.com/keto-restaurant-ordering-scripts/>
- How to stick to keto at restaurants — hidden carbs in sauces, glazes, breading — <https://ketodietdeli.com/how-to-stick-to-keto-at-restaurants-essential-ordering-tips/>
