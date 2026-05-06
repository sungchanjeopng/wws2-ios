// Ported from app/src/main/java/com/wws2/densitymeter/model/TemperatureUnit.kt

import Foundation

public enum TemperatureUnit: Int, CaseIterable, Codable, Sendable {
    case celsius = 0
    case fahrenheit

    public var unitStr: String {
        switch self {
        case .celsius:    return "°C"
        case .fahrenheit: return "°F"
        }
    }

    public func convert(celsius: Double) -> Double {
        switch self {
        case .celsius:    return celsius
        case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
        }
    }

    public func format(celsius: Double) -> String {
        String(format: "%.1f", convert(celsius: celsius))
    }

    public func next() -> TemperatureUnit {
        self == .celsius ? .fahrenheit : .celsius
    }

    public static func fromInt(_ i: Int) -> TemperatureUnit {
        TemperatureUnit(rawValue: i) ?? .celsius
    }
}
