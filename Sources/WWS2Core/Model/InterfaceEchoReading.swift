// Ported from app/src/main/java/com/wws2/densitymeter/model/InterfaceEchoReading.kt
//
// 계면계 Echo 파형 데이터 — 30B header + N×2B wave samples.
// Header layout (15 × U16 BE = 30 bytes):
//   [0..1]   lightLevel   (U16)  x0.01 m
//   [2..3]   heavyLevel   (U16)  x0.01 m
//   [4..5]   deadzone     (U16)
//   [6..7]   empty        (U16)
//   [8..9]   thrLightDist (U16)
//   [10..11] thrHeavyDist (U16)
//   [12..13] thrLightReal (U16)
//   [14..15] thrHeavyReal (U16)
//   [16..17] thrLightSet  (U16)
//   [18..19] thrHeavySet  (U16)
//   [20..21] thrLightMode (U16)  0=Auto, 1=Manual
//   [22..23] thrHeavyMode (U16)  0=Auto, 1=Manual
//   [24..25] echoAmp      (U16)
//   [26..27] statusCh     (U16)
//   [28..29] temperature  (S16)  x0.1 °C
//   [30..]   wave[N] = remaining/2 samples (U16)

import Foundation

public struct InterfaceEchoReading: Equatable, Hashable, Sendable {
    public let lightLevel: Double
    public let heavyLevel: Double
    public let deadzone: Int
    public let empty: Int
    public let thrLightDist: Int
    public let thrHeavyDist: Int
    /// 실제 계산된 THR 진폭 (0..4095)
    public let thrLightReal: Int
    public let thrHeavyReal: Int
    /// 설정 THR (Auto: 0..95%, Manual: 0..32)
    public let thrLightSet: Int
    public let thrHeavySet: Int
    /// 0=Auto, 1=Manual
    public let thrLightMode: Int
    public let thrHeavyMode: Int
    public let echoAmp: Int
    /// 0=WEAK, 1=TRAC, 2=OK, 3=STOP, 4=IDLE, 5=NG, 6=TPR_NG
    public let statusCh: Int
    /// signed, x0.1 °C
    public let temperature: Int
    /// raw wave samples (0..4095)
    public let wave: [Int]

    public init(
        lightLevel: Double, heavyLevel: Double,
        deadzone: Int, empty: Int,
        thrLightDist: Int, thrHeavyDist: Int,
        thrLightReal: Int, thrHeavyReal: Int,
        thrLightSet: Int,  thrHeavySet: Int,
        thrLightMode: Int, thrHeavyMode: Int,
        echoAmp: Int, statusCh: Int,
        temperature: Int = 0,
        wave: [Int]
    ) {
        self.lightLevel = lightLevel
        self.heavyLevel = heavyLevel
        self.deadzone = deadzone
        self.empty = empty
        self.thrLightDist = thrLightDist
        self.thrHeavyDist = thrHeavyDist
        self.thrLightReal = thrLightReal
        self.thrHeavyReal = thrHeavyReal
        self.thrLightSet = thrLightSet
        self.thrHeavySet = thrHeavySet
        self.thrLightMode = thrLightMode
        self.thrHeavyMode = thrHeavyMode
        self.echoAmp = echoAmp
        self.statusCh = statusCh
        self.temperature = temperature
        self.wave = wave
    }

    public var statusLabel: String {
        switch statusCh {
        case 0, 4: return "ST00"
        case 1:    return "ST01"
        case 2:    return "ST02"
        case 3:    return "ST03"
        case 5:    return "ER01"
        case 6:    return "ER02"
        default:   return "--"
        }
    }

    public var thrLightModeLabel: String { thrLightMode == 0 ? "Auto" : "Manual" }
    public var thrHeavyModeLabel: String { thrHeavyMode == 0 ? "Auto" : "Manual" }

    /// EchoChart 표시용 EchoReading 변환 (보간 없이 raw wave 그대로)
    public func toEchoReading() -> EchoReading {
        EchoReading(
            eeaR: echoAmp,
            eeaD: echoAmp,
            level: lightLevel,
            detAreaLO: deadzone,
            detAreaHI: empty,
            pipeDia: 0,
            rawWave: wave,
            wave: wave.map(Double.init),
            sampleUs: 2.0,
            thrLightDist: thrLightDist,
            thrHeavyDist: thrHeavyDist,
            thrLightAmp: thrLightReal,
            thrHeavyAmp: thrHeavyReal
        )
    }

    public static let headerSize = 30  // 14 × U16 + temperature S16

    public static func fromBytes(_ data: [UInt8]) -> InterfaceEchoReading? {
        guard data.count >= headerSize else { return nil }

        let lightLevel = Double(readU16BE(data, 0))  * 0.01
        let heavyLevel = Double(readU16BE(data, 2))  * 0.01
        let deadzone   = Int(readU16BE(data, 4))
        let empty_     = Int(readU16BE(data, 6))
        let thrLightDist = Int(readU16BE(data, 8))
        let thrHeavyDist = Int(readU16BE(data, 10))
        let thrLightReal = Int(readU16BE(data, 12))
        let thrHeavyReal = Int(readU16BE(data, 14))
        let thrLightSet  = Int(readU16BE(data, 16))
        let thrHeavySet  = Int(readU16BE(data, 18))
        let thrLightMode = Int(readU16BE(data, 20))
        let thrHeavyMode = Int(readU16BE(data, 22))
        let echoAmp      = Int(readU16BE(data, 24))
        let statusCh     = Int(readU16BE(data, 26))
        let temperature  = Int(readS16BE(data, 28))   // signed

        let waveByteCount = data.count - headerSize
        let waveSampleCount = waveByteCount / 2
        var wave: [Int] = []
        wave.reserveCapacity(waveSampleCount)
        for i in 0..<waveSampleCount {
            wave.append(Int(readU16BE(data, headerSize + i * 2)))
        }

        return InterfaceEchoReading(
            lightLevel: lightLevel, heavyLevel: heavyLevel,
            deadzone: deadzone, empty: empty_,
            thrLightDist: thrLightDist, thrHeavyDist: thrHeavyDist,
            thrLightReal: thrLightReal, thrHeavyReal: thrHeavyReal,
            thrLightSet: thrLightSet, thrHeavySet: thrHeavySet,
            thrLightMode: thrLightMode, thrHeavyMode: thrHeavyMode,
            echoAmp: echoAmp, statusCh: statusCh,
            temperature: temperature,
            wave: wave
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
