import Foundation

/// A JSON value, used to express a JSON Schema (for structured generation) and to embed it
/// in a prompt. Sendable so schemas are pure data the pipeline can pass across actors.
/// (Not `Equatable`: the ordered-object payload is a tuple array, which blocks synthesis and
/// equality isn't needed.)
indirect enum JSONValue: Sendable {
    case object([(String, JSONValue)]) // ordered: schema readability matters in the prompt
    case array([JSONValue])
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case null

    /// Compact, deterministic JSON serialization (keys in insertion order).
    var jsonString: String {
        switch self {
        case .object(let pairs):
            let body = pairs
                .map { "\(JSONValue.encodeString($0.0)):\($0.1.jsonString)" }
                .joined(separator: ",")
            return "{\(body)}"
        case .array(let items):
            return "[\(items.map(\.jsonString).joined(separator: ","))]"
        case .string(let value): return JSONValue.encodeString(value)
        case .number(let value): return value.isFinite ? String(value) : "null" // JSON has no inf/nan
        case .integer(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    private static func encodeString(_ string: String) -> String {
        // Round-trip through Foundation for correct escaping.
        if let data = try? JSONSerialization.data(withJSONObject: [string]),
           let array = String(data: data, encoding: .utf8) {
            // array is like ["value"] — strip the brackets.
            return String(array.dropFirst().dropLast())
        }
        return "\"\(string)\""
    }

    // Schema-building conveniences -----------------------------------------------------

    static func type(_ name: String, description: String? = nil) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .string(name))]
        if let description { pairs.append(("description", .string(description))) }
        return .object(pairs)
    }

    static func object(
        properties: [(String, JSONValue)],
        required: [String],
        additionalProperties: Bool = false
    ) -> JSONValue {
        .object([
            ("type", .string("object")),
            ("properties", .object(properties)),
            ("required", .array(required.map { .string($0) })),
            ("additionalProperties", .bool(additionalProperties)),
        ])
    }

    static func arrayOf(_ items: JSONValue, description: String? = nil) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .string("array")), ("items", items)]
        if let description { pairs.append(("description", .string(description))) }
        return .object(pairs)
    }
}

/// A named JSON Schema for `Inference.generateStructured`.
struct JSONSchema: Sendable {
    let name: String
    let schema: JSONValue
    var jsonString: String { schema.jsonString }
}

/// Lenient extraction + decoding of a JSON object/array from model output that may include
/// prose, code fences, or a leading reasoning block. Used by the default structured path.
enum JSONExtraction {
    /// Decode `T` from text that contains JSON somewhere inside it. Returns nil on any failure.
    static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        guard let data = firstJSON(in: text)?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Returns the first balanced JSON object or array substring, scanning past any prose,
    /// ```fences```, or `<think>…</think>` reasoning block. String-literal aware so a brace
    /// inside a quoted value never throws off the balance count.
    static func firstJSON(in text: String) -> String? {
        // Drop reasoning-model `<think>…</think>` blocks first — a brace inside them must not
        // be mistaken for the start of the JSON.
        let withoutThink = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        let chars = Array(withoutThink)
        guard let start = chars.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let open = chars[start]
        let close: Character = open == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < chars.count {
            let char = chars[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
            } else {
                if char == "\"" { inString = true }
                else if char == open { depth += 1 }
                else if char == close {
                    depth -= 1
                    if depth == 0 { return String(chars[start...index]) }
                }
            }
            index += 1
        }
        return nil
    }
}
