import Foundation

typealias JSONObject = [String: Any]
typealias JSONArray = [JSONObject]

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, default fallback: String = "") -> String {
        guard let value = self[key], !(value is NSNull) else { return fallback }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    func bool(_ key: String, default fallback: Bool = false) -> Bool {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        if let value = self[key] as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        return fallback
    }

    func integer(_ key: String, default fallback: Int = 0) -> Int {
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? String, let parsed = Int(value) { return parsed }
        return fallback
    }

    func milliseconds(_ key: String, default fallback: Int64 = 0) -> Int64 {
        if let value = self[key] as? NSNumber { return value.int64Value }
        if let value = self[key] as? Int64 { return value }
        if let value = self[key] as? Int { return Int64(value) }
        if let value = self[key] as? String, let parsed = Int64(value) { return parsed }
        return fallback
    }

    func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func objects(_ key: String) -> JSONArray { self[key] as? JSONArray ?? [] }
    func strings(_ key: String) -> [String] { self[key] as? [String] ?? [] }
}

enum JSONCopy {
    static func object(_ value: JSONObject) -> JSONObject {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let copy = try? JSONSerialization.jsonObject(with: data) as? JSONObject else {
            return value
        }
        return copy
    }

    static func array(_ value: JSONArray) -> JSONArray {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let copy = try? JSONSerialization.jsonObject(with: data) as? JSONArray else {
            return value
        }
        return copy
    }
}

func nowMilliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

