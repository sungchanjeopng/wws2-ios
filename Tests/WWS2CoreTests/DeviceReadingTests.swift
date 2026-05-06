import XCTest
@testable import WWS2Core

final class DeviceReadingTests: XCTestCase {

    private func bytes(level: UInt16, tempSigned: Int16, current: UInt16, damping: UInt16,
                       set4: UInt16, set20: UInt16, pipe: UInt16, freq: UInt16) -> [UInt8] {
        var out: [UInt8] = []
        func append(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        append(level)
        append(UInt16(bitPattern: tempSigned))
        append(current)
        append(damping)
        append(set4)
        append(set20)
        append(pipe)
        append(freq)
        return out
    }

    func testParsesAllFields() throws {
        let data = bytes(level: 1234, tempSigned: 250, current: 800, damping: 5,
                         set4: 100, set20: 1000, pipe: 1, freq: 4000)
        let r = try XCTUnwrap(DeviceReading.fromBytes(data))
        XCTAssertEqual(r.level,      1234,    accuracy: 1e-9)   // x0.01m
        XCTAssertEqual(r.temperature, 25.0,   accuracy: 1e-9)   // 250 * 0.1
        XCTAssertEqual(r.currentMA,   8.0,    accuracy: 1e-9)   // 800 * 0.01
        XCTAssertEqual(r.damping,     5)
        XCTAssertEqual(r.set4mA,      1.0,    accuracy: 1e-9)   // 100 * 0.01
        XCTAssertEqual(r.set20mA,    10.0,    accuracy: 1e-9)   // 1000 * 0.01
        XCTAssertEqual(r.pipeDia,     1)
        XCTAssertEqual(r.freqMHz,     4.0,    accuracy: 1e-9)   // 4000 * 0.001
        XCTAssertEqual(r.pipeDiaLabel, "200~400mm")
        // Defaults preserved
        XCTAssertEqual(r.eeaR, 0)
        XCTAssertEqual(r.eeaD, 0)
        XCTAssertNil(r.heavyLevel)
        XCTAssertEqual(r.errorCode, 0)
    }

    func testNegativeTemperaturePreservesSign() throws {
        let data = bytes(level: 0, tempSigned: -100, current: 0, damping: 0,
                         set4: 0, set20: 0, pipe: 0, freq: 0)
        let r = try XCTUnwrap(DeviceReading.fromBytes(data))
        XCTAssertEqual(r.temperature, -10.0, accuracy: 1e-9)
    }

    func testRejectsWrongLength() {
        XCTAssertNil(DeviceReading.fromBytes([UInt8](repeating: 0, count: 15)))
        XCTAssertNil(DeviceReading.fromBytes([UInt8](repeating: 0, count: 17)))
    }

    func testPipeDiaLabelFallback() {
        let r = DeviceReading(level: 0, temperature: 0, currentMA: 0, damping: 0,
                              set4mA: 0, set20mA: 0, pipeDia: 99, freqMHz: 0)
        XCTAssertEqual(r.pipeDiaLabel, "--")
    }

    func testPipeDiaLabelMappings() {
        for (raw, expected) in [(0, "0~200mm"), (1, "200~400mm"), (2, "400~600mm")] {
            let r = DeviceReading(level: 0, temperature: 0, currentMA: 0, damping: 0,
                                  set4mA: 0, set20mA: 0, pipeDia: raw, freqMHz: 0)
            XCTAssertEqual(r.pipeDiaLabel, expected)
        }
    }
}
