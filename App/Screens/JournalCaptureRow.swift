// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// A dictation or meal photo that is not a meal yet, shown in the journal at the time it was taken.
///
/// Drawn as an outline (dashed border, no fill) beside the solid cards of saved meals: the same place in
/// the day, visibly not finished. Its one line of status says what happens next, and the trailing label
/// names the action a tap performs, if any.
struct JournalCaptureRow: View {
    let entry: RecognitionEntry
    let isOffline: Bool

    var body: some View {
        let s = Strings.active
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.isPhoto == true ? "camera" : "mic")
                .font(.subheadline)
                .foregroundStyle(PnColor.brandLeafDeep)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.journalCaptureTitle(Self.time(entry.createdAt)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkDefault)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(entry.state == .needsRetry || entry.state == .unrecoverable
                        ? PnColor.statusBad : PnColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        let s = Strings.active
        switch entry.state {
        case .processing:
            ProgressView().controlSize(.small)
        case .ready:
            actionLabel(s.voiceOpen)
        case .pendingUpload:
            actionLabel(s.voiceSendNow)
        case .needsRetry:
            actionLabel(s.voiceRetry)
        case .unrecoverable:
            EmptyView()
        }
    }

    private func actionLabel(_ text: String) -> some View {
        HStack(spacing: 2) {
            Text(text)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(PnColor.brandLeafDeep)
    }

    private var statusText: String {
        let s = Strings.active
        switch entry.state {
        case .pendingUpload:
            if entry.lastUploadFailure == .unauthorized { return s.voiceApiKeyRefused }
            let offline = isOffline || entry.lastUploadFailure == .offline || entry.lastUploadFailure == .transient
            return offline ? s.voicePendingOffline : s.voiceStatusPendingUpload
        case .processing:
            switch entry.lastStatus {
            case .queued: return s.voiceStatusQueued
            case .transcribing: return s.voiceStatusTranscribing
            case .extracting: return s.voiceStatusExtracting
            default: return s.voiceStatusInProgress
            }
        case .ready:
            return s.voiceReadyItems(entry.result?.items.count ?? 0)
        case .needsRetry:
            if let error = entry.error, !error.isEmpty { return error }
            switch entry.endReason {
            case .expired: return s.voiceExpiredKept
            case .gone: return s.voiceGoneKept
            default: return s.voiceFailedKept
            }
        case .unrecoverable:
            return s.voiceUnrecoverable
        }
    }

    private static func time(_ createdAt: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: LanguageSettings.shared.effective == "en" ? "en_US" : "fr_FR")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: createdAt))
    }
}

extension View {
    /// The outline of a meal that is not finished yet: the card's shape, dashed, on the page colour.
    func pnPendingCard(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(PnColor.surfacePaper)
            .overlay(shape.strokeBorder(PnColor.inkSoft.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
