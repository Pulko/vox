import AppKit
import ApplicationServices
import AVFoundation
import Foundation

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Prompts for Accessibility and Microphone, polling until Accessibility is granted or the user declines.
    @MainActor
    static func requestAll() async {
        if !isAccessibilityTrusted {
            _ = requestAccessibilityPrompt()
            let deadline = Date().addingTimeInterval(60)
            while !AXIsProcessTrusted() && Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if !AXIsProcessTrusted() {
                presentSettingsAlert(
                    title: "Accessibility Required",
                    message: "Vox needs Accessibility permission to read selected text and paste the result with Command-V.",
                    url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                )
            }
        }

        let micGranted = await requestMicrophone()
        if !micGranted {
            presentSettingsAlert(
                title: "Microphone Required",
                message: "Vox needs the microphone to capture your spoken instruction while you hold the hotkey.",
                url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            )
        }
    }

    @MainActor
    private static func presentSettingsAlert(title: String, message: String, url: URL?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url {
            NSWorkspace.shared.open(url)
        }
    }
}
