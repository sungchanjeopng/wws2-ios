import XCTest
@testable import WWS2Core

final class TrendStreamParserTests: XCTestCase {

    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    /// Build one valid 24-byte trend record (year=2024, month=3, day=15, …).
    private func sampleRecord() -> [UInt8] {
        return [
            0x00, 24, 0x00, 3, 0x00, 15,
            0x00, 14, 0x00, 25, 0x00, 30,
            0x12, 0x34,
            0x00, 0x10,
            0x00, 0x64,
            0x00, 0x01,
            0x00, 0x02,
            0x00, 0x03
        ]
    }

    private func buildTrendStream(records: [[UInt8]]) -> [UInt8] {
        // header: [SOF][CMD_HI=0x00][CMD_LO=0x02][totalH][totalL][CRC_L][CRC_H]
        let total = UInt16(records.count)
        let hdr5: [UInt8] = [0x02, 0x00, 0x02] + u16(total)
        let hdrCrc = Crc.crc16Modbus(hdr5)
        var stream: [UInt8] = hdr5 + [UInt8(hdrCrc & 0xFF), UInt8((hdrCrc >> 8) & 0xFF)]

        // body: records (CRC computed across record bytes only)
        var bodyCrc: UInt16 = 0xFFFF
        for rec in records {
            stream += rec
            for b in rec { bodyCrc = Crc.crc16Update(bodyCrc, b) }
        }
        stream += [UInt8(bodyCrc & 0xFF), UInt8((bodyCrc >> 8) & 0xFF)]
        return stream
    }

    private final class CallbackBag {
        var totalRecords: Int = 0
        var collected: [TrendRecord] = []
        var completeCalled = false
        var crcFailReasons: [String] = []
        var errorMsgs: [String] = []
    }

    private func makeParser(_ bag: CallbackBag, retryHandled: Bool = false) -> TrendStreamParser {
        return TrendStreamParser(
            onRecordsParsed: { bag.collected.append(contentsOf: $0) },
            onHeaderParsed:  { bag.totalRecords = $0 },
            onComplete:      { bag.completeCalled = true },
            onCrcFail:       { reason in bag.crcFailReasons.append(reason); return retryHandled },
            onError:         { msg in bag.errorMsgs.append(msg) }
        )
    }

    func testParsesFullStreamSingleCall() {
        let records = [sampleRecord(), sampleRecord(), sampleRecord()]
        var stream = buildTrendStream(records: records)
        let bag = CallbackBag()
        let parser = makeParser(bag)
        parser.startStream()

        parser.tryParse(rxBuf: &stream, downloadedCount: 0)

        XCTAssertEqual(bag.totalRecords, 3)
        XCTAssertEqual(bag.collected.count, 3)
        XCTAssertTrue(bag.completeCalled)
        XCTAssertTrue(bag.errorMsgs.isEmpty)
        XCTAssertFalse(parser.isActive)
        XCTAssertEqual(stream, [], "all bytes consumed")
    }

    func testIncrementalDelivery() {
        let records = [sampleRecord(), sampleRecord()]
        let full = buildTrendStream(records: records)
        let bag = CallbackBag()
        let parser = makeParser(bag)
        parser.startStream()

        // Feed just the header
        var buf: [UInt8] = Array(full.prefix(7))
        parser.tryParse(rxBuf: &buf, downloadedCount: 0)
        XCTAssertEqual(bag.totalRecords, 2)
        XCTAssertEqual(bag.collected.count, 0)
        XCTAssertFalse(bag.completeCalled)

        // Feed remaining bytes
        buf.append(contentsOf: full.dropFirst(7))
        parser.tryParse(rxBuf: &buf, downloadedCount: 0)
        XCTAssertEqual(bag.collected.count, 2)
        XCTAssertTrue(bag.completeCalled)
    }

    func testHeaderCrcFailureReportsError() {
        var stream = buildTrendStream(records: [sampleRecord()])
        // Corrupt header CRC
        stream[5] ^= 0xFF
        let bag = CallbackBag()
        let parser = makeParser(bag, retryHandled: false)
        parser.startStream()

        parser.tryParse(rxBuf: &stream, downloadedCount: 0)
        XCTAssertFalse(bag.crcFailReasons.isEmpty)
        XCTAssertFalse(bag.errorMsgs.isEmpty)
        XCTAssertFalse(bag.completeCalled)
    }

    func testHeaderCrcRetryHandledDoesNotReportError() {
        var stream = buildTrendStream(records: [sampleRecord()])
        stream[5] ^= 0xFF
        let bag = CallbackBag()
        let parser = makeParser(bag, retryHandled: true)
        parser.startStream()

        parser.tryParse(rxBuf: &stream, downloadedCount: 0)
        XCTAssertFalse(bag.crcFailReasons.isEmpty)
        XCTAssertTrue(bag.errorMsgs.isEmpty, "retryHandled=true must suppress error callback")
    }

    func testFinalCrcFailureReportsError() {
        var stream = buildTrendStream(records: [sampleRecord(), sampleRecord()])
        // Corrupt the trailing CRC (last 2 bytes)
        stream[stream.count - 1] ^= 0xFF
        let bag = CallbackBag()
        let parser = makeParser(bag)
        parser.startStream()

        parser.tryParse(rxBuf: &stream, downloadedCount: 0)
        XCTAssertEqual(bag.crcFailReasons, ["final CRC FAIL"])
        XCTAssertFalse(bag.errorMsgs.isEmpty)
        XCTAssertFalse(bag.completeCalled)
    }

    func testIgnoresGarbageBeforeSof() {
        let records = [sampleRecord()]
        let valid = buildTrendStream(records: records)
        var stream: [UInt8] = [0xFF, 0xFE, 0xFD] + valid
        let bag = CallbackBag()
        let parser = makeParser(bag)
        parser.startStream()

        parser.tryParse(rxBuf: &stream, downloadedCount: 0)
        XCTAssertTrue(bag.completeCalled)
        XCTAssertEqual(bag.collected.count, 1)
    }

    func testReset() {
        let bag = CallbackBag()
        let parser = makeParser(bag)
        parser.startStream()
        XCTAssertTrue(parser.isActive)
        parser.reset()
        XCTAssertFalse(parser.isActive)
        XCTAssertTrue(parser.firstVisit)
    }
}
