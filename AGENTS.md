# AGENTS.md

Licensing policy lives in README. This file is working rules and toolchain traps.

## What this repo is

The native iOS client, in two deliberately separated halves:

| Half | What it is | Verified by |
|---|---|---|
| `PocketNutritionCore` | SwiftPM library, Foundation only. The behavioural contract shared with the web client and Android. | CI, on Linux, every push |
| The app target | SwiftUI. Screens, navigation, design tokens. | A human, on a Mac |

Today the core exists and asserts the `rounding` suite. There is no app target yet.

## The rules that matter most here

- **`roundHalfUp`, never `value.rounded()`.** Swift's default rule happens to agree, which is exactly
  why this is easy to "simplify" and lose. Kotlin's `kotlin.math.round` breaks ties towards even, so the
  contract pins `floor(x + 0.5)` and no platform's idea of "round" gets a vote. Substituting
  `.rounded(.toNearestOrEven)` fails three named vectors — try it before assuming the suite is
  decorative.
- **Never invent food data.** No label→cooking-method table, no label→portion-weight table, no default
  weight when the server omits one. The web sandbox had exactly those tables and they were deleted for
  this reason. When the API supplies no portion or no eating state, the correct behaviour is to **skip
  the item and say so**. A missing food is a gap to fill in `pocket-nutrition/knowledge`.
- **`measuredState` is load-bearing.** It records whether a quantity is a raw or a cooked weight. Get it
  wrong and every nutrition number is off by the yield factor. A recipe's component weight is always a
  pre-cooking weight.
- **`contract/` is vendored. Never hand-edit anything in it.** Change it upstream in
  `pocket-nutrition/contracts`, tag, bump `CONTRACTS_VERSION`, then run
  `./scripts/sync-contracts.sh --update`. CI verifies this and fails on a hand edit.

## Four things about this package that look wrong and are not

1. **`contract/swift/Tokens.swift` is not a package target.** It `import SwiftUI`, so adding it to
   `PocketNutritionCore` would make the package unbuildable on Linux — and take the behavioural corpus
   out of CI with it, which is the coverage this split exists to protect. The Xcode app target compiles
   it instead.
2. **The corpus is loaded via `#filePath`, not as a SwiftPM resource.** A resource must live inside the
   test target's own directory, which would mean a second copy outside `contract/` and would defeat the
   byte-for-byte `--verify`. The trade-off is that these tests must run from a source checkout, which is
   where they run.
3. **The corpus reader coerces numbers by hand** (`VectorCorpus.double` / `.int`) instead of casting.
   JSON does not distinguish `64` from `64.0`, and bridging an integer-valued `NSNumber` to `Double`
   works on Apple's Foundation but is not guaranteed on swift-corelibs-foundation. `rounding` holds both
   `0.5` and `64`, so a bare `as? Double` would pass locally and fail only on Linux — where CI runs.
4. **Warnings-as-errors is not in `Package.swift`.** `treatAllWarnings(as: .error)` is the obvious home
   for it and it makes the app target fail outright: Xcode compiles SwiftPM dependencies with
   `-suppress-warnings`, and the two options conflict —
   `error: conflicting options '-warnings-as-errors' and '-suppress-warnings'`. The package builds fine
   standalone, so this only appears once an Xcode project consumes it. The gate lives in CI instead, as
   `swift build -Xswiftc -warnings-as-errors`.

## Allowed without approval

- Porting a function from the sandbox **together with** its vector-suite assertions.
- Adding screens or tests.
- Bumping `CONTRACTS_VERSION` and re-running `--update` for an additive contracts release.

## Requires approval

- **Adding any dependency.** The package has none, and Foundation-only is what keeps it Linux-testable.
- **Adding an Apple-only import to `PocketNutritionCore`** — it silently removes the target from CI.
- **Relaxing `treatAllWarnings(as: .error)`.**
- **Raising or lowering the iOS deployment target.**
- **A major `CONTRACTS_VERSION` bump**, which means a breaking contract change.

## Do not copy code in from the wrong tier

See README for the full two-tier rationale. Operationally:

- **Never copy from an AGPL backend repo** (`pocket-nutrition/api`, `pocket-nutrition/ml`,
  `pocket-nutrition/ingest`, `pocket-nutrition/community`, `pocket-nutrition/data`,
  `pocket-nutrition/knowledge`). That would put AGPL code in a shipped binary and re-impose the
  §10 conflict that makes App Store distribution impossible. Copying in the other direction is fine.
- **Never copy from a GPL-licensed reference implementation.** It cannot be relicensed as MPL-2.0,
  and its §10 would re-break App Store distribution. Treat it as a **behavioural specification
  only**: reading it and describing what it does in prose is permitted; translating its code to
  Swift is a derivative work.
- Header every new source file with `SPDX-License-Identifier: MPL-2.0` (Exhibit A), never Exhibit B.

## Signing

- `*.p12`, `*.cer`, `*.mobileprovision` and `AuthKey_*.p8` are gitignored from the first commit.
  **Never commit one, never paste one into a file, never echo one into a log.** A committed certificate
  or API key is a compromised credential: it must be revoked and reissued, not merely deleted from the
  tree.
- `AuthKey_*.p8` is the App Store Connect API key. It is issued once, cannot be re-downloaded, and
  grants upload rights to the whole account.
- Only the maintainer creates signing identities. An agent must never create one, because the
  credentials would then exist in a transcript. This mirrors the keystore rule in `pocket-nutrition/android`.

## CI notes

CI lives in `.github/workflows/ci.yml` and has three gates: `./scripts/sync-contracts.sh --verify`,
`swift build`/`swift test` on `PocketNutritionCore` on Linux (in the official `swift` image, which already
ships `node` for the checkout action), and an unsigned simulator build of the app target on macOS.

The Linux job cannot build the app: SwiftUI and the iOS SDK are Apple-only. That is why the core stays a
separate package, and why Apple-only imports must never be added to it.

## Environment notes

The core can be built exactly as CI does, without Swift on the host:

```bash
docker build -t pn-ci-swift:local .ci
docker run --rm -v "$PWD":/w -w /w pn-ci-swift:local \
  swift test -Xswiftc -warnings-as-errors
```

`.ci/Dockerfile` pins Swift 6.3.3, the version the package was developed against, so a local result and
a CI result mean the same thing.

### The app target needs an Xcode platform component

Building the app by **target** used to work with only the SDK present, but no longer does: a `-target`
build cannot resolve the Sodium package product that `PocketNutritionVault` depends on. Build by scheme:

```bash
xcodebuild -project PocketNutrition.xcodeproj -scheme PocketNutrition \
  -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Building or running by **scheme** needs a destination, and therefore the iOS platform
component installed (Xcode → Settings → Components). Without it every scheme build fails with

```
error: Unable to find a destination matching the provided destination specifier
       ... error: iOS 26.5 is not installed.
```

which names a destination problem rather than the missing component that causes it. This is a
several-gigabyte download and is not something to trigger on someone's machine unasked.

CI uses the generic simulator destination (`generic/platform=iOS Simulator`), which compiles without
booting or choosing a particular simulator.
