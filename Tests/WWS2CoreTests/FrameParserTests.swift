import XCTest
@testable import WWS2Core

final class FrameParserTests: XCTestCase {

    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    private func s16(_ v: Int16) -> [UInt8] { u16(UInt16(bitPattern: v)) }

    func testExpectedDataSize() {
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0000, isInterface: false), 34)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0000, isInterface: true), 26)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0001, isInterface: false), 224)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0001, isInterface: true), -1)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0003, isInterface: false), 30)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0004, isInterface: false), 16)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x0004, isInterface: true), 22)
        XCTAssertEqual(FrameParser.expectedDataSize(cmd: 0x9999, isInterface: false), -1)
    }

    func testParseStatus4B() {
        let data = u16(1234) + u16(0x0001)   // dst=12.34, errorCode=0x0001
        let r = FrameParser.parse(cmd: 0x0000, data: data, isInterface: false)
        guard case .status4B(let reading) = r else {
            return XCTFail("expected .status4B, got \(String(describing: r))")
        }
        XCTAssertEqual(reading.level, 12.34, accuracy: 1e-9)
        XCTAssertEqual(reading.errorCode, 1)
    }

    func testParseDensityStatus34B() {
        var bytes: [UInt8] = []
        bytes += u16(1234)   // dst → 12.34
        bytes += u16(100)    // eeaD
        bytes += u16(200)    // eeaR
        bytes += s16(250)    // temperature → 25.0
        bytes += u16(800)    // current → 8.00
        bytes += u16(5)      // damping
        bytes += u16(50)     // set4mA → 0.5
        bytes += u16(1000)   // set20mA → 10.0
        bytes += u16(1)      // pipeDia
        bytes += u16(4000)   // freqMHz → 4.0
        bytes += u16(0)      // errorCode
        bytes += u16(1)      // relay
        bytes += u16(2)      // densUnit
        bytes += u16(1)      // extIn1En
        bytes += u16(0)      // extIn1State
        bytes += u16(0)      // extIn2En
        bytes += u16(0)      // extIn2State
        XCTAssertEqual(bytes.count, 34)

        let r = FrameParser.parse(cmd: 0x0000, data: bytes, isInterface: false)
        guard case .densityStatus(let reading, _, let relay, let densUnit,
                                  let extIn1En, _, _, _) = r else {
            return XCTFail("expected .densityStatus")
        }
        XCTAssertEqual(reading.level, 12.34, accuracy: 1e-9)
        XCTAssertEqual(reading.eeaD, 100)
        XCTAssertEqual(reading.eeaR, 200)
        XCTAssertEqual(reading.temperature, 25.0, accuracy: 1e-9)
        XCTAssertEqual(reading.pipeDiaLabel, "200~400mm")
        XCTAssertEqual(relay, 1)
        XCTAssertEqual(densUnit, 2)
        XCTAssertEqual(extIn1En, 1)
    }

    func testParseInterfaceStatus26B() {
        var bytes: [UInt8] = []
        bytes += u16(100)    // ch1Light → 1.00
        bytes += u16(200)    // ch1Heavy → 2.00
        bytes += s16(250)    // temp → 25.0
        bytes += u16(800)    // current → 8.00
        bytes += u16(0)      // freqIdx=0 → 380 kHz
        bytes += s16(-100)   // offset → -1.00
        bytes += u16(50)     // set4mA → 0.50
        bytes += u16(1000)   // set20mA → 10.00
        bytes += u16(30)     // tvg
        bytes += u16(5)      // damping
        bytes += u16(20)     // asf
        bytes += u16(1)      // relay
        bytes += u16(0)      // errorCode
        XCTAssertEqual(bytes.count, 26)

        let r = FrameParser.parse(cmd: 0x0010, data: bytes, isInterface: true)
        guard case .interfaceStatus(let reading, _, _, _, _, _, let freqMHz,
                                    let tvg, let offset, _, let relay, _) = r else {
            return XCTFail("expected .interfaceStatus")
        }
        XCTAssertEqual(reading.level, 1.0, accuracy: 1e-9)
        XCTAssertEqual(reading.heavyLevel ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(freqMHz, 0.380, accuracy: 1e-9)   // 380 kHz
        XCTAssertEqual(tvg, 30)
        XCTAssertEqual(offset, -1.0, accuracy: 1e-9)
        XCTAssertEqual(relay, 1)
    }

    func testParseDensityDiag() {
        var bytes: [UInt8] = []
        bytes += s16(250)
        bytes += u16(800); bytes += u16(5); bytes += u16(50); bytes += u16(1000)
        bytes += u16(2); bytes += u16(4000); bytes += u16(0)
        XCTAssertEqual(bytes.count, 16)
        let r = FrameParser.parse(cmd: 0x0004, data: bytes, isInterface: false)
        guard case .densityDiag(let diag) = r else {
            return XCTFail("expected .densityDiag")
        }
        XCTAssertEqual(diag.temperature, 25.0, accuracy: 1e-9)
        XCTAssertEqual(diag.pipeDia, 2)
    }

    func testReturnsNilForUnknown() {
        XCTAssertNil(FrameParser.parse(cmd: 0xFFFF, data: [0, 1, 2], isInterface: false))
        XCTAssertNil(FrameParser.parse(cmd: 0x0000, data: [0, 1], isInterface: false))
    }

    func testInterfaceFreqIndexMappings() {
        let mappings: [(UInt16, Double)] = [
            (0, 0.380), (1, 0.270), (2, 0.160), (3, 0.130), (99, 0.000)
        ]
        for (idx, expectedMHz) in mappings {
            var bytes: [UInt8] = []
            bytes += u16(0); bytes += u16(0); bytes += s16(0); bytes += u16(0)
            bytes += u16(idx)
            bytes += s16(0); bytes += u16(0); bytes += u16(0); bytes += u16(0)
            bytes += u16(0); bytes += u16(0); bytes += u16(0); bytes += u16(0)
            let r = FrameParser.parse(cmd: 0x0000, data: bytes, isInterface: true)
            guard case .interfaceStatus(_, _, _, _, _, _, let freqMHz, _, _, _, _, _) = r else {
                return XCTFail("freqIdx=\(idx)")
            }
            XCTAssertEqual(freqMHz, expectedMHz, accuracy: 1e-9, "freqIdx=\(idx)")
        }
    }
}
