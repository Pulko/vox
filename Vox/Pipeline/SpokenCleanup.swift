import Foundation
import NaturalLanguage

enum SpokenCleanup {
    static func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = trimmed
        var kept: [String] = []
        tagger.enumerateTags(
            in: trimmed.startIndex..<trimmed.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace]
        ) { tag, range in
            if tag == .interjection {
                return true
            }
            let token = String(trimmed[range])
            if token.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
                if let last = kept.last, last.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
                    kept[kept.count - 1] = token
                } else {
                    kept.append(token)
                }
                return true
            }
            if let last = kept.last,
               last.compare(token, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return true
            }
            kept.append(token)
            return true
        }

        let cleaned = kept.joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " !", with: "!")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? trimmed : cleaned
    }
}
