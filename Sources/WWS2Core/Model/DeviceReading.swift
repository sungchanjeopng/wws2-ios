// Ported from app/src/main/java/com/wws2/densitymeter/model/DeviceReading.kt
//
// 16-byte real-time reading frame (BE):
//   [0..1]   rawLevel  (U16)   x0.01 m   — density: Level, interface: Light
//   [2..3]   rawTemp   (S16!)  x0.1 °C
//   [4..5]   rawCurrent(U16)   x0.01 mA
//   [6..7]   rawDamping(U16)
//   [8..9]   raw4mA    (U16)   x0.01 m
//   [10..11] raw20mA   (U16)   x0.01 m
//   [12..13] rawPipeDia(U16)   0/1/2 (label maps to mm range)
//   [14..15] rawFreq   (U16)   x0.001 MHz
//
// `eeaR`, `eeaD`, `heavyLevel`, and `errorCode` are NOT parsed from this
// 16-byte payload — they are set by callers (other frames / state).

import Foundation

public struct DeviceReading: Equatable, Hashable, Sendable {
    /// x0.01 m (density: Level, interface: Light)
    public let level: Double
    /// x0.1 °C
    public let temperature: Double
    /// x0.01 mA
    public let currentMA: Double
    public let damping: Int
    /// x0.01 m
    public let set4mA: Double
    /// x0.01 m
    public let set20mA: Double
    /// 0/1/2
    public let pipeDia: Int
    /// x0.001 MHz
    public let freqMHz: Double
    /// Echo Amplitude (R) — not parsed from 16-byte frame; set externally.
    public let eeaR: Int
    /// Echo Amplitude (D) — not parsed from 16-byte frame; set externally.
    public let eeaD: Int
    /// interface meter only: Heavy threshold x0.01 m
    public let heavyLevel: Double?
    /// 0x00=정상, 0x01=ER01, 0x02=ER02
    public let errorCode: Int

    public init(
        level: Double,
        temperature: Double,
        currentMA: Double,
        damping: Int,
        set4mA: Double,
        set20mA: Double,
        pipeDia: Int,
        freqMHz: Double,
        eeaR: Int = 0,
        eeaD: Int = 0,
        heavyLevel: Double? = nil,
        errorCode: Int = 0
    ) {
        self.level = level
        self.temperature = temperature
        self.currentMA = currentMA
        self.damping = damping
        self.set4mA = set4mA
        self.set20mA = set20mA
        self.pipeDia = pipeDia
        self.freqMHz = freqMHz
        self.eeaR = eeaR
        self.eeaD = eeaD
        self.heavyLevel = heavyLevel
        self.errorCode = errorCode
    }

    public var pipeDiaLabel: String {
        switch pipeDia {
        case 0: return "0~200mm"
        case 1: return "200~400mm"
        case 2: return "400~600mm"
        default: return "--"
        }
    }

    public static func fromBytes(_ data: [UInt8]) -> DeviceReading? {
        guard data.count == 16 else { return nil }
        let rawLevel    = readU16BE(data, 0)
        let rawTemp     = readS16BE(data, 2)        // signed!
        let rawCurrent  = readU16BE(data, 4)
        let rawDamping  = readU16BE(data, 6)
        let raw4mA      = readU16BE(data, 8)
        let raw20mA     = readU16BE(data, 10)
        let rawPipeDia  = readU16BE(data, 12)
        let rawFreq     = readU16BE(data, 14)
        return DeviceReading(
            level:       Double(rawLevel),
            temperature: Double(rawTemp) * 0.1,
            currentMA:   Double(rawCurrent) * 0.01,
            damping:     Int(rawDamping),
            set4mA:      Double(raw4mA) * 0.01,
            set20mA:     Double(raw20mA) * 0.01,
            pipeDia:     Int(rawPipeDia),
            freqMHz:     Double(rawFreq) * 0.001
        )
    }
}

@inline(__always)
private func readU16BE(_ data: [UInt8], _ offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

@inline(__always)
private func readS16BE(_ data: [UInt8], _ offset: Int) -> Int16 {
    Int16(bitPattern: readU16BE(data, offset))
}
