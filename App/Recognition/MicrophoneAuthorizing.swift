// SPDX-License-Identifier: MPL-2.0

import AVFoundation

enum MicrophonePermission: Sendable, Equatable {
    case undetermined
    case granted
    case denied
}

/// Microphone permission, behind a protocol for the same reason as `CameraAuthorizing`.
///
/// `requestAccess()` shows the OS dialog only the first time; after a denial iOS answers `false`
/// immediately, so callers send the user to Settings instead of asking again.
protocol MicrophoneAuthorizing: Sendable {
    func status() -> MicrophonePermission
    func requestAccess() async -> Bool
}

struct AVFoundationMicrophoneAuthorizer: MicrophoneAuthorizing {
    func status() -> MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .undetermined
        case .granted: .granted
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
