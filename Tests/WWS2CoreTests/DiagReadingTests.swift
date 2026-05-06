import XCTest
@testable import WWS2Core

final class DiagReadingTests: XCTestCase {

    private func bytes(temp: Int16, current: UInt16, damping: UInt16,
                       set4: UInt16, set20: UInt16, pipe: UInt16,
                       freq: UInt16, err: UInt16) -> [UInt8] {
        var out: [UInt8] = []
        func append(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        append(UInt16(bitPattern: temp))
        append(current); append(damping); append(set4); append(set20)
        append(pipe);    append(freq);    append(err)
        return out
    }

    func testParsesAllFields() throws {
        let data = bytes(temp: 250, current: 800, damping: 5,
                         set4: 100, set20: 1000, pipe: 2,
                         freq: 4000, err: 0xDEAD)
        let r = try XCTUnwrap(DiagReading.fromBytes(data))
        XCTAssertEqual(r.temperature, 25.0,  accuracy: 1e-9)
        XCTAssertEqual(r.currentMA,    8.0,  accuracy: 1e-9)
        XCTAssertEqual(r.damping,      5)
        XCTAssertEqual(r.set4mA,       1.0,  accuracy: 1e-9)
        XCTAssertEqual(r.set20mA,     10.0,  accuracy: 1e-9)
        XCTAssertEqual(r.pipeDia,      2)
        XCTAssertEqual(r.freqMHz,      4.0,  accuracy: 1e-9)
    }

    func testNegativeTemperaturePreservesSign() throws {
        let data = bytes(temp: -50, current: 0, damping: 0,
                         set4: 0, set20: 0, pipe: 0, freq: 0, err: 0)
        let r = try XCTUnwrap(DiagReading.fromBytes(data))
        XCTAssertEqual(r.temperature, -5.0, accuracy: 1e-9)
    }

    func testRejectsWrongLength() {
        XCTAssertNil(DiagReading.fromBytes([UInt8](repeating: 0, count: 15)))
        XCTAssertNil(DiagReading.fromBytes([UInt8](repeating: 0, count: 17)))
    }
}
