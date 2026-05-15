// Ported from app/src/main/java/com/wws2/densitymeter/data/parser/InterfaceEchoParser.kt
//
// Stateful parser for multi-chunk interface echo waveforms.
//
// Lifecycle:
//   1. Caller detects a 203-byte header packet in rxBuf and extracts it.
//   2. Calls beginCollection(headerPkt:parsedCmd:).
//   3. Repeatedly calls tryParseChunks(rxBuf:&) until it returns non-nil.
//   4. On tab switch / error, calls reset().

import Foundation

public final class InterfaceEchoParser {

    public static let semanticHeaderSize = 30
    public static let headerPacketSize = 203

    /// 0 = idle, 1 = collecting_chunks
    public private(set) var state: Int = 0
    public private(set) var cmd: UInt16 = 0
    public private(set) var headerData: [UInt8] = []

    private var echoN: Int = 0
    private var fullChunks: Int = 0
    private var chunksDone: Int = 0
    private var wave: [Int] = []
    private var runningCrc: UInt16 = 0xFFFF

    public init() {}

    public var isCollecting: Bool { state == 1 }

    /// Begin collection from the 203-byte Android header packet
    /// (SOF + CMD + 200B data; first 30B are semantic, remaining 170B reserved).
    public func beginCollection(headerPkt: [UInt8], parsedCmd: UInt16) {
        precondition(
            headerPkt.count >= Self.headerPacketSize,
            "headerPkt must be at least \(Self.headerPacketSize) bytes"
        )

        // Extract the 30-byte semantic header (skip SOF + CMD = 3 bytes).
        headerData = Array(headerPkt[3..<(3 + Self.semanticHeaderSize)])

        // N = empty * 1.1, capped at 1100 (ADC_BUFF_MAX).
        let emptyVal = (Int(headerData[6]) << 8) | Int(headerData[7])
        var n = min(Int(Double(emptyVal) * 1.1), 1100)
        if n == 0 { n = 1 }
        echoN = n

        fullChunks = echoN / 98
        chunksDone = 0
        wave.removeAll(keepingCapacity: true)
        cmd = parsedCmd

        // Initialize running CRC over the full 203-byte header packet,
        // including the reserved padding bytes used by Android/firmware.
        runningCrc = 0xFFFF
        for byte in headerPkt {
            runningCrc = Crc.crc16Update(runningCrc, byte)
        }
        state = 1
    }

    /// Attempt to parse chunks from `rxBuf`. Returns non-nil when all chunks
    /// + the trailing CRC have been received and validated. Consumes the
    /// bytes it processes from the front of `rxBuf`.
    public func tryParseChunks(rxBuf: inout [UInt8]) -> InterfaceEchoReading? {
        // Full chunks (98 samples = 196 bytes each)
        while chunksDone < fullChunks {
            if rxBuf.count < 196 { return nil }
            for i in 0..<196 {
                runningCrc = Crc.crc16Update(runningCrc, rxBuf[i])
            }
            for j in 0..<98 {
                let hi = Int(rxBuf[j * 2])
                let lo = Int(rxBuf[j * 2 + 1])
                wave.append((hi << 8) | lo)
            }
            rxBuf.removeFirst(196)
            chunksDone += 1
        }

        // Last partial chunk: lastSamples × 2B samples + 2B CRC.
        let lastSamples = echoN % 98
        let lastSize = lastSamples * 2 + 2
        if rxBuf.count < lastSize { return nil }

        for j in 0..<lastSamples {
            let b0 = rxBuf[j * 2]
            let b1 = rxBuf[j * 2 + 1]
            runningCrc = Crc.crc16Update(runningCrc, b0)
            runningCrc = Crc.crc16Update(runningCrc, b1)
            wave.append((Int(b0) << 8) | Int(b1))
        }

        let crcOff = lastSamples * 2
        let recvCrc = UInt16(rxBuf[crcOff]) | (UInt16(rxBuf[crcOff + 1]) << 8)
        rxBuf.removeFirst(lastSize)
        state = 0

        guard runningCrc == recvCrc else { return nil }

        // Reconstruct: headerData(30B) + wave bytes → InterfaceEchoReading.
        var waveBytes = [UInt8]()
        waveBytes.reserveCapacity(wave.count * 2)
        for v in wave {
            waveBytes.append(UInt8((v >> 8) & 0xFF))
            waveBytes.append(UInt8(v & 0xFF))
        }
        return InterfaceEchoReading.fromBytes(headerData + waveBytes)
    }

    public func reset() {
        state = 0
        cmd = 0
        headerData = []
        echoN = 0
        fullChunks = 0
        chunksDone = 0
        wave.removeAll(keepingCapacity: false)
        runningCrc = 0xFFFF
    }
}
