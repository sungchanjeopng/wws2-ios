import XCTest
@testable import WWS2BLE

final class BleScannerSignalLevelTests: XCTestCase {

    @MainActor
    func testSignalLevelMappings() {
        let scanner = BleScanner()
        XCTAssertEqual(scanner.signalLevel(rssi:   0), 3)
        XCTAssertEqual(scanner.signalLevel(rssi: -55), 3)   // boundary
        XCTAssertEqual(scanner.signalLevel(rssi: -56), 2)
        XCTAssertEqual(scanner.signalLevel(rssi: -72), 2)   // boundary
        XCTAssertEqual(scanner.signalLevel(rssi: -73), 1)
        XCTAssertEqual(scanner.signalLevel(rssi: -120), 1)
    }
}
