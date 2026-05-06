// Ported from app/src/main/java/com/wws2/densitymeter/model/DiagReading.kt
//
// 16-byte diag frame (BE):
//   [0..1]   rawTemp    (S16)  x0.1 °C
//   [2..3]   rawCurrent (U16)  x0.01 mA
//   [4..5]   rawDamping (U16)
//   [6..7]   raw4mA     (U16)  x0.01 m
//   [8..9]   raw20mA    (U16)  x0.01 m
//   [10..11] rawPipeDia (U16)
//   [12..13] rawFreq    (U16)  x0.001 MHz
//   [14..15] err        (U16)  — skipped (Status 응답에서 별도 수신)

import Foundation

public struct DiagReading: Equatable, Hashable, Sendable {
    public let temperature: Double
    public let currentMA: Double
    public let damping: Int
    public let set4mA: Double
    public let set20mA: Double
    public let pipeDia: Int
    public let freqMHz: Double

    public init(
        temperature: Double,
        currentMA: Double,
        damping: Int,
        set4mA: Double,
        set20mA: Double,
        pipeDia: Int,
        freqMHz: Double
    ) {
        self.temperature = temperature
        self.currentMA = currentMA
        self.damping = damping
        self.set4mA = set4mA
        self.set20mA = set20mA
        self.pipeDia = pipeDia
        self.freqMHz = freqMHz
    }

    public static func fromBytes(_ data: [UInt8]) -> DiagReading? {
        guard data.count == 16 else { return nil }
        let rawTemp    = readS16BE(data, 0)
        let rawCurrent = readU16BE(data, 2)
        let rawDamping = readU16BE(data, 4)
        let raw4mA     = readU16BE(data, 6)
        let raw20mA    = readU16BE(data, 8)
        let rawPipeDia = readU16BE(data, 10)
        let rawFreq    = readU16BE(data, 12)
        // [14..15] err — skipped
        return DiagReading(
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
