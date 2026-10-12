import AppKit
import Foundation

enum PasteOutcome {
    case attempted
    case accessibilityRequired
}

enum Paster {
    /// Keep this path deliberately simple. AX writes and repeated pasteboard writes
    /// caused browser focus races; the original setString -> Cmd+V path was reliable.
    static func paste(_ text: String) -> PasteOutcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Log.pipeline.error("Failed to write clipboard")
            return .attempted
        }
        guard Permissions.isAccessibilityTrusted else {
            Log.pipeline.error("Auto-paste skipped: Accessibility is not trusted for this build")
            return .accessibilityRequired
        }
        KeySynth.paste()
        return .attempted
    }
}

enum Feedback {
    static func recordingStarted() {
        play(VoxPreferences.startSoundName)
    }

    static func finished() {
        play(VoxPreferences.doneSoundName)
    }

    private static func play(_ name: String) {
        guard !VoxPreferences.soundsMuted else { return }
        NSSound(named: name)?.play()
    }
}
