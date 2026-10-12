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
final class AppCoordinator: NSObject, NSMenuDelegate {
    private let store = ModelStore()
    private var setup: SetupWindowController?
    private var transcriber: Transcriber?
    private var llm: LLMEngine?
    private var hotkey: HotkeyController?
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?
    private var muteItem: NSMenuItem?
    private var removeLLMMenu: NSMenu?
    private var isSwitchingModel = false
    private let promptEditor = PromptEditorController()

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

        if let selected = VoxPreferences.selectedLLM, !store.isReady(selected) {
            await downloadModels()
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
            if transcriber == nil {
                await loadEngines()
            } else {
                await reloadLLM()
            }
        } catch {
            setup?.model.errorMessage = error.localizedDescription
        }
    }

    private func loadedTranscriber() async throws -> Transcriber {
        if let transcriber {
            return transcriber
        }
        let transcriber = try await Transcriber(modelFolder: store.whisperDirectory)
        self.transcriber = transcriber
        return transcriber
    }

    private func attachLLM(using transcriber: Transcriber) async throws {
        guard let directory = store.llmDirectory else {
            hotkey?.dropPipeline()
            llm = nil
            return
        }
        let llm = try await LLMEngine(modelDirectory: directory)
        self.llm = llm
        let pipeline = InferencePipeline(transcriber: transcriber, llm: llm)
        if let hotkey {
            hotkey.replacePipeline(pipeline)
        } else {
            hotkey = HotkeyController(pipeline: pipeline) { [weak self] text in
                self?.setStatus(text)
            }
        }
    }

    private func reloadLLM() async {
        guard let selected = VoxPreferences.selectedLLM else {
            await selectNone()
            return
        }
        setStatus("Loading \(selected.title)…")
        do {
            let transcriber = try await loadedTranscriber()
            try await attachLLM(using: transcriber)
            setStatus("Ready — \(selected.title)")
        } catch {
            Log.app.error("LLM reload failed: \(error.localizedDescription, privacy: .public)")
            setStatus("Failed to load \(selected.title)")
        }
    }

    private func selectNone() async {
        if hotkey?.isOccupied == true {
            setStatus("Wait — Vox is busy")
            return
        }
        VoxPreferences.selectedLLM = nil
        hotkey?.dropPipeline()
        llm = nil
        setStatus("No language model")
    }

    private func switchToLLM(_ option: LLMOption) async {
        guard !isSwitchingModel else { return }
        if hotkey?.isOccupied == true {
            setStatus("Wait — Vox is busy")
            return
        }
        isSwitchingModel = true
        defer { isSwitchingModel = false }
        VoxPreferences.selectedLLM = option
        if !store.isReady(option) {
            await downloadModels()
            guard store.isReady(option) else { return }
        }
        await reloadLLM()
    }

    private func loadEngines() async {
        setStatus("Loading models…")
        do {
            if store.whisperReady {
                _ = try await loadedTranscriber()
            }
            if let selected = VoxPreferences.selectedLLM, store.isReady(selected) {
                let transcriber = try await loadedTranscriber()
                try await attachLLM(using: transcriber)
                setStatus("Ready — \(selected.title)")
                Log.app.info("Vox is ready")
            } else {
                hotkey?.dropPipeline()
                llm = nil
                setStatus("No language model — pick one to download")
            }
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
            button.imagePosition = .imageOnly
            button.title = ""
        }
        let menu = NSMenu()
        menu.delegate = self
        let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(makeLLMMenu())
        menu.addItem(makeSoundsMenu())
        let promptItem = NSMenuItem(
            title: "Edit System Prompt…",
            action: #selector(openPromptEditor),
            keyEquivalent: ""
        )
        promptItem.target = self
        menu.addItem(promptItem)
        menu.addItem(.separator())
        let axItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibility),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)
        let accessibilityPromptItem = NSMenuItem(
            title: "Request Accessibility…",
            action: #selector(promptAccessibility),
            keyEquivalent: ""
        )
        accessibilityPromptItem.target = self
        menu.addItem(accessibilityPromptItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Vox", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        statusLabel = status
        refreshStatusIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshSoundMenuState()
        refreshLLMMenuState()
        refreshRemoveLLMMenu()
    }

    private func makeLLMMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Language model", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let none = NSMenuItem(title: "None", action: #selector(chooseLLM(_:)), keyEquivalent: "")
        none.target = self
        none.representedObject = LLMCatalog.noneID
        submenu.addItem(none)
        submenu.addItem(.separator())
        for option in LLMCatalog.all {
            let entry = NSMenuItem(title: option.menuTitle, action: #selector(chooseLLM(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = option.id
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove from This Mac", action: nil, keyEquivalent: "")
        let removeMenu = NSMenu()
        remove.submenu = removeMenu
        submenu.addItem(remove)
        item.submenu = submenu
        removeLLMMenu = removeMenu
        refreshLLMMenuState()
        refreshRemoveLLMMenu()
        return item
    }

    private var loadedLLM: LLMOption? {
        guard let selected = VoxPreferences.selectedLLM, store.isReady(selected), llm != nil else {
            return nil
        }
        return selected
    }

    private func refreshLLMMenuState() {
        let loaded = loadedLLM
        guard let llmMenu = statusItem?.menu?.items.first(where: { $0.title == "Language model" })?.submenu else {
            return
        }
        for item in llmMenu.items {
            guard let id = item.representedObject as? String else { continue }
            if id == LLMCatalog.noneID {
                item.state = loaded == nil ? .on : .off
                continue
            }
            guard let option = LLMCatalog.option(id: id) else { continue }
            item.title = store.isReady(option) ? option.menuTitle : "\(option.menuTitle), not installed"
            item.state = loaded?.id == option.id ? .on : .off
        }
    }

    private func refreshRemoveLLMMenu() {
        guard let removeLLMMenu else { return }
        removeLLMMenu.removeAllItems()
        let installed = store.installedLLMs
        if installed.isEmpty {
            let empty = NSMenuItem(title: "None installed", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            removeLLMMenu.addItem(empty)
            return
        }
        for option in installed {
            let title = option.id == loadedLLM?.id
                ? "\(option.menuTitle) (active)"
                : option.menuTitle
            let entry = NSMenuItem(title: title, action: #selector(removeLLM(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = option.id
            removeLLMMenu.addItem(entry)
        }
    }

    private func makeSoundsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let mute = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = VoxPreferences.soundsMuted ? .on : .off
        submenu.addItem(mute)
        muteItem = mute
        submenu.addItem(.separator())
        submenu.addItem(soundPicker(title: "Start", names: SoundCatalog.startOptions, action: #selector(chooseStartSound(_:))))
        submenu.addItem(soundPicker(title: "Done", names: SoundCatalog.doneOptions, action: #selector(chooseDoneSound(_:))))
        item.submenu = submenu
        return item
    }

    private func soundPicker(title: String, names: [String], action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for name in names {
            let entry = NSMenuItem(title: name, action: action, keyEquivalent: "")
            entry.target = self
            entry.representedObject = name
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private func refreshSoundMenuState() {
        muteItem?.state = VoxPreferences.soundsMuted ? .on : .off
        guard let sounds = muteItem?.menu else { return }
        for item in sounds.items {
            guard let submenu = item.submenu else { continue }
            let selected = item.title == "Start" ? VoxPreferences.startSoundName : VoxPreferences.doneSoundName
            for entry in submenu.items {
                entry.state = (entry.representedObject as? String) == selected ? .on : .off
            }
        }
    }

    private func setStatus(_ text: String) {
        statusLabel?.title = text
    }

    private func refreshStatusIcon() {
        let muted = VoxPreferences.soundsMuted
        statusItem?.button?.image = Self.makeMenuBarIcon(muted: muted)
        statusItem?.button?.toolTip = muted ? "Vox — muted" : "Vox"
    }

    private static func makeMenuBarIcon(muted: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
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
            if muted {
                let slash = NSBezierPath()
                slash.lineWidth = 1.8
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 4.2, y: 13.6))
                slash.line(to: NSPoint(x: 13.8, y: 4.4))
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func chooseLLM(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if id == LLMCatalog.noneID {
            Task { await selectNone() }
            return
        }
        guard let option = LLMCatalog.option(id: id) else { return }
        if option.id == loadedLLM?.id { return }
        Task { await switchToLLM(option) }
    }

    @objc private func removeLLM(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let option = LLMCatalog.option(id: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(option.title)?"
        alert.informativeText = "This deletes the downloaded weights from this Mac. You can install them again from Language model."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await deleteLLM(option) }
    }

    private func deleteLLM(_ option: LLMOption) async {
        if hotkey?.isOccupied == true {
            setStatus("Wait — Vox is busy")
            return
        }
        let removingActive = option.id == loadedLLM?.id || option.id == VoxPreferences.selectedLLM?.id
        if removingActive {
            hotkey?.dropPipeline()
            llm = nil
        }
        do {
            try store.remove(option)
            Log.app.info("Removed LLM \(option.title, privacy: .public)")
        } catch {
            setStatus("Could not remove \(option.title)")
            if removingActive {
                await reloadLLM()
            }
            return
        }
        if removingActive {
            if let next = store.installedLLMs.first {
                VoxPreferences.selectedLLM = next
                await reloadLLM()
            } else {
                VoxPreferences.selectedLLM = nil
                setStatus("No language model — pick one to download")
            }
        } else {
            setStatus("Removed \(option.title)")
        }
        refreshRemoveLLMMenu()
    }

    @objc private func toggleMute() {
        VoxPreferences.soundsMuted.toggle()
        refreshStatusIcon()
        refreshSoundMenuState()
    }

    @objc private func chooseStartSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        VoxPreferences.startSoundName = name
        VoxPreferences.soundsMuted = false
        refreshStatusIcon()
        NSSound(named: name)?.play()
    }

    @objc private func chooseDoneSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        VoxPreferences.doneSoundName = name
        VoxPreferences.soundsMuted = false
        refreshStatusIcon()
        NSSound(named: name)?.play()
    }

    @objc private func openPromptEditor() {
        promptEditor.show()
    }

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
