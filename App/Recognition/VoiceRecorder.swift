// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import Observation

/// Records one meal description to an AAC `.m4a` at a caller-supplied path, with a hard stop at 60 s.
///
/// The path is inside the app's private audio folder, so a clip is never written anywhere less
/// protected. Every way a recording can end on its own — the 60 s limit, an audio interruption (a
/// call, Siri), an encoder error — goes through `onAutoStop` with the clip so far, so the caller can
/// save it instead of losing it. Only `cancel()` deletes.
@MainActor
@Observable
final class VoiceRecorder {

    static let maxDuration: TimeInterval = 60

    enum RecorderError: Error {
        case couldNotStart
    }

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    /// Called when the recording ended by itself, with the file recorded so far (nil if it failed to
    /// produce anything usable).
    var onAutoStop: ((URL?) -> Void)?

    private var recorder: AVAudioRecorder?
    private var recorderDelegate: RecorderDelegate?
    private var fileURL: URL?
    private var timerTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    func start(writingTo url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            // Speech: mono, 22.05 kHz, 64 kbps keeps 60 s far below the server's 10 MB limit.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            let delegate = RecorderDelegate { [weak self] in
                Task { @MainActor in self?.endedByItself() }
            }
            recorder.delegate = delegate
            guard recorder.record(forDuration: Self.maxDuration) else { throw RecorderError.couldNotStart }
            self.recorder = recorder
            recorderDelegate = delegate
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        fileURL = url
        elapsed = 0
        isRecording = true
        observeInterruptions()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    /// Stops and returns the recorded file, or nil if nothing was recording.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        return finish()
    }

    /// Stops and deletes the recording — the one path that discards a clip, behind the Cancel button.
    func cancel() {
        guard isRecording else { return }
        if let url = finish() { try? FileManager.default.removeItem(at: url) }
    }

    private func tick() {
        guard let recorder, isRecording else { return }
        elapsed = min(recorder.currentTime, Self.maxDuration)
        if !recorder.isRecording { endedByItself() }
    }

    private func endedByItself() {
        guard isRecording else { return }
        onAutoStop?(finish())
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.endedByItself() }
        }
    }

    private func finish() -> URL? {
        timerTask?.cancel()
        timerTask = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        // Always stop, so the m4a header is finalised — even when the recorder already stopped itself.
        recorder?.stop()
        isRecording = false
        recorder = nil
        recorderDelegate = nil
        // Deactivate AFTER stop. Failing here is harmless: the clip is complete and there is nothing to retry.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { fileURL = nil }
        return fileURL
    }
}

/// `AVAudioRecorderDelegate` needs an `NSObject`; it only forwards "the recorder ended on its own".
private final class RecorderDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    private let onEnd: @Sendable () -> Void

    init(onEnd: @escaping @Sendable () -> Void) { self.onEnd = onEnd }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { onEnd() }
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { onEnd() }
}
