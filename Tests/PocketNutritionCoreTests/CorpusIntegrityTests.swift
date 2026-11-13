// SPDX-License-Identifier: MPL-2.0

import Testing

/// Structural checks over the whole vendored corpus, independent of whether Swift implements any given
/// suite yet.
///
/// **Every suite is implemented and asserted — 190 of 190 cases across 23 suites.** The counts are not
/// restated in the assertions below: those read `index.json`, so this comment is the only thing that can
/// go stale, and a suite added upstream without a port here fails `required` rather than this prose.
/// Six of the 23 (the `-en` siblings) are hand-authored rather than sandbox-generated — see
/// `vectors/README.md` — but are ported and asserted the same as every other suite.
///
/// This file therefore no longer covers for any gap. It still earns its place: it proves the corpus
/// arrived intact and matches `index.json`, which is what fails loudly if a half-finished
/// `sync-contracts.sh --update` leaves a truncated tree behind.
@Suite("corpus integrity")
struct CorpusIntegrityTests {

    /// Every suite, named explicitly so one disappearing upstream fails here rather than quietly
    /// reducing what this client is held to. A count check would not catch a rename.
    static let required = [
        "apply-method-change",
        "switch-measured-state",
        "build-anchors",
        "build-anchors-en",
        "build-meal-ingredient",
        "deduplicate-suggestions",
        "selection-mode",
        "describe-quantity",
        "describe-quantity-en",
        "english-number",
        "english-plural",
        "food-group-icon",
        "french-number",
        "french-plural",
        "rounding",
        "serving-unit-emoji",
        "shortcut-profile",
        "shortcut-profile-en",
        "step-label",
        "step-label-en",
        "step-raw-weight",
        "unpack-recipe",
        "yield-factor",
        "daily-targets",
        "weight-for-day",
        "profile-for-day",
        "apply-target-overrides",
        "day-progress",
        "self-comparison",
    ]

    @Test("every declared suite loads and matches its declared count")
    func everyDeclaredSuiteLoadsAndMatchesItsCount() throws {
        let index = try VectorCorpus.index()
        #expect(!index.suites.isEmpty, "index.json declares no suites")

        var problems: [String] = []
        var observed = 0

        for (name, declaredCount) in index.suites.sorted(by: { $0.key < $1.key }) {
            do {
                let suite = try VectorCorpus.load(name)
                observed += suite.cases.count
                if suite.name != name {
                    problems.append("\(name): suite field says '\(suite.name)'")
                }
                if suite.cases.count != declaredCount {
                    problems.append(
                        "\(name): index.json says \(declaredCount), file holds \(suite.cases.count)"
                    )
                }
                if suite.description.count < 40 {
                    problems.append("\(name): description too short to guide a port")
                }
            } catch {
                problems.append("\(name): failed to load — \(error)")
            }
        }

        #expect(problems == [], "suites that do not match index.json")
        #expect(
            observed == index.totalCases,
            "case counts across suites do not sum to index.json totalCases"
        )
    }

    @Test("case ids are unique within each suite")
    func caseIdsAreUniqueWithinEachSuite() throws {
        var duplicates: [String] = []
        for name in try VectorCorpus.index().suites.keys.sorted() {
            let ids = try VectorCorpus.load(name).cases.map(\.id)
            if Set(ids).count != ids.count {
                var counts: [String: Int] = [:]
                for id in ids { counts[id, default: 0] += 1 }
                let repeated = counts.filter { $0.value > 1 }.keys.sorted()
                duplicates.append("\(name): \(repeated.joined(separator: ", "))")
            }
        }
        #expect(duplicates == [], "duplicate case ids")
    }

    /// A rationale is what makes a failing vector actionable, so an empty or perfunctory `why` is a
    /// corpus defect. All offenders are collected: fixing them one failure at a time is miserable.
    @Test("every case carries a rationale long enough to be useful")
    func everyCaseCarriesAUsableRationale() throws {
        var thin: [String] = []
        for name in try VectorCorpus.index().suites.keys.sorted() {
            for testCase in try VectorCorpus.load(name).cases where testCase.why.count < 40 {
                thin.append("\(name)/\(testCase.id): \(testCase.why.count) chars")
            }
        }
        #expect(thin == [], "cases whose why is too short to explain the expectation")
    }

    @Test("the corpus covers the suites this client needs")
    func corpusCoversTheSuitesThisClientNeeds() throws {
        let present = try VectorCorpus.index().suites.keys
        let missing = Self.required.filter { !present.contains($0) }
        #expect(missing == [], "required suites absent from the vendored corpus")
    }
}
