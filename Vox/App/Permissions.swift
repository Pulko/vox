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

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for string in urls {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    static func requestMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
            let granted = await withTimeout(seconds: 20) {
                await AVCaptureDevice.requestAccess(for: .audio)
            }
            return granted ?? (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Prompt once and return quickly. Does not wait for the user to toggle Accessibility;
    /// a rebuilt ad-hoc binary is a new identity even if Settings still shows Vox enabled.
    @MainActor
    static func requestAll() async {
        if !isAccessibilityTrusted {
            _ = requestAccessibilityPrompt()
            for _ in 0..<4 where !AXIsProcessTrusted() {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        let micGranted = await requestMicrophone()
        if !micGranted, AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
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

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
