import XCTest
@testable import WWS2Core

final class InterfaceEchoParserTests: XCTestCase {

    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    /// Builds a complete capture: 203-byte header packet + N×U16 wave + CRC.
    /// Returns (headerPkt, waveStream, expectedSamples).
    private func buildCapture(emptyVal: Int, samples: [UInt16])
        -> (headerPkt: [UInt8], waveStream: [UInt8])
    {
        // 203-byte header packet = SOF + CMD + 200B data
        var headerPkt: [UInt8] = []
        headerPkt.append(0x02)         // SOF
        headerPkt += u16(0x0001)       // CMD
        // 200B header payload: first 30B semantic data, trailing 170B reserved.
        var hdr = [UInt8](repeating: 0, count: 200)
        hdr[6] = UInt8((emptyVal >> 8) & 0xFF)
        hdr[7] = UInt8(emptyVal & 0xFF)
        for i in 30..<200 {
            hdr[i] = UInt8((i * 7) & 0xFF)
        }
        headerPkt += hdr
        XCTAssertEqual(headerPkt.count, 203)

        // wave bytes
        var waveBytes: [UInt8] = []
        for s in samples { waveBytes += u16(s) }

        // CRC = update over the full 203B headerPkt followed by all wave bytes
        var crc: UInt16 = 0xFFFF
        for b in headerPkt { crc = Crc.crc16Update(crc, b) }
        for b in waveBytes { crc = Crc.crc16Update(crc, b) }

        let stream = waveBytes + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
        return (headerPkt, stream)
    }

    func testBeginCollectionUses30ByteSemanticHeaderFrom203BytePacket() {
        let cap = buildCapture(emptyVal: 10, samples: [UInt16](repeating: 0, count: 11))

        let parser = InterfaceEchoParser()
        parser.beginCollection(headerPkt: cap.headerPkt, parsedCmd: 0x0001)

        XCTAssertEqual(parser.headerData.count, 30)
        XCTAssertEqual(parser.headerData[6], cap.headerPkt[9])
        XCTAssertEqual(parser.headerData[7], cap.headerPkt[10])
    }

    func testCollectsSingleSmallChunk() throws {
        // emptyVal=10 → echoN = min(11, 1100) = 11 → fullChunks=0, lastSamples=11
        let samples: [UInt16] = (0..<11).map { _ in 1234 }
        let cap = buildCapture(emptyVal: 10, samples: samples)

        let parser = InterfaceEchoParser()
        parser.beginCollection(headerPkt: cap.headerPkt, parsedCmd: 0x0001)
        XCTAssertTrue(parser.isCollecting)

        var buf = cap.waveStream
        let result = parser.tryParseChunks(rxBuf: &buf)
        let reading = try XCTUnwrap(result)
        XCTAssertFalse(parser.isCollecting)
        XCTAssertEqual(reading.wave.count, 11)
        XCTAssertEqual(buf, [], "all bytes should have been consumed")
    }

    func testCollectsMultipleFullChunks() throws {
        // emptyVal=200 → echoN=min(220, 1100)=220 → fullChunks=2 (196 each), lastSamples=24
        let samples = [UInt16](repeating: 0xAABB, count: 220)
        let cap = buildCapture(emptyVal: 200, samples: samples)

        let parser = InterfaceEchoParser()
        parser.beginCollection(headerPkt: cap.headerPkt, parsedCmd: 0x0001)

        var buf = cap.waveStream
        let result = parser.tryParseChunks(rxBuf: &buf)
        let reading = try XCTUnwrap(result)
        XCTAssertEqual(reading.wave.count, 220)
        XCTAssertEqual(reading.wave.first, 0xAABB)
    }

    func testReturnsNilUntilEnoughBytes() {
        let samples = [UInt16](repeating: 0xC0DE, count: 220)
        let cap = buildCapture(emptyVal: 200, samples: samples)
        let parser = InterfaceEchoParser()
        parser.beginCollection(headerPkt: cap.headerPkt, parsedCmd: 0x0001)

        // Feed only the first 100 bytes — not enough for first 196B chunk.
        var partial = Array(cap.waveStream.prefix(100))
        XCTAssertNil(parser.tryParseChunks(rxBuf: &partial))
        // partial untouched (no full chunk yet)
        XCTAssertEqual(partial.count, 100)
    }

    func testRejectsBadCrc() {
        let samples = [UInt16](repeating: 0, count: 11)
        let cap = buildCapture(emptyVal: 10, samples: samples)
        var corrupted = cap.waveStream
        corrupted[corrupted.count - 1] ^= 0xFF

        let parser = InterfaceEchoParser()
        parser.beginCollection(headerPkt: cap.headerPkt, parsedCmd: 0x0001)
        var buf = corrupted
        XCTAssertNil(parser.tryParseChunks(rxBuf: &buf))
        XCTAssertFalse(parser.isCollecting, "state should reset to idle even on CRC fail")
    }

    func testRejectsBadCrcWhenReservedHeaderPaddingChanges() {
        let samples = [UInt16](repeating: 0x2222, count: 11)
        var cap = buildCapture(emptyVal: 10, samples: samples)
        cap.headerPkt[150] ^= 0xFF   // mutate reserved padding after CRC generation

        let parser = InterfaceEchoParser()
        parser.beginCollection(headerPkt: cap.headerPkt, parsedCmd: 0x0001)
        var buf = cap.waveStream

        XCTAssertNil(parser.tryParseChunks(rxBuf: &buf))
        XCTAssertFalse(parser.isCollecting)
    }

    func testReset() {
        let parser = InterfaceEchoParser()
        let headerPkt = [UInt8](repeating: 0, count: 203)
        parser.beginCollection(headerPkt: headerPkt, parsedCmd: 0x0001)
        parser.reset()
        XCTAssertFalse(parser.isCollecting)
        XCTAssertEqual(parser.headerData, [])
    }
}
