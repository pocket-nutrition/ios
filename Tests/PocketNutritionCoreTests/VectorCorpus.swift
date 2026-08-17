// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Reader for the shared behavioural corpus vendored at `contract/data/vectors`.
///
/// WHY `#filePath` RATHER THAN A RESOURCE BUNDLE
/// Declaring the corpus as a SwiftPM resource would require it to sit inside the test target's own
/// directory, which would mean a second copy outside `contract/` — and `contract/` is a single tree
/// that sync-contracts.sh owns byte-for-byte so `--verify` can detect drift. Two copies defeat that.
/// `#filePath` resolves at compile time to this source file, so the corpus is found relative to the
/// checkout. These tests therefore run from source, which is the only place they run: `swift test`.
///
/// WHY UNTYPED JSON
/// `expected` has a different shape in every suite — an Int here, a string there, an object
/// elsewhere. Modelling that with Codable would mean a hand-written type per suite, which is one more
/// thing that can drift from the contract. JSONSerialization keeps the reader honest: it knows the
/// corpus structure and nothing about any individual suite's payload.
enum VectorCorpus {

    struct Case {
        let id: String
        let why: String
        let input: [String: Any]
        let expected: Any
    }

    struct Suite {
        let name: String
        let description: String
        let cases: [Case]
    }

    struct Index {
        let totalCases: Int
        /// suite name -> declared case count
        let suites: [String: Int]
    }

    enum CorpusError: Error, CustomStringConvertible {
        case missingFile(URL)
        case malformed(String)

        var description: String {
            switch self {
            case .missingFile(let url):
                return """
                    vendored corpus not found at \(url.path) — \
                    run ./scripts/sync-contracts.sh --update
                    """
            case .malformed(let detail):
                return "corpus is malformed: \(detail)"
            }
        }
    }

    /// Repository root, derived from this file's own location:
    /// `<root>/Tests/PocketNutritionCoreTests/VectorCorpus.swift`
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var vectorsDirectory: URL {
        repositoryRoot
            .appendingPathComponent("contract")
            .appendingPathComponent("data")
            .appendingPathComponent("vectors")
    }

    // JSON does not distinguish 64 from 64.0, and the two Foundations disagree about what that means.
    // `rounding` alone holds 0.5 (a JSON double) and 64 and 0 (JSON integers); a bare `as? Double`
    // picks up the first and can miss the others, because bridging an integer-valued NSNumber to
    // Double works on Apple's Foundation and is not guaranteed on swift-corelibs-foundation. Since
    // Linux is exactly where CI runs, that would be a failure visible only there. Coerce explicitly.
    static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        // A whole Double is acceptable; a fractional one is a corpus error, not something to truncate.
        if let double = value as? Double, double == double.rounded() { return Int(double) }
        return nil
    }

    private static func readObject(_ fileName: String) throws -> [String: Any] {
        let url = vectorsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CorpusError.missingFile(url)
        }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CorpusError.malformed("\(fileName) is not a JSON object")
        }
        return object
    }

    static func index() throws -> Index {
        let object = try readObject("index.json")
        guard let total = object["totalCases"] as? Int else {
            throw CorpusError.malformed("index.json has no integer totalCases")
        }
        guard let rawSuites = object["suites"] as? [[String: Any]] else {
            throw CorpusError.malformed("index.json has no suites array")
        }
        var suites: [String: Int] = [:]
        for entry in rawSuites {
            guard let name = entry["suite"] as? String, let count = entry["cases"] as? Int else {
                throw CorpusError.malformed("a suite entry in index.json lacks suite or cases")
            }
            suites[name] = count
        }
        return Index(totalCases: total, suites: suites)
    }

    static func load(_ suiteName: String) throws -> Suite {
        let object = try readObject("\(suiteName).json")
        guard let name = object["suite"] as? String else {
            throw CorpusError.malformed("\(suiteName).json has no suite field")
        }
        guard let description = object["description"] as? String else {
            throw CorpusError.malformed("\(suiteName).json has no description")
        }
        guard let rawCases = object["cases"] as? [[String: Any]] else {
            throw CorpusError.malformed("\(suiteName).json has no cases array")
        }

        let cases: [Case] = try rawCases.map { raw in
            guard let id = raw["id"] as? String else {
                throw CorpusError.malformed("\(suiteName): a case has no id")
            }
            guard let why = raw["why"] as? String else {
                throw CorpusError.malformed("\(suiteName)/\(id): no why")
            }
            guard let input = raw["input"] as? [String: Any] else {
                throw CorpusError.malformed("\(suiteName)/\(id): input is not an object")
            }
            // Left as Any rather than unwrapped: NSNull is a legitimate expected value in some
            // suites and has to survive the round trip rather than read as "absent".
            guard let expected = raw["expected"] else {
                throw CorpusError.malformed("\(suiteName)/\(id): no expected")
            }
            return Case(id: id, why: why, input: input, expected: expected)
        }

        return Suite(name: name, description: description, cases: cases)
    }
}
