import XCTest
@testable import WWS2Core

final class TrendRecordTests: XCTestCase {

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Build a fixture: 2024-03-15 14:25:30 UTC, eeaD=0x1234, dst=0x5678,
    /// temp=0x0064 (=100 → 10.0°C), step=1, vca=2, status=3
    private func fixture() -> [UInt8] {
        return [
            0x00, 24,            // year - 2000
            0x00, 3,             // month
            0x00, 15,            // day
            0x00, 14,            // hour
            0x00, 25,            // minute
            0x00, 30,            // second
            0x12, 0x34,          // eeaD
            0x56, 0x78,          // density (rawDst)
            0x00, 0x64,          // temp (signed): 100 → 10.0°C
            0x00, 0x01,          // step
            0x00, 0x02,          // vca
            0x00, 0x03           // status
        ]
    }

    func testParsesValidRecord() throws {
        let record = try XCTUnwrap(TrendRecord.fromBytes(fixture()))
        XCTAssertEqual(record.eeaD,    0x1234)
        XCTAssertEqual(record.dst,     Double(0x5678), accuracy: 1e-9)
        XCTAssertEqual(record.temperature, 10.0,        accuracy: 1e-9)
        XCTAssertEqual(record.step,    1)
        XCTAssertEqual(record.vca,     2)
        XCTAssertEqual(record.status,  3)
        XCTAssertEqual(record.deviceId, "")

        let comps = Self.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: record.dateTime)
        XCTAssertEqual(comps.year,   2024)
        XCTAssertEqual(comps.month,  3)
        XCTAssertEqual(comps.day,    15)
        XCTAssertEqual(comps.hour,   14)
        XCTAssertEqual(comps.minute, 25)
        XCTAssertEqual(comps.second, 30)
    }

    func testNegativeTemperaturePreservesSign() throws {
        var bytes = fixture()
        // temp = 0xFF9C = -100 → -10.0 °C
        bytes[16] = 0xFF
        bytes[17] = 0x9C
        let record = try XCTUnwrap(TrendRecord.fromBytes(bytes))
        XCTAssertEqual(record.temperature, -10.0, accuracy: 1e-9)
    }

    func testReturnsNilForShortBuffer() {
        let bytes = [UInt8](repeating: 0, count: 23)
        XCTAssertNil(TrendRecord.fromBytes(bytes))
    }

    func testCoercesOutOfRangeDateComponents() throws {
        var bytes = fixture()
        bytes[3] = 0    // month=0 → coerced to 1
        bytes[5] = 99   // day=99 → coerced to 31
        let record = try XCTUnwrap(TrendRecord.fromBytes(bytes))
        let comps = Self.utc.dateComponents([.month, .day], from: record.dateTime)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day,   31)
    }
}
