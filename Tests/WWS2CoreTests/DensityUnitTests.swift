import XCTest
@testable import WWS2Core

final class DensityUnitTests: XCTestCase {

    private let raw: Double = 1234  // 0.01% 단위 → 12.34%

    func testConvertPct() {
        XCTAssertEqual(DensityUnit.pct.convert(raw), 12.34, accuracy: 1e-9)
    }

    func testConvertGL() {
        XCTAssertEqual(DensityUnit.gL.convert(raw), 123.4, accuracy: 1e-9)
    }

    func testConvertPpm() {
        XCTAssertEqual(DensityUnit.ppm.convert(raw), 123_400, accuracy: 1e-9)
    }

    func testConvertKgM3() {
        XCTAssertEqual(DensityUnit.kgM3.convert(raw), 1234, accuracy: 1e-9)
    }

    func testConvertGCm3() {
        XCTAssertEqual(DensityUnit.gCm3.convert(raw), 1.234, accuracy: 1e-9)
    }

    func testFormatPctTwoDecimals() {
        XCTAssertEqual(DensityUnit.pct.format(raw: raw), "12.34")
    }

    func testFormatGLOneDecimal() {
        XCTAssertEqual(DensityUnit.gL.format(raw: raw), "123.4")
    }

    func testFormatPpmInteger() {
        XCTAssertEqual(DensityUnit.ppm.format(raw: raw), "123400")
    }

    func testFormatGCm3ThreeDecimals() {
        XCTAssertEqual(DensityUnit.gCm3.format(raw: raw), "1.234")
    }

    func testFromIntWithinRange() {
        XCTAssertEqual(DensityUnit.fromInt(0), .pct)
        XCTAssertEqual(DensityUnit.fromInt(5), .gCm3)
    }

    func testFromIntOutOfRangeFallsBackToPct() {
        XCTAssertEqual(DensityUnit.fromInt(-1), .pct)
        XCTAssertEqual(DensityUnit.fromInt(99), .pct)
    }

    func testNextWrapsAround() {
        XCTAssertEqual(DensityUnit.pct.next(), .gL)
        XCTAssertEqual(DensityUnit.gCm3.next(), .pct)
    }

    func testAllCasesOrderMatchesRawValues() {
        let ordered = DensityUnit.allCases.map { $0.rawValue }
        XCTAssertEqual(ordered, [0, 1, 2, 3, 4, 5])
    }

    func testLabelsMatchKotlinOriginal() {
        XCTAssertEqual(DensityUnit.pct.label,  "%")
        XCTAssertEqual(DensityUnit.gL.label,   "g/L")
        XCTAssertEqual(DensityUnit.ppm.label,  "ppm")
        XCTAssertEqual(DensityUnit.mgL.label,  "mg/L")
        XCTAssertEqual(DensityUnit.kgM3.label, "kg/m³")
        XCTAssertEqual(DensityUnit.gCm3.label, "g/cm³")
    }
}
