import XCTest
@testable import WWS2Core

final class TemperatureUnitTests: XCTestCase {

    func testCelsiusIdentity() {
        XCTAssertEqual(TemperatureUnit.celsius.convert(celsius: 25.0), 25.0, accuracy: 1e-9)
    }

    func testFahrenheitConversion() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(celsius: 0.0),  32.0,  accuracy: 1e-9)
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(celsius: 100.0), 212.0, accuracy: 1e-9)
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(celsius: -40.0), -40.0, accuracy: 1e-9)
    }

    func testFormatOneDecimal() {
        XCTAssertEqual(TemperatureUnit.celsius.format(celsius: 25.555), "25.6")
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius: 100.0), "212.0")
    }

    func testNextToggles() {
        XCTAssertEqual(TemperatureUnit.celsius.next(), .fahrenheit)
        XCTAssertEqual(TemperatureUnit.fahrenheit.next(), .celsius)
    }

    func testFromIntFallback() {
        XCTAssertEqual(TemperatureUnit.fromInt(0), .celsius)
        XCTAssertEqual(TemperatureUnit.fromInt(1), .fahrenheit)
        XCTAssertEqual(TemperatureUnit.fromInt(-1), .celsius)
        XCTAssertEqual(TemperatureUnit.fromInt(99), .celsius)
    }
}
