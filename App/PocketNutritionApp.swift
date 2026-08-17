// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main
struct PocketNutritionApp: App {

    /// Created once for the process lifetime and handed to the view tree. The store reads its file in
    /// `init`, so making it a `@State` here rather than constructing it per-view keeps that to a
    /// single read at launch.
    @State private var journal = JournalStore()

    var body: some Scene {
        WindowGroup {
            JournalView()
                .environment(journal)
                // PnColor is a fixed light palette with no dark variants (matches Android's
                // light-only theme). Without pinning this, system Dark Mode flips automatic
                // colors (nav title, text field text, status bar) to white while our custom
                // backgrounds stay light, making titles unreadable.
                .preferredColorScheme(.light)
        }
    }
}
