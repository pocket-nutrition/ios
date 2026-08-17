// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import VisionKit

/// Wraps VisionKit's `DataScannerViewController` rather than a hand-rolled `AVCaptureSession` +
/// `AVCaptureMetadataOutput` stack. Both are physical-device-only — the Simulator has no camera either
/// way — so there is no compatibility trade-off, only how much code has to be written and maintained.
/// `DataScannerViewController` supplies the live preview, the barcode-highlighting UI and automatic
/// continuous detection for free, which is exactly the "auto-detect, no shutter button" behaviour this
/// feature needs.
///
/// Restricted to the `.ean13` symbology only: this app's backend endpoint is path-templated
/// `{ean13}`, and a scanned EAN-8 cannot be safely expanded into a 13-digit key (it is a
/// checksum-compressed encoding, not a truncated EAN-13) — see `normalizeToEan13`-equivalent reasoning
/// in the Android twin. Vision reports a UPC-A code under the `.ean13` symbology with its leading
/// zero already present, so UPC-A needs no separate handling here.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetect: onDetect)
    }

    /// Forwards the first recognised barcode's payload, then stops scanning immediately so the
    /// delegate does not keep firing while the lookup this triggers is in flight.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onDetect: (String) -> Void
        private var hasFired = false

        init(onDetect: @escaping (String) -> Void) {
            self.onDetect = onDetect
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasFired,
                  case let .barcode(barcode) = addedItems.first,
                  let payload = barcode.payloadStringValue
            else { return }
            hasFired = true
            dataScanner.stopScanning()
            onDetect(payload)
        }
    }
}
