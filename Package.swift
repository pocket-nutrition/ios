// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0
//
// WARNINGS-AS-ERRORS IS NOT DECLARED HERE, AND MUST NOT BE.
//
// `treatAllWarnings(as: .error)` looks like the right home for it — android's equivalent lives in the
// build script — but Xcode compiles SwiftPM dependencies with `-suppress-warnings`, and the two cannot
// coexist:
//
//     error: conflicting options '-warnings-as-errors' and '-suppress-warnings'
//
// The package builds fine standalone and the app target fails outright, so declaring it here trades a
// working app for a stricter library. The gate lives in CI instead, as
// `swift build -Xswiftc -warnings-as-errors`, which is where it actually needs to hold.

import PackageDescription

// PocketNutritionCore deliberately depends on Foundation and nothing else — no SwiftUI, no UIKit.
//
// That is what lets this package build and test on Linux, in a container, in CI. The behavioural
// contract shared with the web client and Android lives here, so it is the part that most needs a
// gate on every push; the SwiftUI app target is built on a Mac and cannot be checked by CI at all.
// Keeping the two apart means the rules that must not drift are the ones that are actually verified.
//
// Adding an Apple-only import to this target silently removes it from CI. Platform code belongs in
// the app target instead.
//
// This is why the vendored `contract/swift/Tokens.swift` is NOT a target here: it `import SwiftUI`,
// because a colour token is only useful as a `Color`. The Xcode app project compiles that file
// directly. Adding it to this package would make the package unbuildable on Linux and take the
// behavioural corpus out of CI with it — the exact coverage this split exists to protect.
//
// The vendored JSON is not declared as a resource either. The tests locate it from `#filePath`, so
// `contract/` stays one tree that sync-contracts.sh owns byte-for-byte. The trade-off is that these
// tests must run from a source checkout, which is where they run: `swift test`, in CI and locally.
let package = Package(
    name: "PocketNutrition",
    platforms: [
        // Matches the app target. The library has no platform-specific code and also builds for
        // Linux, where this declaration is ignored.
        .iOS(.v17)
    ],
    products: [
        .library(name: "PocketNutritionCore", targets: ["PocketNutritionCore"])
    ],
    targets: [
        .target(name: "PocketNutritionCore"),
        .testTarget(
            name: "PocketNutritionCoreTests",
            dependencies: ["PocketNutritionCore"]
        )
    ]
)
