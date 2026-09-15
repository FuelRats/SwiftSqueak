/*
 Copyright 2026 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

/// A dynamic JSON value used for tool input schemas, tool-call arguments, and tool results.
/// Object key order is preserved so emitted JSON Schemas are stable and diffable.
enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
            case (.null, .null): return true
            case let (.bool(left), .bool(right)): return left == right
            case let (.int(left), .int(right)): return left == right
            case let (.double(left), .double(right)): return left == right
            case let (.int(left), .double(right)): return Double(left) == right
            case let (.double(left), .int(right)): return left == Double(right)
            case let (.string(left), .string(right)): return left == right
            case let (.array(left), .array(right)): return left == right
            case let (.object(left), .object(right)):
            guard left.count == right.count else { return false }
            return Dictionary(left, uniquingKeysWith: { first, _ in first })
                == Dictionary(right, uniquingKeysWith: { first, _ in first })
            default: return false
        }
    }
}

// MARK: - Accessors

extension JSONValue {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
            case let .int(value): return value
            case let .double(value): return Int(value)
            default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
            case let .double(value): return value
            case let .int(value): return Double(value)
            default: return nil
        }
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    /// Looks a key up in an object value.
    subscript(_ key: String) -> JSONValue? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first(where: { $0.0 == key })?.1
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            let keyed = try decoder.container(keyedBy: DynamicKey.self)
            var pairs: [(String, JSONValue)] = []
            for key in keyed.allKeys {
                pairs.append((key.stringValue, try keyed.decode(JSONValue.self, forKey: key)))
            }
            self = .object(pairs)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
            case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
            case let .int(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
            case let .double(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
            case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
            case let .array(value):
            var container = encoder.unkeyedContainer()
            for element in value {
                try container.encode(element)
            }
            case let .object(pairs):
            var container = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in pairs {
                try container.encode(value, forKey: DynamicKey(stringValue: key))
            }
        }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

// MARK: - Schema construction helpers

extension JSONValue {
    /// Builds a JSON Schema `object` with the given properties and a `required` list,
    /// always emitting `additionalProperties: false` (Anthropic strict-tool requirement).
    static func objectSchema(
        properties: [(String, JSONValue)],
        required: [String]
    ) -> JSONValue {
        .object([
            ("type", .string("object")),
            ("properties", .object(properties)),
            ("required", .array(required.map(JSONValue.string))),
            ("additionalProperties", .bool(false))
        ])
    }

    static func stringSchema(_ description: String) -> JSONValue {
        .object([("type", .string("string")), ("description", .string(description))])
    }

    /// A JSON Schema `array` whose elements match `items` (defaults to strings).
    static func arraySchema(
        _ description: String,
        items: JSONValue = .object([("type", .string("string"))])
    ) -> JSONValue {
        .object([
            ("type", .string("array")),
            ("description", .string(description)),
            ("items", items)
        ])
    }

    static func integerSchema(_ description: String) -> JSONValue {
        .object([("type", .string("integer")), ("description", .string(description))])
    }

    static func numberSchema(_ description: String) -> JSONValue {
        .object([("type", .string("number")), ("description", .string(description))])
    }

    static func boolSchema(_ description: String) -> JSONValue {
        .object([("type", .string("boolean")), ("description", .string(description))])
    }
}
