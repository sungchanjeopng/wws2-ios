import XCTest
@testable import WWS2Core

final class InterfaceTrendRecordTests: XCTestCase {

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// 2024-03-15 14:25, ch1Light=1.00, ch1Heavy=2.00, ch2Light=3.00, ch2Heavy=4.00
    private func fixture() -> [UInt8] {
        return [
            24, 3, 15, 14, 25,
            0x00, 0x64,   // 100 → 1.00
            0x00, 0xC8,   // 200 → 2.00
            0x01, 0x2C,   // 300 → 3.00
            0x01, 0x90    // 400 → 4.00
        ]
    }

    func testParsesAllFields() throws {
        let r = try XCTUnwrap(InterfaceTrendRecord.fromBytes(fixture()))
        XCTAssertEqual(r.ch1Light, 1.0, accuracy: 1e-9)
        XCTAssertEqual(r.ch1Heavy, 2.0, accuracy: 1e-9)
        XCTAssertEqual(r.ch2Light, 3.0, accuracy: 1e-9)
        XCTAssertEqual(r.ch2Heavy, 4.0, accuracy: 1e-9)

        let comps = Self.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.dateTime)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 25)
        XCTAssertEqual(comps.second, 0)
    }

    func testCoercesOutOfRangeDateComponents() throws {
        var bytes = fixture()
        bytes[1] = 0    // month=0 → coerced to 1
        bytes[2] = 99   // day=99 → coerced to 31
        bytes[3] = 99   // hour=99 → coerced to 23
        bytes[4] = 99   // minute=99 → coerced to 59
        let r = try XCTUnwrap(InterfaceTrendRecord.fromBytes(bytes))
        let comps = Self.utc.dateComponents([.month, .day, .hour, .minute], from: r.dateTime)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 31)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 59)
    }

    func testRejectsShortBuffer() {
        XCTAssertNil(InterfaceTrendRecord.fromBytes([UInt8](repeating: 0, count: 12)))
    }
}
