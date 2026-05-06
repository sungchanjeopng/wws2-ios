import XCTest
@testable import WWS2Core

final class CalibrationPointTests: XCTestCase {

    func testCalibrationFramePayloadParsesFiveAndroidCompatibleRecords() throws {
        var data: [UInt8] = []
        for i in 0..<5 {
            let flag: UInt16 = i == 0 ? 0x0003 : UInt16(i & 0x0001)
            appendU16BE(flag, to: &data)
            appendU16BE(UInt16(100 + i), to: &data)       // eea
            appendU16BE(UInt16(900 + i), to: &data)       // density raw
            appendU16BE(UInt16(24), to: &data)            // year offset => 2024
            appendU16BE(UInt16(5 + i), to: &data)         // month
            appendU16BE(UInt16(10 + i), to: &data)        // day
            appendU16BE(UInt16(8 + i), to: &data)         // hour
            appendU16BE(UInt16(30 + i), to: &data)        // minute
        }

        let points = try XCTUnwrap(CalibrationPoint.fromBytes(data))
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(points[0], CalibrationPoint(
            fEEA: true,
            fLV: true,
            eea: 100,
            density: 900,
            year: 2024,
            month: 5,
            day: 10,
            hour: 8,
            minute: 30
        ))
        XCTAssertEqual(points[4].eea, 104)
        XCTAssertEqual(points[4].density, 904)
        XCTAssertEqual(points[4].year, 2024)
        XCTAssertEqual(points[4].month, 9)
        XCTAssertEqual(points[4].day, 14)
        XCTAssertEqual(points[4].hour, 12)
        XCTAssertEqual(points[4].minute, 34)
    }

    func testCalibrationParserRejectsShortPayload() {
        XCTAssertNil(CalibrationPoint.fromBytes(Array(repeating: 0, count: 79)))
    }

    private func appendU16BE(_ value: UInt16, to data: inout [UInt8]) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}
