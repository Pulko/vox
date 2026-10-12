import Foundation

struct ModelStore {
    static let llamaRepo = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    static let whisperRepo = "argmaxinc/whisperkit-coreml"
    static let whisperPrefix = "openai_whisper-base"

    let root: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        root = support.appendingPathComponent("Vox/models", isDirectory: true)
    }

    var llamaDirectory: URL {
        root.appendingPathComponent("Llama-3.2-3B-Instruct-4bit", isDirectory: true)
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

    var llamaReady: Bool { isComplete(llamaDirectory) }
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
}
