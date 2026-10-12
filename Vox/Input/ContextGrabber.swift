import ApplicationServices
import AppKit
import Foundation

enum ContextGrabber {
    static func grabSelectedText() -> String {
        if let axText = axSelectedText(), !axText.isEmpty {
            return axText
        }
        return clipboardFallback()
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusedStatus == .success, let element = focused else { return nil }

        var value: CFTypeRef?
        let textStatus = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard textStatus == .success else { return nil }
        return value as? String
    }

    private static func clipboardFallback() -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let before = pasteboard.changeCount
        KeySynth.copy()

        let deadline = Date().addingTimeInterval(0.15)
        while Date() < deadline {
            if pasteboard.changeCount != before {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        let text: String
        if pasteboard.changeCount != before {
            text = pasteboard.string(forType: .string) ?? ""
        } else {
            text = ""
        }
        snapshot.restore(to: pasteboard)
        return text
    }
}
