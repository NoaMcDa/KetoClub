# M15 OpenRouter Models — Issue #411 & #414

## Summary

M15 shipped with three free-tier OpenRouter model IDs that had all retired upstream within weeks. A user with a valid API key reported the estimation feature returning "אין חיבור אינטרנט" (no internet). The root cause was not the retired models alone — it was **timeout coupling in the error path**. The replacement model was chosen for JSON quality and existed, but it took 32 seconds to answer, exceeding the 30-second timeout and mapping to the identical offline error message. The fix pinned `nex-agi/nex-n2.5-pro:free` (8–12 s response time) and verified latency against the real system prompt, not a smoke test. The timeout was later increased to 2 minutes to accommodate slower models and network conditions.

## Issue #411 — Model Retirement

**What shipped:** Three :free model IDs on OpenRouter.
- `meta-llama/llama-3.2-11b-vision:free`
- `qwen/qwen2.5-vl-32b-instruct:free`
- `google/gemini-2.0-flash-exp:free`

**What went wrong:** Within weeks, all three had been delisted. A user with a valid API key got `ChatFailureReason.badResponse` (status 404), surfaced to the user as "אין חיבור אינטרנט".

**Why it went wrong:** Free model IDs on OpenRouter are not stable. The docstring in `open_router_client.dart` already named this risk — the fallback list exists for exactly this reason. Shipping without trying all three first cost the feature's usability for days.

## Issue #414 — The Timeout Trap

**What happened:** PR #412 replaced the three retired IDs with three candidates that existed.

**What went wrong:** The primary choice, `dots-studio/dots-3-note-preview:free`, produced cleaner JSON on test prompts but took **32 seconds to answer the real system prompt** in `MacroEstimationPrompt.system`. The timeout was then `Duration(seconds: 30)`. `RemoteMacroEstimator` maps `ChatFailureReason.timeout` to `EstimateFailureReason.offline` — line 120 — so a 32-second response surfaces identically to "אין חיבור אינטרנט". The timeout is now `Duration(seconds: 120)`, accommodating slower responses.

**Why it wasn't caught:** Testing was done with short prompts — "estimate the macros of this meal" — not the full system prompt the app actually sends. Latency is a **correctness property here**: a number the user can rely on and an indeterminate spinner are not the same failure, and both happen at `timeout`. The prompt that matters is the one the user hands the app, not a convenient short version.

## The Fix — PR #416

**Approach:** Measure every candidate model against `MacroEstimationPrompt.system`, the real system prompt. Accept only models that:
1. Support vision (photo mode is a requirement)
2. Return valid JSON in the required schema
3. Respond in under 20 seconds (6 s margin below timeout)

**Result:** `nex-agi/nex-n2.5-pro:free` — 8–12 s response time, valid JSON, vision-capable.

**Fallbacks remain:**
- `dots-studio/dots-3-note-preview:free` (cleaner JSON, 32 s)
- `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` (52 s)

Both are listed as documented alternatives for the day someone raises the timeout or the provider gets faster. They are not silent fallbacks — a 404 on the pinned one is a `badResponse`, never a crash, and choosing a different model is a product decision that needs a settings screen.

## Lessons

1. **Latency is a correctness property**, not a polish concern. Speed was the *only* reason to prefer this model over one with tidier JSON. `design/m15_meal_entry_research.md` records this trade: "Speed is a correctness property here."
2. **Test with the real artifact**, not a convenient proxy. A short prompt that runs in 2 s and a real prompt that runs in 32 s are different failures.
3. **Free-tier model IDs come and go.** The fallback list and the error mapping exist for this. Verify at ship time that what you committed exists.
4. **Timeout → offline is a lie when the timeout is too short.** A 32-second response is not offline; it is slow. The daily net-carb budget is 20 g, and a user who correctly estimated a meal only to see an indeterminate spinner would distrust the feature forever.

## Verification

- PR #416 passed all CI checks (9/9 jobs green).
- All three modes (manual, description, photo) route through the same `RemoteMacroEstimator` and use the same model.
- A user with a valid API key should now see the estimate within ~10 seconds rather than a network error.

## The bug neither issue fixed — #419

**Both of the above were real, and neither was what the user hit.** After #416 merged the
user reported the same `אין חיבור לאינטרנט` chip — **on web, instantly**. That rules out
both earlier diagnoses on their own evidence: a retired id answers 404, which maps to
`badResponse` and words as `ההערכה נכשלה`, and a 32-second model needs 32 seconds. The
reported failure takes one frame.

The cause was in the app's own provider wiring, and it had been there since M15 shipped:

1. `llmChatClientProvider` was autoDispose (the `@riverpod` default) and creates the
   `http.Client`, registering `ref.onDispose(client.close)`.
2. Every screen that estimates — both add-meal sheets, and M16's `MenuScannerScreen` —
   reaches its engine with a bare `ref.read(...)` in a button handler and holds **no**
   listener, because the result is awaited once rather than watched.
3. riverpod disposes an unlistened autoDispose provider after one frame. That cascaded to
   the client provider and ran `client.close()` **while the request was in flight**.
4. **Closing an `http.Client` cancels what it is carrying.** `BrowserClient.close` calls
   `abort()` on every open request's `AbortController`; the pending `fetch` rejects with an
   `AbortError`, which `package:http` rewraps as `RequestAbortedException extends
   ClientException`. On the VM, `IOClient.close` force-closes the socket.
5. `OpenRouterClient` maps **every** `ClientException` to `ChatFailureReason.offline`, and
   the sheet words that as "no internet".

Measured: **23 ms** in Chromium with the `fetch` aborted, **30 ms** on the VM with the
request never attempted. The fix is one annotation — `@Riverpod(keepAlive: true)` — and it
cures all three consumers at once, which is the argument for fixing the client provider
rather than the call sites.

### Lessons this one adds

5. **`curl` cannot reproduce a provider-graph bug.** #411 and #414 were both verified with
   `curl` against the real endpoint, which is why both concluded the transport was fine —
   it was. Nothing outside the app can exercise the app's own object lifetimes.
6. **A green suite proved nothing here, by construction.** `open_router_client_test.dart`
   builds `OpenRouterClient` directly, and both e2e flows override `macroEstimatorProvider`.
   No test had ever sent a request through the real provider graph, so the graph's disposal
   timing was never exercised. The regression tests added with the fix are the first that do.
7. **An error mapping that collapses distinct causes hides the cause.** Five different
   failures — no route, a torn socket, a timeout, an aborted request and a closed client —
   all arrive as `offline` and all read as "check your connection". Three separate
   investigations chased the network because the message named the network.

## Open

Issue #419 — the provider-lifecycle defect above. Issues #411 and #414 are closed by
PR #412 and PR #416; neither made the feature work for the reporting user.
