import XCTest
@testable import WWS2Core

final class EchoReadingTests: XCTestCase {

    /// Build a valid ≥220 byte frame.
    private func makeFrame(rawWave: [UInt16], extra: [UInt16] = []) -> [UInt8] {
        precondition(rawWave.count == 103)
        var out: [UInt8] = []
        func appendU16(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        // header: eeaR, eeaD, level, detLO, detHI, pipeDia, err
        appendU16(0x0102)   // eeaR
        appendU16(0x0304)   // eeaD
        appendU16(500)      // level
        appendU16(10)       // detLO
        appendU16(20)       // detHI
        appendU16(1)        // pipeDia
        appendU16(0)        // err (skipped)
        for w in rawWave { appendU16(w) }
        for e in extra { appendU16(e) }
        return out
    }

    func testParsesMinimumFrame() throws {
        let raw = (0..<103).map { UInt16($0 * 10) }
        let frame = makeFrame(rawWave: raw)
        XCTAssertEqual(frame.count, 220)
        let r = try XCTUnwrap(EchoReading.fromBytes(frame))

        XCTAssertEqual(r.eeaR, 0x0102)
        XCTAssertEqual(r.eeaD, 0x0304)
        XCTAssertEqual(r.level, 500, accuracy: 1e-9)
        XCTAssertEqual(r.detAreaLO, 10)
        XCTAssertEqual(r.detAreaHI, 20)
        XCTAssertEqual(r.pipeDia, 1)
        XCTAssertEqual(r.rawWave.count, 103)
        XCTAssertEqual(r.rawWave.first, 0)
        XCTAssertEqual(r.rawWave.last, 1020)
        XCTAssertEqual(r.wave.count, EchoReading.intpSize)
        XCTAssertEqual(r.sampleUs, 2.0)

        // Optional THR fields default to 0 when buffer is exactly 220
        XCTAssertEqual(r.thrLightDist, 0)
        XCTAssertEqual(r.thrHeavyDist, 0)
        XCTAssertEqual(r.thrLightAmp, 0)
        XCTAssertEqual(r.thrHeavyAmp, 0)
    }

    func testInterpolationLinear() throws {
        // src linearly increasing by 8 → interpolation should produce values
        // increasing by exactly 1 between samples.
        let raw: [UInt16] = (0..<103).map { UInt16($0 * 8) }
        let frame = makeFrame(rawWave: raw)
        let r = try XCTUnwrap(EchoReading.fromBytes(frame))
        // wave[0]=0, wave[1]=1, ..., wave[7]=7, wave[8]=8 (start of next interval)
        XCTAssertEqual(r.wave[0], 0,  accuracy: 1e-9)
        XCTAssertEqual(r.wave[1], 1,  accuracy: 1e-9)
        XCTAssertEqual(r.wave[7], 7,  accuracy: 1e-9)
        XCTAssertEqual(r.wave[8], 8,  accuracy: 1e-9)
        XCTAssertEqual(r.wave[100], 100, accuracy: 1e-9)
    }

    func testReadsTHRWhenPresent() throws {
        let raw = [UInt16](repeating: 0, count: 103)
        // Add 4 THR U16s → frame size = 220 + 8 = 228
        let frame = makeFrame(rawWave: raw, extra: [101, 202, 303, 404])
        XCTAssertEqual(frame.count, 228)
        let r = try XCTUnwrap(EchoReading.fromBytes(frame))
        XCTAssertEqual(r.thrLightDist, 101)
        XCTAssertEqual(r.thrHeavyDist, 202)
        XCTAssertEqual(r.thrLightAmp,  303)
        XCTAssertEqual(r.thrHeavyAmp,  404)
    }

    func testThrPartialPresence() throws {
        let raw = [UInt16](repeating: 0, count: 103)
        // Add only 2 THR U16s → frame size = 224 → first two THR populated, rest 0
        let frame = makeFrame(rawWave: raw, extra: [777, 888])
        XCTAssertEqual(frame.count, 224)
        let r = try XCTUnwrap(EchoReading.fromBytes(frame))
        XCTAssertEqual(r.thrLightDist, 777)
        XCTAssertEqual(r.thrHeavyDist, 888)
        XCTAssertEqual(r.thrLightAmp, 0)
        XCTAssertEqual(r.thrHeavyAmp, 0)
    }

    func testRejectsShortFrame() {
        XCTAssertNil(EchoReading.fromBytes([UInt8](repeating: 0, count: 219)))
    }

    func testCustomSampleUs() throws {
        let raw = [UInt16](repeating: 0, count: 103)
        let frame = makeFrame(rawWave: raw)
        let r = try XCTUnwrap(EchoReading.fromBytes(frame, sampleUs: 3.2))
        XCTAssertEqual(r.sampleUs, 3.2)
    }
}
