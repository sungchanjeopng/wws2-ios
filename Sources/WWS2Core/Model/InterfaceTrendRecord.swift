// Ported from app/src/main/java/com/wws2/densitymeter/model/InterfaceTrendRecord.kt
//
// Interface meter trend record — 13 bytes per record:
//   [0]      year - 2000
//   [1]      month   (clamped to 1..12)
//   [2]      day     (clamped to 1..31)
//   [3]      hour    (clamped to 0..23)
//   [4]      minute  (clamped to 0..59)
//   [5..6]   ch1Light (U16 BE)  x0.01 m
//   [7..8]   ch1Heavy (U16 BE)  x0.01 m
//   [9..10]  ch2Light (U16 BE)  x0.01 m
//   [11..12] ch2Heavy (U16 BE)  x0.01 m
//
// No seconds field — minute resolution. Date semantics match TrendRecord
// (UTC gregorian calendar; mirrors Kotlin LocalDateTime naive-time).

import Foundation

public struct InterfaceTrendRecord: Equatable, Hashable, Sendable {
    public let dateTime: Date
    public let ch1Light: Double
    public let ch1Heavy: Double
    public let ch2Light: Double
    public let ch2Heavy: Double

    public init(
        dateTime: Date,
        ch1Light: Double,
        ch1Heavy: Double,
        ch2Light: Double,
        ch2Heavy: Double
    ) {
        self.dateTime = dateTime
        self.ch1Light = ch1Light
        self.ch1Heavy = ch1Heavy
        self.ch2Light = ch2Light
        self.ch2Heavy = ch2Heavy
    }

    public static let recordSize = 13

    private static let utcGregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    public static func fromBytes(_ data: [UInt8]) -> InterfaceTrendRecord? {
        guard data.count >= recordSize else { return nil }

        let year   = 2000 + Int(data[0])
        let month  = max(1, min(12, Int(data[1])))
        let day    = max(1, min(31, Int(data[2])))
        let hour   = max(0, min(23, Int(data[3])))
        let minute = max(0, min(59, Int(data[4])))

        let ch1Light = Double(readU16BE(data, 5))  * 0.01
        let ch1Heavy = Double(readU16BE(data, 7))  * 0.01
        let ch2Light = Double(readU16BE(data, 9))  * 0.01
        let ch2Heavy = Double(readU16BE(data, 11)) * 0.01

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = utcGregorian.date(from: components) else { return nil }

        return InterfaceTrendRecord(
            dateTime: date,
            ch1Light: ch1Light, ch1Heavy: ch1Heavy,
            ch2Light: ch2Light, ch2Heavy: ch2Heavy
        )
    }
}

@inline(__always)
private func readU16BE(_ data: [UInt8], _ offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}
