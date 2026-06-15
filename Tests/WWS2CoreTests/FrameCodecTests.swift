import XCTest
@testable import WWS2Core

final class FrameCodecTests: XCTestCase {

    func testBuildDeviceInfoRequestStructure() {
        let frame = FrameCodec.buildDeviceInfoRequest(pin: 0x1234)
        // [SOF=0x02][0x00][0xF0][PIN_HI=0x12][PIN_LO=0x34][CRC_LO][CRC_HI]
        XCTAssertEqual(frame.count, 7)
        XCTAssertEqual(frame[0], 0x02)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame[2], 0xF0)   // 0x00F0 low byte = 0xF0
        XCTAssertEqual(frame[3], 0x12)
        XCTAssertEqual(frame[4], 0x34)

        // CRC trailer is little-endian
        let crc = Crc.crc16Modbus(Array(frame[0..<5]))
        XCTAssertEqual(frame[5], UInt8(crc & 0xFF))
        XCTAssertEqual(frame[6], UInt8((crc >> 8) & 0xFF))
    }

    func testBuildHeartbeatStructure() {
        let frame = FrameCodec.buildHeartbeat(pageIndex: 0x0001, expectedLen: 0x00FE)
        XCTAssertEqual(frame.count, 7)
        XCTAssertEqual(frame[0], 0x02)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame[2], 0x01)
        XCTAssertEqual(frame[3], 0x00)
        XCTAssertEqual(frame[4], 0xFE)
    }

    func testBuildFrameRoundtripsThroughParse() throws {
        let payload: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        // Note: buildFrame writes len in bytes 1..2 (cmd field for codec).
        let frame = FrameCodec.buildFrame(len: 0x0042, data: payload)
        let parsed = try XCTUnwrap(FrameCodec.parseFrame(frame))
        XCTAssertEqual(parsed.cmd, 0x0042)
        XCTAssertEqual(parsed.data, payload)
    }

    func testParseFrameRejectsBadCrc() {
        var frame = FrameCodec.buildFrame(len: 1, data: [0x00])
        frame[frame.count - 1] ^= 0xFF   // corrupt CRC high byte
        XCTAssertNil(FrameCodec.parseFrame(frame))
    }

    func testParseFrameRejectsBadSof() {
        var frame = FrameCodec.buildFrame(len: 1, data: [0x00])
        frame[0] = 0x03
        XCTAssertNil(FrameCodec.parseFrame(frame))
    }

    func testParseFrameRejectsTooShort() {
        XCTAssertNil(FrameCodec.parseFrame([0x02, 0x00, 0x00, 0x00]))
    }

    func testParsePairingResponseSuccessLegacyNoVersion() throws {
        // Legacy 7-byte success response: result=0x0000, no version bytes.
        let payload: [UInt8] = [0x02, 0x00, 0xF0, 0x00, 0x00]
        let crc = Crc.crc16Modbus(payload)
        let frame = payload + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
        let result = FrameCodec.parsePairingResponse(frame)
        guard case .success(let info) = result else {
            return XCTFail("expected .success, got \(String(describing: result))")
        }
        // Old firmware reports no version.
        XCTAssertNil(info.fwVersion)
    }

    func testParsePairingResponseSuccessWithVersion() throws {
        // v1.1.2+ 10-byte success response: result=0x0000 + version 1.1.2.
        let payload: [UInt8] = [0x02, 0x00, 0xF0, 0x00, 0x00, 0x01, 0x01, 0x02]
        let crc = Crc.crc16Modbus(payload)
        let frame = payload + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
        let result = FrameCodec.parsePairingResponse(frame)
        guard case .success(let info) = result else {
            return XCTFail("expected .success, got \(String(describing: result))")
        }
        XCTAssertEqual(info.fwVersion, FwVersion(major: 1, minor: 1, patch: 2))
        XCTAssertEqual(info.fwVersion?.description, "v1.1.2")
    }

    func testPairingResponseSuccessAndPinFailed() {
        let ok = FrameCodec.buildFrame(len: Int(Command.cmdDeviceInfo), data: [0x00, 0x00])
        let fail = FrameCodec.buildFrame(len: Int(Command.cmdDeviceInfo), data: [0x00, 0x01])
        XCTAssertEqual(
            FrameCodec.parsePairingResponse(ok),
            PairingResult.success(DeviceInfo(siteNameHi: "?", siteNameLo: 0, fwVersion: nil))
        )
        XCTAssertEqual(FrameCodec.parsePairingResponse(fail), PairingResult.pinFailed)
    }

    func testPairingResponseCanBeParsedAfterFrameExtraction() {
        XCTAssertEqual(
            FrameCodec.parsePairingResponse(cmd: Command.cmdDeviceInfo, data: [0x00, 0x00]),
            PairingResult.success(DeviceInfo(siteNameHi: "?", siteNameLo: 0, fwVersion: nil))
        )
        XCTAssertEqual(
            FrameCodec.parsePairingResponse(cmd: Command.cmdDeviceInfo, data: [0x00, 0x00, 0x01, 0x01, 0x02]),
            PairingResult.success(DeviceInfo(siteNameHi: "?", siteNameLo: 0, fwVersion: FwVersion(major: 1, minor: 1, patch: 2)))
        )
        XCTAssertEqual(
            FrameCodec.parsePairingResponse(cmd: Command.cmdDeviceInfo, data: [0x00, 0x01]),
            PairingResult.pinFailed
        )
        XCTAssertNil(FrameCodec.parsePairingResponse(cmd: Command.cmdStatus, data: [0x00, 0x00]))
        XCTAssertNil(FrameCodec.parsePairingResponse(cmd: Command.cmdDeviceInfo, data: [0x00]))
    }

    func testParsePairingResponseRejectsBadCrc() {
        var frame = FrameCodec.buildDeviceInfoRequest(pin: 0)
        frame[frame.count - 1] ^= 0xFF
        XCTAssertNil(FrameCodec.parsePairingResponse(frame))
    }

    func testU32le() {
        XCTAssertEqual(FrameCodec.u32le(0x12345678), [0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(FrameCodec.u32le(0), [0x00, 0x00, 0x00, 0x00])
    }

    func testIndexOfSubsequenceFound() {
        let data: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        XCTAssertEqual(FrameCodec.indexOfSubsequence(data, [0x03, 0x04]), 2)
        XCTAssertEqual(FrameCodec.indexOfSubsequence(data, [0x01]), 0)
        XCTAssertEqual(FrameCodec.indexOfSubsequence(data, [0x05]), 4)
    }

    func testIndexOfSubsequenceNotFound() {
        let data: [UInt8] = [0x01, 0x02, 0x03]
        XCTAssertEqual(FrameCodec.indexOfSubsequence(data, [0x04]), -1)
        XCTAssertEqual(FrameCodec.indexOfSubsequence(data, []), -1)
        XCTAssertEqual(FrameCodec.indexOfSubsequence([], [0x01]), -1)
    }

    func testStartEndFrames() {
        let start = FrameCodec.makeStartFrame()
        let end   = FrameCodec.makeEndFrame()
        XCTAssertEqual(start.count, 7)
        XCTAssertEqual(end.count,   7)
        XCTAssertEqual(start[1], 0x00)
        XCTAssertEqual(start[2], 0x50)   // CMD_OTA_START = 0x0050
        XCTAssertEqual(end[1],   0x00)
        XCTAssertEqual(end[2],   0x51)   // CMD_OTA_END = 0x0051
    }

    func testOtaStartFrameEncodesRoundedKilobytes() {
        let frame = FrameCodec.makeStartFrame(fileSizeBytes: 4097)

        XCTAssertEqual(frame[0], 0x02)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame[2], 0x50)
        XCTAssertEqual(frame[3], 0x00)
        XCTAssertEqual(frame[4], 0x05)
        XCTAssertNotNil(FrameCodec.parseFrame(frame))
    }

    func testFwVersionDescription() {
        XCTAssertEqual(String(describing: FwVersion(major: 1, minor: 2, patch: 3)), "v1.2.3")
    }
}
