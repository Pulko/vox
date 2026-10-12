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
        setStatus("Checking permissions…")
        await Permissions.requestAll()
        if !Permissions.isAccessibilityTrusted {
            setStatus("Toggle Vox off/on in Accessibility, then wait")
            Log.app.error("Accessibility not trusted for this binary; Settings may list a previous build")
        }
        watchAccessibility()

        if !store.isComplete {
            await downloadModels()
            guard store.isComplete else { return }
        }

        await loadEngines()
    }

    private func watchAccessibility() {
        Task { [weak self] in
            while let self, !Task.isCancelled {
                if Permissions.isAccessibilityTrusted {
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Permissions.isAccessibilityTrusted {
                    self.setStatus("Accessibility granted")
                    Log.app.info("Accessibility became trusted")
                    return
                }
            }
        }
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
            hotkey = HotkeyController(
                pipeline: InferencePipeline(transcriber: transcriber, llm: llm)
            ) { [weak self] text in
                self?.setStatus(text)
            }
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarIcon
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Vox"
        }
        let menu = NSMenu()
        let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let axItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibility),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)
        let promptItem = NSMenuItem(
            title: "Request Accessibility…",
            action: #selector(promptAccessibility),
            keyEquivalent: ""
        )
        promptItem.target = self
        menu.addItem(promptItem)
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

    private static let menuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.2, y: 1.2, width: 15.6, height: 15.6)).fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let barWidth: CGFloat = 1.45
            let origins: [(CGFloat, CGFloat)] = [
                (5.7, 4.4),
                (7.6, 7.8),
                (9.5, 5.6),
                (11.4, 6.8),
            ]
            for (x, height) in origins {
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: 9 - height / 2, width: barWidth, height: height),
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                )
                bar.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func promptAccessibility() {
        _ = Permissions.requestAccessibilityPrompt()
        Permissions.openAccessibilitySettings()
        setStatus("Toggle Vox off/on in Accessibility")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
