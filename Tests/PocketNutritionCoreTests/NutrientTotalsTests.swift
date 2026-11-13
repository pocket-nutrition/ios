// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

@Suite("nutrient totals")
struct NutrientTotalsTests {

    @Test("unknown stays unknown when summing, known values add up")
    func sum() {
        let a = NutrientTotals(["energyKcal": 100, "ironMg": 1.5])
        let b = NutrientTotals(["energyKcal": 50, "vitaminCMg": 10])
        let total = a + b
        #expect(total["energyKcal"] == 150)
        #expect(total["ironMg"] == 1.5)
        #expect(total["vitaminCMg"] == 10)
        #expect(total["zincMg"] == nil)
    }

    @Test("unknown keys and non-finite values are dropped")
    func filtering() {
        let t = NutrientTotals(["energyKcal": .nan, "madeUpG": 3, "proteinG": 2])
        #expect(t.values == ["proteinG": 2])
    }

    @Test("reads the nutrient fields of an API profile and ignores the rest")
    func fromProfile() throws {
        struct Wrapper: Decodable {
            let n: NutrientTotals
            init(from decoder: Decoder) throws { n = try NutrientTotals(profileFrom: decoder) }
        }
        let json = #"{"name":"riz","quantity":150,"energyKcal":195,"ironMg":null,"fiberG":0.6,"confidence":0.9}"#
        let w = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        #expect(w.n.values == ["energyKcal": 195, "fiberG": 0.6])
    }

    @Test("round-trips as a flat object and scales")
    func codable() throws {
        let t = NutrientTotals(["energyKcal": 100, "sodiumMg": 40])
        let back = try JSONDecoder().decode(NutrientTotals.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        #expect(t.scaled(by: 0.5)["sodiumMg"] == 20)
        #expect(NutrientTotals.keys.count == 24)
    }
}
