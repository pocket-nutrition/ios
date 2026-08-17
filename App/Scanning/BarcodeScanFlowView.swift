// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import VisionKit
import PocketNutritionCore

/// Everything the barcode-scan button needs: the permission state machine, the live scanner, and the
/// lookup against `GET /ingredients/barcode/{ean13}`.
///
/// Kept as its own view rather than more `@State` on `MealBuilderView` — that view is already large
/// and unrelated to a six-branch permission flow. `MealBuilderView` only ever sees one `Bool`
/// (`isScanningBarcode`) and this closure.
///
/// Presented with `.fullScreenCover`, which recreates this view's state on every presentation. That is
/// what makes "denied, granted via Settings, tapped again" and "already granted" behave correctly with
/// no `scenePhase` observer: `stage` is computed fresh from `authorizer.status()` in `.onAppear` every
/// single time the flow opens, and the retry is always a new user-initiated tap of the camera button —
/// never something that must react the instant the user leaves Settings.
struct BarcodeScanFlowView: View {
    let onFound: (IngredientSuggestion) -> Void

    private let authorizer: any CameraAuthorizing = AVFoundationCameraAuthorizer()

    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .checking

    private enum Stage: Equatable {
        case checking
        case unavailable
        case explainer
        case deniedGoToSettings
        case scanning
        case lookingUp
        case notFound
        case failed(String)
    }

    var body: some View {
        ZStack {
            PnColor.surfaceInverse.ignoresSafeArea()

            switch stage {
            case .checking:
                ProgressView().tint(.white)

            case .unavailable:
                messageCard(
                    title: Fr.scanUnavailableTitle,
                    body: Fr.scanUnavailable,
                    primaryTitle: Fr.aboutClose,
                    primaryAction: { dismiss() }
                )

            case .explainer:
                messageCard(
                    title: Fr.scanExplainerTitle,
                    body: Fr.scanExplainerBody,
                    primaryTitle: Fr.scanExplainerContinue,
                    primaryAction: requestAccess,
                    secondaryTitle: Fr.scanExplainerNotNow,
                    secondaryAction: { dismiss() }
                )

            case .deniedGoToSettings:
                messageCard(
                    title: Fr.scanSettingsTitle,
                    body: Fr.scanSettingsBody,
                    primaryTitle: Fr.scanSettingsOpenSettings,
                    primaryAction: openSettings,
                    secondaryTitle: Fr.searchCancel,
                    secondaryAction: { dismiss() }
                )

            // One switch arm for both stages, not two: a `switch` case change is a branch change, and
            // SwiftUI is free to tear down and rebuild a view whose branch changed — which here would
            // restart the live camera right as a lookup begins. `lookUp`'s own guard is what actually
            // stops a second addition; this just avoids the camera visibly restarting for no reason.
            case .scanning, .lookingUp:
                ZStack {
                    scannerLayer
                    if stage == .lookingUp {
                        ProgressView(Fr.scanLookingUp)
                            .tint(.white)
                            .foregroundStyle(.white)
                            .padding(20)
                            .background(PnColor.surfaceInverse.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

            case .notFound:
                messageCard(
                    title: Fr.scanNotFoundTitle,
                    body: Fr.scanNotFound,
                    primaryTitle: Fr.retry,
                    primaryAction: { stage = .scanning },
                    secondaryTitle: Fr.searchCancel,
                    secondaryAction: { dismiss() }
                )

            case .failed(let message):
                messageCard(
                    title: Fr.scanErrorTitle,
                    body: Fr.error(message),
                    primaryTitle: Fr.retry,
                    primaryAction: { stage = .scanning },
                    secondaryTitle: Fr.searchCancel,
                    secondaryAction: { dismiss() }
                )
            }
        }
        .onAppear(perform: evaluateAccess)
    }

    // MARK: - Scanner

    private var scannerLayer: some View {
        ZStack(alignment: .topTrailing) {
            BarcodeScannerView(onDetect: lookUp)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            .padding(20)
        }
    }

    // MARK: - Permission state machine

    private func evaluateAccess() {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            stage = .unavailable
            return
        }
        switch authorizer.status() {
        case .authorized: stage = .scanning
        case .notDetermined: stage = .explainer
        case .denied, .restricted: stage = .deniedGoToSettings
        @unknown default: stage = .deniedGoToSettings
        }
    }

    /// Called only from `.explainer`, i.e. only when `status()` was `.notDetermined` — the one case
    /// where the OS dialog is guaranteed to actually appear. Once denied, iOS never shows it again for
    /// this app, so every other branch goes straight to `.deniedGoToSettings` instead of calling this.
    private func requestAccess() {
        Task {
            let granted = await authorizer.requestAccess()
            stage = granted ? .scanning : .deniedGoToSettings
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Lookup

    /// The real guard against a second detection turning into a second addition. `BarcodeScannerView`'s
    /// `Coordinator` also guards this with its own `hasFired` flag plus `stopScanning()`, but that
    /// protection lives on the camera view, which SwiftUI can recreate (with a fresh, unfired
    /// coordinator) across a state change — and the scanned product is almost certainly still in frame
    /// when that happens, so a recreated camera detects it again immediately. `stage` belongs to this
    /// view, not the camera view, so it stays correct regardless of what the camera view does.
    private func lookUp(_ payload: String) {
        guard stage == .scanning else { return }
        // A defensive length/digit check before calling the server. `DataScannerViewController`
        // already validates the EAN-13 check digit before reporting a match at all, so a payload
        // failing this is effectively unreachable — treated the same as "not in the catalogue" rather
        // than invented copy for a case that shouldn't occur.
        guard payload.count == 13, payload.allSatisfy(\.isNumber) else {
            stage = .notFound
            return
        }
        stage = .lookingUp
        Task {
            do {
                if let suggestion = try await PocketNutritionApi.shared.lookupBarcode(payload) {
                    onFound(suggestion)
                } else {
                    stage = .notFound
                }
            } catch {
                stage = .failed((error as? ApiError)?.errorDescription ?? "\(error)")
            }
        }
    }

    // MARK: - Shared card layout

    @ViewBuilder
    private func messageCard(
        title: String,
        body: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(PnColor.brandLeaf)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PnColor.inkDefault)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(PnColor.inkSoft)
                .multilineTextAlignment(.center)

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(PrimaryButtonStyle())

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkSoft)
            }
        }
        .padding(24)
        .pnCard(cornerRadius: 20)
        .padding(32)
    }
}
