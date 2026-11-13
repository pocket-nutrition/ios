# iOS client

Native iOS client for Pocket Nutrition. Behavioural twin of `pocket-nutrition/android`: both
vendor a tagged snapshot of `pocket-nutrition/contracts` and must behave identically without
sharing runtime code.

- API: <https://api.pocketnutrition.org>
- Organisation: <https://github.com/pocket-nutrition>

> **Status: a working meal-logging app, short of store paperwork.** `PocketNutritionCore` asserts the
> shared behavioural corpus — **all 17 suites, 144 of 144 cases** — and is verified by CI on Linux. The
> app target compiles, runs on a physical device, and searches, analyses and keeps a meal against the
> live API. The portion ladder is built, so quantities are no longer plain grams.
>
> `AboutView` carries the licence, the Open Food Facts attribution and the privacy summary, and
> `TokenGalleryView` is now compiled out of a Release build entirely — the whole file is behind
> `#if DEBUG`, verified by `strings` on the Release binary rather than assumed.
>
> Left to do before a submission, and each is paperwork rather than a feature: a designed app icon (the
> committed mark is provisional — a leaf generated from the brand tokens, matching Android's), and the
> privacy-policy URL actually being served — the page exists in `pocket-nutrition/website` but that
> repo's deployed image predates it, so the URL currently returns the home page with a 200. There are
> no UI tests, and the shared scheme runs no tests under ⌘U because the 61 of them live in the SwiftPM
> package rather than an Xcode test target — `swift test` is the only path that executes them.

## Layout

| Part | What it is | Verified by |
|---|---|---|
| `Sources/PocketNutritionCore` | SwiftPM library, Foundation only. The behavioural contract shared with the web client and Android. | CI, on Linux, every push |
| `App/` + `PocketNutrition.xcodeproj` | SwiftUI app target. Also compiles the vendored design tokens. | A human, on a Mac |
| `contract/` | Vendored from `pocket-nutrition/contracts`. Never hand-edited. | `scripts/sync-contracts.sh --verify` |

## Build and test

```bash
# The shared core — exactly what CI runs.
swift test -Xswiftc -warnings-as-errors

# The contract has not drifted from its pin.
./scripts/sync-contracts.sh --verify

# The app target, unsigned. It has to be a scheme build: `-target` cannot resolve the Sodium package
# product that PocketNutritionVault depends on. A scheme build needs the iOS platform component.
xcodebuild -project PocketNutrition.xcodeproj -scheme PocketNutrition \
  -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

### Running it on a device

Two prerequisites, and each one fails in a way that names something other than itself.

**The iOS platform component** (Xcode → Settings → Components) is several gigabytes and is not part
of the Xcode download. Without it every scheme or device build fails with
`Unable to find a destination matching...`, which reads as a destination problem rather than the
missing component behind it.

**A signing team.** `DEVELOPMENT_TEAM` is deliberately absent from `project.pbxproj` so the checkout
stays clean for anyone; it comes from a gitignored `Local.xcconfig` instead, wired as the base
configuration for both Debug and Release. It has to be absent for that to work: a project-level build
setting overrides the project's base `.xcconfig`, so a committed team id would silently win over yours.
It had drifted back in at some point and was removed again — if you find yourself adding one, put it in
`Local.xcconfig`.

```bash
cp Local.xcconfig.example Local.xcconfig   # then set your own team id
```

This step is not optional. Skip it and every Xcode build stops before compiling with
`error: Unable to open base configuration reference file .../Local.xcconfig` — a missing base
configuration is a hard error, not a warning. That is the intended trade: a fresh clone refuses to
build until its owner names a team, rather than quietly attempting to sign as somebody else. The
error names the missing path, and the template sits beside it. `swift test` is unaffected — the
package does not go through Xcode.

A free Apple ID signs 7-day builds onto your own device, capped at three apps; the Apple Developer
Program is needed only for TestFlight and the App Store.

With both in place, open the project, select the device, ⌘R.

#### Installing from the command line

```bash
DEVICE=$(xcrun devicectl list devices | awk '/connected/ {print $3; exit}')

# -allowProvisioningUpdates is not optional here, and its absence names the wrong thing:
# "No profiles for 'org.pocketnutrition' were found ... Automatic signing is disabled".
# It reads as a project misconfiguration; it usually just means the last free 7-day profile lapsed
# and a new one has to be minted.
xcodebuild -scheme PocketNutrition -destination "id=$DEVICE" \
  -configuration Debug -allowProvisioningUpdates build

APP=$(xcodebuild -scheme PocketNutrition -destination "id=$DEVICE" -configuration Debug \
  -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR/{print $2; exit}')/PocketNutrition.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" org.pocketnutrition
```

#### Trusting the developer, which is not a one-time step

The launch above fails, on a fresh profile, with

```
Unable to launch org.pocketnutrition because it has an invalid code signature, inadequate
entitlements or its profile has not been explicitly trusted by the user.
```

Three things about this, each of which has cost time:

1. **It recurs.** Not just the first ever launch — **every time the profile is regenerated**, which for a
   free Apple ID is at least every 7 days. Trust is granted to a certificate/profile pair, and a newly
   minted profile inherits nothing from the one it replaced.
2. **Settings shows nothing until you try to open the app from the home screen.** The entry under
   *Settings → General → VPN & Device Management → Developer App* is created by the "Untrusted
   Developer" alert, and `devicectl` launching the app does not raise that alert. Going to Settings
   first — the obvious order — finds an empty page and reads as though something is broken.
3. **The device must be unlocked.** A locked phone refuses both the developer-disk-image mount and the
   launch, and reports the mount failure as `kAMDMobileImageMounterDeviceLocked` — which at least names
   itself, unlike the launch error.

So: unlock, tap the icon, dismiss the alert, trust the certificate in Settings, tap again.

Before blaming signing, check the profile actually covers the device:

```bash
# The UDID here must appear in ProvisionedDevices below, and ExpirationDate must be in the future.
xcrun devicectl device info details --device "$DEVICE" | grep udid
security cms -D -i "$APP/embedded.mobileprovision" | plutil -p - | grep -A3 -E "ProvisionedDevices|ExpirationDate"
```

```bash
# Compiles against the device SDK without needing a signing identity at all — the fastest way to
# tell a code problem apart from a signing one.
xcodebuild -project PocketNutrition.xcodeproj -scheme PocketNutrition \
  -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

CI builds the app too, on a macOS runner (for the simulator, unsigned). The core is still a separate,
dependency-free package so that the rules that must not drift across three clients are also tested on
Linux, where the SwiftUI app cannot build. CI produces no installable binary: archiving and signing
stay a manual step on a Mac.

## Contributing

See `CONTRIBUTING.md` for the first-time setup (including the `Local.xcconfig` signing step), the
full build/test commands, what's allowed without asking versus what needs a maintainer's sign-off, and
the PR process. Bug and feature templates live under `.github/ISSUE_TEMPLATE/`.

## Acknowledgments

This app was inspired by the excellent [OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker).
Trying to improve on its interface and
support ingredients we curate ourselves is what led to building a dedicated API and backend for
this app, rather than tracking nutrition entirely on-device.

## Licence

MPL-2.0 — see `LICENSE`.

Pocket Nutrition uses two tiers: the backend (`api`, `ml`, `ingest`, `community`, `data`,
`knowledge`) is AGPL-3.0-or-later; the client chain (`contracts`, `android`, **this repo**) is
MPL-2.0, because AGPL's terms conflict with the App Store's distribution terms and MPL-2.0's don't.

### Rules for contributors

- Header every new source file with `SPDX-License-Identifier: MPL-2.0` (Exhibit A).
- **Never attach Exhibit B** ("Incompatible With Secondary Licenses"). It would make this code
  un-combinable with the AGPL backend repos.
- Never copy code from an AGPL backend repo into this one — it would put AGPL code in a shipped
  binary and re-break App Store distribution. Copying the other direction is fine.
- Never copy from a GPL-licensed reference implementation: it cannot be relicensed as MPL-2.0, and
  its §10 would re-impose the App Store problem. Treat it as a **behavioural specification only** —
  reading it and describing what it does in prose is permitted; translating its code to Swift is a
  derivative work.
