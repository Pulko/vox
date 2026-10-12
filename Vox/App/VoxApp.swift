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
final class AppCoordinator: NSObject, NSMenuDelegate, ModelsHosting {
    let store = ModelStore()
    let modelsState = ModelsState()
    private var setup: SetupWindowController?
    private var transcriber: Transcriber?
    private var llm: LLMEngine?
    private var parserEngine: LLMEngine?
    private var pipeline: InferencePipeline?
    private var hotkey: HotkeyController?
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?
    private var soundsMenu: NSMenu?
    private var isSwitchingModel = false
    private var downloadTarget: LLMOption?
    private let promptEditor = PromptEditorController()
    private let welcome = WelcomeWindowController()
    private lazy var modelsWindow = ModelsWindowController(host: self)

    func start() {
        installStatusItem()
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        if !VoxPreferences.didShowWelcome {
            await welcome.present()
        }
        setStatus("Checking permissions…")
        await Permissions.requestAll()
        if !Permissions.isAccessibilityTrusted {
            setStatus("Toggle Vox off/on in Accessibility, then wait")
            Log.app.error("Accessibility not trusted for this binary; Settings may list a previous build")
        }
        watchAccessibility()

        if let selected = VoxPreferences.selectedLLM, !store.isReady(selected) {
            await downloadModels(for: selected)
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

    private func downloadModels(for option: LLMOption) async {
        downloadTarget = option
        setStatus("Downloading \(option.title)…")
        let controller = SetupWindowController()
        setup = controller
        controller.show { [weak self] in
            Task { await self?.retryDownload() }
        }
        do {
            try await ModelDownloader(store: store, progress: controller.model).download(option)
            controller.close()
            setup = nil
        } catch {
            Log.download.error("\(error.localizedDescription, privacy: .public)")
            controller.model.errorMessage = error.localizedDescription
            setStatus("Download failed")
        }
    }

    private func retryDownload() async {
        guard let option = downloadTarget else { return }
        setup?.model.errorMessage = nil
        do {
            try await ModelDownloader(store: store, progress: setup!.model).download(option)
            setup?.close()
            setup = nil
            await loadEngines()
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

    private func attachEngines(using transcriber: Transcriber) async throws {
        guard let directory = store.llmDirectory else {
            hotkey?.dropPipeline()
            pipeline = nil
            llm = nil
            parserEngine = nil
            return
        }
        let writer = try await LLMEngine(modelDirectory: directory)
        llm = writer
        parserEngine = await loadParserIfReady()
        if let pipeline {
            pipeline.replace(llm: writer, parser: parserEngine)
        } else {
            let pipeline = InferencePipeline(transcriber: transcriber, llm: writer, parser: parserEngine)
            self.pipeline = pipeline
            if let hotkey {
                hotkey.replacePipeline(pipeline)
            } else {
                hotkey = HotkeyController(pipeline: pipeline) { [weak self] text in
                    self?.setStatus(text)
                }
            }
        }
    }

    private func loadParserIfReady() async -> LLMEngine? {
        guard let option = VoxPreferences.selectedParser, store.isReady(option) else {
            return nil
        }
        guard let directory = store.parserDirectory else { return nil }
        do {
            let engine = try await LLMEngine(modelDirectory: directory)
            Log.pipeline.info("Parser loaded: \(option.title, privacy: .public)")
            return engine
        } catch {
            Log.pipeline.error("Parser load skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func readyStatus() -> String {
        let writer = llm == nil ? "None" : (VoxPreferences.selectedLLM?.title ?? "None")
        let parser = parserEngine == nil ? "None" : (VoxPreferences.selectedParser?.title ?? "None")
        return "Writer: \(writer) · Parser: \(parser)"
    }

    private func refreshModelsUI() {
        modelsState.writerInUseID = llm == nil ? nil : VoxPreferences.selectedLLM?.id
        modelsState.parserInUseID = parserEngine == nil ? nil : VoxPreferences.selectedParser?.id
        modelsState.ping()
    }

    private func reloadWriter() async {
        guard let selected = VoxPreferences.selectedLLM else {
            await useWriter(nil)
            return
        }
        setStatus("Loading \(selected.title)…")
        do {
            let transcriber = try await loadedTranscriber()
            try await attachEngines(using: transcriber)
            setStatus(readyStatus())
        } catch {
            Log.app.error("Writer reload failed: \(error.localizedDescription, privacy: .public)")
            setStatus("Failed to load \(selected.title)")
        }
        refreshModelsUI()
    }

    func useWriter(_ option: LLMOption?) async {
        guard !isSwitchingModel else { return }
        if hotkey?.isOccupied == true {
            setStatus("Wait — Vox is busy")
            return
        }
        isSwitchingModel = true
        defer { isSwitchingModel = false }
        guard let option else {
            VoxPreferences.selectedLLM = nil
            hotkey?.dropPipeline()
            pipeline = nil
            llm = nil
            setStatus(readyStatus())
            refreshModelsUI()
            return
        }
        VoxPreferences.selectedLLM = option
        if !store.isReady(option) {
            await downloadModels(for: option)
            guard store.isReady(option) else { return }
        }
        await reloadWriter()
    }

    func useParser(_ option: LLMOption?) async {
        guard !isSwitchingModel else { return }
        if hotkey?.isOccupied == true {
            setStatus("Wait — Vox is busy")
            return
        }
        isSwitchingModel = true
        defer { isSwitchingModel = false }
        guard let option else {
            VoxPreferences.selectedParser = nil
            parserEngine = nil
            if let llm {
                pipeline?.replace(llm: llm, parser: nil)
            }
            setStatus(readyStatus())
            refreshModelsUI()
            return
        }
        VoxPreferences.selectedParser = option
        if !store.isReady(option) {
            await downloadModels(for: option)
            guard store.isReady(option) else {
                parserEngine = nil
                refreshModelsUI()
                return
            }
        }
        parserEngine = await loadParserIfReady()
        if let llm {
            pipeline?.replace(llm: llm, parser: parserEngine)
        }
        setStatus(readyStatus())
        refreshModelsUI()
    }

    func removeModel(_ option: LLMOption) async {
        if hotkey?.isOccupied == true {
            setStatus("Wait — Vox is busy")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Remove \(option.title)?"
        alert.informativeText = "This deletes the downloaded weights from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let removingWriter = option.id == VoxPreferences.selectedLLM?.id
        let removingParser = option.id == VoxPreferences.selectedParser?.id
        if removingWriter {
            hotkey?.dropPipeline()
            pipeline = nil
            llm = nil
        }
        if removingParser {
            parserEngine = nil
        }
        do {
            try store.remove(option)
        } catch {
            setStatus("Could not remove \(option.title)")
            await loadEngines()
            return
        }
        if removingWriter {
            VoxPreferences.selectedLLM = nil
        }
        if removingParser {
            VoxPreferences.selectedParser = nil
        }
        if llm != nil, let writer = llm {
            pipeline?.replace(llm: writer, parser: parserEngine)
        }
        setStatus("Removed \(option.title)")
        refreshModelsUI()
        if VoxPreferences.selectedLLM != nil, llm == nil {
            await loadEngines()
        }
    }

    private func loadEngines() async {
        setStatus("Loading models…")
        do {
            if store.whisperReady {
                _ = try await loadedTranscriber()
            }
            if let selected = VoxPreferences.selectedLLM, store.isReady(selected) {
                let transcriber = try await loadedTranscriber()
                try await attachEngines(using: transcriber)
                setStatus(readyStatus())
                Log.app.info("Vox is ready")
            } else {
                hotkey?.dropPipeline()
                pipeline = nil
                llm = nil
                parserEngine = await loadParserIfReady()
                setStatus(readyStatus())
            }
        } catch {
            Log.app.error("Engine load failed: \(error.localizedDescription, privacy: .public)")
            setStatus("Failed to load models")
            let alert = NSAlert()
            alert.messageText = "Vox could not load models"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshModelsUI()
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
        let modelsItem = NSMenuItem(title: "Models…", action: #selector(openModels), keyEquivalent: "")
        modelsItem.target = self
        menu.addItem(modelsItem)
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
        let noticesItem = NSMenuItem(
            title: "Third-Party Notices…",
            action: #selector(openNotices),
            keyEquivalent: ""
        )
        noticesItem.target = self
        menu.addItem(noticesItem)
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
    }

    private func makeSoundsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(soundPicker(title: "Start", names: SoundCatalog.startOptions, action: #selector(chooseStartSound(_:))))
        submenu.addItem(soundPicker(title: "Done", names: SoundCatalog.doneOptions, action: #selector(chooseDoneSound(_:))))
        item.submenu = submenu
        soundsMenu = submenu
        return item
    }

    private func soundPicker(title: String, names: [String], action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let mute = NSMenuItem(title: "Mute", action: action, keyEquivalent: "")
        mute.target = self
        mute.representedObject = SoundCatalog.muteID
        submenu.addItem(mute)
        submenu.addItem(.separator())
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
        guard let sounds = soundsMenu else { return }
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
        modelsState.note = text
    }

    private func refreshStatusIcon() {
        let muted = VoxPreferences.allSoundsMuted
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

    @objc private func openModels() {
        modelsWindow.show()
        refreshModelsUI()
    }

    @objc private func chooseStartSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        VoxPreferences.startSoundName = name
        refreshStatusIcon()
        refreshSoundMenuState()
        Feedback.recordingStarted()
    }

    @objc private func chooseDoneSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        VoxPreferences.doneSoundName = name
        refreshStatusIcon()
        refreshSoundMenuState()
        Feedback.finished()
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

    @objc private func openNotices() {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "Notices", withExtension: "txt")
            ?? bundle.url(forResource: "Notices", withExtension: "txt", subdirectory: "Resources")
        guard let url else {
            setStatus("Notices file is missing")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
