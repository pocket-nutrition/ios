// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionVault
import UIKit

/// The microphone side of dictating a meal from the add-ingredient screen: permission, recording, and
/// handing the clip to the recognition coordinator. Meal photos take the same path (one entry, one
/// ticket, the result added to the meal), only the capture differs.
///
/// Every recording becomes a local entry BEFORE any network call, so a dictation is never lost to a bad
/// connection; only `cancel()` throws a clip away. The entries made here are remembered in `recordedIds`
/// so the screen can follow them and add what they recognise to the meal.
@MainActor
@Observable
final class DictationSession {

    enum MicAlert: Identifiable {
        case explainer, denied
        var id: Self { self }
    }

    let recorder = VoiceRecorder()
    var micAlert: MicAlert?
    var errorMessage: String?
    /// The microphone was tapped with no vault account: the vault onboarding opens instead of recording.
    var isShowingVault = false
    /// Entries recorded from this screen, oldest first.
    private(set) var recordedIds: [String] = []

    private let authorizer: any MicrophoneAuthorizing

    init(authorizer: any MicrophoneAuthorizing = AVFoundationMicrophoneAuthorizer()) {
        self.authorizer = authorizer
    }

    /// Voice needs a linked vault account (that is where the result is delivered). Without one the mic
    /// leads to onboarding, never to an upload.
    func tapMic(store: RecognitionEntryStore, coordinator: RecognitionCoordinator) {
        guard VaultInbox.live() != nil else {
            isShowingVault = true
            return
        }
        switch authorizer.status() {
        case .granted: begin(store: store, coordinator: coordinator)
        case .undetermined: micAlert = .explainer
        case .denied: micAlert = .denied
        }
    }

    /// Only reached from the explainer, i.e. when the OS dialog is guaranteed to appear.
    func requestMicrophone(store: RecognitionEntryStore, coordinator: RecognitionCoordinator) {
        Task {
            if await authorizer.requestAccess() {
                begin(store: store, coordinator: coordinator)
            } else {
                micAlert = .denied
            }
        }
    }

    func stop(store: RecognitionEntryStore, coordinator: RecognitionCoordinator) {
        guard let url = recorder.stop() else { return }
        if !persist(url, store: store, coordinator: coordinator) { errorMessage = Strings.active.voiceSaveFailed }
    }

    func cancel() { recorder.cancel() }

    // MARK: - Meal photo

    enum PhotoSource: Identifiable {
        case camera, library
        var id: Self { self }
    }

    /// The camera button was tapped: the source picker shows (camera or library).
    var isChoosingPhotoSource = false
    /// The camera was chosen. The library uses `isPickingFromLibrary` (a different presentation).
    var isTakingPhoto = false
    var isPickingFromLibrary = false

    /// A photo is delivered through the vault like a dictation, so it needs the same linked account.
    func tapPhoto() {
        guard VaultInbox.live() != nil else {
            isShowingVault = true
            return
        }
        isChoosingPhotoSource = true
    }

    /// The camera was refused in Settings: explain instead of opening a black viewfinder.
    var isCameraDenied = false

    func choose(_ source: PhotoSource, camera: any CameraAuthorizing = AVFoundationCameraAuthorizer()) {
        switch source {
        case .library:
            isPickingFromLibrary = true
        case .camera:
            switch camera.status() {
            // Not determined: the camera picker asks by itself.
            case .authorized, .notDetermined: isTakingPhoto = true
            default: isCameraDenied = true
            }
        }
    }

    /// Encodes the photo (metadata dropped, size bounded), saves it beside the clips and queues it like
    /// a dictation: persisted BEFORE any network call.
    func submitPhoto(_ image: UIImage, store: RecognitionEntryStore, coordinator: RecognitionCoordinator) {
        guard let jpeg = MealPhotoEncoder.jpeg(from: image),
              let url = try? store.savePhoto(jpeg),
              persist(url, store: store, coordinator: coordinator)
        else {
            errorMessage = Strings.active.photoSaveFailed
            return
        }
    }

    /// Leaving the screen keeps a clip in progress: it is saved and sent like any other.
    func saveIfRecording(store: RecognitionEntryStore, coordinator: RecognitionCoordinator) {
        if recorder.isRecording { stop(store: store, coordinator: coordinator) }
    }

    // MARK: - Plumbing

    private func begin(store: RecognitionEntryStore, coordinator: RecognitionCoordinator) {
        recorder.onAutoStop = { [weak self] url in
            guard let self else { return }
            guard let url else {
                errorMessage = Strings.active.voiceMicFailed
                return
            }
            if !persist(url, store: store, coordinator: coordinator) { errorMessage = Strings.active.voiceSaveFailed }
        }
        do {
            try recorder.start(writingTo: store.newRecordingURL())
        } catch {
            errorMessage = Strings.active.voiceMicFailed
        }
    }

    private func persist(_ url: URL, store: RecognitionEntryStore, coordinator: RecognitionCoordinator) -> Bool {
        guard let entry = try? store.createEntry(adopting: url) else { return false }
        recordedIds.append(entry.localId)
        coordinator.track(entry.localId)
        return true
    }
}
