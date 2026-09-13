# M16 Structured Output — the Menu Analyzer failing on every input mode

## Summary

The Menu Analyzer failed on pasted text, photographed pages and PDFs alike, while the
Daily Intake description mode — which sends its text over the **same** `LlmChatClient`,
the same key and the same pinned model — kept working. Lengthening the request timeout
to two minutes (#429) changed nothing. The cause is not connectivity, the key, the
model id, OCR, or text sanitisation: **the menu request is the only request in the app
that asks for a strict `json_schema` response format**, and the gateway refuses that
request *before any model sees it*, with a 4xx that `OpenRouterClient._read` maps to
`badResponse` — which `MenuScannerScreen` words as "הניתוח נכשל".

Two changes fix it, each closing one of the two ways that refusal happens, and both
were made because this session could not reach `openrouter.ai` to learn which one the
pinned model trips (the same egress block `design/m16_menu_scanner_research.md` §10
recorded when the schema shape was first pinned from secondary sources):

1. **`OpenRouterClient.complete` now falls back once to `json_object`** when a
   `json_schema` request comes back 400, 404 or 422. `json_object` is exactly the shape
   M15's estimator is verified live with. The research document (§4.4, §6.4) always
   described the schema as a strong hint with `json_object` as the fallback — the
   fallback was simply never implemented.
2. **`MenuAnalysisPrompt.schema` is now valid under strict mode.** Every property is in
   `required`, both objects carry `additionalProperties: false`, and the two fields a
   dish may lack (`description`, `modification`) are typed `["string","null"]`. The
   prompt's rule 3 and a new rule 6 tell the model to send `null` there.

## Why the meal estimator worked and the menu did not

| | `RemoteMacroEstimator` (Daily Intake) | `RemoteMenuAnalyzer` (Menu) |
|---|---|---|
| Transport | `llmChatClientProvider` → `OpenRouterClient` | same |
| Key | `UserApiKeyCredentials` | same |
| Model | `nex-agi/nex-n2.5-pro:free` | same |
| `max_tokens` | provider default | 6000 |
| `response_format` | `{"type":"json_object"}` | `{"type":"json_schema","json_schema":{"strict":true,"schema":…}}` |

Everything the user varied — text, photo, PDF — converges on one `complete` call in
`RemoteMenuAnalyzer.analyse`, after OCR has already succeeded on the device. The three
modes failing identically is therefore expected from a fault at or below that call, and
the `response_format` row is the only one that differs from the request that works.

## How a strict `json_schema` request is refused

OpenRouter's `json_schema` response format is honoured only by endpoints that advertise
`structured_outputs` in `supported_parameters`; for a model whose endpoint does not, the
gateway answers with an error instead of routing the request. Separately, a schema sent
with `strict: true` is validated against the OpenAI strict-mode rules — every property
listed in `required`, `additionalProperties: false` on every object — and the original
menu schema broke both (two optional properties, open objects).

Either refusal shares the three symptoms reported:

- **Instant, not slow.** The request never reaches a model, so a longer timeout cannot
  help. `ChatFailureReason.timeout` would have read "אין חיבור לאינטרנט" in any case, and
  the user saw "הניתוח נכשל" — `badResponse`, a status the gateway sent.
- **Every input mode.** All three are the same call with different text.
- **Daily Intake unaffected.** Its request carries no schema.

`ChatFailed` deliberately carries no detail (`llm_chat_client.dart`: an upstream error
body can echo a request header), which is also why the symptom could not be told apart
from a retired model id or a network fault from the screen alone.

## The fix

### `OpenRouterClient.complete`

```dart
var response = await _post(token, _body(..., responseSchema: responseSchema));
if (responseSchema != null && rejectsRequestShape(response.statusCode)) {
  response = await _post(token, _body(..., responseSchema: null));
}
return _read(response);
```

`rejectsRequestShape` is exactly `400 || 404 || 422` — a malformed or unsupported
parameter, no endpoint able to serve the requested parameters, a body that parsed but
failed validation. It is **not** a general retry:

- 401/403/429 and 5xx are never re-sent. They are answers about the key, the quota and
  the provider, and a different `response_format` changes none of them; the class's
  "no retry on 429 against a 50-a-day quota" promise still holds.
- A request with no `responseSchema` is never re-sent, so M15 behaviour is unchanged.
- The fallback request differs from the first in `response_format` only: same
  prompts, model, `max_tokens`, temperature, bearer. Asserted in
  `test/core/services/llm/open_router_client_test.dart`.
- Each request gets the full timeout of its own. A refused shape comes back in well
  under a second, so the worst case is not in practice doubled.
- A 404 from a retired model id now costs one extra request that also 404s and still
  reads `badResponse`; neither request reaches a model, so neither spends quota.

### `MenuAnalysisPrompt.schema`

`MenuResponseParser` already treats `null` and absent identically (`rawX is String ?
rawX.trim() : ''`), so the contract above the seam is unchanged: a `modifiable` dish with
`modification: null` is still demoted to `unclassified` ("a yellow without an
instruction does not exist"), a green or red with `null` keeps its verdict, and a
`description: null` is a dish with no description. Those four cases are now tests.

## What was verified, and what was not

- `flutter analyze` clean, `dart format` clean, the full unit and widget suite green
  with the coverage gates passing (see the PR's CI run for the numbers).
- **Not verified live.** `openrouter.ai` is blocked from this session, so neither the
  pinned model's `supported_parameters` nor the gateway's exact error body could be
  read, and no real request was made. The fix is built to hold in both of the cases that
  produce the reported symptoms; the first real menu analysis after merge is the
  confirmation. If it still fails, the remaining candidate in the table above is
  `max_tokens: 6000` — try the same text through a build with
  `MenuVerdictRules.maxOutputTokens` lowered, and if that passes, the pinned endpoint's
  `max_completion_tokens` is below 6000.

## Lessons

- **A request shape a feature adds must be exercised live before it ships**, with the
  same rigour `design/m15_openrouter_models_fix.md` asks for model ids: the meal
  estimator's live verification did not cover `json_schema`, because the estimator never
  sends one.
- **A documented fallback is not a fallback until it is code.** §4.4 and §6.4 of the
  research document described `json_object` as the fallback from the start.
- **Failure reasons that carry no detail need a table like the one above somewhere.**
  Comparing the two requests field by field is what located this, and it is a two-minute
  exercise once written down.
