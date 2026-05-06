import XCTest
@testable import WWS2Core

final class CalibrationPointTests: XCTestCase {

    func testParsesFiveRecords() throws {
        var data = [UInt8](repeating: 0, count: 80)
        // Record 0: flag bits 0+1, eea=0x0010, density=0x0064, year=24, month=1, day=2, hour=3, minute=4
        data[0]  = 0x00; data[1]  = 0x03   // flag = 0x0003 (fEEA=true, fLV=true)
        data[2]  = 0x00; data[3]  = 0x10   // eea = 16
        data[4]  = 0x00; data[5]  = 0x64   // density = 100
        data[6]  = 0x00; data[7]  = 24     // year - 2000
        data[8]  = 0x00; data[9]  = 1
        data[10] = 0x00; data[11] = 2
        data[12] = 0x00; data[13] = 3
        data[14] = 0x00; data[15] = 4

        let points = try XCTUnwrap(CalibrationPoint.fromBytes(data))
        XCTAssertEqual(points.count, 5)

        let p0 = points[0]
        XCTAssertTrue(p0.fEEA)
        XCTAssertTrue(p0.fLV)
        XCTAssertEqual(p0.eea, 16)
        XCTAssertEqual(p0.density, 100, accuracy: 1e-9)
        XCTAssertEqual(p0.year, 2024)
        XCTAssertEqual(p0.month, 1)
        XCTAssertEqual(p0.day, 2)
        XCTAssertEqual(p0.hour, 3)
        XCTAssertEqual(p0.minute, 4)

        // Records 1..4 should all be zero-initialized
        for p in points.dropFirst() {
            XCTAssertFalse(p.fEEA)
            XCTAssertFalse(p.fLV)
            XCTAssertEqual(p.eea, 0)
            XCTAssertEqual(p.year, 2000)
        }
    }

    func testFlagBitsIndependent() throws {
        var data = [UInt8](repeating: 0, count: 80)
        data[0] = 0x00; data[1] = 0x01  // only fEEA
        let p = try XCTUnwrap(CalibrationPoint.fromBytes(data))[0]
        XCTAssertTrue(p.fEEA)
        XCTAssertFalse(p.fLV)

        data[0] = 0x00; data[1] = 0x02  // only fLV
        let q = try XCTUnwrap(CalibrationPoint.fromBytes(data))[0]
        XCTAssertFalse(q.fEEA)
        XCTAssertTrue(q.fLV)
    }

    func testReturnsNilForShortBuffer() {
        XCTAssertNil(CalibrationPoint.fromBytes([UInt8](repeating: 0, count: 79)))
    }
}
