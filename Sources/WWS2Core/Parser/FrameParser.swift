// Ported from app/src/main/java/com/wws2/densitymeter/data/parser/FrameParser.kt
//
// Stateless frame data parser. Converts raw cmd+data bytes into domain
// model objects. Corresponds to firmware msr_calc.c (signal processing).

import Foundation

public enum FrameParser {

    /// Sealed result type — each case carries the parsed domain objects.
    public enum ParseResult: Equatable, Sendable {
        /// Status 4B: minimal reading (distance + error code only).
        case status4B(DeviceReading)

        /// Status 34B: full density-meter reading + extras.
        case densityStatus(
            reading: DeviceReading,
            trendRecord: TrendRecord,
            relay: Int,
            densUnit: Int,
            extIn1En: Int,
            extIn1State: Int,
            extIn2En: Int,
            extIn2State: Int
        )

        /// Status 26B (or 30B+/32B+ extended): full interface-meter reading + extras.
        /// Extended layout (matches MainViewModel.kt:870-871):
        ///   - bytes 28..29  → emptyDistance  (only present when data.count >= 30)
        ///   - bytes 30..31  → deadZone       (only present when data.count >= 32)
        /// When the firmware sends the minimal 26B payload these two values are
        /// reported as nil so the caller can preserve the previously-known state.
        case interfaceStatus(
            reading: DeviceReading,
            temperature: Double,
            currentMA: Double,
            damping: Int,
            set4mA: Double,
            set20mA: Double,
            freqMHz: Double,
            tvg: Int,
            offset: Double,
            asf: Int,
            relay: Int,
            emptyDistance: Double?,
            deadZone: Double?,
            trendRecord: TrendRecord
        )

        /// Echo 224B: density-meter echo waveform + temperature + densUnit.
        case densityEcho(
            echo: EchoReading,
            temperature: Double,
            trendRecord: TrendRecord,
            densUnit: Int
        )

        /// Diag 16B: density diagnostics.
        case densityDiag(DiagReading)

        /// Diag 22B+: interface diagnostics.
        case interfaceDiag(InterfaceDiagReading)
    }

    /// Expected data size for a given command. Returns -1 if variable / unknown.
    public static func expectedDataSize(cmd: UInt16, isInterface: Bool) -> Int {
        switch cmd {
        case 0x0000, 0x0010: return isInterface ? 200 : 34
        case 0x0001:         return isInterface ? -1 : 224
        case 0x0003:         return 30
        case 0x0004, 0x0014: return isInterface ? 22 : 16
        default:             return -1
        }
    }

    /// Parse a fully-extracted frame (cmd + data) into a domain result.
    /// Returns nil if the data doesn't match any known pattern.
    public static func parse(cmd: UInt16, data: [UInt8], isInterface: Bool) -> ParseResult? {
        // Status: CMD = 0x0000 / 0x0010
        if cmd == 0x0000 || cmd == 0x0010 {
            return parseStatus(data: data, isInterface: isInterface)
        }

        // Density Echo: CMD = 0x0001, 224B
        if cmd == 0x0001 && data.count == 224 {
            return parseDensityEcho(data)
        }

        // Density Diag: CMD = 0x0004, 16B
        if cmd == 0x0004 && data.count == 16 {
            guard let diag = DiagReading.fromBytes(data) else { return nil }
            return .densityDiag(diag)
        }

        // Interface Diag: CMD = 0x0004 / 0x0014, 22B+
        if (cmd == 0x0004 || cmd == 0x0014) && data.count >= 22 {
            guard let diag = InterfaceDiagReading.fromBytes(data) else { return nil }
            return .interfaceDiag(diag)
        }

        return nil
    }

    private static func parseStatus(data: [UInt8], isInterface: Bool) -> ParseResult? {
        switch data.count {
        case 4:  return parseStatus4B(data)
        case 34: return parseDensityStatus34B(data)
        // Interface status: minimal 26B, the extended 28/30/32B layouts that append
        // echoAmp (26..27) / emptyDistance (28..29) / deadZone (30..31), or the full
        // 200B payload the firmware actually sends (bytes 32..199 are reserved 0x00).
        // Pass the FULL data — never truncate — so parseInterfaceStatus26B can read
        // emptyDistance/deadZone when present. Mirrors Kotlin MainViewModel.kt:852-871
        // and firmware data_commu.c:787-794 ("append at reserved offset 28~31").
        case 26, 28, 30, 32:
            return parseInterfaceStatus26B(data)
        case 200 where isInterface:
            return parseInterfaceStatus26B(data)
        default: return nil
        }
    }

    private static func parseStatus4B(_ data: [UInt8]) -> ParseResult {
        let dst = Double(readU16BE(data, 0)) * 0.01
        let errorCode = Int(readU16BE(data, 2))
        let reading = DeviceReading(
            level: dst,
            temperature: 0.0, currentMA: 0.0, damping: 0,
            set4mA: 0.0, set20mA: 0.0, pipeDia: 0, freqMHz: 0.0,
            errorCode: errorCode
        )
        return .status4B(reading)
    }

    private static func parseDensityStatus34B(_ data: [UInt8]) -> ParseResult {
        let dst         = Double(readU16BE(data, 0))  * 0.01
        let eeaD        = Int(readU16BE(data, 2))
        let eeaR        = Int(readU16BE(data, 4))
        let temperature = Double(readS16BE(data, 6)) * 0.1
        let currentMA   = Double(readU16BE(data, 8))  * 0.01
        let damping     = Int(readU16BE(data, 10))
        let set4mA      = Double(readU16BE(data, 12)) * 0.01
        let set20mA     = Double(readU16BE(data, 14)) * 0.01
        let pipeDia     = Int(readU16BE(data, 16))
        let freqMHz     = Double(readU16BE(data, 18)) * 0.001
        let errorCode   = Int(readU16BE(data, 20))
        let relay       = Int(readU16BE(data, 22))
        let densUnit    = Int(readU16BE(data, 24))
        let extIn1En    = Int(readU16BE(data, 26))
        let extIn1State = Int(readU16BE(data, 28))
        let extIn2En    = Int(readU16BE(data, 30))
        let extIn2State = Int(readU16BE(data, 32))

        let reading = DeviceReading(
            level: dst, temperature: temperature, currentMA: currentMA, damping: damping,
            set4mA: set4mA, set20mA: set20mA, pipeDia: pipeDia, freqMHz: freqMHz,
            eeaR: eeaR, eeaD: eeaD, errorCode: errorCode
        )
        let trendRecord = TrendRecord(
            dateTime: Date(),
            eeaD: eeaD,
            dst: dst,
            temperature: temperature
        )
        return .densityStatus(
            reading: reading, trendRecord: trendRecord,
            relay: relay, densUnit: densUnit,
            extIn1En: extIn1En, extIn1State: extIn1State,
            extIn2En: extIn2En, extIn2State: extIn2State
        )
    }

    private static func parseInterfaceStatus26B(_ data: [UInt8]) -> ParseResult {
        let lightRaw    = readU16BE(data, 0)
        let heavyRaw    = readU16BE(data, 2)
        let light       = Double(lightRaw) * 0.01
        let heavy       = Double(heavyRaw) * 0.01
        let temperature = Double(readS16BE(data, 4))  * 0.1
        let currentMA   = Double(readU16BE(data, 6))  * 0.01
        // Interface-meter freq index → kHz: 0=380, 1=270, 2=160, 3=130
        let freqIdx = Int(readU16BE(data, 8))
        let freq: Int = {
            switch freqIdx {
            case 0: return 380
            case 1: return 270
            case 2: return 160
            case 3: return 130
            default: return 0
            }
        }()
        let offset    = Int(readS16BE(data, 10))
        let set4mA    = Double(readU16BE(data, 12)) * 0.01
        let set20mA   = Double(readU16BE(data, 14)) * 0.01
        let tvg       = Int(readU16BE(data, 16))
        let damping   = Int(readU16BE(data, 18))
        let asf       = Int(readU16BE(data, 20))
        let relay     = Int(readU16BE(data, 22))
        let errorCode = Int(readU16BE(data, 24))
        // bytes 26..27 are an echoAmp reservation in the firmware payload; we
        // mirror Kotlin's behaviour and skip them, then opportunistically read
        // emptyDistance/deadZone when the firmware sends the extended layout.
        let emptyDistance: Double? = data.count >= 30
            ? Double(readU16BE(data, 28)) * 0.01
            : nil
        let deadZone: Double? = data.count >= 32
            ? Double(readU16BE(data, 30)) * 0.01
            : nil

        let reading = DeviceReading(
            level: light, temperature: temperature, currentMA: currentMA, damping: damping,
            set4mA: set4mA, set20mA: set20mA, pipeDia: 0, freqMHz: Double(freq) * 0.001,
            heavyLevel: heavy, errorCode: errorCode
        )
        // TrendRecord.dst/eeaD store raw uint16 (cm) — chart/stats apply *0.01.
        // Matches TrendRecord.fromBytes (density download path) which keeps raw.
        let trendRecord = TrendRecord(
            dateTime: Date(),
            eeaD: Int(heavyRaw),
            dst: Double(lightRaw),
            temperature: temperature
        )
        return .interfaceStatus(
            reading: reading,
            temperature: temperature, currentMA: currentMA, damping: damping,
            set4mA: set4mA, set20mA: set20mA, freqMHz: Double(freq) * 0.001,
            tvg: tvg, offset: Double(offset) * 0.01, asf: asf, relay: relay,
            emptyDistance: emptyDistance, deadZone: deadZone,
            trendRecord: trendRecord
        )
    }

    private static func parseDensityEcho(_ data: [UInt8]) -> ParseResult? {
        // Layout: 14B header + 2B temperature(S16) + 206B wave + 2B densUnit = 224B
        // Splice header (0..14) + wave (16..222) → 14 + 206 = 220B for EchoReading
        let echoData = Array(data[0..<14]) + Array(data[16..<222])
        guard let echo = EchoReading.fromBytes(echoData) else { return nil }

        let rawTemp = Int(readS16BE(data, 14))
        let temperature = Double(rawTemp) * 0.1
        let densUnit = Int(readU16BE(data, 222))

        let trendRecord = TrendRecord(
            dateTime: Date(),
            eeaD: echo.eeaD,
            dst: echo.level,
            temperature: temperature
        )
        return .densityEcho(echo: echo, temperature: temperature,
                            trendRecord: trendRecord, densUnit: densUnit)
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
