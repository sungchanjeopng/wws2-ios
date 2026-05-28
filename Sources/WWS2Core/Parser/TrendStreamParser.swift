// Ported from app/src/main/java/com/wws2/densitymeter/data/parser/TrendStreamParser.kt
//
// Stateful trend-stream parser. Manages the
//   header → records (24-byte each) → trailing CRC
// state machine, with closure callbacks decoupling the parser from any
// view-model state. Corresponds to firmware trd.c (trend ring-buffer).

import Foundation

public final class TrendStreamParser {

    public typealias RecordsParsed = ([TrendRecord]) -> Void
    public typealias HeaderParsed  = (_ totalRecords: Int) -> Void
    public typealias Complete      = () -> Void
    /// Returns true if the caller has handled the failure (e.g. queued a retry).
    public typealias CrcFail       = (_ reason: String) -> Bool
    public typealias ErrorReport   = (_ message: String) -> Void

    /// 0 = idle, 1 = waiting_header, 2 = receiving_chunks
    public private(set) var streamState: Int = 0
    public private(set) var totalRecords: Int = 0
    public var retryCount: Int = 0
    public var firstVisit: Bool = true

    private var runningCrc: UInt16 = 0xFFFF
    private static let recSize = 24
    private static let interfaceRecSize = InterfaceTrendRecord.recordSize

    private let isInterface: Bool
    private let onRecordsParsed: RecordsParsed
    private let onHeaderParsed:  HeaderParsed
    private let onComplete:      Complete
    private let onCrcFail:       CrcFail
    private let onError:         ErrorReport

    public init(
        isInterface: Bool = false,
        onRecordsParsed: @escaping RecordsParsed,
        onHeaderParsed:  @escaping HeaderParsed,
        onComplete:      @escaping Complete,
        onCrcFail:       @escaping CrcFail,
        onError:         @escaping ErrorReport
    ) {
        self.isInterface = isInterface
        self.onRecordsParsed = onRecordsParsed
        self.onHeaderParsed  = onHeaderParsed
        self.onComplete      = onComplete
        self.onCrcFail       = onCrcFail
        self.onError         = onError
    }

    public var isActive: Bool { streamState > 0 }

    public func startStream() {
        streamState = 1
        totalRecords = 0
        runningCrc = 0xFFFF
        retryCount = 0
    }

    public func reset() {
        streamState = 0
        totalRecords = 0
        runningCrc = 0xFFFF
        firstVisit = true
        retryCount = 0
    }

    /// Main entry point. Call whenever new bytes arrive in `rxBuf`.
    /// Consumes processed bytes from the front of `rxBuf`.
    public func tryParse(rxBuf: inout [UInt8], downloadedCount: Int) {
        if streamState == 1 {
            tryParseHeader(rxBuf: &rxBuf)
        }
        if streamState == 2 {
            parseChunks(rxBuf: &rxBuf, downloadedCount: downloadedCount)
        }
    }

    private func tryParseHeader(rxBuf: inout [UInt8]) {
        while rxBuf.count >= 7 {
            // Find SOF (0x02). If absent → drop the buffer entirely.
            guard let sofIdx = rxBuf.firstIndex(of: 0x02) else {
                rxBuf.removeAll(keepingCapacity: true)
                return
            }
            if sofIdx > 0 { rxBuf.removeFirst(sofIdx) }
            if rxBuf.count < 7 { return }

            // Trend header: [SOF][CMD_HI][CMD_LO][records_HI][records_LO][CRC_L][CRC_H]
            let cmd = (UInt16(rxBuf[1]) << 8) | UInt16(rxBuf[2])
            let acceptedCmds: [UInt16] = [0x0002, 0x0012, 0x0007, 0x0017]
            if !acceptedCmds.contains(cmd) {
                rxBuf.removeFirst(1)
                continue
            }

            // CRC over SOF+CMD+DATA = first 5 bytes
            let hdrBytes = Array(rxBuf[0..<5])
            let hdrCrcCalc = Crc.crc16Modbus(hdrBytes)
            let hdrCrcRecv = UInt16(rxBuf[5]) | (UInt16(rxBuf[6]) << 8)
            if hdrCrcCalc != hdrCrcRecv {
                if onCrcFail("header CRC FAIL") { return }
                onError("Header CRC error. Transfer failed.")
                return
            }

            totalRecords = (Int(rxBuf[3]) << 8) | Int(rxBuf[4])
            onHeaderParsed(totalRecords)
            rxBuf.removeFirst(7)
            runningCrc = 0xFFFF
            streamState = 2
            break
        }
    }

    private func parseChunks(rxBuf: inout [UInt8], downloadedCount: Int) {
        var newRecords: [TrendRecord] = []
        let recSize = isInterface ? Self.interfaceRecSize : Self.recSize

        while downloadedCount + newRecords.count < totalRecords && rxBuf.count >= recSize {
            let recBytes = Array(rxBuf[0..<recSize])
            rxBuf.removeFirst(recSize)

            for b in recBytes {
                runningCrc = Crc.crc16Update(runningCrc, b)
            }

            if let rec = parseRecord(recBytes) {
                newRecords.append(rec)
            }
        }

        if !newRecords.isEmpty {
            onRecordsParsed(newRecords)
        }

        // All records received → verify the trailing CRC trailer.
        if downloadedCount + newRecords.count >= totalRecords {
            if rxBuf.count >= 2 {
                let crcReceived = UInt16(rxBuf[0]) | (UInt16(rxBuf[1]) << 8)
                rxBuf.removeFirst(2)
                if crcReceived != runningCrc {
                    if onCrcFail("final CRC FAIL") { return }
                    onError("CRC verification failed. Data corrupted.")
                    return
                }
            }
            streamState = 0
            onComplete()
        }
    }

    private func parseRecord(_ recBytes: [UInt8]) -> TrendRecord? {
        if isInterface {
            guard let record = InterfaceTrendRecord.fromBytes(recBytes) else { return nil }
            // TrendRecord.dst/eeaD store raw uint16 (cm); chart/stats apply *0.01.
            return TrendRecord(
                dateTime: record.dateTime,
                eeaD: Int(record.ch1Heavy * 100.0),
                dst: record.ch1Light * 100.0,
                temperature: 0.0
            )
        }
        return TrendRecord.fromBytes(recBytes)
    }
}
