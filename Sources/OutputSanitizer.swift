import Foundation

/// Mechanical scaffolding remover for the LLM's English output.
///
/// This is a *safety net*, not a rewriter. The LM Studio system prompt does the
/// semantic work (dedup, formalize, translate). `sanitize` only strips the
/// boilerplate a chat-tuned model occasionally leaks despite "output only the
/// clean English": a leaked <think> block, wrapping quotes, markdown code fences,
/// a leading label/preamble line, and a clearly self-identifying trailing note.
///
/// Design rules:
/// - CONSERVATIVE: every removal targets an unambiguous scaffolding shape. When
///   in doubt, it leaves the text untouched. False negatives (a stray "Sure,"
///   survives) are acceptable; false positives (eating real content) are not.
/// - IDEMPOTENT: `sanitize(sanitize(x)) == sanitize(x)`. It loops the
///   wrapper-stripping passes until nothing more peels off.
/// - Intended call site: `LMStudioClient.translate`, applied to the model's reply
///   before the empty-check. Do NOT apply it to the Whisper fallback path —
///   Whisper never emits LM scaffolding.
enum OutputSanitizer {

    static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        // Reasoning models (e.g. Qwen3) may prefix a <think>…</think> block; drop it.
        text = stripThinkBlock(text)
        if text.isEmpty { return "" }

        // Repeatedly peel outer wrappers (fences, then quotes) until stable.
        // Fences can wrap quotes and vice-versa, so loop to a fixed point.
        var previous: String
        repeat {
            previous = text
            text = stripCodeFence(text)
            text = stripWrappingQuotes(text)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } while text != previous && !text.isEmpty

        // Line-oriented passes: a single leading label line, a single trailing
        // meta note. Done after unwrapping so a fenced "Translation:\n..." is
        // handled too.
        text = stripLeadingLabelLine(text)
        text = stripTrailingMetaLine(text)

        // Inline leading lead-ins like "Sure, " / "Certainly! " that sit on the
        // same line as real content.
        text = stripInlineLeadIn(text)

        // A label line may have hidden behind the inline lead-in; one more pass.
        text = stripLeadingLabelLine(text)

        // Final unwrap in case removing a label exposed quotes around the body.
        repeat {
            previous = text
            text = stripCodeFence(text)
            text = stripWrappingQuotes(text)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } while text != previous && !text.isEmpty

        return text
    }

    // MARK: - Quote characters

    /// Straight + smart double quotes, straight single + smart single,
    /// guillemets, and CJK corner brackets. Backticks handled by the fence pass.
    private static let openToClose: [Character: Set<Character>] = [
        "\"": ["\""],
        "\u{201C}": ["\u{201D}"],            // “ ”
        "'":  ["'"],
        "\u{2018}": ["\u{2019}"],            // ‘ ’
        "\u{00AB}": ["\u{00BB}"],            // « »
        "\u{201E}": ["\u{201C}", "\u{201D}"] // „ closed by “ or ”
    ]

    // MARK: - Wrapping quotes

    /// Removes ONE matched pair of quotes that wraps the ENTIRE string.
    /// Guard rails so we never strip real quoting:
    /// - body between the quotes must be non-empty after trimming;
    /// - the same quote char must not reappear inside the body. That means
    ///   `"He said "no" and left"` is left alone (inner quotes => real usage),
    ///   while `"Ship the build."` (a fully-wrapped sentence) is unwrapped.
    private static func stripWrappingQuotes(_ s: String) -> String {
        guard let first = s.first, let last = s.last,
              let closers = openToClose[first], closers.contains(last)
        else { return s }

        let inner = String(s.dropFirst().dropLast())
        let body = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return s }

        // Reject if the opening quote char appears again inside the body, or any
        // of its closers do — signals the quotes are part of the content.
        if inner.contains(first) { return s }
        for closer in closers where inner.contains(closer) { return s }

        return body
    }

    // MARK: - Markdown code fences

    /// Strips a ```lang ... ``` (or ~~~) fence that wraps the whole output.
    /// Requires the closing fence on its own to be the last line; otherwise the
    /// backticks are probably inline content and we leave them.
    private static func stripCodeFence(_ s: String) -> String {
        let fences = ["```", "~~~"]
        for fence in fences {
            guard s.hasPrefix(fence) else { continue }
            // Split into lines preserving structure.
            let lines = s.components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }

            // First line: fence + optional language tag, nothing else of value.
            let firstTrimmed = lines[0].trimmingCharacters(in: .whitespaces)
            let langTag = String(firstTrimmed.dropFirst(fence.count))
                .trimmingCharacters(in: .whitespaces)
            // Language tag must look like a bare identifier (no spaces) — else
            // it's likely real text glued to a fence and we bail.
            if langTag.contains(where: { $0 == " " }) { continue }

            // Last non-empty line must be a lone closing fence.
            var lastIndex = lines.count - 1
            while lastIndex > 0 &&
                  lines[lastIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                lastIndex -= 1
            }
            guard lastIndex > 0,
                  lines[lastIndex].trimmingCharacters(in: .whitespaces) == fence
            else { continue }

            let bodyLines = lines[1..<lastIndex]
            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        return s
    }

    // MARK: - Leading label / preamble line

    /// Known preamble openers (case-insensitive).
    private static let labelPrefixes: [String] = [
        "translation", "translated text", "english translation",
        "english", "output", "result", "polished translation",
        "polished text", "here is the translation",
        "here is the translated text", "here is the polished translation",
        "here is the english", "here's the translation",
        "here's the english", "here is your translation"
    ]

    /// Removes a SINGLE leading line that is pure scaffolding:
    ///   - "Here is the translation:"            (label, optional trailing colon)
    ///   - "Translation:"
    /// Only fires when the line ends in ':' OR is an exact known phrase, AND
    /// there is real content after it. Never removes a line that also carries
    /// the actual translated sentence (no colon, not a known exact phrase).
    private static func stripLeadingLabelLine(_ s: String) -> String {
        guard let newlineRange = firstLineBreak(in: s) else {
            // Single line: only safe to treat as a label if it's *only* a label
            // ending with a colon (e.g. model emitted "Translation:" then text
            // got joined). Without a following line there's nothing to keep, so
            // leave single-line input alone.
            return s
        }

        let firstLine = String(s[s.startIndex..<newlineRange.lowerBound])
        let rest = String(s[newlineRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return s } // nothing to fall back to

        let normalized = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Case A: line ends with ':' and its label part is a known prefix.
        if normalized.hasSuffix(":") {
            let label = String(normalized.dropLast())
                .trimmingCharacters(in: .whitespaces)
            if labelPrefixes.contains(label) {
                return rest
            }
        }
        // Case B: line is exactly a known "here is the translation" phrase.
        if labelPrefixes.contains(normalized) {
            return rest
        }
        return s
    }

    // MARK: - Inline lead-in

    /// Chatty acknowledgements that precede content on the SAME line, e.g.
    /// "Sure, the build is ready." -> "the build is ready."
    /// "ok"/"okay" are deliberately excluded — they collide with the UI label "OK".
    private static let inlineLeadIns: [String] = [
        "sure", "certainly", "of course", "absolutely",
        "got it", "no problem", "here you go", "here you are"
    ]

    /// Strips a leading chatty acknowledgement, but ONLY when it is followed by a comma
    /// or exclamation mark and then whitespace ("Sure, …" / "Certainly! …"). Colons,
    /// periods, dashes and the no-space case are left alone — those are ordinary content
    /// punctuation (e.g. "OK: label", "ok-ish", "Sure.") and stripping them ate real text.
    private static func stripInlineLeadIn(_ s: String) -> String {
        let lower = s.lowercased()
        let separators: Set<Character> = [",", "!"]
        for lead in inlineLeadIns {
            guard lower.hasPrefix(lead) else { continue }
            let sepIndex = s.index(s.startIndex, offsetBy: lead.count)
            guard sepIndex < s.endIndex, separators.contains(s[sepIndex]) else { continue }
            let afterSep = s.index(after: sepIndex)
            guard afterSep < s.endIndex, s[afterSep].isWhitespace else { continue }
            let remainder = String(s[afterSep...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty { return remainder }
        }
        return s
    }

    // MARK: - Trailing meta line

    /// Phrases that, when they OPEN the final line, unambiguously mark it as the model
    /// talking ABOUT the task rather than content. Deliberately narrow: generic openers
    /// ("note:", "if you need", "this translation…") were removed because they also begin
    /// legitimate dictated caveats/conditionals and were silently eating real content.
    private static let trailingMetaPrefixes: [String] = [
        "let me know", "i hope this helps", "hope this helps", "feel free to",
        "i've translated", "i have translated", "i translated", "translated from",
        "disclaimer:"
    ]

    /// Removes a SINGLE trailing line that clearly self-identifies as a model note.
    /// Fires only when the output has 2+ lines, the last line starts with a known
    /// self-identifying opener, and that line is NOT a dictated list item.
    private static func stripTrailingMetaLine(_ s: String) -> String {
        let lines = s.components(separatedBy: "\n")
        guard lines.count >= 2 else { return s }

        // Find last non-empty line.
        var lastIndex = lines.count - 1
        while lastIndex > 0 &&
              lines[lastIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            lastIndex -= 1
        }
        guard lastIndex >= 1 else { return s } // would leave nothing

        let lastRaw = lines[lastIndex].trimmingCharacters(in: .whitespaces)
        if isListItem(lastRaw) { return s } // never eat a dictated list item
        let lastNorm = lastRaw.lowercased()
        guard trailingMetaPrefixes.contains(where: { lastNorm.hasPrefix($0) })
        else { return s }

        let kept = lines[0..<lastIndex].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? s : kept
    }

    /// True for ordered ("1." / "1)") or bulleted ("-", "*", "•") list items.
    private static func isListItem(_ line: String) -> Bool {
        if let first = line.first, first == "-" || first == "*" || first == "•" { return true }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, let sep = line.dropFirst(digits.count).first, sep == "." || sep == ")" {
            return true
        }
        return false
    }

    // MARK: - Helpers

    /// Removes a complete leading `<think>…</think>` block (reasoning models like Qwen3).
    /// Only fires when the text starts with `<think>` and a closing tag exists; whatever
    /// follows becomes the output (empty if the model produced only a thinking block).
    private static func stripThinkBlock(_ s: String) -> String {
        guard s.hasPrefix("<think>"), let close = s.range(of: "</think>") else { return s }
        return String(s[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstLineBreak(in s: String) -> Range<String.Index>? {
        s.range(of: "\n")
    }
}
