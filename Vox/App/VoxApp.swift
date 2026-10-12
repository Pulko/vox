import AppKit
import Foundation

@main
@MainActor
final class VoxApp: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()
    private static var retainedDelegate: VoxApp?

    static func main() {
        let app = NSApplication.shared
        let delegate = VoxApp()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
final class AppCoordinator: NSObject {
    private let store = ModelStore()
    private var setup: SetupWindowController?
    private var transcriber: Transcriber?
    private var llm: LLMEngine?
    private var hotkey: HotkeyController?
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?

    func start() {
        installStatusItem()
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        setStatus("Requesting permissions…")
        await Permissions.requestAll()

        if !store.isComplete {
            await downloadModels()
            guard store.isComplete else { return }
        }

        await loadEngines()
    }

    private func downloadModels() async {
        setStatus("Downloading models…")
        let controller = SetupWindowController()
        setup = controller
        controller.show { [weak self] in
            Task { await self?.retryDownload() }
        }
        do {
            try await ModelDownloader(store: store, progress: controller.model).downloadAll()
            controller.close()
            setup = nil
        } catch {
            Log.download.error("\(error.localizedDescription, privacy: .public)")
            controller.model.errorMessage = error.localizedDescription
            setStatus("Download failed")
        }
    }

    private func retryDownload() async {
        setup?.model.errorMessage = nil
        do {
            try await ModelDownloader(store: store, progress: setup!.model).downloadAll()
            setup?.close()
            setup = nil
            await loadEngines()
        } catch {
            setup?.model.errorMessage = error.localizedDescription
        }
    }

    private func loadEngines() async {
        setStatus("Loading models…")
        do {
            let transcriber = try await Transcriber(modelFolder: store.whisperDirectory)
            let llm = try await LLMEngine(modelDirectory: store.llamaDirectory)
            self.transcriber = transcriber
            self.llm = llm
            hotkey = HotkeyController(pipeline: InferencePipeline(transcriber: transcriber, llm: llm))
            setStatus("Ready — hold Option-Space")
            Log.app.info("Vox is ready")
        } catch {
            Log.app.error("Engine load failed: \(error.localizedDescription, privacy: .public)")
            setStatus("Failed to load models")
            let alert = NSAlert()
            alert.messageText = "Vox could not load models"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Vox"
        let menu = NSMenu()
        let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Vox", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        statusLabel = status
    }

    private func setStatus(_ text: String) {
        statusLabel?.title = text
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
