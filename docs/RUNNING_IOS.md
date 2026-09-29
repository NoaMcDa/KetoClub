# Running KetoClub on iOS

The iOS-specific steps: a simulator, a physical iPhone, and turning on AI
analysis with your own Gemini key. `docs/RUNNING.md` covers everything that is the same
on every platform (the backend itself, the test gate, the recordings).

**Nobody has run this app on a real iPhone yet** (`CLAUDE.md`, "What is NOT
verified yet"). CI only proves `flutter build ios --release --no-codesign`
compiles. The first device run is the one that finds what a simulator cannot:
the location permission prompt, the Waiter Card's screen-brightness raise, the
share sheet, and opening a Wolt link in the Wolt app.

## What you need

| | |
|---|---|
| A Mac | Xcode does not run anywhere else |
| Xcode | current release from the App Store; open it once and accept the licence |
| Command-line tools | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| CocoaPods | `sudo gem install cocoapods` (or `brew install cocoapods`) — the plugins need it; `ios/Podfile` is generated on the first build, it is not committed |
| Flutter | **3.47.4** — `flutter --version`; `flutter doctor` must show Xcode and CocoaPods green |
| An Apple ID | free is enough for a personal device; a paid developer account only for TestFlight/App Store |

Facts about the project you will meet in Xcode:

- Bundle identifier `club.keto.app` (tests: `club.keto.app.RunnerTests`).
- Deployment target **iOS 15.0**.
- Display name **KetoClub**.
- `Info.plist` already declares `NSLocationWhenInUseUsageDescription`
  (English inline as the default). Hebrew and English localised strings
  live under `ios/Runner/en.lproj/InfoPlist.strings` and
  `ios/Runner/he.lproj/InfoPlist.strings` (issue #169) — see "iOS Hebrew
  permission string" below for how to register them with the pbxproj on
  your first Xcode open. `LSApplicationQueriesSchemes` supplies the
  scheme "Open on Wolt/10bis" needs. No background location, no camera,
  no photo library.

## 1. Simulator

```bash
git clone https://github.com/NoaMcDa/KetoClub.git && cd KetoClub
flutter pub get
open -a Simulator            # or: xcrun simctl boot "iPhone 16"
flutter devices              # note the simulator id
flutter run -d <simulator-id>
```

The first `flutter run` takes several minutes: it runs `pod install` and a
full Xcode build. Hot reload (`r` in the terminal) works from then on.

What a simulator can and cannot show you:

| Works | Does not |
|---|---|
| Every screen, both languages (Settings → Language), light/dark (Settings → Appearance) | Screen brightness (no backlight; the Waiter Card's raise is a no-op) |
| Wolt and 10bis menus fetched directly — no backend needed, no CORS on native | The location prompt is real, but the position is whatever *Features → Location* in the Simulator menu says (set "Custom Location…" to 32.07, 34.77 for Tel Aviv) |
| Share sheet (simulator has a limited set of targets) | Opening the Wolt app (not installed on a simulator; the link falls back to Safari) |
| AI analysis, with your own Gemini key (§3) | Performance numbers for `docs/RELEASE.md` §5 — measure on a device |

## 2. A physical iPhone

1. Plug the phone in (or pair over Wi-Fi in Xcode → Window → Devices and
   Simulators). On the phone, trust the computer.
2. Signing, once: `open ios/Runner.xcworkspace`, select the **Runner** target →
   **Signing & Capabilities** → tick *Automatically manage signing* → choose
   your Team (your Apple ID). With a free Apple ID Xcode may ask you to change
   the bundle id to something unique; if so, change it there — nothing in the
   Dart code depends on it.
3. `flutter run -d <device-id>` (the id is in `flutter devices`; a release
   build for timing is `flutter run --release -d <device-id>`).
4. First launch only: the phone refuses an untrusted developer. Settings →
   General → VPN & Device Management → your Apple ID → Trust.

A free Apple ID's provisioning profile expires after 7 days; run from Xcode or
`flutter run` again to renew it.

The location permission prompt appears the first time you tap the location
button on the Discovery tab — never on launch. Deny it once to see the
"Type a name instead" path; deny with "Don't Allow" and check that the
permanent-denial state offers Open Settings (once PR `claude/location-settings-phototile`
is merged).

## 3. AI analysis on the phone

The phone calls Wolt and Google's Gemini API itself and never talks to
KetoClub's backend (`architecture.md` D17), so there is nothing to run on the
Mac and no App Transport Security exception to add: every host it calls is
`https://`.

1. Create a free API key in [Google AI Studio](https://aistudio.google.com/apikey).
2. In the app open **Settings**, paste it under **Gemini API key**, and tap
   **Save key**. It is kept in the iOS Keychain and sent only to Google.
3. AI analysis is on by default (D16), so leave **Allow AI analysis** ticked,
   open a menu, and the engine chip should read "AI" instead of "rules".

Without a key the menu still opens with rule-based verdicts, and the banner
says to add a key, with a shortcut to Settings.

## 4. Builds

```bash
flutter build ios --release --no-codesign   # what CI runs; proves it compiles
flutter build ipa                            # signed archive for TestFlight; needs a paid account
```

An iOS build needs no `--dart-define`: `KETOCLUB_BACKEND_URL` is read only by
the web build (D17). The Gemini key is never compiled in; each user pastes
their own in Settings.

## iOS Hebrew permission string

`ios/Runner/{en,he}.lproj/InfoPlist.strings` translate the location
permission prompt (issue #169). The files exist on disk, but the
Runner Xcode project needs them added to its resources for iOS to
discover them at runtime — pbxproj edits from outside Xcode risk
corrupting the project file. Once, on your Mac:

1. `open ios/Runner.xcworkspace`
2. Select the **Runner** target in the sidebar.
3. In the file navigator, right-click **Runner** → **Add Files to
   "Runner"…** → select both `ios/Runner/en.lproj/InfoPlist.strings`
   and `ios/Runner/he.lproj/InfoPlist.strings`. Xcode will detect the
   `.lproj` naming and offer to combine them into an `InfoPlist.strings`
   variant group; accept.
4. In **Build Phases** → **Copy Bundle Resources**, verify that the new
   `InfoPlist.strings` (with the disclosure triangle showing both
   locales) is present.
5. Commit the resulting `ios/Runner.xcodeproj/project.pbxproj` diff.

Until step 5 has happened, Info.plist's inline English string is what
iOS renders on any locale. After step 5, iOS reads the matching
`InfoPlist.strings` per locale (Hebrew phone → Hebrew prompt).

## 5. What to check on the first device run

The device matrix in `docs/RELEASE.md` is the full list; the items no
simulator can answer:

- Location prompt wording and the approximate/precise choice on iOS 15+.
- Waiter Card raises screen brightness and restores it on close.
- Share sheet exports the text summary to Messages/Notes.
- "Open on Wolt" opens the Wolt app when installed.
- Hebrew: RTL layout, and the location prompt is still English (known).
- Time from tapping a card to a classified menu on 4G, for `docs/RELEASE.md` §5.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `CocoaPods not installed` / `pod install` fails | install CocoaPods (table above), then `cd ios && pod install --repo-update` |
| `Signing for "Runner" requires a development team` | §2 step 2 |
| "Untrusted Developer" on launch | §2 step 4 |
| Build fails after switching Flutter versions | `flutter clean && rm -rf ios/Pods ios/Podfile.lock && flutter pub get && flutter run` |
| `backendUnreachable` on a device, fine on a simulator | ATS — §3; or the Mac firewall, or `--host 0.0.0.0` missing |
| Location button does nothing | permission denied permanently: Settings → KetoClub → Location → While Using |
| `flutter devices` does not list the phone | unlock it, tap Trust, `sudo xcode-select` to the right Xcode, Xcode → Devices shows it |
