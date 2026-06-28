import Foundation

/// Splits a long transcript into context-safe pieces so the *whole* recording is refined,
/// never just the part that survives LM Studio's context-overflow truncation.
///
/// Pure and deterministic — the splitting + token-estimate logic lives here so it can be
/// unit-tested without a running server. `LMStudioClient` decides *whether* to chunk (from
/// the model's loaded context length) and stitches the refined pieces back together.
enum TranscriptChunker {
    /// Rough upper-bound token estimate. Serbian (often Cyrillic) packs fewer characters
    /// per token than English, so we deliberately *over*-estimate (≈2.5 chars/token) — an
    /// over-estimate makes us chunk a little early, which is always safe; an under-estimate
    /// would let a prompt overflow and silently lose text, the exact bug we're fixing.
    static func estimateTokens(_ text: String) -> Int {
        Int((Double(text.count) / 2.5).rounded(.up))
    }

    /// Greedily packs whole sentences into chunks no longer than `maxChars`. A single
    /// sentence longer than the limit (a run-on with no punctuation) is hard-split on word
    /// boundaries; a single word longer than the limit is cut by character as a last resort.
    /// Every character of the input survives — chunks rejoined with a space reproduce the
    /// transcript up to whitespace normalization.
    static func split(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let limit = max(1, maxChars)
        guard trimmed.count > limit else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences(in: trimmed) {
            if sentence.count > limit {
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(contentsOf: hardSplit(sentence, limit: limit))
                continue
            }
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= limit {
                current += " " + sentence
            } else {
                chunks.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Internals

    /// Breaks text into sentence-ish fragments at terminal punctuation (`. ! ? … 。`) when
    /// followed by whitespace/end, and at newlines. Fragments are trimmed and non-empty.
    private static func sentences(in text: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
        var result: [String] = []
        var buffer = ""
        let chars = Array(text)

        for (index, char) in chars.enumerated() {
            if char == "\n" {
                appendTrimmed(buffer, to: &result)
                buffer = ""
                continue
            }
            buffer.append(char)
            if terminators.contains(char) {
                let next = index + 1 < chars.count ? chars[index + 1] : " "
                if next.isWhitespace {
                    appendTrimmed(buffer, to: &result)
                    buffer = ""
                }
            }
        }
        appendTrimmed(buffer, to: &result)
        return result
    }

    private static func appendTrimmed(_ s: String, to result: inout [String]) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { result.append(t) }
    }

    /// Splits an over-long fragment on word boundaries, falling back to a hard character
    /// cut for a single word that itself exceeds the limit.
    private static func hardSplit(_ sentence: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: true) {
            let word = String(word)
            if word.count > limit {
                if !current.isEmpty { pieces.append(current); current = "" }
                pieces.append(contentsOf: charSplit(word, limit: limit))
                continue
            }
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                pieces.append(current)
                current = word
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private static func charSplit(_ word: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var index = word.startIndex
        while index < word.endIndex {
            let end = word.index(index, offsetBy: limit, limitedBy: word.endIndex) ?? word.endIndex
            pieces.append(String(word[index..<end]))
            index = end
        }
        return pieces
    }
}
