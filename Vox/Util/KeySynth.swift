import CoreGraphics
import Foundation

enum KeySynth {
    static let cKey: CGKeyCode = 0x08
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

    static func copy() {
        postCommand(cKey)
    }

    static func paste() {
        postCommand(vKey)
    }
}
