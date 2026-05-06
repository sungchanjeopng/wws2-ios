import XCTest
@testable import WWS2BLE

final class OtaResultTests: XCTestCase {

    func testRawValuesMatchFirmwareConstants() {
        XCTAssertEqual(OtaResult.ok.rawValue,        0x0001)
        XCTAssertEqual(OtaResult.tooShort.rawValue,  0x0002)
        XCTAssertEqual(OtaResult.crcFail.rawValue,   0x0003)
        XCTAssertEqual(OtaResult.eraseFail.rawValue, 0x0004)
        XCTAssertEqual(OtaResult.writeFail.rawValue, 0x0005)
        XCTAssertEqual(OtaResult.timeout.rawValue,   0x0006)
    }

    func testKnownMessages() {
        XCTAssertEqual(OtaResult.ok.message,        "Firmware update successful")
        XCTAssertEqual(OtaResult.crcFail.message,   "Upload failed: CRC mismatch")
        XCTAssertEqual(OtaResult.timeout.message,   "Upload failed: device timeout")
    }

    func testFromMapsKnownAndFallsBackToTimeout() {
        XCTAssertEqual(OtaResult.from(0x0001), .ok)
        XCTAssertEqual(OtaResult.from(0x9999), .timeout)
    }

    func testResultMessageHandlesUnknownCode() {
        XCTAssertEqual(OtaResult.resultMessage(0x0001), OtaResult.ok.message)
        XCTAssertTrue(
            OtaResult.resultMessage(0x9999).contains("0x9999"),
            "unknown code should be hex-formatted"
        )
    }
}
