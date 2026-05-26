// Ported from app/src/main/java/com/wws2/densitymeter/ble/protocol/FrameCodec.kt
//
// BLE protocol frame assembly and disassembly. Stateless — all functions are pure.
//
// Frame format (BE for header, LE for trailing CRC16):
//   [SOF=0x02] [CMD_HI] [CMD_LO] [DATA...] [CRC16_LO] [CRC16_HI]

import Foundation

public enum FrameCodec {

    public static let sof: UInt8 = 0x02

    public static func buildDeviceInfoRequest(pin: Int = 0) -> [UInt8] {
        let pinHi = UInt8((pin >> 8) & 0xFF)
        let pinLo = UInt8(pin & 0xFF)
        let payload: [UInt8] = [
            sof,
            0x00,
            UInt8(Command.cmdDeviceInfo & 0xFF),
            pinHi,
            pinLo
        ]
        let crc = Crc.crc16Modbus(payload)
        return payload + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
    }

    public static func parsePairingResponse(_ frame: [UInt8]) -> PairingResult? {
        guard frame.count >= 7 else { return nil }
        guard frame[0] == sof else { return nil }

        let cmd = (UInt16(frame[1]) << 8) | UInt16(frame[2])
        guard cmd == Command.cmdDeviceInfo else { return nil }

        let crcExpected = Crc.crc16Modbus(Array(frame[0..<5]))
        let crcReceived = UInt16(frame[5]) | (UInt16(frame[6]) << 8)
        guard crcExpected == crcReceived else { return nil }

        return parsePairingResponse(cmd: cmd, data: Array(frame[3..<5]))
    }

    public static func parsePairingResponse(cmd: UInt16, data: [UInt8]) -> PairingResult? {
        guard cmd == Command.cmdDeviceInfo else { return nil }
        guard data.count >= 2 else { return nil }

        let result = (UInt16(data[0]) << 8) | UInt16(data[1])
        if result == 0x0000 {
            return .success(DeviceInfo(
                siteNameHi: "?",
                siteNameLo: 0,
                fwVersion: FwVersion(major: 0, minor: 0, patch: 0)
            ))
        } else {
            return .pinFailed
        }
    }

    public static func buildFrame(len: Int, data: [UInt8] = []) -> [UInt8] {
        let lenHi = UInt8((len >> 8) & 0xFF)
        let lenLo = UInt8(len & 0xFF)
        let payload: [UInt8] = [sof, lenHi, lenLo] + data
        let crc = Crc.crc16Modbus(payload)
        return payload + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
    }

    /// Build an app-setting write frame matching Android `BleProtocolService.buildSettingFrame`.
    ///
    /// Frame layout:
    ///   [SOF=0x03] [CMD_HI] [CMD_LO] [DATA_HI] [DATA_LO] [CRC16_LO] [CRC16_HI]
    ///
    /// NOTE: This is the ONLY frame in the protocol that uses SOF = 0x03 (rather than 0x02).
    /// The peer firmware uses this SOF to distinguish a write request from normal traffic.
    /// `data` is encoded as 16-bit unsigned big-endian (negative values are sign-extended
    /// then masked, matching the Kotlin `data and 0xFFFF` behaviour).
    public static func buildSettingFrame(cmd: Int, data: Int) -> [UInt8] {
        let settingSof: UInt8 = 0x03
        let cmdHi = UInt8((cmd >> 8) & 0xFF)
        let cmdLo = UInt8(cmd & 0xFF)
        let data16 = data & 0xFFFF
        let dataHi = UInt8((data16 >> 8) & 0xFF)
        let dataLo = UInt8(data16 & 0xFF)
        let payload: [UInt8] = [settingSof, cmdHi, cmdLo, dataHi, dataLo]
        let crc = Crc.crc16Modbus(payload)
        return payload + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
    }

    public static func buildHeartbeat(pageIndex: Int, expectedLen: Int = 0) -> [UInt8] {
        let cmdHi = UInt8((pageIndex >> 8) & 0xFF)
        let cmdLo = UInt8(pageIndex & 0xFF)
        let lenHi = UInt8((expectedLen >> 8) & 0xFF)
        let lenLo = UInt8(expectedLen & 0xFF)
        let payload: [UInt8] = [sof, cmdHi, cmdLo, lenHi, lenLo]
        let crc = Crc.crc16Modbus(payload)
        return payload + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
    }

    public static func parseFrame(_ raw: [UInt8]) -> ParsedFrame? {
        guard raw.count >= 5 else { return nil }
        guard raw[0] == sof else { return nil }

        let cmd = (UInt16(raw[1]) << 8) | UInt16(raw[2])
        let payloadEnd = raw.count - 2
        let crcReceived = UInt16(raw[payloadEnd]) | (UInt16(raw[payloadEnd + 1]) << 8)
        let crcCalc = Crc.crc16Modbus(Array(raw[0..<payloadEnd]))
        guard crcReceived == crcCalc else { return nil }

        let dataSize = raw.count - 5
        let data: [UInt8] = dataSize > 0 ? Array(raw[3..<payloadEnd]) : []
        return ParsedFrame(cmd: cmd, data: data)
    }

    public static func makeStartFrame() -> [UInt8] {
        buildHeartbeat(pageIndex: Int(Command.cmdOtaStart))
    }
    /// OTA start frame variant that encodes file size (rounded up to KB) in
    /// the heartbeat payload, matching the legacy BleProtocolService path.
    public static func makeStartFrame(fileSizeBytes: Int) -> [UInt8] {
        let sizeKB = (fileSizeBytes + 1023) / 1024
        return buildHeartbeat(pageIndex: Int(Command.cmdOtaStart), expectedLen: sizeKB)
    }
    public static func makeEndFrame() -> [UInt8] {
        buildHeartbeat(pageIndex: Int(Command.cmdOtaEnd))
    }

    /// Encode a 32-bit value as little-endian bytes.
    public static func u32le(_ v: UInt32) -> [UInt8] {
        return [
            UInt8(v & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 24) & 0xFF)
        ]
    }

    /// First index where `pattern` occurs in `data`, or -1 if not found.
    public static func indexOfSubsequence(_ data: [UInt8], _ pattern: [UInt8]) -> Int {
        guard !pattern.isEmpty, data.count >= pattern.count else { return -1 }
        let lastStart = data.count - pattern.count
        outer: for i in 0...lastStart {
            for j in 0..<pattern.count {
                if data[i + j] != pattern[j] { continue outer }
            }
            return i
        }
        return -1
    }
}
