// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// What the app owes the person holding it.
///
/// This screen is not "nice to have" — three separate obligations land on it, and each one is a
/// shipping blocker rather than a polish item:
///
/// 1. **MPL-2.0 §3.2.** The licence covers the *executable*, not only the repository. Someone who
///    installed the app from a store is a recipient of covered software and must be told they may
///    read, modify and redistribute the source. A LICENSE file in a Gitea repo reaches developers;
///    it does not reach them.
/// 2. **ODbL attribution.** Product names, brands and photographs come from Open Food Facts, whose
///    Open Database License requires attribution wherever the database is publicly used. Displaying
///    that data with no credit anywhere in the product is a licence breach.
/// 3. **A reachable privacy policy.** App Store Connect and Play Console both refuse a listing
///    without one. The in-app link is not itself the requirement — the hosted URL is — but an app
///    that only declares the policy in a console field and never shows it to the user is answering
///    the reviewer rather than the user.
///
/// WHAT THIS SCREEN MUST NOT DO
/// The copy here is a *summary* of the hosted policy. If the two ever disagree, the app is making a
/// privacy claim nobody reviewed. `about.privacySummary` is deliberately paired with
/// `about.privacyNetwork`: the first sentence alone reads as "nothing ever leaves the phone", which
/// is false — searching and analysing both make requests. Ship the pair or neither.
struct AboutView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    privacySection
                    sourcesSection
                    licenceSection
                }
                .padding(20)
            }
            .background(PnColor.surfacePaper)
            .navigationTitle(Fr.aboutTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Fr.aboutClose) { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fr.brand)
                .font(.title2.weight(.semibold))
                .foregroundStyle(PnColor.inkDefault)
            Text(Fr.aboutVersion(Self.marketingVersion))
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var privacySection: some View {
        section(Fr.aboutPrivacyTitle) {
            paragraph(Fr.aboutPrivacySummary)
            paragraph(Fr.aboutPrivacyNetwork)
            link(Fr.aboutPrivacyLink, Self.privacyPolicyURL)
        }
    }

    private var sourcesSection: some View {
        section(Fr.aboutSourcesTitle) {
            paragraph(Fr.aboutSourcesBody)
        }
    }

    private var licenceSection: some View {
        section(Fr.aboutLicenceTitle) {
            paragraph(Fr.aboutLicenceBody)
            link(Fr.aboutSourceLink, Self.sourceURL)

            // Kept in the same card as the licence because it answers the same question: what, other
            // than our own code, is running on your phone. The honest answer for this target is
            // "nothing", and it is checked rather than assumed — see `thirdPartyNone` below.
            Text(Fr.aboutThirdPartyTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PnColor.inkDefault)
                .padding(.top, 4)
            paragraph(Fr.aboutThirdPartyNone)
        }
    }

    // MARK: - Building blocks

    private func section(
        _ title: String,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PnColor.brandLeafDeep)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pnCard()
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PnColor.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tappable row rather than a `Link`: the whole line is the target, so it clears the 44 pt
    /// minimum without the caller having to think about it.
    private func link(_ label: String, _ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.footnote.weight(.medium))
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PnColor.brandLeafDeep)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Constants

    /// Read from the bundle rather than hardcoded, so it cannot disagree with what the store shows.
    /// `CFBundleShortVersionString` is `MARKETING_VERSION` — CalVer, e.g. 2026.08.3.
    private static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// The same URL the App Store Connect listing declares. Force-unwrapped deliberately: these are
    /// two compile-time literals, and a typo should be caught by the launch of the screen in review
    /// rather than silently rendering a dead row.
    private static let privacyPolicyURL = URL(string: "https://website.pocketnutrition.org/privacy.html")!

    /// Verified reachable **unauthenticated** before shipping. A source link behind a login would
    /// make `about.licenceBody` untrue in practice, which is the one thing this screen cannot be.
    private static let sourceURL = URL(string: "https://github.com/pocket-nutrition/ios")!
}
