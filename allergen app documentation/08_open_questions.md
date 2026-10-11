# 08 — Open questions

> **Answers received 2026-10-11** from the product owner are recorded
> inline as **Answer:** lines. Unanswered questions stay open.

## From the source research (part 5)

1. Do existing KetoClub users already have other restrictions — how many,
   which, and how many are paying?
   **Answer: there are no users yet.** The core assumption (how many people
   carry 2+ restrictions) cannot be read from an installed base; it has to
   be validated from onboarding data after launch and from interviews
   before it.
2. Start with level A (anaphylaxis) despite its legal risk, or launch with
   B–D and add A later?
   **Answer: not yet decided** (the question needed rephrasing; see the
   plain-language version in `09_conclusions.md` D-b). The epic assumes
   "build for A from day one, behind the consent and helper-tool wording".
3. Which first market: Israel (pilot, Hebrew, small), the UK or EU
   (regulation on our side), or the US (largest, most competitive)?
   **Answer: Israel and the United States.** Consequences: the home
   taxonomy is the EU 14 (Israel's 2028 list) ∪ US 9 — already the
   first-release scope; US-regulated-only sesame and the US-unregulated
   mustard, celery, lupin, molluscs are both in it; trip mode (ALG-13)
   drops in priority because both markets are home markets.
4. Inference cost per scan with Gemini — does it fit a $4–8 price?
5. Is there access to a dietitian or allergist to build the test set and
   validate the taxonomy?
   **Answer: no — use published sources from the internet instead.**
   Files `11_hidden_allergen_sources.md` and
   `12_israeli_and_us_menu_lexicon.md` are that research: every
   vocabulary entry must cite one of their sources. The ALG-10 gate is a
   regression tool, not a clinical claim, until a reviewer exists.
6. B2B — a consumer product only, or restaurants too, and when?
   **Open.**
7. Which privacy posture (cloud processing or on-device), and are there EU
   users?
8. Can the current version's tests be turned into the evaluation set?

## Added by this documentation pass (see `09_conclusions.md`)

9. **Verdict vocabulary.** Keep three wire verdicts and derive "ask" from
   per-restriction concerns (least invasive), or add a fourth wire verdict
   (cleanest for the UI, touches the cache, the Python port and the
   goldens)? The epic recommends the first.
10. **Where the profile lives.** On the device only (today's posture for
    every setting), or also on the backend to enable group profiles and
    history across devices (health data, consent, account system that does
    not exist)?
11. **Does Wolt's `dietary_preferences` field actually carry values in
    Israel?** The only real fixture has it empty on every item.
12. **Who owns the allergen vocabulary's correctness?** Every trigger is a
    safety claim; the keto vocabulary had one author and a golden corpus.
    An allergen vocabulary needs a clinical reviewer or a published source
    per entry.
13. **Name and brand.** Rename, or ship an "allergens" mode inside
    KetoClub first and decide after the pilot?
    **Answer: a rename is planned; the name is not decided.** The epic
    keeps every code identifier and wire name (`nonKeto`, `ketoScore`,
    the `keto*` constants) and changes UI copy only, so the rename is a
    branding and store-listing task, not an engine task.
14. **Keto users' experience.** When the profile has only "keto", the app
    must look and behave exactly as today; is a regression suite for that
    promise enough, or does keto need to stay a separate mode?

## Decided alongside

- The epic becomes GitHub issues: one parent epic issue with 18 sub-issues
  (one per ALG feature). The milestone `Phase 9: Allergens` still has to
  be created by hand — this session had no token for milestone creation.
