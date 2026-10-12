import Foundation

enum VoxError: LocalizedError {
    case microphoneDenied
    case accessibilityDenied
    case shortRecording
    case emptyTranscription
    case emptyOutput
    case downloadFailed(String)
    case modelsMissing
    case audioFormat

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is required for push-to-talk."
        case .accessibilityDenied:
            return "Accessibility access is required to read selected text and paste results."
        case .shortRecording:
            return "Recording was too short."
        case .emptyTranscription:
            return "Could not transcribe the recording."
        case .emptyOutput:
            return "The model returned empty text."
        case .downloadFailed(let message):
            return "Model download failed: \(message)"
        case .modelsMissing:
            return "Model files are missing."
        case .audioFormat:
            return "Could not configure the microphone audio format."
        }
    }
}
