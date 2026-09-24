# Running KetoClub on iOS

The iOS-specific steps: a simulator, a physical iPhone, and talking to the
backend from the phone. `docs/RUNNING.md` covers everything that is the same
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
  (English only — Hebrew localisation of that string is still a follow-up)
  and the `LSApplicationQueriesSchemes` that "Open on Wolt/10bis" needs. No
  background location, no camera, no photo library.

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
| AI analysis, with the backend on the Mac (§3) | Performance numbers for `docs/RELEASE.md` §5 — measure on a device |

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

## 3. Talking to the backend from the phone

Native apps have no CORS, so menus and search work with no backend at all.
The backend adds **AI analysis** (it holds the Gemini key). Start it on the Mac
per `docs/RUNNING.md` §2, then point the phone at the Mac's LAN address, not
`localhost`:

```bash
ipconfig getifaddr en0      # the Mac's Wi-Fi address, e.g. 192.168.1.23
flutter run -d <device-id> --dart-define=KETOCLUB_BACKEND_URL=http://192.168.1.23:8000
```

Both must be on the same Wi-Fi, and the backend must listen on all interfaces:
`uv run uvicorn app.main:app --host 0.0.0.0 --port 8000`.

**App Transport Security.** iOS blocks plain `http://` to a LAN host unless
the app opts in. `Info.plist` does not currently carry an exception, so a LAN
backend over `http://` fails with `backendUnreachable` on a device (a
simulator is exempt). For a local test add, under the top-level `<dict>` of
`ios/Runner/Info.plist`, and do not ship it:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

Then Settings → allow AI analysis (consent is off by default), open a menu,
and the engine chip should read "AI" instead of "rules".

## 4. Builds

```bash
flutter build ios --release --no-codesign   # what CI runs; proves it compiles
flutter build ipa                            # signed archive for TestFlight; needs a paid account
```

Add `--dart-define=KETOCLUB_BACKEND_URL=…` to any build that should reach a
backend; there is no in-app setting for it. Whatever `.env` the backend runs
with stays on the Mac — the app never holds a model key.

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
