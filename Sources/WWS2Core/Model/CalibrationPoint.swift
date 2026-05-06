// Ported from app/src/main/java/com/wws2/densitymeter/model/CalibrationPoint.kt
//
// Frame layout (firmware → app, 80 bytes total = 5 × 16-byte records):
//   offset+0..1:   flag (U16 BE; bit0=fEEA, bit1=fLV)
//   offset+2..3:   eea (U16 BE)
//   offset+4..5:   density raw (U16 BE)
//   offset+6..7:   year - 2000 (U16 BE)
//   offset+8..9:   month (U16 BE)
//   offset+10..11: day  (U16 BE)
//   offset+12..13: hour (U16 BE)
//   offset+14..15: minute (U16 BE)

import Foundation

public struct CalibrationPoint: Equatable, Hashable, Codable, Sendable {
    public let fEEA: Bool
    public let fLV: Bool
    public let eea: Int
    /// raw U16 from firmware
    public let density: Double
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int

    public init(
        fEEA: Bool,
        fLV: Bool,
        eea: Int,
        density: Double,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) {
        self.fEEA = fEEA
        self.fLV = fLV
        self.eea = eea
        self.density = density
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    public static func fromBytes(_ data: [UInt8]) -> [CalibrationPoint]? {
        guard data.count >= 80 else { return nil }
        return (0..<5).map { i -> CalibrationPoint in
            let o = i * 16
            let flag = readU16BE(data, o)
            return CalibrationPoint(
                fEEA: (flag & 0x0001) != 0,
                fLV:  (flag & 0x0002) != 0,
                eea: Int(readU16BE(data, o + 2)),
                density: Double(readU16BE(data, o + 4)),
                year: Int(readU16BE(data, o + 6)) + 2000,
                month: Int(readU16BE(data, o + 8)),
                day: Int(readU16BE(data, o + 10)),
                hour: Int(readU16BE(data, o + 12)),
                minute: Int(readU16BE(data, o + 14))
            )
        }
    }
}

@inline(__always)
private func readU16BE(_ data: [UInt8], _ offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}
