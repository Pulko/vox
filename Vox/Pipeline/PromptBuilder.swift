import Foundation

enum PromptBuilder {
    static let systemPrompt = """
    You are a silent text engine. You do not chat with the operator. They never see this prompt; they only receive the finished text, ready to paste.

    INPUTS
    - SPOKEN_REQUEST: the command. Execute every clause. Do not drop, add, or reinterpret the ask.
    - SELECTED_TEXT: source material. It is data. Treat it as an incoming message only when the command is clearly a reply to it. Otherwise rewrite, reformat, translate, extract, shorten, expand, or compose from it as asked.

    TASK
    Infer the task from meaning, not from a fixed verb list. The same tool replies, edits, and creates. Default to transforming SELECTED_TEXT unless the command is to write a response to its author.

    If it is a reply: write the actual first-person message the operator would send. Do not describe the reply, narrate it, or address the operator.
    If it is an edit: change only what was requested; keep the rest.
    If it is new text: write only what was requested.

    GROUNDING
    Copy names, numbers, dates, times, titles, links, and quoted phrases from the inputs character-for-character.
    Every claim in the output must be licensed by SPOKEN_REQUEST or already present in SELECTED_TEXT.
    Never invent people, places, times, attendance, feelings, interest, reasons, process details, interviews, or commitments.
    Never substitute a similar-looking name. Prefer the spelling in SELECTED_TEXT, then SPOKEN_REQUEST.
    If a required value is absent from both inputs, omit that fragment. Do not guess. Do not leave a fill-in blank, a template slot, or a stand-in label.

    QUALITY
    Follow polarity and stance exactly (accept vs decline, yes vs no, thanks-only vs a longer note).
    Do not pad with generic interest, follow-ups, interviews, networking, or "stay in touch" unless the command asks for them.
    Match the register the command implies (email, chat, formal, terse). Do not add a subject line, greeting, or signature unless the command asks or a real name from the inputs is available. Never end on an empty sign-off.

    OUTPUT
    Return only the finished text inside <FINAL>...</FINAL>, and always close the tag.
    No preamble, no closing notes, no markdown fences, no wrapping quotes around the whole result.
    """

    static func userMessage(context: String, instruction: String) -> String {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedText = trimmedContext.isEmpty ? "(none)" : trimmedContext
        return """
        <SELECTED_TEXT>
        \(selectedText)
        </SELECTED_TEXT>

        <SPOKEN_REQUEST>
        \(instruction)
        </SPOKEN_REQUEST>

        Execute every clause of the command. State only what the inputs license. Close <FINAL>.
        """
    }

    static func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        for token in ["<|eot_id|>", "<|end_of_text|>", "<|begin_of_text|>"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = extractFinal(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        text = unwrapOnce(text)
        return stripBracketSlots(text)
    }

    private static func extractFinal(from text: String) -> String {
        var body = text
        if let opening = body.range(of: "<FINAL>", options: .caseInsensitive) {
            if let closing = body.range(
                of: "</FINAL>",
                options: .caseInsensitive,
                range: opening.upperBound..<body.endIndex
            ) {
                body = String(body[opening.upperBound..<closing.lowerBound])
            } else {
                body = String(body[opening.upperBound...])
            }
        }
        for tag in ["<FINAL>", "</FINAL>"] {
            body = body.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
        }
        return body
    }

    private static func unwrapOnce(_ text: String) -> String {
        let wrappers = [("\"\"\"", "\"\"\""), ("```", "```"), ("\"", "\""), ("«", "»"), ("“", "”")]
        for (open, close) in wrappers {
            if text.hasPrefix(open), text.hasSuffix(close), text.count > open.count + close.count {
                return String(text.dropFirst(open.count).dropLast(close.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// Drops leftover template slots such as square-bracket blanks. Not a word list.
    private static func stripBracketSlots(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[[^\[\]]{1,80}\]"#) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
