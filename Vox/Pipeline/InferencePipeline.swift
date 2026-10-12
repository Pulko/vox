import Foundation

final class InferencePipeline {
    private let transcriber: Transcriber
    private let llm: LLMEngine

    init(transcriber: Transcriber, llm: LLMEngine) {
        self.transcriber = transcriber
        self.llm = llm
    }

    func run(samples: [Float], context: String) async throws -> String {
        let minimumSamples = Int(16_000 * 0.3)
        guard samples.count >= minimumSamples else {
            throw VoxError.shortRecording
        }
        let instruction = try await transcriber.transcribe(samples)
        Log.pipeline.info("Heard: \(instruction, privacy: .public)")
        return try await llm.generate(context: context, instruction: instruction)
    }
}
