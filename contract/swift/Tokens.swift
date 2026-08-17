// SPDX-License-Identifier: MPL-2.0
/*
 * GENERATED FILE — DO NOT EDIT.
 * Source: pocket-nutrition-contracts/tokens/{tokens,semantic-map,cooking-palette}.json
 * Regenerate: python3 scripts/emit_tokens.py
 *
 * Editing this by hand guarantees the two apps drift apart, which is the single thing the
 * contracts repository exists to prevent. Change the JSON and re-run.
 */
import SwiftUI

extension Color {
    /// 0xRRGGBB plus a separate opacity, matching the generated call sites below.
    init(pnHex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((pnHex >> 16) & 0xFF) / 255,
            green: Double((pnHex >> 8) & 0xFF) / 255,
            blue: Double(pnHex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Raw palette. Prefer `PnRole` at call sites — a role survives a palette change.
public enum PnColor {
    /// Application background. Warm off-white, not #fff — the whole system reads as paper.
    public static let surfacePaper = Color(pnHex: 0xFAF7F0)
    /// Secondary surface: badge backgrounds, progress track, .card-cream.
    public static let surfaceCream = Color(pnHex: 0xF1EAD9)
    /// Raised card surface. Pure white, deliberately brighter than paper so a card lifts off the background without needing a shadow.
    public static let surfaceCard = Color(pnHex: 0xFFFFFF)
    /// Dark surface (.card-dark, .btn-primary fill). Same value as color.brand.leafDeep, kept separate because this is a surface role rather than a brand accent.
    public static let surfaceInverse = Color(pnHex: 0x1F3D29)
    /// Primary text. A very dark desaturated green, not black.
    public static let inkDefault = Color(pnHex: 0x1E2B22)
    /// Secondary text: .lead, table headers, field help, nav links.
    public static let inkSoft = Color(pnHex: 0x4A5A4E)
    /// Text on a dark surface. Same value as surface.paper.
    public static let inkOnInverse = Color(pnHex: 0xFAF7F0)
    /// Hairline borders. Deliberately an alpha of ink rather than an opaque grey, so it tints correctly over both paper and cream. A port must keep the alpha — flattening it to an opaque hex breaks it over cream.
    public static let inkLine = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// Primary brand green. Also emphasis italics, kickers, and input focus borders.
    public static let brandLeaf = Color(pnHex: 0x3E7A4E)
    /// Deep brand green: primary button fill, active pills, dark cards.
    public static let brandLeafDeep = Color(pnHex: 0x1F3D29)
    /// Accent orange: logo mark, accent buttons, and the focus ring.
    public static let brandCarrot = Color(pnHex: 0xE07A2F)
    /// Tint of carrot for accent backgrounds.
    public static let brandCarrotSoft = Color(pnHex: 0xF7E3CF)
    /// Good / high confidence. Currently identical to brand.leaf.
    public static let statusOk = Color(pnHex: 0x3E7A4E)
    public static let statusOkSoft = Color(pnHex: 0xE2ECDF)
    /// Caution / medium confidence. Also the dashed border of .badge-outline.
    public static let statusWarn = Color(pnHex: 0xC9862E)
    public static let statusWarnSoft = Color(pnHex: 0xF6E8CF)
    /// Error / low confidence.
    public static let statusBad = Color(pnHex: 0xB0402F)
    public static let statusBadSoft = Color(pnHex: 0xF4DDD7)
    public static let hueSea = Color(pnHex: 0x3D6A7A)
    public static let hueSeaSoft = Color(pnHex: 0xDDE9EC)
    public static let hueGold = Color(pnHex: 0xB08A2E)
    public static let hueGoldSoft = Color(pnHex: 0xF2E9D0)
    public static let huePlum = Color(pnHex: 0x7A4A66)
    public static let huePlumSoft = Color(pnHex: 0xECDFE7)
    /// On status.okSoft (.badge-ok). Reuses brand.leafDeep.
    public static let onSoftOk = Color(pnHex: 0x1F3D29)
    /// On status.warnSoft (.badge-warn, .badge-outline).
    public static let onSoftWarn = Color(pnHex: 0x7A5116)
    /// On status.badSoft (.badge-bad).
    public static let onSoftBad = Color(pnHex: 0x7C2C1F)
    /// On hue.seaSoft (.badge-sea).
    public static let onSoftSea = Color(pnHex: 0x274B58)
    /// On hue.goldSoft (.badge-gold).
    public static let onSoftGold = Color(pnHex: 0x6E5518)
    /// On hue.plumSoft (.badge-plum).
    public static let onSoftPlum = Color(pnHex: 0x55304A)
    public static let chartSeries1 = Color(pnHex: 0x6366F1)
    public static let chartSeries2 = Color(pnHex: 0x10B981)
    public static let chartSeries3 = Color(pnHex: 0xF59E0B)
    public static let chartSeries4 = Color(pnHex: 0xEF4444)
    public static let chartSeries5 = Color(pnHex: 0x8B5CF6)
    public static let chartSeries6 = Color(pnHex: 0xF97316)
    public static let chartSeries7 = Color(pnHex: 0x0EA5E9)
    public static let chartSeries8 = Color(pnHex: 0xEC4899)
}

/// Semantic roles, resolved from tokens/semantic-map.json. UI code should reference these:
/// a role records a decision, a palette entry is only a value.
public enum PnRole {
    /// color.brand.leafDeep
    public static let buttonPrimaryBackground = Color(pnHex: 0x1F3D29)
    /// color.surface.paper
    public static let buttonPrimaryForeground = Color(pnHex: 0xFAF7F0)
    /// color.brand.leafDeep
    public static let buttonGhostForeground = Color(pnHex: 0x1F3D29)
    /// color.brand.leafDeep
    public static let buttonGhostBorderColor = Color(pnHex: 0x1F3D29)
    /// color.brand.leaf @ 0.08
    public static let buttonGhostHoverBackground = Color(pnHex: 0x3E7A4E, opacity: 0.08)
    /// color.brand.carrot
    public static let buttonAccentBackground = Color(pnHex: 0xE07A2F)
    /// color.surface.card
    public static let cardDefaultBackground = Color(pnHex: 0xFFFFFF)
    /// color.ink.line
    public static let cardDefaultBorderColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.surface.cream
    public static let cardCreamBackground = Color(pnHex: 0xF1EAD9)
    /// color.ink.line
    public static let cardCreamBorderColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.surface.inverse
    public static let cardDarkBackground = Color(pnHex: 0x1F3D29)
    /// color.ink.onInverse
    public static let cardDarkForeground = Color(pnHex: 0xFAF7F0)
    /// color.surface.cream
    public static let badgeNeutralBackground = Color(pnHex: 0xF1EAD9)
    /// color.ink.soft
    public static let badgeNeutralForeground = Color(pnHex: 0x4A5A4E)
    /// color.status.okSoft
    public static let badgeOkBackground = Color(pnHex: 0xE2ECDF)
    /// color.onSoft.ok
    public static let badgeOkForeground = Color(pnHex: 0x1F3D29)
    /// color.status.warnSoft
    public static let badgeWarnBackground = Color(pnHex: 0xF6E8CF)
    /// color.onSoft.warn
    public static let badgeWarnForeground = Color(pnHex: 0x7A5116)
    /// color.status.badSoft
    public static let badgeBadBackground = Color(pnHex: 0xF4DDD7)
    /// color.onSoft.bad
    public static let badgeBadForeground = Color(pnHex: 0x7C2C1F)
    /// color.hue.seaSoft
    public static let badgeSeaBackground = Color(pnHex: 0xDDE9EC)
    /// color.onSoft.sea
    public static let badgeSeaForeground = Color(pnHex: 0x274B58)
    /// color.hue.goldSoft
    public static let badgeGoldBackground = Color(pnHex: 0xF2E9D0)
    /// color.onSoft.gold
    public static let badgeGoldForeground = Color(pnHex: 0x6E5518)
    /// color.hue.plumSoft
    public static let badgePlumBackground = Color(pnHex: 0xECDFE7)
    /// color.onSoft.plum
    public static let badgePlumForeground = Color(pnHex: 0x55304A)
    /// color.status.warn
    public static let badgeOutlineBorderColor = Color(pnHex: 0xC9862E)
    /// color.onSoft.warn
    public static let badgeOutlineForeground = Color(pnHex: 0x7A5116)
    /// color.surface.card
    public static let filterPillIdleBackground = Color(pnHex: 0xFFFFFF)
    /// color.ink.soft
    public static let filterPillIdleForeground = Color(pnHex: 0x4A5A4E)
    /// color.ink.line
    public static let filterPillIdleBorderColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.brand.leaf
    public static let filterPillHoverBorderColor = Color(pnHex: 0x3E7A4E)
    /// color.brand.leafDeep
    public static let filterPillHoverForeground = Color(pnHex: 0x1F3D29)
    /// color.brand.leafDeep
    public static let filterPillActiveBackground = Color(pnHex: 0x1F3D29)
    /// color.brand.leafDeep
    public static let filterPillActiveBorderColor = Color(pnHex: 0x1F3D29)
    /// color.surface.paper
    public static let filterPillActiveForeground = Color(pnHex: 0xFAF7F0)
    /// color.surface.card
    public static let inputDefaultBackground = Color(pnHex: 0xFFFFFF)
    /// color.ink.default
    public static let inputDefaultForeground = Color(pnHex: 0x1E2B22)
    /// color.ink.line
    public static let inputDefaultBorderColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.brand.leaf
    public static let inputFocusBorderColor = Color(pnHex: 0x3E7A4E)
    /// color.brand.leaf @ 0.18
    public static let inputFocusRingColor = Color(pnHex: 0x3E7A4E, opacity: 0.18)
    /// color.ink.default
    public static let inputLabelForeground = Color(pnHex: 0x1E2B22)
    /// color.ink.soft
    public static let inputHelpForeground = Color(pnHex: 0x4A5A4E)
    /// color.ink.soft
    public static let tableHeaderForeground = Color(pnHex: 0x4A5A4E)
    /// color.ink.line
    public static let tableHeaderBorderBottomColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.ink.line
    public static let tableCellBorderBottomColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.brand.leaf @ 0.05
    public static let tableRowHoverBackground = Color(pnHex: 0x3E7A4E, opacity: 0.05)
    /// color.surface.cream
    public static let progressTrackBackground = Color(pnHex: 0xF1EAD9)
    /// color.brand.leaf
    public static let progressSegmentOkBackground = Color(pnHex: 0x3E7A4E)
    /// color.brand.carrot
    public static let progressSegmentWarnBackground = Color(pnHex: 0xE07A2F)
    /// color.status.bad
    public static let progressSegmentBadBackground = Color(pnHex: 0xB0402F)
    /// color.surface.paper @ 0.9
    public static let navBackground = Color(pnHex: 0xFAF7F0, opacity: 0.9)
    /// color.ink.line
    public static let navBorderBottomColor = Color(pnHex: 0x1E2B22, opacity: 0.14)
    /// color.ink.default
    public static let navLogoForeground = Color(pnHex: 0x1E2B22)
    /// color.brand.carrot
    public static let navLogoMarkForeground = Color(pnHex: 0xE07A2F)
    /// color.ink.soft
    public static let navLinkForeground = Color(pnHex: 0x4A5A4E)
    /// color.brand.leafDeep
    public static let navLinkActiveForeground = Color(pnHex: 0x1F3D29)
    /// color.brand.leaf
    public static let typographyEmphasisForeground = Color(pnHex: 0x3E7A4E)
    /// color.brand.leaf
    public static let typographyKickerForeground = Color(pnHex: 0x3E7A4E)
    /// color.ink.soft
    public static let typographyLeadForeground = Color(pnHex: 0x4A5A4E)
    /// color.ink.soft
    public static let typographyStatLabelForeground = Color(pnHex: 0x4A5A4E)
    /// focus.ringColor
    public static let focusRingColor = Color(pnHex: 0xE07A2F)
}

public enum PnRadius {
    /// Cards and panels.
    public static let `default`: CGFloat = 18
    /// Inputs and selects.
    public static let small: CGFloat = 10
    /// Buttons, badges, filter pills, progress track. A literal in the stylesheet rather than a :root variable; captured here because a port needs a real number, and 999px means 'fully rounded'.
    public static let pill: CGFloat = 999
}

public enum PnMotion {
    /// Honour UIAccessibility.isReduceMotionEnabled: the design system disables all motion
    /// under reduced-motion, so these must collapse to 0 in that case.
    public static let fastSeconds: Double = 0.15
    public static let cardSeconds: Double = 0.18
    public static let outExpo = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.16, y: 1),
        endControlPoint: UnitPoint(x: 0.3, y: 1)
    )
}

/// One focus treatment system-wide, in the ACCENT colour so focus never reads as selected.
public enum PnFocus {
    public static let ring = Color(pnHex: 0xE07A2F)
    public static let width: CGFloat = 3
    public static let offset: CGFloat = 2
}

/// Platform-default families. The design ships no webfont, so there is nothing to bundle.
public enum PnFont {
    // display: Iowan Old Style, Palatino Linotype, Book Antiqua, Georgia, serif
    // body: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif
    // mono: ui-monospace, SF Mono, Menlo, monospace
}

/// Confidence badge colours. The THRESHOLDS are contractual — a user comparing Android and
/// iOS on the same meal must see the same badge. Evaluated in order, lower bound inclusive.
public enum PnConfidence {
    public struct Level: Sendable {
        public let min: Double
        public let level: String
        public let background: Color
        public let foreground: Color
    }

    public static let levels: [Level] = [
        Level(min: 0.8, level: "ok", background: Color(pnHex: 0xE2ECDF), foreground: Color(pnHex: 0x1F3D29)),
        Level(min: 0.6, level: "warn", background: Color(pnHex: 0xF6E8CF), foreground: Color(pnHex: 0x7A5116)),
        Level(min: 0.0, level: "bad", background: Color(pnHex: 0xF4DDD7), foreground: Color(pnHex: 0x7C2C1F)),
    ]

    public static func forConfidence(_ value: Double) -> Level {
        levels.first { value >= $0.min } ?? levels[levels.count - 1]
    }
}

/// Cooking methods, in picker order. Labels are NOT here — they are translatable and live in
/// strings/fr.json under `cookingMethods`, keyed by `id`.
///
/// `onBase` is dark rather than white for grilled and roasted, because white on those fills is
/// only 3.0:1 and 3.2:1. An active chip must also keep a border: those two fills are below the
/// 3:1 that WCAG 1.4.11 wants against paper, so the border carries the component boundary.
public enum PnCooking {
    public struct Method: Identifiable, Sendable {
        public let id: String
        public let emoji: String
        /// Fill of the active chip.
        public let base: Color
        /// Inactive pill and lane drop-zone background.
        public let soft: Color
        /// Label on `base`.
        public let onBase: Color
        /// Label on `soft`, and the lane header text.
        public let onSoft: Color
    }

    public static let methods: [Method] = [
        Method(id: "raw", emoji: "🌿", base: Color(pnHex: 0x3E7A4E), soft: Color(pnHex: 0xDBECDE), onBase: Color(pnHex: 0xFFFFFF), onSoft: Color(pnHex: 0x275433)),
        Method(id: "boiled", emoji: "🫧", base: Color(pnHex: 0x3D6A7A), soft: Color(pnHex: 0xD5EBF4), onBase: Color(pnHex: 0xFFFFFF), onSoft: Color(pnHex: 0x015166)),
        Method(id: "steamed", emoji: "♨️", base: Color(pnHex: 0x28756E), soft: Color(pnHex: 0xD5EDEA), onBase: Color(pnHex: 0xFFFFFF), onSoft: Color(pnHex: 0x005650)),
        Method(id: "grilled", emoji: "🔥", base: Color(pnHex: 0xE07A2F), soft: Color(pnHex: 0xF6E3D7), onBase: Color(pnHex: 0x4C2303), onSoft: Color(pnHex: 0x683C1F)),
        Method(id: "roasted", emoji: "🫕", base: Color(pnHex: 0xB08A2E), soft: Color(pnHex: 0xEFE6D4), onBase: Color(pnHex: 0x3A2500), onSoft: Color(pnHex: 0x5B450F)),
        Method(id: "fried", emoji: "🍳", base: Color(pnHex: 0xB9502D), soft: Color(pnHex: 0xF7E1DA), onBase: Color(pnHex: 0xFFFFFF), onSoft: Color(pnHex: 0x6B3A2A)),
    ]

    /// nil for an unknown method — the API can add one, so do not trap.
    public static func byId(_ id: String) -> Method? {
        methods.first { $0.id == id }
    }
}
