# Keto-only baseline

These files are the keto-only app, byte for byte, as
`test/architecture/keto_unchanged_test.dart` rebuilds it from the real code
(issue #342; the allergen epic's first principle: a keto-only profile is
today's app). They are **outputs**, not recorded platform payloads.

| File | What it pins |
|---|---|
| `system_prompt_defaults.txt` | `MenuAnalysisPrompt.systemPrompt()` with default options |
| `system_prompt_all_rules_limit2.txt` | the same with all three keto toggles on and a 2 g limit, through `ClassificationOptions.fromSettings` |
| `vision_system_prompt_defaults_2_pages.txt` | `visionSystemPrompt(pageCount: 2)` with default options |
| `response_schema.json`, `vision_response_schema.json` | the two reply schemas |
| `options_snapshot_*.json` | `ClassificationOptions.snapshot.toJson()`, the cache-key material |
| `app_settings_defaults.json` | `const AppSettings().toJson()`, and the same with `copyWith(profile: DietaryProfile.empty)` (no `dietaryProfile` key) |
| `document_title.txt` | `documentTitle(null)`, whose `app` defaults to `BantoMode.appName`, in a build without `BANTO_MODE` |
| `rules_<menu>_<options>.json` | `HeuristicMenuClassifier` over the golden corpus's hand-built menus, without `analysedAt` |
| `copy_en.json`, `copy_he.json` | the verdict, tile and legend copy |
| `share_text_*.txt` | `MenuShareText.build` over the English and Hebrew golden menus |

The schema version, the keto score table and the English menu's verdict
counts are pinned inline in the test instead.

## No regeneration switch, on purpose

Unlike `test/golden/golden_drift_test.dart`, this test has **no**
`UPDATE_*` define and never writes a file. A drift must reach review as a
diff to one of these files, written by a person who meant it, never as a
regenerated one nobody read.

## Updating a fixture when a keto change is intended

1. Make the change and run
   `flutter test test/architecture/keto_unchanged_test.dart`.
2. The failure names the file and the first line that differs, with both
   versions.
3. Edit that file by hand to the new text, in the same pull request, and
   say in the pull request why the keto-only app changes.

Format, so a hand edit matches: plain UTF-8, LF line endings, and exactly
one trailing newline that is not part of the value. JSON files are
canonical: keys sorted at every depth, two-space indent, non-ASCII text
written as is (no `\u` escapes). A file with no matching check, or a check
with no file, fails the test's folder check.
