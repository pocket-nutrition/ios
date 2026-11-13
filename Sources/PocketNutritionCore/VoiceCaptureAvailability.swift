// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Whether voice capture can be used, and if not, what the person has to do first.
///
/// A vault account comes first: the result of a recording is sealed into the person's own vault, so
/// without one there is nowhere to put it and the recording is not sent at all. The recognition server
/// setup only matters once that is in place.
public enum VoiceCaptureAvailability: Equatable, Sendable {
    case needsVaultAccount
    case needsServerSetup
    case ready
}

public func voiceCaptureAvailability(vaultLinked: Bool, serverConfigured: Bool) -> VoiceCaptureAvailability {
    guard vaultLinked else { return .needsVaultAccount }
    return serverConfigured ? .ready : .needsServerSetup
}
