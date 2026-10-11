# 08 — Open questions

## From the source research (part 5)

1. Do existing KetoClub users already have other restrictions — how many,
   which, and how many are paying?
2. Start with level A (anaphylaxis) despite its legal risk, or launch with
   B–D and add A later?
3. Which first market: Israel (pilot, Hebrew, small), the UK or EU
   (regulation on our side), or the US (largest, most competitive)?
4. Inference cost per scan with Gemini — does it fit a $4–8 price?
5. Is there access to a dietitian or allergist to build the test set and
   validate the taxonomy?
6. B2B — a consumer product only, or restaurants too, and when?
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
14. **Keto users' experience.** When the profile has only "keto", the app
    must look and behave exactly as today; is a regression suite for that
    promise enough, or does keto need to stay a separate mode?
