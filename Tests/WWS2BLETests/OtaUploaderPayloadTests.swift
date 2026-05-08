import XCTest
@testable import WWS2BLE

final class OtaUploaderPayloadTests: XCTestCase {

    func testPayloadForUploadKeepsShortFirmwareUntouched() {
        let bytes = Array(0..<32).map(UInt8.init)

        XCTAssertEqual(OtaUploader.payloadForUpload(bytes), bytes)
    }

    func testPayloadForUploadKeepsExactBootloaderLengthUntouched() {
        let bytes = Array(repeating: UInt8(0x5A), count: OtaUploader.bootloaderTrimOffset)

        XCTAssertEqual(OtaUploader.payloadForUpload(bytes), bytes)
    }

    func testPayloadForUploadTrimsBootloaderPrefixForAndroidParity() {
        let prefix = Array(repeating: UInt8(0xAA), count: OtaUploader.bootloaderTrimOffset)
        let suffix = Array(0..<16).map(UInt8.init)
        let bytes = prefix + suffix

        XCTAssertEqual(OtaUploader.payloadForUpload(bytes), suffix)
    }
}
