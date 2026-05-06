// Ported from app/src/main/java/com/wws2/densitymeter/model/TrendRecord.kt
//
// 24-byte trend record from firmware:
//   [0]=00 [1]=year [2]=00 [3]=month [4]=00 [5]=day
//   [6]=00 [7]=hour [8]=00 [9]=minute [10]=00 [11]=second
//   [12..13]=eea (U16 BE)   [14..15]=density (U16 BE)
//   [16..17]=temp (S16 BE!) [18]=00 [19]=step
//   [20..21]=vca (U16 BE)   [22]=00 [23]=status
//
// Note: temperature is interpreted as SIGNED 16-bit (matches Kotlin original
// where `buf.short.toInt()` is NOT followed by `and 0xFFFF`). All other 16-bit
// fields are unsigned.
//
// Date semantics: Kotlin uses `LocalDateTime` (naive, no timezone). We map to
// `Foundation.Date` constructed via `DateComponents` in the gregorian calendar
// at UTC, so the encoded year/month/day/h/m/s round-trip exactly when read
// back through the same calendar.

import Foundation

public struct TrendRecord: Equatable, Hashable, Sendable {
    public let dateTime: Date
    public let eeaD: Int
    /// x0.01 m
    public let dst: Double
    /// x0.1 °C
    public let temperature: Double
    public let step: Int
    public let vca: Int
    public let status: Int
    /// 실시간 트렌드 채널 구분용 (a01=..._CH1, a02=..._CH2). 다운로드/과거 기록은 ""
    public let deviceId: String

    public init(
        dateTime: Date,
        eeaD: Int,
        dst: Double,
        temperature: Double,
        step: Int = 0,
        vca: Int = 0,
        status: Int = 0,
        deviceId: String = ""
    ) {
        self.dateTime = dateTime
        self.eeaD = eeaD
        self.dst = dst
        self.temperature = temperature
        self.step = step
        self.vca = vca
        self.status = status
        self.deviceId = deviceId
    }

    private static let utcGregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    public static func fromBytes(_ data: [UInt8]) -> TrendRecord? {
        guard data.count >= 24 else { return nil }

        let year   = 2000 + Int(data[1])
        let month  = max(1,  min(12, Int(data[3])))
        let day    = max(1,  min(31, Int(data[5])))
        let hour   = max(0,  min(23, Int(data[7])))
        let minute = max(0,  min(59, Int(data[9])))
        let second = max(0,  min(59, Int(data[11])))

        let eeaD    = Int(readU16BE(data, 12))
        let rawDst  = Int(readU16BE(data, 14))
        let rawTemp = Int(readS16BE(data, 16))   // signed!
        let step    = Int(readU16BE(data, 18))
        let vca     = Int(readU16BE(data, 20))
        let status  = Int(readU16BE(data, 22))

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = utcGregorian.date(from: components) else { return nil }

        return TrendRecord(
            dateTime: date,
            eeaD: eeaD,
            dst: Double(rawDst),
            temperature: Double(rawTemp) * 0.1,
            step: step,
            vca: vca,
            status: status
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
