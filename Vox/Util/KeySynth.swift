import CoreGraphics
import Foundation

enum KeySynth {
    static let vKey: CGKeyCode = 0x09

    static func postCommand(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func paste() {
        postCommand(vKey)
    }
}
