import XCTest
@testable import WWS2Core

final class CrcTests: XCTestCase {

    // CRC-16 Modbus reference vectors:
    // - empty input → 0xFFFF (initial value, untouched)
    // - "123456789" ASCII → 0x4B37 (well-known Modbus test vector)

    func testCrc16ModbusEmpty() {
        XCTAssertEqual(Crc.crc16Modbus([]), 0xFFFF)
    }

    func testCrc16ModbusKnownVector() {
        let bytes: [UInt8] = "123456789".utf8.map { $0 }
        XCTAssertEqual(Crc.crc16Modbus(bytes), 0x4B37)
    }

    func testCrc16UpdateMatchesBatch() {
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]
        var inc: UInt16 = 0xFFFF
        for b in bytes { inc = Crc.crc16Update(inc, b) }
        XCTAssertEqual(inc, Crc.crc16Modbus(bytes))
    }

    func testCrc32KnownVector() {
        // Standard CRC-32/IEEE for "123456789" = 0xCBF43926
        let bytes: [UInt8] = "123456789".utf8.map { $0 }
        XCTAssertEqual(Crc.crc32(bytes), 0xCBF43926)
    }

    func testCrc32Empty() {
        XCTAssertEqual(Crc.crc32([]), 0x00000000)
    }
}
