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
            extraEOSTokens: ["<|eot_id|>", "<|end_of_text|>", "<|im_end|>"]
        )
        container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        _ = try await complete(
            system: "ok",
            user: "ok",
            maxTokens: 1,
            temperature: 0,
            sanitizeOutput: false
        )
        Log.pipeline.info("LLM loaded")
    }

    func generate(context: String, instruction: String, parsed: String? = nil) async throws -> String {
        let text = try await complete(
            system: VoxPreferences.systemPrompt,
            user: PromptBuilder.userMessage(context: context, instruction: instruction, parsed: parsed),
            maxTokens: 1024,
            temperature: 0,
            sanitizeOutput: true
        )
        if text.isEmpty {
            throw VoxError.emptyOutput
        }
        return text
    }

    func parseInstruction(_ instruction: String) async -> String? {
        do {
            let raw = try await complete(
                system: PromptBuilder.parserSystemPrompt,
                user: PromptBuilder.parserUserMessage(instruction),
                maxTokens: 256,
                temperature: 0,
                sanitizeOutput: false
            )
            return PromptBuilder.extractJSONObject(from: raw)
        } catch {
            Log.pipeline.error("Parser failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func complete(
        system: String,
        user: String,
        maxTokens: Int,
        temperature: Float,
        sanitizeOutput: Bool
    ) async throws -> String {
        let userInput = UserInput(chat: [
            .system(system),
            .user(user),
        ])
        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
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
        if sanitizeOutput {
            return PromptBuilder.sanitize(result.output)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
