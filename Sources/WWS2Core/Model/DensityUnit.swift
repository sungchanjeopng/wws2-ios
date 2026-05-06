// Ported from app/src/main/java/com/wws2/densitymeter/model/DensityUnit.kt
//
// raw = 펌웨어 density U16 (0.01% 단위)
//
// 변환식과 포맷 자릿수는 Kotlin 원본과 1:1 일치한다 (단위계 의미는 펌웨어 사양에 위임).

import Foundation

public enum DensityUnit: Int, CaseIterable, Codable, Sendable {
    case pct = 0
    case gL
    case ppm
    case mgL
    case kgM3
    case gCm3

    public var label: String {
        switch self {
        case .pct:  return "%"
        case .gL:   return "g/L"
        case .ppm:  return "ppm"
        case .mgL:  return "mg/L"
        case .kgM3: return "kg/m³"
        case .gCm3: return "g/cm³"
        }
    }

    public var unitStr: String { label }

    /// raw = 펌웨어 density U16 (0.01% 단위)
    public func convert(_ raw: Double) -> Double {
        switch self {
        case .pct:  return raw / 100.0
        case .gL:   return raw / 10.0
        case .ppm:  return raw * 100.0
        case .mgL:  return raw * 100.0
        case .kgM3: return raw
        case .gCm3: return raw / 1000.0
        }
    }

    public func format(raw: Double) -> String {
        formatValue(convert(raw))
    }

    /// Format a value already in this unit (not raw).
    public func formatValue(_ v: Double) -> String {
        switch self {
        case .pct:  return String(format: "%.2f", v)
        case .gL:   return String(format: "%.1f", v)
        case .ppm:  return String(format: "%lld", Int64(v.rounded()))
        case .mgL:  return String(format: "%lld", Int64(v.rounded()))
        case .kgM3: return String(format: "%lld", Int64(v.rounded()))
        case .gCm3: return String(format: "%.3f", v)
        }
    }

    public func next() -> DensityUnit {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }

    public static func fromInt(_ i: Int) -> DensityUnit {
        DensityUnit(rawValue: i) ?? .pct
    }
}
