import Foundation
import WhisperKit

final class Transcriber {
    private let kit: WhisperKit

    init(modelFolder: URL) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: modelFolder,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let results = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw VoxError.emptyTranscription
        }
        return text
    }
}
