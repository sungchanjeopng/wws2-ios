import XCTest
@testable import WWS2Core

final class InterfaceDiagReadingTests: XCTestCase {

    private func makeBytes(
        temp: Int16, current: UInt16, freq: UInt16,
        offset: Int16, set4: UInt16, set20: UInt16,
        tvg: UInt16, damp: UInt16, asf: UInt16,
        relay: UInt16, error: UInt16 = 0
    ) -> [UInt8] {
        var out: [UInt8] = []
        func append(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        append(UInt16(bitPattern: temp))
        append(current); append(freq)
        append(UInt16(bitPattern: offset))
        append(set4); append(set20); append(tvg); append(damp); append(asf)
        append(relay); append(error)
        return out
    }

    func testParsesAllFields() throws {
        let data = makeBytes(temp: 250, current: 800, freq: 1,
                             offset: -100, set4: 50, set20: 1000,
                             tvg: 30, damp: 5, asf: 20, relay: 0)
        XCTAssertEqual(data.count, 22)
        let r = try XCTUnwrap(InterfaceDiagReading.fromBytes(data))
        XCTAssertEqual(r.temperature, 25.0, accuracy: 1e-9)
        XCTAssertEqual(r.currentMA, 8.0, accuracy: 1e-9)
        XCTAssertEqual(r.freq, 1)
        XCTAssertEqual(r.freqLabel, "160K")
        XCTAssertEqual(r.offset, -1.0, accuracy: 1e-9)   // signed!
        XCTAssertEqual(r.set4mA, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.set20mA, 10.0, accuracy: 1e-9)
        XCTAssertEqual(r.tvg, 30)
        XCTAssertEqual(r.damp, 5)
        XCTAssertEqual(r.asf, 20)
        XCTAssertTrue(r.relayOn)
    }

    func testRelayOff() throws {
        let data = makeBytes(temp: 0, current: 0, freq: 0, offset: 0,
                             set4: 0, set20: 0, tvg: 0, damp: 0, asf: 0, relay: 1)
        let r = try XCTUnwrap(InterfaceDiagReading.fromBytes(data))
        XCTAssertFalse(r.relayOn)
    }

    func testFreqLabels() {
        let labels: [(Int, String)] = [
            (0, "130K"), (1, "160K"), (2, "270K"), (3, "380K"), (4, "--"), (-1, "--")
        ]
        for (f, expected) in labels {
            let r = InterfaceDiagReading(
                temperature: 0, currentMA: 0, freq: f, offset: 0,
                set4mA: 0, set20mA: 0, tvg: 0, damp: 0, asf: 0, relayOn: false
            )
            XCTAssertEqual(r.freqLabel, expected, "freq=\(f)")
        }
    }

    func testRejectsShortBuffer() {
        XCTAssertNil(InterfaceDiagReading.fromBytes([UInt8](repeating: 0, count: 21)))
    }

    func testAcceptsLongerBuffer() throws {
        // Kotlin uses size < 22 (not !=), so 22+ should parse
        let base = makeBytes(temp: 0, current: 0, freq: 0, offset: 0,
                             set4: 0, set20: 0, tvg: 0, damp: 0, asf: 0, relay: 0)
        let extended = base + [0xAA, 0xBB, 0xCC]
        XCTAssertNotNil(InterfaceDiagReading.fromBytes(extended))
    }
}
