import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class HotkeyController {
    private var pipeline: InferencePipeline
    private let onStatus: (String) -> Void
    private let recorder = AudioRecorder()
    private var contextText = ""
    private var isRecording = false
    private var isBusy = false

    var isOccupied: Bool { isBusy || isRecording }

    init(pipeline: InferencePipeline, onStatus: @escaping (String) -> Void) {
        self.pipeline = pipeline
        self.onStatus = onStatus
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.handleKeyDown()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.handleKeyUp()
        }
        Log.input.info("Registered Option-Space push-to-talk")
    }

    func replacePipeline(_ pipeline: InferencePipeline) {
        self.pipeline = pipeline
    }

    private func handleKeyDown() {
        guard !isBusy, !isRecording else { return }
        contextText = ContextGrabber.grabSelectedText()
        do {
            try recorder.start()
            isRecording = true
            Feedback.recordingStarted()
            Log.input.info("Recording started; context length \(self.contextText.count)")
        } catch {
            Log.input.error("Recorder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleKeyUp() {
        guard isRecording else { return }
        isRecording = false
        let samples = recorder.stop()
        isBusy = true
        let context = contextText
        onStatus("Working…")
        Task {
            defer { isBusy = false }
            do {
                let output = try await pipeline.run(samples: samples, context: context)
                let outcome = Paster.paste(output)
                Feedback.finished()
                switch outcome {
                case .attempted:
                    onStatus("Done — paste sent, also on clipboard")
                case .accessibilityRequired:
                    onStatus("On clipboard — Accessibility needed for auto-paste")
                }
            } catch {
                Log.pipeline.error("Run failed: \(error.localizedDescription, privacy: .public)")
                onStatus("Failed — \(error.localizedDescription)")
            }
        }
    }
}
