import Foundation

public enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case imperial
    case metric

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .imperial: "Feet & inches"
        case .metric: "Metric"
        }
    }
}

public enum Units {
    public static let metersPerInch = 0.0254
    public static let metersPerFoot = 0.3048
    public static let squareMetersPerSquareFoot = metersPerFoot * metersPerFoot

    /// Imperial lengths round to the nearest 1/4 inch; metric to the nearest centimeter.
    public static func formatLength(_ meters: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric:
            return String(format: "%.2f m", meters)
        case .imperial:
            let quarters = Int((meters / metersPerInch * 4).rounded())
            let feet = quarters / 48
            let remainder = quarters % 48
            let inches = remainder / 4
            let fraction = ["", " 1/4", " 1/2", " 3/4"][remainder % 4]
            return "\(feet)' \(inches)\(fraction)\""
        }
    }

    public static func formatArea(_ squareMeters: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric:
            return String(format: "%.2f m²", squareMeters)
        case .imperial:
            return String(format: "%.1f sq ft", squareMeters / squareMetersPerSquareFoot)
        }
    }

    /// Parses a length typed by the user and returns meters.
    ///
    /// Imperial accepts `12' 3 1/2"`, `12'3"`, `12'`, `147"`, `3 1/4"`, and plain
    /// numbers as decimal feet (`12.5`). Metric accepts `3.5`, `3.5 m`, `350 cm`
    /// and `3500 mm`; plain numbers are meters.
    public static func parseLength(_ text: String, _ system: UnitSystem) -> Double? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let value: Double?
        switch system {
        case .metric: value = parseMetric(s)
        case .imperial: value = parseImperial(s)
        }
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }

    /// Parses an area in the user's units and returns square meters.
    public static func parseArea(_ text: String, _ system: UnitSystem) -> Double? {
        let s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
            .lowercased()
            .replacingOccurrences(of: "sq ft", with: "")
            .replacingOccurrences(of: "m²", with: "")
            .replacingOccurrences(of: "m2", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let number = Double(s), number > 0, number.isFinite else { return nil }
        return system == .metric ? number : number * squareMetersPerSquareFoot
    }

    private static func parseMetric(_ s: String) -> Double? {
        for (suffix, scale) in [("mm", 0.001), ("cm", 0.01), ("m", 1.0)] where s.hasSuffix(suffix) {
            let number = s.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            return Double(number).map { $0 * scale }
        }
        return Double(s)
    }

    private static func parseImperial(_ s: String) -> Double? {
        let normalized = s
            .replacingOccurrences(of: "\u{2032}", with: "'")   // prime
            .replacingOccurrences(of: "\u{2033}", with: "\"")  // double prime
            .replacingOccurrences(of: "''", with: "\"")
            .replacingOccurrences(of: "ft", with: "'")
            .replacingOccurrences(of: "in", with: "\"")

        var feet = 0.0
        var inchesPart = normalized
        if let tick = normalized.firstIndex(of: "'") {
            guard let f = Double(normalized[..<tick].trimmingCharacters(in: .whitespaces)) else { return nil }
            feet = f
            inchesPart = String(normalized[normalized.index(after: tick)...])
        } else if !normalized.contains("\"") {
            // Plain number: decimal feet.
            return Double(normalized).map { $0 * metersPerFoot }
        }

        inchesPart = inchesPart.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        var inches = 0.0
        if !inchesPart.isEmpty {
            guard let parsed = parseInches(inchesPart) else { return nil }
            inches = parsed
        }
        return feet * metersPerFoot + inches * metersPerInch
    }

    /// "3", "3.5", "3 1/2", "1/2"
    private static func parseInches(_ s: String) -> Double? {
        var total = 0.0
        for token in s.split(separator: " ") {
            if let slash = token.firstIndex(of: "/") {
                guard let n = Double(token[..<slash]),
                      let d = Double(token[token.index(after: slash)...]), d != 0 else { return nil }
                total += n / d
            } else {
                guard let n = Double(token) else { return nil }
                total += n
            }
        }
        return total
    }
}
