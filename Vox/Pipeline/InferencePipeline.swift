import Foundation

final class InferencePipeline {
    private let transcriber: Transcriber
    private var llm: LLMEngine
    private var parser: LLMEngine?

    init(transcriber: Transcriber, llm: LLMEngine, parser: LLMEngine? = nil) {
        self.transcriber = transcriber
        self.llm = llm
        self.parser = parser
    }

    func replace(llm: LLMEngine, parser: LLMEngine?) {
        self.llm = llm
        self.parser = parser
    }

    func run(samples: [Float], context: String) async throws -> String {
        let minimumSamples = Int(16_000 * 0.3)
        guard samples.count >= minimumSamples else {
            throw VoxError.shortRecording
        }
        let raw = try await transcriber.transcribe(samples)
        let instruction = SpokenCleanup.clean(raw)
        Log.pipeline.info("Heard (raw): \(raw, privacy: .public)")
        Log.pipeline.info("Heard (clean): \(instruction, privacy: .public)")
        var parsed: String?
        if let parser {
            parsed = await parser.parseInstruction(instruction)
            if let parsed {
                Log.pipeline.info("Parsed: \(parsed, privacy: .public)")
            } else {
                Log.pipeline.info("Parser skipped or produced no JSON")
            }
        }
        return try await llm.generate(context: context, instruction: instruction, parsed: parsed)
    }
}
