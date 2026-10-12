import AppKit
import SwiftUI

@MainActor
final class PromptEditorController: NSObject {
    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: PromptEditorView { [weak self] in
            self?.close()
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = "System Prompt"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 480))
        window.minSize = NSSize(width: 420, height: 320)
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

private struct PromptEditorView: View {
    let onClose: () -> Void
    @State private var text = VoxPreferences.systemPrompt
    @State private var savedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Used as the model’s system message on every run. Takes effect immediately.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
            HStack {
                Button("Reset to Default") {
                    VoxPreferences.resetSystemPrompt()
                    text = PromptBuilder.defaultSystemPrompt
                    savedMessage = "Restored built-in prompt"
                }
                Spacer()
                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Close", action: onClose)
                Button("Save") {
                    VoxPreferences.systemPrompt = text
                    savedMessage = "Saved"
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }
}
