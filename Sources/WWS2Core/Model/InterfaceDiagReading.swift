// Ported from app/src/main/java/com/wws2/densitymeter/model/InterfaceDiagReading.kt
//
// 계면계 Diag 응답. Per the Kotlin original the runtime layout is read as
// 11 × 2-byte BE fields (= 22 bytes total), even though the spec comment
// shows mixed widths. We mirror the runtime layout exactly:
//
//   [0..1]   rawTemp    (S16)  x0.1 °C
//   [2..3]   rawCurrent (U16)  x0.01 mA
//   [4..5]   rawFreq    (U16)  enum (0=130K, 1=160K, 2=270K, 3=380K)
//   [6..7]   rawOffset  (S16)  x0.01 m
//   [8..9]   raw4mA     (U16)  x0.01
//   [10..11] raw20mA    (U16)  x0.01
//   [12..13] rawTvg     (U16)
//   [14..15] rawDamp    (U16)
//   [16..17] rawAsf     (U16)
//   [18..19] rawRelay   (U16)  0=OPEN(ON), nonzero=CLOSED(OFF)
//   [20..21] rawError   (U16)  — accepted but unused

import Foundation

public struct InterfaceDiagReading: Equatable, Hashable, Sendable {
    public let temperature: Double
    public let currentMA: Double
    public let freq: Int
    public let offset: Double
    public let set4mA: Double
    public let set20mA: Double
    public let tvg: Int
    public let damp: Int
    public let asf: Int
    public let relayOn: Bool

    public init(
        temperature: Double,
        currentMA: Double,
        freq: Int,
        offset: Double,
        set4mA: Double,
        set20mA: Double,
        tvg: Int,
        damp: Int,
        asf: Int,
        relayOn: Bool
    ) {
        self.temperature = temperature
        self.currentMA = currentMA
        self.freq = freq
        self.offset = offset
        self.set4mA = set4mA
        self.set20mA = set20mA
        self.tvg = tvg
        self.damp = damp
        self.asf = asf
        self.relayOn = relayOn
    }

    public var freqLabel: String {
        switch freq {
        case 0: return "130K"
        case 1: return "160K"
        case 2: return "270K"
        case 3: return "380K"
        default: return "--"
        }
    }

    public static func fromBytes(_ data: [UInt8]) -> InterfaceDiagReading? {
        guard data.count >= 22 else { return nil }
        let rawTemp    = readS16BE(data, 0)
        let rawCurrent = readU16BE(data, 2)
        let rawFreq    = readU16BE(data, 4)
        let rawOffset  = readS16BE(data, 6)
        let raw4mA     = readU16BE(data, 8)
        let raw20mA    = readU16BE(data, 10)
        let rawTvg     = readU16BE(data, 12)
        let rawDamp    = readU16BE(data, 14)
        let rawAsf     = readU16BE(data, 16)
        let rawRelay   = readU16BE(data, 18)
        // [20..21] rawError — accepted but unused (Kotlin reads & discards)

        return InterfaceDiagReading(
            temperature: Double(rawTemp) * 0.1,
            currentMA:   Double(rawCurrent) * 0.01,
            freq:        Int(rawFreq),
            offset:      Double(rawOffset) * 0.01,
            set4mA:      Double(raw4mA) * 0.01,
            set20mA:     Double(raw20mA) * 0.01,
            tvg:         Int(rawTvg),
            damp:        Int(rawDamp),
            asf:         Int(rawAsf),
            relayOn:     rawRelay == 0
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
