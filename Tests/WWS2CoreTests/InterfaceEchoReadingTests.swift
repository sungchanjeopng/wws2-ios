import XCTest
@testable import WWS2Core

final class InterfaceEchoReadingTests: XCTestCase {

    /// Build a frame: 30B header + N×2B wave samples.
    private func makeFrame(wave: [UInt16] = []) -> [UInt8] {
        var out: [UInt8] = []
        func appendU16(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        // 14 × U16 + 1 × S16 (temperature) = 30 bytes
        appendU16(100)    // lightLevel       → 1.00 m
        appendU16(200)    // heavyLevel       → 2.00 m
        appendU16(10)     // deadzone
        appendU16(20)     // empty
        appendU16(30)     // thrLightDist
        appendU16(40)     // thrHeavyDist
        appendU16(50)     // thrLightReal
        appendU16(60)     // thrHeavyReal
        appendU16(70)     // thrLightSet
        appendU16(80)     // thrHeavySet
        appendU16(0)      // thrLightMode = Auto
        appendU16(1)      // thrHeavyMode = Manual
        appendU16(123)    // echoAmp
        appendU16(2)      // statusCh = OK → "ST02"
        appendU16(UInt16(bitPattern: -50))  // temperature S16 = -5.0 °C
        for w in wave { appendU16(w) }
        return out
    }

    func testParsesHeaderOnly() throws {
        let frame = makeFrame()
        XCTAssertEqual(frame.count, 30)
        let r = try XCTUnwrap(InterfaceEchoReading.fromBytes(frame))
        XCTAssertEqual(r.lightLevel, 1.0, accuracy: 1e-9)
        XCTAssertEqual(r.heavyLevel, 2.0, accuracy: 1e-9)
        XCTAssertEqual(r.deadzone, 10)
        XCTAssertEqual(r.empty, 20)
        XCTAssertEqual(r.thrLightDist, 30)
        XCTAssertEqual(r.thrHeavyDist, 40)
        XCTAssertEqual(r.thrLightReal, 50)
        XCTAssertEqual(r.thrHeavyReal, 60)
        XCTAssertEqual(r.thrLightSet, 70)
        XCTAssertEqual(r.thrHeavySet, 80)
        XCTAssertEqual(r.thrLightMode, 0)
        XCTAssertEqual(r.thrHeavyMode, 1)
        XCTAssertEqual(r.echoAmp, 123)
        XCTAssertEqual(r.statusCh, 2)
        XCTAssertEqual(r.temperature, -50)
        XCTAssertEqual(r.wave, [])
    }

    func testParsesWaveSamples() throws {
        let wave: [UInt16] = [11, 22, 33, 44, 55]
        let frame = makeFrame(wave: wave)
        XCTAssertEqual(frame.count, 30 + 5 * 2)
        let r = try XCTUnwrap(InterfaceEchoReading.fromBytes(frame))
        XCTAssertEqual(r.wave, [11, 22, 33, 44, 55])
    }

    func testStatusLabelMappings() {
        let cases: [(Int, String)] = [
            (0, "ST00"), (4, "ST00"),
            (1, "ST01"), (2, "ST02"), (3, "ST03"),
            (5, "ER01"), (6, "ER02"), (99, "--")
        ]
        for (status, expected) in cases {
            let r = InterfaceEchoReading(
                lightLevel: 0, heavyLevel: 0, deadzone: 0, empty: 0,
                thrLightDist: 0, thrHeavyDist: 0,
                thrLightReal: 0, thrHeavyReal: 0,
                thrLightSet: 0, thrHeavySet: 0,
                thrLightMode: 0, thrHeavyMode: 0,
                echoAmp: 0, statusCh: status, wave: []
            )
            XCTAssertEqual(r.statusLabel, expected, "statusCh=\(status)")
        }
    }

    func testThrModeLabels() {
        let r = InterfaceEchoReading(
            lightLevel: 0, heavyLevel: 0, deadzone: 0, empty: 0,
            thrLightDist: 0, thrHeavyDist: 0,
            thrLightReal: 0, thrHeavyReal: 0,
            thrLightSet: 0, thrHeavySet: 0,
            thrLightMode: 0, thrHeavyMode: 1,
            echoAmp: 0, statusCh: 0, wave: []
        )
        XCTAssertEqual(r.thrLightModeLabel, "Auto")
        XCTAssertEqual(r.thrHeavyModeLabel, "Manual")
    }

    func testToEchoReadingNoInterpolation() throws {
        let frame = makeFrame(wave: [10, 20, 30])
        let r = try XCTUnwrap(InterfaceEchoReading.fromBytes(frame))
        let echo = r.toEchoReading()
        XCTAssertEqual(echo.eeaR, 123)
        XCTAssertEqual(echo.eeaD, 123)
        XCTAssertEqual(echo.level, 1.0, accuracy: 1e-9)
        XCTAssertEqual(echo.detAreaLO, 10)
        XCTAssertEqual(echo.detAreaHI, 20)
        XCTAssertEqual(echo.rawWave, [10, 20, 30])
        XCTAssertEqual(echo.wave, [10.0, 20.0, 30.0])
        XCTAssertEqual(echo.thrLightAmp, 50)
        XCTAssertEqual(echo.thrHeavyAmp, 60)
    }

    func testRejectsShortFrame() {
        XCTAssertNil(InterfaceEchoReading.fromBytes([UInt8](repeating: 0, count: 29)))
    }
}
