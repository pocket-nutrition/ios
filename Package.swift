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
// PocketNutritionVault is the exception to "no dependencies": the vault protocol needs Argon2id,
// XChaCha20-Poly1305 and sealed boxes, none of which Apple ships. It depends on swift-sodium (libsodium),
// and is declared ONLY when this manifest is read on a Mac. Swift-sodium's libsodium is a prebuilt Apple
// binary, so on Linux the target would not build and would take PocketNutritionCore's CI down with it.
// Declaring it behind `#if os(macOS)` keeps Linux CI building and testing Core exactly as before, while
// `swift test` on a Mac also runs the vault's cross-language crypto vectors.
//
// Approved by the maintainer for this one purpose; do not widen it, and keep Core free of it.
var dependencies: [Package.Dependency] = []
var products: [Product] = [
    .library(name: "PocketNutritionCore", targets: ["PocketNutritionCore"])
]
var targets: [Target] = [
    .target(name: "PocketNutritionCore"),
    .testTarget(
        name: "PocketNutritionCoreTests",
        dependencies: ["PocketNutritionCore"]
    ),
]

#if os(macOS)
dependencies.append(.package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.9.1"))
products.append(.library(name: "PocketNutritionVault", targets: ["PocketNutritionVault"]))
targets += [
    .target(
        name: "PocketNutritionVault",
        dependencies: [
            "PocketNutritionCore",
            .product(name: "Sodium", package: "swift-sodium"),
            .product(name: "Clibsodium", package: "swift-sodium"),
        ]
    ),
    .testTarget(
        name: "PocketNutritionVaultTests",
        dependencies: ["PocketNutritionVault", "PocketNutritionCore"],
        exclude: ["README.md"],
        resources: [.copy("test-vectors.json")]
    ),
]
#endif

let package = Package(
    name: "PocketNutrition",
    platforms: [
        // Matches the app target. The library has no platform-specific code and also builds for
        // Linux, where this declaration is ignored.
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
