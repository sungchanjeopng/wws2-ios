// Ported from app/src/main/java/com/wws2/densitymeter/model/InterfaceReading.kt
//
// Interface meter (계면계) status reading — 26 bytes payload (LEN=0x1A).
// Two channels (CH1/CH2), each with Light/Heavy thresholds + temperature + mA.
//
// 13 × U16/S16 BE fields (ch1/ch2 temperature are SIGNED; everything else U16):
//   [0..1]   ch1Light  (U16)  x0.01 m
//   [2..3]   ch1Heavy  (U16)  x0.01 m
//   [4..5]   ch1Temp   (S16)  x0.1 °C
//   [6..7]   ch1Cur    (U16)  x0.01 mA
//   [8..9]   ch2Light  (U16)  x0.01 m
//   [10..11] ch2Heavy  (U16)  x0.01 m
//   [12..13] ch2Temp   (S16)  x0.1 °C
//   [14..15] ch2Cur    (U16)  x0.01 mA
//   [16..17] damping   (U16)
//   [18..19] set4mA    (U16)  x0.01 m
//   [20..21] set20mA   (U16)  x0.01 m
//   [22..23] emptyDist (U16)  x0.01 m
//   [24..25] status    (U16)

import Foundation

public struct InterfaceReading: Equatable, Hashable, Sendable {
    public let ch1Light: Double
    public let ch1Heavy: Double
    public let ch1Temperature: Double
    public let ch1CurrentMA: Double
    public let ch2Light: Double
    public let ch2Heavy: Double
    public let ch2Temperature: Double
    public let ch2CurrentMA: Double
    public let damping: Int
    public let set4mA: Double
    public let set20mA: Double
    public let emptyDist: Double
    public let status: Int

    public init(
        ch1Light: Double, ch1Heavy: Double, ch1Temperature: Double, ch1CurrentMA: Double,
        ch2Light: Double, ch2Heavy: Double, ch2Temperature: Double, ch2CurrentMA: Double,
        damping: Int, set4mA: Double, set20mA: Double, emptyDist: Double, status: Int
    ) {
        self.ch1Light = ch1Light
        self.ch1Heavy = ch1Heavy
        self.ch1Temperature = ch1Temperature
        self.ch1CurrentMA = ch1CurrentMA
        self.ch2Light = ch2Light
        self.ch2Heavy = ch2Heavy
        self.ch2Temperature = ch2Temperature
        self.ch2CurrentMA = ch2CurrentMA
        self.damping = damping
        self.set4mA = set4mA
        self.set20mA = set20mA
        self.emptyDist = emptyDist
        self.status = status
    }

    /// Convert CH1 data to a `DeviceReading` for unified display.
    public func toCh1Reading() -> DeviceReading {
        DeviceReading(
            level: ch1Light,
            temperature: ch1Temperature,
            currentMA: ch1CurrentMA,
            damping: damping,
            set4mA: set4mA,
            set20mA: set20mA,
            pipeDia: 0,
            freqMHz: 0.0,
            heavyLevel: ch1Heavy
        )
    }

    /// Convert CH2 data to a `DeviceReading` for unified display.
    public func toCh2Reading() -> DeviceReading {
        DeviceReading(
            level: ch2Light,
            temperature: ch2Temperature,
            currentMA: ch2CurrentMA,
            damping: damping,
            set4mA: set4mA,
            set20mA: set20mA,
            pipeDia: 0,
            freqMHz: 0.0,
            heavyLevel: ch2Heavy
        )
    }

    public static func fromBytes(_ data: [UInt8]) -> InterfaceReading? {
        guard data.count == 26 else { return nil }
        let ch1Light = Double(readU16BE(data, 0))  * 0.01
        let ch1Heavy = Double(readU16BE(data, 2))  * 0.01
        let ch1Temp  = Double(readS16BE(data, 4))  * 0.1
        let ch1Cur   = Double(readU16BE(data, 6))  * 0.01
        let ch2Light = Double(readU16BE(data, 8))  * 0.01
        let ch2Heavy = Double(readU16BE(data, 10)) * 0.01
        let ch2Temp  = Double(readS16BE(data, 12)) * 0.1
        let ch2Cur   = Double(readU16BE(data, 14)) * 0.01
        let damping  = Int(readU16BE(data, 16))
        let set4     = Double(readU16BE(data, 18)) * 0.01
        let set20    = Double(readU16BE(data, 20)) * 0.01
        let empty_   = Double(readU16BE(data, 22)) * 0.01
        let status   = Int(readU16BE(data, 24))
        return InterfaceReading(
            ch1Light: ch1Light, ch1Heavy: ch1Heavy,
            ch1Temperature: ch1Temp, ch1CurrentMA: ch1Cur,
            ch2Light: ch2Light, ch2Heavy: ch2Heavy,
            ch2Temperature: ch2Temp, ch2CurrentMA: ch2Cur,
            damping: damping, set4mA: set4, set20mA: set20,
            emptyDist: empty_, status: status
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
