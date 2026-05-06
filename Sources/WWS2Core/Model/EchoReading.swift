// Ported from app/src/main/java/com/wws2/densitymeter/model/EchoReading.kt
//
// Frame layout (BE):
//   [0..1]    eeaR     (U16)
//   [2..3]    eeaD     (U16)
//   [4..5]    rawLevel (U16)
//   [6..7]    detAreaLO(U16)
//   [8..9]    detAreaHI(U16)
//   [10..11]  pipeDia  (U16)
//   [12..13]  err      (U16) — skipped (not stored)
//   [14..219] rawWave  103 × U16 BE  (= 206 bytes)
//   --- minimum frame: 220 bytes ---
//   [220..221] thrLightDist (U16, optional)
//   [222..223] thrHeavyDist (U16, optional)
//   [224..225] thrLightAmp  (U16, optional)
//   [226..227] thrHeavyAmp  (U16, optional)
//
// Each optional THR field is read only if the buffer is long enough — exactly
// matches the Kotlin original where `buf.short` advances only inside the
// `if (data.size >= …)` branches.
//
// `wave` is the 816-point interpolation of `rawWave` (102 intervals × 8 = 816,
// matching the firmware ADC_INTP_SIZE).

import Foundation

public struct EchoReading: Equatable, Hashable, Sendable {
    public let eeaR: Int
    public let eeaD: Int
    /// raw U16 from firmware
    public let level: Double
    public let detAreaLO: Int
    public let detAreaHI: Int
    public let pipeDia: Int
    /// 103 raw ADC points
    public let rawWave: [Int]
    /// 816 interpolated points
    public let wave: [Double]
    /// ADC sample interval in µs (from DWT measurement)
    public let sampleUs: Float
    // THR (계면계 전용)
    /// x0.01 m, 미검출 = 0
    public let thrLightDist: Int
    /// x0.01 m, 미검출 = 0
    public let thrHeavyDist: Int
    /// 0..65535
    public let thrLightAmp: Int
    /// 0..65535
    public let thrHeavyAmp: Int

    public init(
        eeaR: Int,
        eeaD: Int,
        level: Double,
        detAreaLO: Int,
        detAreaHI: Int,
        pipeDia: Int,
        rawWave: [Int],
        wave: [Double],
        sampleUs: Float,
        thrLightDist: Int,
        thrHeavyDist: Int,
        thrLightAmp: Int,
        thrHeavyAmp: Int
    ) {
        self.eeaR = eeaR
        self.eeaD = eeaD
        self.level = level
        self.detAreaLO = detAreaLO
        self.detAreaHI = detAreaHI
        self.pipeDia = pipeDia
        self.rawWave = rawWave
        self.wave = wave
        self.sampleUs = sampleUs
        self.thrLightDist = thrLightDist
        self.thrHeavyDist = thrHeavyDist
        self.thrLightAmp = thrLightAmp
        self.thrHeavyAmp = thrHeavyAmp
    }

    /// 102 intervals × 8 = 816 points (firmware ADC_INTP_SIZE)
    public static let intpSize = 816
    /// Display window in mm
    public static let mmRange = 300

    public static func fromBytes(_ data: [UInt8], sampleUs: Float = 2.0) -> EchoReading? {
        guard data.count >= 220 else { return nil }

        let eeaR    = Int(readU16BE(data, 0))
        let eeaD    = Int(readU16BE(data, 2))
        let level   = Int(readU16BE(data, 4))
        let detLO   = Int(readU16BE(data, 6))
        let detHI   = Int(readU16BE(data, 8))
        let pipeDia = Int(readU16BE(data, 10))
        // [12..13] err — skip

        var rawWave: [Int] = []
        rawWave.reserveCapacity(103)
        for i in 0..<103 {
            rawWave.append(Int(readU16BE(data, 14 + i * 2)))
        }

        let wave = interpolateX8(rawWave)

        // Optional THR fields. Each is read only if the buffer is large enough.
        // Kotlin advances the buffer cursor inside each `if`; that's equivalent
        // to reading at fixed offsets when present.
        let thrLightDist = data.count >= 222 ? Int(readU16BE(data, 220)) : 0
        let thrHeavyDist = data.count >= 224 ? Int(readU16BE(data, 222)) : 0
        let thrLightAmp  = data.count >= 226 ? Int(readU16BE(data, 224)) : 0
        let thrHeavyAmp  = data.count >= 228 ? Int(readU16BE(data, 226)) : 0

        return EchoReading(
            eeaR: eeaR, eeaD: eeaD,
            level: Double(level),
            detAreaLO: detLO, detAreaHI: detHI,
            pipeDia: pipeDia,
            rawWave: rawWave, wave: wave,
            sampleUs: sampleUs,
            thrLightDist: thrLightDist,
            thrHeavyDist: thrHeavyDist,
            thrLightAmp: thrLightAmp,
            thrHeavyAmp: thrHeavyAmp
        )
    }

    private static func interpolateX8(_ src: [Int]) -> [Double] {
        var dst = [Double](repeating: 0, count: intpSize)
        for j in 0..<102 {
            let base = j * 8
            let cur  = Double(src[j])
            let nxt  = Double(src[j + 1])
            let diff = (nxt - cur) / 8.0
            dst[base] = cur
            for k in 1..<8 {
                let idx = base + k
                if idx >= intpSize { break }
                dst[idx] = cur + diff * Double(k)
            }
        }
        return dst
    }
}

@inline(__always)
private func readU16BE(_ data: [UInt8], _ offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}
