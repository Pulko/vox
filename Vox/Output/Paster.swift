import AppKit
import Foundation

enum Paster {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        KeySynth.paste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            snapshot.restore(to: pasteboard)
        }
    }
}

enum Feedback {
    static func recordingStarted() {
        NSSound(named: "Tink")?.play()
    }

    static func finished() {
        NSSound(named: "Glass")?.play()
    }
}
