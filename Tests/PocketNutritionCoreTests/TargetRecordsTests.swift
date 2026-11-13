// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

/// The `profile`, `targets` and `weight` vault payloads (spec 05 §3): wire shape, round trip, and refusal of
/// what this client cannot read.
@Suite("daily-targets vault records")
struct TargetRecordsTests {

    private let profile = ProfileRecordPayload(
        updatedAt: 1_793_000_000,
        versions: [
            ProfileVersion(
                effectiveFrom: "2026-11-06", birthYear: 1996, basis: .female, situation: .pregnant, trimester: 2,
                postmenopausal: false, pal: 1.6, weightKg: 65)
        ])

    private let targets = TargetsRecordPayload(
        updatedAt: 1_793_000_000,
        overrides: [
            OverrideVersion(
                effectiveFrom: "2026-11-06",
                values: ["energyKcal": TargetOverride(min: 2200, max: 2200), "sugarsG": TargetOverride(min: nil, max: 50)])
        ],
        watchList: WatchList(preset: "standard", keys: ["energyKcal", "proteinG"]))

    private let weight = WeightRecordPayload(updatedAt: 1_793_000_000, date: "2026-11-06", kg: 70.5)

    private func json(_ record: TargetsVaultRecord) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try encodeTargetsRecord(record)) as? [String: Any])
    }

    @Test("each record round-trips through its plaintext")
    func roundTrip() throws {
        for record in [TargetsVaultRecord.profile(profile), .targets(targets), .weight(weight)] {
            let data = try encodeTargetsRecord(record)
            #expect(try decodeTargetsRecord(data, type: record.recordType, expectedId: record.recordId) == record)
        }
    }

    @Test("record ids and types follow the spec")
    func idsAndTypes() {
        #expect(TargetsVaultRecord.profile(profile).recordId == "profile")
        #expect(TargetsVaultRecord.targets(targets).recordId == "targets")
        #expect(TargetsVaultRecord.weight(weight).recordId == "weight-2026-11-06")
        #expect(TargetsVaultRecord.weight(weight).recordType == "weight")
        for id in ["profile", "targets", "weight-2026-11-06"] { #expect(isValidVaultRecordId(id)) }
        #expect(!isValidVaultRecordId("weight/2026"))
        #expect(weightRecordDate(recordId: "weight-2026-11-06") == "2026-11-06")
        #expect(weightRecordDate(recordId: "weight-x") == nil)
    }

    @Test("the JSON is snake_case and writes null optionals, as the spec example shows")
    func wireShape() throws {
        let p = try json(.profile(profile))
        #expect(p["version"] as? Int == 1)
        #expect(p["updated_at"] as? Double == 1_793_000_000)
        let v = try #require((p["versions"] as? [[String: Any]])?.first)
        #expect(v["effective_from"] as? String == "2026-11-06")
        #expect(v["birth_year"] as? Int == 1996)
        #expect(v["basis"] as? String == "female")
        #expect(v["situation"] as? String == "pregnant")
        #expect(v["trimester"] as? Int == 2)
        #expect(v["lactation"] is NSNull)
        #expect(v["phytate_mg_per_day"] is NSNull)
        #expect(v["weight_kg"] as? Double == 65)

        let t = try json(.targets(targets))
        let o = try #require((t["overrides"] as? [[String: Any]])?.first)
        #expect(o["effective_from"] as? String == "2026-11-06")
        let sugars = try #require((o["values"] as? [String: Any])?["sugarsG"] as? [String: Any])
        #expect(sugars["min"] is NSNull)
        #expect(sugars["max"] as? Double == 50)
        let watch = try #require(t["watch_list"] as? [String: Any])
        #expect(watch["preset"] as? String == "standard")

        let w = try json(.weight(weight))
        #expect(w["date"] as? String == "2026-11-06" && w["kg"] as? Double == 70.5)
    }

    @Test("the spec's own example decodes, unknown fields ignored")
    func specExampleDecodes() throws {
        let example = """
            { "version": 1, "updated_at": 1793000000, "future_field": true,
              "versions": [ { "effective_from": "2026-11-06", "birth_year": 1996, "basis": "female",
                              "situation": "lactating", "trimester": null, "lactation": "first-6-months",
                              "postmenopausal": false, "pal": 1.6, "weight_kg": 65.0, "phytate_mg_per_day": null } ] }
            """
        let record = try decodeTargetsRecord(Data(example.utf8), type: "profile", expectedId: "profile")
        guard case .profile(let p) = record else {
            Issue.record("not a profile")
            return
        }
        #expect(p.profileVersions.first?.lactation == .firstSixMonths)
    }

    @Test("a newer version is refused, never decoded as something else")
    func newerVersionRefused() throws {
        let newer = #"{ "version": 2, "updated_at": 1, "date": "2026-11-06", "kg": 70 }"#
        #expect(throws: TargetsRecordError.unsupportedVersion(2)) {
            try decodeTargetsRecord(Data(newer.utf8), type: "weight", expectedId: "weight-2026-11-06")
        }
    }

    @Test("a payload in the wrong record is refused")
    func swappedRecordRefused() throws {
        let data = try encodeTargetsRecord(.weight(weight))
        #expect(throws: TargetsRecordError.idMismatch) {
            try decodeTargetsRecord(data, type: "weight", expectedId: "weight-2026-11-07")
        }
        #expect(throws: TargetsRecordError.malformed) {
            try decodeTargetsRecord(Data("{}".utf8), type: "weight", expectedId: "weight-2026-11-06")
        }
    }
}
