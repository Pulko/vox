import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSObject {
    let model = DownloadProgress()
    private var window: NSWindow?
    private var retry: (() -> Void)?

    func show(retry: @escaping () -> Void) {
        self.retry = retry
        let root = SetupView(model: model) { [weak self] in
            self?.retry?()
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vox Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 160))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}

private struct SetupView: View {
    @ObservedObject var model: DownloadProgress
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Downloading on-device models")
                .font(.headline)
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ProgressView(value: model.fraction)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Retry", action: onRetry)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
