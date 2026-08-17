# Contributing

Thanks for looking at this. Two things before anything else:

- Read the **Licence** section of `README.md`. This repo is MPL-2.0, deliberately, and there are hard
  rules about what may and may not be copied in from where.
- Read `AGENTS.md`. It has the toolchain traps that have already cost time once each — rounding,
  the vendored `contract/` tree, and why the app target isn't gated by CI.

## Prerequisites

- **Swift 6.3.3** to match CI exactly (`.ci/Dockerfile` pins this version). Check with `swift --version`;
  a different Swift 6.x will usually still run the suite, but a mismatch is the first thing to rule out
  if a test disagrees with CI.
- **Xcode**, with the iOS platform component installed (Xcode → Settings → Components), only if you're
  building or running the app target on a device or in the simulator by scheme. Building by `-target`
  only needs the SDK — see below.
- Docker, optionally, to run the exact CI image locally without installing Swift on the host.

## First-time setup

```bash
git clone https://github.com/pocket-nutrition/ios.git
cd ios

# Per-developer signing team — required before any Xcode build, not before swift test.
cp Local.xcconfig.example Local.xcconfig
# then edit Local.xcconfig and set DEVELOPMENT_TEAM to your own team id
# (Xcode → Settings → Accounts → your Apple ID → Team ID column, or:
#  security find-identity -v -p codesigning)
```

`Local.xcconfig` is gitignored and wired as the base configuration for both Debug and Release. Skipping
this step is not "optional but slower" — every Xcode build stops before compiling with `error: Unable to
open base configuration reference file .../Local.xcconfig`. `swift test` never touches Xcode and is
unaffected either way.

## Build and test

```bash
# The shared core — exactly what CI runs. This is the suite that matters for most changes.
swift test -Xswiftc -warnings-as-errors

# The contract has not drifted from its pin in CONTRACTS_VERSION.
./scripts/sync-contracts.sh --verify

# The app target, compile-only, no signing or destination needed.
xcodebuild -project PocketNutrition.xcodeproj -target PocketNutrition \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Without installing Swift locally, the same core build/test runs in the CI image:

```bash
docker build -t pn-ci-swift:local .ci
docker run --rm -v "$PWD":/w -w /w pn-ci-swift:local \
  swift test -Xswiftc -warnings-as-errors
```

Running on a physical device (provisioning, trusting the developer certificate, `devicectl` install)
is documented in full in `README.md` under "Running it on a device" — it isn't repeated here.

## The `contract/` directory

`contract/` is **vendored, not hand-edited.** It's a pinned snapshot of `pocket-nutrition/contracts`
(design tokens, the OpenAPI schema, French strings, and the shared behavioural vector corpus),
copied in byte-for-byte by `scripts/sync-contracts.sh`. Android vendors the same artefacts
independently — the two clients stay behaviourally identical without sharing runtime code.

- To change anything under `contract/`: change it **upstream**, in `pocket-nutrition/contracts`, tag a
  release there, bump `CONTRACTS_VERSION` in this repo, then run `./scripts/sync-contracts.sh --update`
  and commit the result.
- `./scripts/sync-contracts.sh --verify` checks the tree is byte-identical to what `CONTRACTS_VERSION`
  pins. CI runs this and fails on any hand edit — don't try to patch a file under `contract/` directly.
- A stray `VENDORED` stamp file at the root of `contract/` names the pinned version it came from.

## What's allowed without asking first

- Porting a function from the web sandbox, **together with** the vector-suite assertions that pin its
  behaviour.
- Adding screens or tests.
- Bumping `CONTRACTS_VERSION` and re-running `--update` for an additive (non-breaking) contracts release.

## What needs a maintainer's sign-off first

- Adding any dependency to `PocketNutritionCore` (currently zero — that's what keeps it Linux-testable).
- Adding an Apple-only import (`SwiftUI`, `UIKit`, ...) to `PocketNutritionCore` — it silently drops the
  target from CI.
- Relaxing `treatAllWarnings(as: .error)` anywhere in CI.
- Raising or lowering the iOS deployment target.
- A major `CONTRACTS_VERSION` bump (a breaking contract change).
- Creating signing identities, certificates, or App Store Connect API keys. Only the maintainer does
  this — see `AGENTS.md` → Signing.

## Code style

- `roundHalfUp`, never `value.rounded()` or `.rounded(.toNearestOrEven)` — see `AGENTS.md` for why the
  contract pins a specific rounding rule and which vectors catch a regression.
- No invented food data: no label→cooking-method table, no label→portion-weight table, no default
  weight when the server omits one. If the API supplies no portion or no eating state, skip the item —
  a missing food is a gap to fill in `pocket-nutrition/knowledge`, not something to guess at client-side.
- `measuredState` (raw vs. cooked weight) must be threaded through correctly; getting it wrong throws
  every nutrition number off by the yield factor.
- Header every new source file with `// SPDX-License-Identifier: MPL-2.0` — never attach Exhibit B.

## Pull request process

1. Fork the repo and create a branch off `main` named for the change (`fix/...`, `feat/...`).
2. Make your change. If it touches `PocketNutritionCore`, add or update the corresponding vector-suite
   test under `Tests/PocketNutritionCoreTests/` — behaviour without a pinned test isn't considered
   verified.
3. Run locally before opening the PR:
   ```bash
   swift test -Xswiftc -warnings-as-errors
   ./scripts/sync-contracts.sh --verify
   ```
4. Commit with a clear, imperative message (`fix: correct yield factor for grilled chicken`, not
   `updates`). Keep commits focused — one logical change per commit.
5. Open a PR against `main` describing what changed and why. Link any related issue.
6. CI must be green (the `swift test` suite on Linux). CI cannot build or test the app target — SwiftUI
   and the iOS SDK are Apple-only and there is deliberately no macOS runner — so app-target changes are
   verified by a human, on a Mac, before merge.

## Reporting issues

Use the GitHub issue templates under `.github/ISSUE_TEMPLATE/`. For a bug, include the device model,
iOS version, and app version/build — the templates prompt for these. For anything that looks like it
might be a security issue (signing material, leaked credentials, an API key in a log), do not open a
public issue — contact the maintainer directly instead.
