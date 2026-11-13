// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

/// Asserts the daily-targets calculation against its six suites of the shared corpus (contracts 2.6.0):
/// `daily-targets`, `weight-for-day`, `profile-for-day`, `apply-target-overrides`, `day-progress` and
/// `self-comparison`.
///
/// Inputs and expectations are decoded into the Core types through `JSONDecoder`, then compared with
/// `==`. A symmetric decoding bug (a misspelled optional key read as nil on both sides) would hide a
/// difference, so every expected object is also checked key by key against the re-encoded value: a key
/// the corpus sets that the Swift type drops fails here.
@Suite("daily-targets vectors")
struct DailyTargetsVectorTests {

    // MARK: - Harness

    /// Loads a suite, checks its size against index.json, and returns its cases.
    private func cases(_ name: String) throws -> [VectorCorpus.Case] {
        let suite = try VectorCorpus.load(name)
        #expect(suite.cases.count == (try VectorCorpus.index().suites[name]), "\(name) case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the \(name) suite is empty")
        return suite.cases
    }

    /// Runs `body` on every case and proves none was skipped: each id must be reported back once.
    private func everyCase(_ name: String, _ body: (VectorCorpus.Case) throws -> Void) throws {
        let all = try cases(name)
        var asserted: [String] = []
        for c in all {
            try body(c)
            asserted.append(c.id)
        }
        #expect(asserted == all.map(\.id), "\(name): a case was skipped")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any?) throws -> T {
        let raw = try #require(value)
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// The JSON object an Encodable value turns into.
    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Keys with a non-null value, recursively, as dotted paths ("0.min", "targets.2.sources").
    private func keyPaths(_ value: Any, prefix: String = "") -> Set<String> {
        var out: Set<String> = []
        if let dict = value as? [String: Any] {
            for (key, child) in dict where !(child is NSNull) {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                out.insert(path)
                out.formUnion(keyPaths(child, prefix: path))
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                out.formUnion(keyPaths(child, prefix: prefix.isEmpty ? "\(index)" : "\(prefix).\(index)"))
            }
        }
        return out
    }

    /// Decodes `expected`, compares it with `actual`, and checks no key of `expected` was lost in decoding.
    private func assertMatches<T: Codable & Equatable>(
        _ actual: T, _ expected: Any, _ type: T.Type, _ c: VectorCorpus.Case
    ) throws {
        let wanted = try decode(T.self, expected)
        #expect(actual == wanted, "\(c.id): \(c.why)")
        #expect(keyPaths(try jsonObject(wanted)) == keyPaths(expected), "\(c.id): the Swift type drops a key of the corpus")
    }

    // MARK: - Suites

    @Test("daily-targets")
    func dailyTargetsSuite() throws {
        try everyCase("daily-targets") { c in
            let table = try decode([ReferenceRow].self, c.input["table"])
            let profile = try decode(TargetProfile.self, c.input["profile"])
            #expect(keyPaths(try jsonObject(profile)) == keyPaths(c.input["profile"] as Any), "\(c.id): profile key lost")
            try assertMatches(dailyTargets(table, profile: profile), c.expected, TargetsResult.self, c)
        }
    }

    @Test("weight-for-day")
    func weightForDaySuite() throws {
        try everyCase("weight-for-day") { c in
            let entries = try decode([WeightEntry].self, c.input["entries"])
            let day = try #require(c.input["day"] as? String)
            let actual = weightForDay(entries, day: day)
            if c.expected is NSNull {
                #expect(actual == nil, "\(c.id): \(c.why)")
            } else {
                #expect(actual == VectorCorpus.double(c.expected), "\(c.id): \(c.why)")
            }
        }
    }

    @Test("profile-for-day")
    func profileForDaySuite() throws {
        try everyCase("profile-for-day") { c in
            let versions = try decode([ProfileVersion].self, c.input["versions"])
            let weights = try decode([WeightEntry].self, c.input["weights"])
            let day = try #require(c.input["day"] as? String)
            let actual = profileForDay(versions, weights: weights, day: day)
            if c.expected is NSNull {
                #expect(actual == nil, "\(c.id): \(c.why)")
            } else {
                try assertMatches(try #require(actual, "\(c.id)"), c.expected, TargetProfile.self, c)
            }
        }
    }

    @Test("apply-target-overrides")
    func applyOverridesSuite() throws {
        try everyCase("apply-target-overrides") { c in
            let targets = try decode([NutrientTarget].self, c.input["targets"])
            let versions = try decode([OverrideVersion].self, c.input["versions"])
            let day = try #require(c.input["day"] as? String)
            try assertMatches(applyOverrides(targets, versions: versions, day: day), c.expected, [DayTarget].self, c)
        }
    }

    @Test("day-progress")
    func dayProgressSuite() throws {
        try everyCase("day-progress") { c in
            let targets = try decode([ProgressTarget].self, c.input["targets"])
            let meals = try decode([MealNutrients].self, c.input["meals"])
            let keys = try decode([String].self, c.input["keys"])
            try assertMatches(dayProgress(targets, meals: meals, keys: keys), c.expected, [NutrientProgress].self, c)
        }
    }

    @Test("self-comparison")
    func selfComparisonSuite() throws {
        try everyCase("self-comparison") { c in
            let history = try decode([DayTotal].self, c.input["history"])
            let day = try #require(c.input["day"] as? String)
            let total = c.input["total"].flatMap(VectorCorpus.double)
            try assertMatches(selfComparison(history, day: day, total: total), c.expected, SelfComparison.self, c)
        }
    }
}
