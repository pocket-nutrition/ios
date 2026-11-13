// SPDX-License-Identifier: MPL-2.0

import Foundation

// Daily nutrient targets from the EFSA reference table served by `GET /reference-intakes`.
//
// Port of the sandbox's `src/lib/dailyTargets.ts`, held to the `daily-targets` vector suite. The table comes
// from the API; this file only selects the rows that apply to one person and does the arithmetic
// (increments, per-kg protein, % of energy). It embeds no reference value: every number in the output traces
// back to a row of the input table. The only constants are the ones the contract allows: the default zinc
// phytate level, the adult age, and the kcal per gram used to convert "% of energy" rows.

/// One row of `GET /reference-intakes`, reduced to the fields the selection reads. Other fields of the
/// response (`raw`, `note`, `ageLabel`…) decode away.
public struct ReferenceRow: Codable, Equatable, Sendable {
    public var nutrient: String
    public var nutrientKey: String?
    public var population: String
    public var populationDescription: String
    public var ageFrom: Double?
    public var ageTo: Double?
    public var ageUnit: String?
    public var pal: Double?
    public var isMale: Bool
    public var isFemale: Bool
    public var valueKind: String
    public var valueMin: Double?
    public var valueMax: Double?
    public var isIncrement: Bool
    public var unit: String?
    public var sourceLink: String?

    public init(
        nutrient: String, nutrientKey: String?, population: String, populationDescription: String,
        ageFrom: Double?, ageTo: Double?, ageUnit: String?, pal: Double?, isMale: Bool, isFemale: Bool,
        valueKind: String, valueMin: Double?, valueMax: Double?, isIncrement: Bool, unit: String?,
        sourceLink: String?
    ) {
        self.nutrient = nutrient
        self.nutrientKey = nutrientKey
        self.population = population
        self.populationDescription = populationDescription
        self.ageFrom = ageFrom
        self.ageTo = ageTo
        self.ageUnit = ageUnit
        self.pal = pal
        self.isMale = isMale
        self.isFemale = isFemale
        self.valueKind = valueKind
        self.valueMin = valueMin
        self.valueMax = valueMax
        self.isIncrement = isIncrement
        self.unit = unit
        self.sourceLink = sourceLink
    }
}

/// Which reference values to compute with. Never a gender: EFSA publishes different values, and the person
/// picks the set, or the average of both.
public enum CalculationBasis: String, Codable, CaseIterable, Sendable {
    case female, male, average
}

public enum TargetSituation: String, Codable, CaseIterable, Sendable {
    case none, pregnant, lactating
}

public enum LactationPeriod: String, Codable, CaseIterable, Sendable {
    case firstSixMonths = "first-6-months"
    case afterSixMonths = "after-6-months"
}

/// What `dailyTargets` needs to know about one person on one day.
public struct TargetProfile: Codable, Equatable, Sendable {
    /// Age in whole years on the day the targets are for.
    public var ageYears: Int
    /// Pregnancy and lactation always use the female values, whatever the basis.
    public var basis: CalculationBasis
    public var situation: TargetSituation
    /// 1, 2 or 3. Required when pregnant.
    public var trimester: Int?
    /// Required when lactating.
    public var lactation: LactationPeriod?
    /// Selects EFSA's postmenopausal values where it publishes them (iron, from 40).
    public var postmenopausal: Bool?
    /// Physical activity level; EFSA publishes energy for 1.4, 1.6, 1.8 and 2.0.
    public var pal: Double
    public var weightKg: Double
    /// Dietary phytate (LPI) for zinc. EFSA publishes 300, 600, 900 and 1200; 600 when absent.
    public var phytateMgPerDay: Double?

    public init(
        ageYears: Int, basis: CalculationBasis, situation: TargetSituation, trimester: Int? = nil,
        lactation: LactationPeriod? = nil, postmenopausal: Bool? = nil, pal: Double, weightKg: Double,
        phytateMgPerDay: Double? = nil
    ) {
        self.ageYears = ageYears
        self.basis = basis
        self.situation = situation
        self.trimester = trimester
        self.lactation = lactation
        self.postmenopausal = postmenopausal
        self.pal = pal
        self.weightKg = weightKg
        self.phytateMgPerDay = phytateMgPerDay
    }
}

public enum TargetUnit: String, Codable, Sendable {
    case kcal
    case g
    case mg
    /// U+00B5 MICRO SIGN, as the contract writes it.
    case ug = "µg"

    /// The unit of a journal key, from its suffix (`Kcal`, `Ug`, `Mg`, else grams).
    public init(key: String) {
        if key.hasSuffix("Kcal") {
            self = .kcal
        } else if key.hasSuffix("Ug") {
            self = .ug
        } else if key.hasSuffix("Mg") {
            self = .mg
        } else {
            self = .g
        }
    }

    /// Strict variant for the calculation: nil for a key with no known suffix.
    static func strict(key: String) -> TargetUnit? {
        if key.hasSuffix("Kcal") || key.hasSuffix("Ug") || key.hasSuffix("Mg") || key.hasSuffix("G") {
            return TargetUnit(key: key)
        }
        return nil
    }
}

/// One daily target, in the journal's unit for the key.
public struct NutrientTarget: Codable, Equatable, Sendable {
    public var nutrientKey: String
    public var unit: TargetUnit
    /// Reach at least this (PRI, else AI); equal to max for energy, a point target.
    public var min: Double?
    /// Upper end of a recommended range (RI) or of a point target (energy). Not a safety limit.
    public var max: Double?
    /// EFSA tolerable upper intake level: a safety ceiling, shown apart from the target.
    public var upperLimit: Double?
    /// Links of the EFSA opinions the values come from, sorted and de-duplicated.
    public var sources: [String]

    public init(
        nutrientKey: String, unit: TargetUnit, min: Double?, max: Double?, upperLimit: Double?, sources: [String]
    ) {
        self.nutrientKey = nutrientKey
        self.unit = unit
        self.min = min
        self.max = max
        self.upperLimit = upperLimit
        self.sources = sources
    }
}

public enum UnsupportedTargetReason: String, Codable, Sendable {
    case infant
    case pregnancyUnder18 = "pregnancy-under-18"
    case lactationUnder18 = "lactation-under-18"
}

public enum TargetsResult: Codable, Equatable, Sendable {
    case ok([NutrientTarget])
    case unsupported(UnsupportedTargetReason)

    private enum CodingKeys: String, CodingKey { case status, targets, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "ok": self = .ok(try c.decode([NutrientTarget].self, forKey: .targets))
        case "unsupported": self = .unsupported(try c.decode(UnsupportedTargetReason.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: c, debugDescription: "unknown status")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ok(let targets):
            try c.encode("ok", forKey: .status)
            try c.encode(targets, forKey: .targets)
        case .unsupported(let reason):
            try c.encode("unsupported", forKey: .status)
            try c.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - Constants the contract allows

/// EFSA's middle phytate level, used for zinc when the profile does not say. Labelled as our choice.
public let defaultPhytateMgPerDay: Double = 600
private let adultAge = 18
private let energyKey = "energyKcal"

/// kcal per gram, for reference intakes given in % of energy (E%).
private let energyDensity: [String: Double] = [
    "carbohydratesG": 4, "proteinG": 4, "fatG": 9, "saturatedFatG": 9,
]

private let trimesterLabel: [Int: String] = [1: "1st trimester", 2: "2nd trimester", 3: "3rd trimester"]

// MARK: - Ordering

/// The order the sandbox gets from `String.localeCompare` for these ASCII camelCase keys: case-insensitive,
/// lowercase first on a tie. Not `<`, which would put every uppercase letter before every lowercase one.
func nutrientKeyOrder(_ a: String, _ b: String) -> Bool {
    let la = a.lowercased(), lb = b.lowercased()
    if la != lb { return la < lb }
    return a > b
}

// MARK: - Selection

private enum TargetField: CaseIterable {
    case energy, goal, range, upperLimit
}

private func field(of valueKind: String) -> TargetField? {
    switch valueKind {
    case "ar_kcal": return .energy
    case "pri", "ai": return .goal
    case "ri": return .range
    case "ul": return .upperLimit
    default: return nil
    }
}

private let massInMg: [String: Double] = ["g": 1000, "mg": 1, "µg": 0.001]

/// Converts one EFSA amount to the journal unit of `key`. Nil for a unit that cannot be converted, so the row
/// is skipped rather than compared wrongly.
private func toJournalUnit(
    _ amount: Double, unit rawUnit: String, key: String, weightKg: Double, energyKcal: Double?
) -> Double? {
    guard let target = TargetUnit.strict(key: key) else { return nil }
    // U+03BC GREEK SMALL LETTER MU and U+00B5 MICRO SIGN are the same micro sign here.
    let unit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{03BC}", with: "\u{00B5}")
    if unit == "kcal/day" { return target == .kcal ? amount : nil }
    if unit == "g/kg bw per day" { return target == .g ? amount * weightKg : nil }
    if unit == "E%" {
        guard let density = energyDensity[key], let energyKcal, target == .g else { return nil }
        return (energyKcal * amount) / (100 * density)
    }
    guard unit.hasSuffix("/day"), target != .kcal else { return nil }
    let mass = String(unit.dropLast("/day".count))
    guard let from = massInMg[mass], let to = massInMg[target.rawValue] else { return nil }
    return (amount * from) / to
}

private func inAgeBand(_ row: ReferenceRow, _ age: Int) -> Bool {
    guard row.ageUnit == "y", let from = row.ageFrom, let to = row.ageTo else { return false }
    return from <= Double(age) && Double(age) <= to
}

/// The phytate level a zinc row is for, from "(LPI 600 mg/day)" in its description.
private func lpi(_ description: String) -> Double? {
    guard let range = description.range(of: "LPI") else { return nil }
    let rest = description[range.upperBound...].drop(while: { $0 == " " })
    let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
    guard !digits.isEmpty else { return nil }
    let tail = rest.dropFirst(digits.count).drop(while: { $0 == " " })
    guard tail.hasPrefix("mg/day") else { return nil }
    return Double(String(digits))
}

/// Narrows the rows of one nutrient and one kind to the variant that applies: the activity level for energy,
/// the phytate level for zinc, menopause status for iron. A narrowing that would leave nothing is not applied
/// (EFSA has no postmenopausal value under 40, so an early menopause keeps the general value).
private func narrowVariants(_ rows: [ReferenceRow], _ profile: TargetProfile) -> [ReferenceRow] {
    var out = rows.filter { $0.pal == nil || $0.pal == profile.pal }

    let phytate = profile.phytateMgPerDay ?? defaultPhytateMgPerDay
    if out.contains(where: { lpi($0.populationDescription) != nil }) {
        out = out.filter { row in lpi(row.populationDescription).map { $0 == phytate } ?? true }
    }

    let post = out.filter { $0.populationDescription.contains("Postmenopausal") }
    if profile.postmenopausal == true && !post.isEmpty {
        out = post
    } else {
        out = out.filter { !$0.populationDescription.contains("Postmenopausal") }
    }
    return out
}

/// Matches a pregnancy or lactation row to the trimester or post-partum period, when the row names one.
private func matchesPeriod(_ row: ReferenceRow, _ profile: TargetProfile) -> Bool {
    let d = row.populationDescription
    if d.contains("trimester") {
        guard let trimester = profile.trimester, let label = trimesterLabel[trimester] else { return false }
        return d.contains(label)
    }
    if d.contains("post partum") {
        guard let lactation = profile.lactation else { return false }
        return lactation == .firstSixMonths ? (d.contains("0–6") || d.contains("0-6")) : d.contains(">6")
    }
    return true
}

private struct RawTarget {
    var energy: Double?
    var goal: Double?
    var rangeMin: Double?
    var rangeMax: Double?
    var upperLimit: Double?
    var sources: Set<String> = []
    /// The value kinds and age bands of the rows used, for the explanation screen only.
    var kinds: Set<String> = []
    var ageBands: Set<AgeBand> = []

    var isEmpty: Bool { energy == nil && goal == nil && rangeMin == nil && upperLimit == nil }
}

/// The first row of each target field for one nutrient key, in table order, after narrowing.
private func pickByField(_ rows: [ReferenceRow], _ profile: TargetProfile) -> [TargetField: ReferenceRow] {
    var picked: [TargetField: ReferenceRow] = [:]
    // pri before ai: a PRI, when EFSA sets one, is the target; an AI is the fallback.
    for kind in ["ar_kcal", "pri", "ai", "ri", "ul"] {
        guard let f = field(of: kind), picked[f] == nil else { continue }
        let candidates = narrowVariants(rows.filter { $0.valueKind == kind }, profile).filter { $0.valueMin != nil }
        if let first = candidates.first { picked[f] = first }
    }
    return picked
}

private struct Amount {
    var min: Double
    var max: Double
}

private func convert(_ row: ReferenceRow, key: String, profile: TargetProfile, energyKcal: Double?) -> Amount? {
    guard let unit = row.unit, let valueMin = row.valueMin else { return nil }
    guard
        let min = toJournalUnit(valueMin, unit: unit, key: key, weightKg: profile.weightKg, energyKcal: energyKcal),
        let max = toJournalUnit(row.valueMax ?? valueMin, unit: unit, key: key, weightKg: profile.weightKg, energyKcal: energyKcal)
    else { return nil }
    return Amount(min: min, max: max)
}

private enum Sex { case female, male }

/// Targets for one sex: base population, then the pregnancy or lactation rows on top.
private func targetsForSex(_ table: [ReferenceRow], _ profile: TargetProfile, _ sex: Sex) -> [String: RawTarget] {
    let age = profile.ageYears
    let basePopulation = age >= adultAge ? "Adults" : "Children"
    let situationPopulation: String? = switch profile.situation {
    case .pregnant: "Pregnant women"
    case .lactating: "Lactating women"
    case .none: nil
    }

    func rowsByKey(_ population: String, _ extra: (ReferenceRow) -> Bool) -> [String: [ReferenceRow]] {
        var out: [String: [ReferenceRow]] = [:]
        for row in table {
            guard let key = row.nutrientKey, row.population == population else { continue }
            guard inAgeBand(row, age), sex == .male ? row.isMale : row.isFemale, extra(row) else { continue }
            out[key, default: []].append(row)
        }
        return out
    }

    let base = rowsByKey(basePopulation) { _ in true }
    let situation = situationPopulation.map { rowsByKey($0) { matchesPeriod($0, profile) } } ?? [:]

    // Energy first: % of energy intakes are converted with it.
    let ordered = Set(base.keys).union(situation.keys).sorted { a, b in
        if a == energyKey { return b != energyKey }
        if b == energyKey { return false }
        return nutrientKeyOrder(a, b)
    }

    var result: [String: RawTarget] = [:]
    var energyKcal: Double?

    for key in ordered {
        let basePicked = pickByField(base[key] ?? [], profile)
        let situationPicked = pickByField(situation[key] ?? [], profile)
        var raw = RawTarget()

        for f in TargetField.allCases {
            let baseRow = basePicked[f]
            var amount = baseRow.flatMap { convert($0, key: key, profile: profile, energyKcal: energyKcal) }
            var links: [String?] = amount == nil ? [] : [baseRow?.sourceLink]
            var used: [ReferenceRow] = amount == nil ? [] : baseRow.map { [$0] } ?? []

            if let extraRow = situationPicked[f], let extra = convert(extraRow, key: key, profile: profile, energyKcal: energyKcal) {
                if !extraRow.isIncrement {
                    amount = extra
                    links = [extraRow.sourceLink]
                    used = [extraRow]
                } else if let current = amount {
                    amount = Amount(min: current.min + extra.min, max: current.max + extra.max)
                    links.append(extraRow.sourceLink)
                    used.append(extraRow)
                }
            }
            guard let amount else { continue }
            for link in links { if let link { raw.sources.insert(link) } }
            for row in used {
                raw.kinds.insert(row.valueKind)
                if let from = row.ageFrom, let to = row.ageTo { raw.ageBands.insert(AgeBand(from: from, to: to)) }
            }

            switch f {
            case .energy: raw.energy = amount.min
            case .goal: raw.goal = amount.min
            case .range:
                raw.rangeMin = amount.min
                raw.rangeMax = amount.max
            case .upperLimit: raw.upperLimit = amount.min
            }
        }

        if key == energyKey { energyKcal = raw.energy }
        if !raw.isEmpty { result[key] = raw }
    }
    return result
}

/// kcal and g to whole numbers, mg and µg to one decimal, half-up.
public func roundTargetValue(_ value: Double, unit: TargetUnit) -> Double {
    switch unit {
    case .kcal, .g: return Double(roundHalfUp(value))
    case .mg, .ug: return Double(roundHalfUp(value * 10)) / 10
    }
}

private func toTarget(_ key: String, _ raw: RawTarget) -> NutrientTarget? {
    guard let unit = TargetUnit.strict(key: key) else { return nil }
    var min: Double?
    var max: Double?
    if let energy = raw.energy {
        min = energy
        max = energy
    } else if let rangeMin = raw.rangeMin {
        min = rangeMin
        max = raw.rangeMax
    } else if let goal = raw.goal {
        min = goal
    }
    return NutrientTarget(
        nutrientKey: key, unit: unit,
        min: min.map { roundTargetValue($0, unit: unit) },
        max: max.map { roundTargetValue($0, unit: unit) },
        upperLimit: raw.upperLimit.map { roundTargetValue($0, unit: unit) },
        sources: raw.sources.sorted())
}

private func mean(_ a: Double?, _ b: Double?) -> Double? {
    guard let a else { return b }
    guard let b else { return a }
    return (a + b) / 2
}

private func averageRaw(_ f: RawTarget?, _ m: RawTarget?) -> RawTarget {
    let a = f ?? RawTarget()
    let b = m ?? RawTarget()
    return RawTarget(
        energy: mean(a.energy, b.energy), goal: mean(a.goal, b.goal), rangeMin: mean(a.rangeMin, b.rangeMin),
        rangeMax: mean(a.rangeMax, b.rangeMax), upperLimit: mean(a.upperLimit, b.upperLimit),
        sources: a.sources.union(b.sources), kinds: a.kinds.union(b.kinds), ageBands: a.ageBands.union(b.ageBands))
}

/// The daily targets that apply to `profile`, from the EFSA `table`.
///
/// - Infants (under 1 year) and pregnancy or lactation under 18 are not supported: EFSA's pregnancy and
///   lactation rows are for adults, and infant needs are not a journal's business.
/// - Pregnancy and lactation always compute with the female values, whatever the basis.
/// - The "average" basis averages the female and male results field by field, after each is complete, so
///   increments and % of energy are applied per sex before averaging.
public func dailyTargets(_ table: [ReferenceRow], profile: TargetProfile) -> TargetsResult {
    if let reason = unsupportedReason(profile) { return .unsupported(reason) }
    let targets = rawTargets(table, profile).compactMap { toTarget($0.key, $0.value) }
        .sorted { nutrientKeyOrder($0.nutrientKey, $1.nutrientKey) }
    return .ok(targets)
}

private func unsupportedReason(_ profile: TargetProfile) -> UnsupportedTargetReason? {
    if profile.ageYears < 1 { return .infant }
    if profile.ageYears < adultAge && profile.situation == .pregnant { return .pregnancyUnder18 }
    if profile.ageYears < adultAge && profile.situation == .lactating { return .lactationUnder18 }
    return nil
}

/// An EFSA age band in years; `to` is 999 for "no upper bound".
public struct AgeBand: Hashable, Sendable, Comparable {
    public var from: Double
    public var to: Double

    public init(from: Double, to: Double) {
        self.from = from
        self.to = to
    }

    public static func < (a: AgeBand, b: AgeBand) -> Bool { (a.from, a.to) < (b.from, b.to) }
}

/// Where a computed target comes from, for the explanation screen: EFSA's value kinds of the rows used
/// (`ar_kcal`, `pri`, `ai`, `ri`, `ul`) and their age bands.
public struct TargetBasis: Equatable, Sendable {
    public var kinds: [String]
    public var ageBands: [AgeBand]
}

/// The basis of each target `dailyTargets` returns for `profile`, by nutrient key. Empty when unsupported.
public func dailyTargetBases(_ table: [ReferenceRow], profile: TargetProfile) -> [String: TargetBasis] {
    guard unsupportedReason(profile) == nil else { return [:] }
    return rawTargets(table, profile).mapValues { raw in
        TargetBasis(kinds: raw.kinds.sorted(), ageBands: raw.ageBands.sorted())
    }
}

private func rawTargets(_ table: [ReferenceRow], _ profile: TargetProfile) -> [String: RawTarget] {
    let basis: CalculationBasis = profile.situation == .none ? profile.basis : .female
    let raws: [String: RawTarget]
    switch basis {
    case .average:
        let f = targetsForSex(table, profile, .female)
        let m = targetsForSex(table, profile, .male)
        raws = Dictionary(uniqueKeysWithValues: Set(f.keys).union(m.keys).map { ($0, averageRaw(f[$0], m[$0])) })
    case .female: raws = targetsForSex(table, profile, .female)
    case .male: raws = targetsForSex(table, profile, .male)
    }
    return raws
}
