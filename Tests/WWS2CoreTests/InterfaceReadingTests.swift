import XCTest
@testable import WWS2Core

final class InterfaceReadingTests: XCTestCase {

    private func makeBytes(
        ch1Light: UInt16, ch1Heavy: UInt16, ch1Temp: Int16, ch1Cur: UInt16,
        ch2Light: UInt16, ch2Heavy: UInt16, ch2Temp: Int16, ch2Cur: UInt16,
        damping: UInt16, set4: UInt16, set20: UInt16, empty: UInt16, status: UInt16
    ) -> [UInt8] {
        var out: [UInt8] = []
        func append(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        append(ch1Light); append(ch1Heavy)
        append(UInt16(bitPattern: ch1Temp)); append(ch1Cur)
        append(ch2Light); append(ch2Heavy)
        append(UInt16(bitPattern: ch2Temp)); append(ch2Cur)
        append(damping); append(set4); append(set20); append(empty); append(status)
        return out
    }

    func testParsesAllFields() throws {
        let data = makeBytes(
            ch1Light: 100, ch1Heavy: 200, ch1Temp: 250, ch1Cur: 800,
            ch2Light: 300, ch2Heavy: 400, ch2Temp: -50, ch2Cur: 1600,
            damping: 5, set4: 50, set20: 1000, empty: 5000, status: 2
        )
        XCTAssertEqual(data.count, 26)
        let r = try XCTUnwrap(InterfaceReading.fromBytes(data))
        XCTAssertEqual(r.ch1Light, 1.00, accuracy: 1e-9)
        XCTAssertEqual(r.ch1Heavy, 2.00, accuracy: 1e-9)
        XCTAssertEqual(r.ch1Temperature, 25.0, accuracy: 1e-9)
        XCTAssertEqual(r.ch1CurrentMA, 8.00, accuracy: 1e-9)
        XCTAssertEqual(r.ch2Light, 3.00, accuracy: 1e-9)
        XCTAssertEqual(r.ch2Heavy, 4.00, accuracy: 1e-9)
        XCTAssertEqual(r.ch2Temperature, -5.0, accuracy: 1e-9)   // signed!
        XCTAssertEqual(r.ch2CurrentMA, 16.00, accuracy: 1e-9)
        XCTAssertEqual(r.damping, 5)
        XCTAssertEqual(r.set4mA, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.set20mA, 10.0, accuracy: 1e-9)
        XCTAssertEqual(r.emptyDist, 50.0, accuracy: 1e-9)
        XCTAssertEqual(r.status, 2)
    }

    func testToCh1ReadingMapsHeavyLevel() throws {
        let data = makeBytes(
            ch1Light: 100, ch1Heavy: 200, ch1Temp: 250, ch1Cur: 800,
            ch2Light: 0, ch2Heavy: 0, ch2Temp: 0, ch2Cur: 0,
            damping: 5, set4: 50, set20: 1000, empty: 0, status: 0
        )
        let r = try XCTUnwrap(InterfaceReading.fromBytes(data)).toCh1Reading()
        XCTAssertEqual(r.level, 1.0, accuracy: 1e-9)
        XCTAssertEqual(r.heavyLevel ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(r.temperature, 25.0, accuracy: 1e-9)
        XCTAssertEqual(r.pipeDia, 0)
        XCTAssertEqual(r.freqMHz, 0.0, accuracy: 1e-9)
    }

    func testToCh2ReadingMapsHeavyLevel() throws {
        let data = makeBytes(
            ch1Light: 0, ch1Heavy: 0, ch1Temp: 0, ch1Cur: 0,
            ch2Light: 300, ch2Heavy: 400, ch2Temp: -50, ch2Cur: 1600,
            damping: 7, set4: 0, set20: 0, empty: 0, status: 0
        )
        let r = try XCTUnwrap(InterfaceReading.fromBytes(data)).toCh2Reading()
        XCTAssertEqual(r.level, 3.0, accuracy: 1e-9)
        XCTAssertEqual(r.heavyLevel ?? -1, 4.0, accuracy: 1e-9)
        XCTAssertEqual(r.temperature, -5.0, accuracy: 1e-9)
        XCTAssertEqual(r.damping, 7)
    }

    func testRejectsWrongLength() {
        XCTAssertNil(InterfaceReading.fromBytes([UInt8](repeating: 0, count: 25)))
        XCTAssertNil(InterfaceReading.fromBytes([UInt8](repeating: 0, count: 27)))
    }
}
