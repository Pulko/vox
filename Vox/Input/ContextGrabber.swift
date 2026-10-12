import ApplicationServices
import Foundation

enum ContextGrabber {
    static func grabSelectedText() -> String {
        axSelectedText() ?? ""
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
}
