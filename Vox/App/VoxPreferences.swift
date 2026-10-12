import Foundation

struct LLMOption: Equatable, Sendable {
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
    static let all: [LLMOption] = [
        LLMOption(
            id: "llama-3.2-3b",
            title: "Llama 3.2 3B",
            repo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            folder: "Llama-3.2-3B-Instruct-4bit",
            sizeGigabytes: 1.8
        ),
        LLMOption(
            id: "llama-3.2-1b",
            title: "Llama 3.2 1B",
            repo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            folder: "Llama-3.2-1B-Instruct-4bit",
            sizeGigabytes: 0.7
        ),
        LLMOption(
            id: "qwen2.5-3b",
            title: "Qwen 2.5 3B",
            repo: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            folder: "Qwen2.5-3B-Instruct-4bit",
            sizeGigabytes: 1.8
        ),
        LLMOption(
            id: "qwen2.5-1.5b",
            title: "Qwen 2.5 1.5B",
            repo: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            folder: "Qwen2.5-1.5B-Instruct-4bit",
            sizeGigabytes: 0.9
        ),
        LLMOption(
            id: "phi-3.5-mini",
            title: "Phi 3.5 Mini",
            repo: "mlx-community/Phi-3.5-mini-instruct-4bit",
            folder: "Phi-3.5-mini-instruct-4bit",
            sizeGigabytes: 2.2
        ),
    ]

    static let `default` = all[0]
    static let noneID = "none"

    static func option(id: String) -> LLMOption? {
        all.first { $0.id == id }
    }
}

enum SoundCatalog {
    static let startOptions = ["Tink", "Pop", "Ping", "Purr", "Submarine"]
    static let doneOptions = ["Glass", "Tink", "Pop", "Ping", "Purr"]
}

enum VoxPreferences {
    private static let llmKey = "selectedLLMId"
    private static let mutedKey = "soundsMuted"
    private static let startSoundKey = "startSoundName"
    private static let doneSoundKey = "doneSoundName"
    private static let systemPromptKey = "systemPrompt"

    static var selectedLLM: LLMOption? {
        get {
            let raw = UserDefaults.standard.string(forKey: llmKey)
            if raw == LLMCatalog.noneID { return nil }
            if let raw { return LLMCatalog.option(id: raw) }
            return nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.id, forKey: llmKey)
            } else {
                UserDefaults.standard.set(LLMCatalog.noneID, forKey: llmKey)
            }
        }
    }

    static var soundsMuted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    static var startSoundName: String {
        get { storedSound(for: startSoundKey, fallback: "Tink", allowed: SoundCatalog.startOptions) }
        set { UserDefaults.standard.set(newValue, forKey: startSoundKey) }
    }

    static var doneSoundName: String {
        get { storedSound(for: doneSoundKey, fallback: "Glass", allowed: SoundCatalog.doneOptions) }
        set { UserDefaults.standard.set(newValue, forKey: doneSoundKey) }
    }

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

    private static func storedSound(for key: String, fallback: String, allowed: [String]) -> String {
        let value = UserDefaults.standard.string(forKey: key) ?? fallback
        return allowed.contains(value) ? value : fallback
    }
}
