import Foundation

struct LLMOption: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let repo: String
    let folder: String
    let sizeGigabytes: Double

    var menuTitle: String {
        String(format: "%@ — %.1f GB", title, sizeGigabytes)
    }
}

enum LLMCatalog {
    static let noneID = "none"

    static let writers: [LLMOption] = [
        LLMOption(
            id: "llama-3.2-3b",
            title: "Llama 3.2 3B",
            repo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            folder: "Llama-3.2-3B-Instruct-4bit",
            sizeGigabytes: 1.8
        ),
        LLMOption(
            id: "qwen2.5-3b",
            title: "Qwen 2.5 3B",
            repo: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            folder: "Qwen2.5-3B-Instruct-4bit",
            sizeGigabytes: 1.8
        ),
        LLMOption(
            id: "phi-3.5-mini",
            title: "Phi 3.5 Mini",
            repo: "mlx-community/Phi-3.5-mini-instruct-4bit",
            folder: "Phi-3.5-mini-instruct-4bit",
            sizeGigabytes: 2.2
        ),
    ]

    static let parsers: [LLMOption] = [
        LLMOption(
            id: "qwen3-0.6b",
            title: "Qwen3 0.6B",
            repo: "mlx-community/Qwen3-0.6B-4bit",
            folder: "Qwen3-0.6B-4bit",
            sizeGigabytes: 0.4
        ),
        LLMOption(
            id: "gemma-3-1b",
            title: "Gemma 3 1B",
            repo: "mlx-community/gemma-3-1b-it-4bit",
            folder: "gemma-3-1b-it-4bit",
            sizeGigabytes: 0.8
        ),
        LLMOption(
            id: "llama-3.2-1b",
            title: "Llama 3.2 1B",
            repo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            folder: "Llama-3.2-1B-Instruct-4bit",
            sizeGigabytes: 0.7
        ),
        LLMOption(
            id: "qwen3-1.7b",
            title: "Qwen3 1.7B",
            repo: "mlx-community/Qwen3-1.7B-4bit",
            folder: "Qwen3-1.7B-4bit",
            sizeGigabytes: 1.0
        ),
    ]

    static var all: [LLMOption] { writers + parsers }

    static func writer(id: String) -> LLMOption? {
        writers.first { $0.id == id }
    }

    static func parser(id: String) -> LLMOption? {
        parsers.first { $0.id == id }
    }

    static func option(id: String) -> LLMOption? {
        all.first { $0.id == id }
    }
}

enum SoundCatalog {
    static let muteID = "mute"
    static let startOptions = ["Tink", "Pop", "Ping", "Purr", "Submarine"]
    static let doneOptions = ["Glass", "Tink", "Pop", "Ping", "Purr"]
}

enum VoxPreferences {
    private static let llmKey = "selectedLLMId"
    private static let parserKey = "selectedParserId"
    private static let mutedKey = "soundsMuted"
    private static let startSoundKey = "startSoundName"
    private static let doneSoundKey = "doneSoundName"
    private static let systemPromptKey = "systemPrompt"
    private static let didShowWelcomeKey = "didShowWelcome"

    static var didShowWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: didShowWelcomeKey) }
        set { UserDefaults.standard.set(newValue, forKey: didShowWelcomeKey) }
    }

    static var selectedLLM: LLMOption? {
        get { storedOption(key: llmKey, lookup: LLMCatalog.writer) }
        set { store(newValue, key: llmKey) }
    }

    static var selectedParser: LLMOption? {
        get { storedOption(key: parserKey, lookup: LLMCatalog.parser) }
        set { store(newValue, key: parserKey) }
    }

    static var startSoundName: String {
        get { storedSound(for: startSoundKey, fallback: "Tink", allowed: SoundCatalog.startOptions) }
        set { UserDefaults.standard.set(newValue, forKey: startSoundKey) }
    }

    static var doneSoundName: String {
        get { storedSound(for: doneSoundKey, fallback: "Glass", allowed: SoundCatalog.doneOptions) }
        set { UserDefaults.standard.set(newValue, forKey: doneSoundKey) }
    }

    static var startSoundMuted: Bool { startSoundName == SoundCatalog.muteID }
    static var doneSoundMuted: Bool { doneSoundName == SoundCatalog.muteID }
    static var allSoundsMuted: Bool { startSoundMuted && doneSoundMuted }

    static var systemPrompt: String {
        get {
            let stored = UserDefaults.standard.string(forKey: systemPromptKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? PromptBuilder.defaultSystemPrompt : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: systemPromptKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: systemPromptKey)
            }
        }
    }

    static var usesCustomSystemPrompt: Bool {
        let stored = UserDefaults.standard.string(forKey: systemPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !stored.isEmpty
    }

    static func resetSystemPrompt() {
        UserDefaults.standard.removeObject(forKey: systemPromptKey)
    }

    private static func storedOption(
        key: String,
        lookup: (String) -> LLMOption?
    ) -> LLMOption? {
        let raw = UserDefaults.standard.string(forKey: key)
        if raw == nil || raw == LLMCatalog.noneID { return nil }
        guard let raw else { return nil }
        return lookup(raw)
    }

    private static func store(_ option: LLMOption?, key: String) {
        if let option {
            UserDefaults.standard.set(option.id, forKey: key)
        } else {
            UserDefaults.standard.set(LLMCatalog.noneID, forKey: key)
        }
    }

    private static func storedSound(for key: String, fallback: String, allowed: [String]) -> String {
        migrateGlobalMuteIfNeeded()
        let value = UserDefaults.standard.string(forKey: key) ?? fallback
        if value == SoundCatalog.muteID { return value }
        return allowed.contains(value) ? value : fallback
    }

    private static func migrateGlobalMuteIfNeeded() {
        guard UserDefaults.standard.bool(forKey: mutedKey) else { return }
        UserDefaults.standard.set(SoundCatalog.muteID, forKey: startSoundKey)
        UserDefaults.standard.set(SoundCatalog.muteID, forKey: doneSoundKey)
        UserDefaults.standard.removeObject(forKey: mutedKey)
    }
}
