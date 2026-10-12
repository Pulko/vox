import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<Void, Never>?

    func present() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
    }

    private func show() {
        let hosting = NSHostingController(rootView: WelcomeView { [weak self] in
            self?.finish()
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Vox"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 280))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private func finish() {
        guard continuation != nil else { return }
        VoxPreferences.didShowWelcome = true
        let pending = continuation
        continuation = nil
        window?.delegate = nil
        window?.close()
        window = nil
        pending?.resume()
    }
}

private struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vox is in the menu bar")
                .font(.title2.weight(.semibold))
            Text("It does not appear in the Dock. Look for the waveform icon at the top of the screen.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Hold Option-Space with text highlighted, then speak what to do.")
                Text("Open Models… and press Use to download a writer. Nothing downloads until then.")
                Text("macOS will ask for the microphone and Accessibility.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
