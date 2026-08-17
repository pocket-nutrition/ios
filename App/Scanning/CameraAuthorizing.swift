// SPDX-License-Identifier: MPL-2.0

import AVFoundation

/// Camera permission, behind a protocol so the state machine in `BarcodeScanFlowView` does not depend
/// directly on `AVCaptureDevice` — the same default-parameter DI shape `JournalStore` and
/// `PocketNutritionApi` already use elsewhere in this app.
protocol CameraAuthorizing: Sendable {
    func status() -> AVAuthorizationStatus
    func requestAccess() async -> Bool
}

/// The real implementation, backed by `AVCaptureDevice`.
///
/// `requestAccess()` only shows the OS permission dialog the first time it is ever called for this
/// app: once the user has denied it, iOS returns `false` immediately on every subsequent call without
/// prompting again. `BarcodeScanFlowView` relies on this — it never calls `requestAccess()` again once
/// `status()` reports `.denied`, and instead directs the user to Settings.
struct AVFoundationCameraAuthorizer: CameraAuthorizing {
    func status() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
