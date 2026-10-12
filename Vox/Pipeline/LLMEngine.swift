import Foundation
import MLX
import MLXLLM
import MLXLMCommon

final class LLMEngine {
    private let container: ModelContainer

    init(modelDirectory: URL) async throws {
        GPU.set(cacheLimit: 20 * 1024 * 1024)
        let configuration = ModelConfiguration(
            directory: modelDirectory,
            extraEOSTokens: ["<|eot_id|>", "<|end_of_text|>"]
        )
        container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        _ = try await generate(context: "warmup", instruction: "ok", maxTokens: 1)
        Log.pipeline.info("LLM loaded")
    }

    func generate(context: String, instruction: String, maxTokens: Int = 1024) async throws -> String {
        let userInput = UserInput(chat: [
            .system(VoxPreferences.systemPrompt),
            .user(PromptBuilder.userMessage(context: context, instruction: instruction)),
        ])
        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0,
            repetitionPenalty: 1.1
        )
        let result = try await container.perform { modelContext in
            let input = try await modelContext.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: modelContext
            ) { tokens in
                tokens.count >= maxTokens ? .stop : .more
            }
        }
        let text = PromptBuilder.sanitize(result.output)
        if text.isEmpty {
            throw VoxError.emptyOutput
        }
        return text
    }
}
