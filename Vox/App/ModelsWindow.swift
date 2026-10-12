import AppKit
import SwiftUI

@MainActor
final class ModelsState: ObservableObject {
    @Published var writerInUseID: String?
    @Published var parserInUseID: String?
    @Published var note: String = ""

    func ping() {
        objectWillChange.send()
    }
}

@MainActor
protocol ModelsHosting: AnyObject {
    var store: ModelStore { get }
    var modelsState: ModelsState { get }
    func useWriter(_ option: LLMOption?) async
    func useParser(_ option: LLMOption?) async
    func removeModel(_ option: LLMOption) async
}

@MainActor
final class ModelsWindowController: NSObject {
    private weak var host: ModelsHosting?
    private var window: NSWindow?

    init(host: ModelsHosting) {
        self.host = host
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let host else { return }
        let hosting = NSHostingController(rootView: ModelsView(host: host))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Models"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 520))
        window.minSize = NSSize(width: 480, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct ModelsView: View {
    let host: ModelsHosting
    @ObservedObject var state: ModelsState

    init(host: ModelsHosting) {
        self.host = host
        self.state = host.modelsState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(
                    title: "Text writer",
                    subtitle: "Turns the selection and your request into the text you paste. None means Vox does not generate.",
                    options: LLMCatalog.writers,
                    inUseID: state.writerInUseID,
                    onNone: { Task { await host.useWriter(nil) } },
                    onUse: { option in Task { await host.useWriter(option) } }
                )
                Divider()
                section(
                    title: "Instruction parser",
                    subtitle: "Optional. A small, fast model that reads your speech before the writer. If none is installed or in use, cleaned speech goes straight to the writer.",
                    options: LLMCatalog.parsers,
                    inUseID: state.parserInUseID,
                    onNone: { Task { await host.useParser(nil) } },
                    onUse: { option in Task { await host.useParser(option) } }
                )
                if !state.note.isEmpty {
                    Text(state.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func section(
        title: String,
        subtitle: String,
        options: [LLMOption],
        inUseID: String?,
        onNone: @escaping () -> Void,
        onUse: @escaping (LLMOption) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            row(
                title: "None",
                status: inUseID == nil ? "In use" : "",
                inUse: inUseID == nil,
                showRemove: false,
                onUse: onNone,
                onRemove: {}
            )
            ForEach(options) { option in
                let installed = host.store.isReady(option)
                let inUse = inUseID == option.id
                row(
                    title: option.menuTitle,
                    status: inUse ? "In use" : (installed ? "Installed" : "Not installed"),
                    inUse: inUse,
                    showRemove: installed,
                    onUse: { onUse(option) },
                    onRemove: { Task { await host.removeModel(option) } }
                )
            }
        }
    }

    private func row(
        title: String,
        status: String,
        inUse: Bool,
        showRemove: Bool,
        onUse: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: inUse ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(inUse ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Use", action: onUse)
            if showRemove {
                Button("Remove", action: onRemove)
            }
        }
        .padding(.vertical, 4)
    }
}
