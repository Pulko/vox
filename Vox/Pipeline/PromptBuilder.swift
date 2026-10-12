import Foundation

enum PromptBuilder {
    static let systemPrompt = """
    You are a context-aware text transformer. You receive highlighted Context and a Spoken Instruction.
    Output ONLY the transformed or generated text. Do NOT include greetings, preamble, or explanations.
    """

    static func userMessage(context: String, instruction: String) -> String {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContext.isEmpty {
            return "Instruction: \(instruction)"
        }
        return """
        Context:
        \"\"\"
        \(trimmedContext)
        \"\"\"

        Instruction: \(instruction)
        """
    }

    static func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"\"\""), text.hasSuffix("\"\"\""), text.count > 6 {
            text = String(text.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
