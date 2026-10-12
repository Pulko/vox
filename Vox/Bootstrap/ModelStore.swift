import Foundation

struct ModelStore {
    static let whisperRepo = "argmaxinc/whisperkit-coreml"
    static let whisperPrefix = "openai_whisper-base"

    let root: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        root = support.appendingPathComponent("Vox/models", isDirectory: true)
        Self.migrateLegacyLlamaIfNeeded(root: root, fileManager: fileManager)
    }

    var llmDirectory: URL? {
        VoxPreferences.selectedLLM.map { directory(for: $0) }
    }

    func directory(for option: LLMOption) -> URL {
        root.appendingPathComponent("llm/\(option.folder)", isDirectory: true)
    }

    var whisperDirectory: URL {
        root.appendingPathComponent("openai_whisper-base", isDirectory: true)
    }

    func markerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(".complete")
    }

    func isComplete(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(in: directory).path)
    }

    func isReady(_ option: LLMOption) -> Bool {
        isComplete(directory(for: option))
    }

    var installedLLMs: [LLMOption] {
        LLMCatalog.all.filter { isReady($0) }
    }

    func remove(_ option: LLMOption) throws {
        let directory = directory(for: option)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    var llamaReady: Bool {
        guard let selected = VoxPreferences.selectedLLM else { return true }
        return isReady(selected)
    }
    var whisperReady: Bool { isComplete(whisperDirectory) }
    var isComplete: Bool { llamaReady && whisperReady }

    func markComplete(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: markerURL(in: directory), options: .atomic)
    }

    func prepareDirectory(_ directory: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func migrateLegacyLlamaIfNeeded(root: URL, fileManager: FileManager) {
        let legacy = root.appendingPathComponent("Llama-3.2-3B-Instruct-4bit", isDirectory: true)
        let destination = root.appendingPathComponent("llm/Llama-3.2-3B-Instruct-4bit", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            return
        }
        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.moveItem(at: legacy, to: destination)
    }
}
