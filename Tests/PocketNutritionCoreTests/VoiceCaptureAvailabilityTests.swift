// SPDX-License-Identifier: MPL-2.0

import Testing

@testable import PocketNutritionCore

@Suite("voice capture availability")
struct VoiceCaptureAvailabilityTests {

    @Test("without a vault account nothing else matters", arguments: [true, false])
    func vaultComesFirst(serverConfigured: Bool) {
        #expect(voiceCaptureAvailability(vaultLinked: false, serverConfigured: serverConfigured) == .needsVaultAccount)
    }

    @Test("with a vault, the server setup decides")
    func serverSetup() {
        #expect(voiceCaptureAvailability(vaultLinked: true, serverConfigured: false) == .needsServerSetup)
        #expect(voiceCaptureAvailability(vaultLinked: true, serverConfigured: true) == .ready)
    }
}
