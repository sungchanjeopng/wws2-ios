// Ported from app/src/main/java/com/wws2/densitymeter/ble/ota/OtaUploader.kt
//
// OTA firmware upload orchestration. Manages chunked transfer with CRC-32
// verification. Depends on `GattClient` for raw BLE write/reconnect and on
// `FrameCodec` / `Crc` for framing & checksum.

import Foundation
import Combine
import WWS2Core

public enum OtaResult: Int, Sendable {
    case ok        = 0x0001
    case tooShort  = 0x0002
    case crcFail   = 0x0003
    case eraseFail = 0x0004
    case writeFail = 0x0005
    case timeout   = 0x0006

    public var message: String {
        switch self {
        case .ok:        return "Firmware update successful"
        case .tooShort:  return "Upload failed: data too short"
        case .crcFail:   return "Upload failed: CRC mismatch"
        case .eraseFail: return "Upload failed: flash erase error"
        case .writeFail: return "Upload failed: flash write error"
        case .timeout:   return "Upload failed: device timeout"
        }
    }

    public static func from(_ raw: Int) -> OtaResult {
        OtaResult(rawValue: raw) ?? .timeout
    }

    public static func resultMessage(_ raw: Int) -> String {
        if let r = OtaResult(rawValue: raw) { return r.message }
        return String(format: "Upload failed: unknown error (0x%X)", raw)
    }
}

@MainActor
public final class OtaUploader {

    public nonisolated static let bootloaderTrimOffset = 0x8000

    public nonisolated static func payloadForUpload(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.count > bootloaderTrimOffset else { return bytes }
        return Array(bytes.dropFirst(bootloaderTrimOffset))
    }

    private let gatt: GattClient
    public init(gatt: GattClient) { self.gatt = gatt }

    public func upload(
        data: [UInt8],
        awaitStartAck: @escaping @Sendable (TimeInterval) async -> Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> Int {
        defer {
            // Re-enable notifications for normal operation, regardless of outcome.
            self.gatt.setNotifyEnabled(true)
        }

        // 1) Send OTA start frame
        try? await Task.sleep(nanoseconds: 50_000_000)
        if Task.isCancelled { return OtaResult.timeout.rawValue }
        let startAckTask = Task { await awaitStartAck(10.0) }
        await Task.yield()
        let wroteStart = await gatt.write(
            data: FrameCodec.makeStartFrame(fileSizeBytes: data.count),
            withoutResponse: true
        )
        if !wroteStart { return OtaResult.timeout.rawValue }

        let acked = await startAckTask.value
        if Task.isCancelled { return OtaResult.timeout.rawValue }
        if acked {
            try? await Task.sleep(nanoseconds: 500_000_000)
        } else {
            return OtaResult.timeout.rawValue
        }

        // 2) Stream payload in chunks
        var payload = min(200, gatt.payloadFromMtu())
        let total = data.count
        var i = 0
        var lastProgress = 0.0

        while i < total {
            if Task.isCancelled { return OtaResult.timeout.rawValue }
            let end = min(i + payload, total)
            let chunk = Array(data[i..<end])

            let ok = await gatt.write(data: chunk, withoutResponse: true)
            if !ok {
                // Try forceReconnect once; if it fails, attempt a smaller payload.
                let reconnected = await gatt.forceReconnect(maxRetries: 5)
                if reconnected {
                    _ = await gatt.refreshWriteChar()
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }
                if payload > 32 {
                    payload = max(32, payload - 16)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
                // Out of options — abandon upload and surface a timeout.
                onProgress(1.0)
                return OtaResult.timeout.rawValue
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
            i = end

            let progress = Double(i) / Double(total)
            if progress > lastProgress + 0.001 {
                lastProgress = progress
                onProgress(progress)
            }
        }

        // 3) Trailer: CRC-32 + END frame
        if Task.isCancelled { return OtaResult.timeout.rawValue }
        try? await Task.sleep(nanoseconds: 80_000_000)
        if Task.isCancelled { return OtaResult.timeout.rawValue }
        let crc = Crc.crc32(data)
        _ = await gatt.write(data: FrameCodec.u32le(crc), withoutResponse: true)
        try? await Task.sleep(nanoseconds: 30_000_000)
        _ = await gatt.write(data: FrameCodec.makeEndFrame(), withoutResponse: true)

        onProgress(1.0)

        // 4) Wait for device result (CMD 0x0051 with result code)
        return await awaitOtaResult(timeout: 10.0)
    }

    /// Wait for the device's 7-byte result frame after OTA processing
    /// (CRC verify → flash erase → flash write → result → reset on OK).
    /// Can take 10-30s for large firmware.
    private func awaitOtaResult(timeout: TimeInterval) async -> Int {
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            var buf: [UInt8] = []
            var resumed = false
            var cancellable: AnyCancellable?
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !resumed {
                    resumed = true
                    cancellable?.cancel()
                    cont.resume(returning: nil)
                }
            }

            cancellable = self.gatt.notifications.sink { chunk in
                if resumed { return }
                buf.append(contentsOf: chunk)

                while buf.count >= 7 {
                    if buf[0] != FrameCodec.sof {
                        buf.removeFirst()
                        continue
                    }
                    let cmd = (UInt16(buf[1]) << 8) | UInt16(buf[2])
                    if cmd != Command.cmdOtaEnd {
                        buf.removeFirst()
                        continue
                    }
                    let frame = Array(buf[0..<7])
                    let crcCalc = Crc.crc16Modbus(Array(frame[0..<5]))
                    let crcRecv = UInt16(frame[5]) | (UInt16(frame[6]) << 8)
                    if crcCalc != crcRecv {
                        buf.removeFirst()
                        continue
                    }
                    let value = (Int(frame[3]) << 8) | Int(frame[4])
                    resumed = true
                    timeoutTask.cancel()
                    cancellable?.cancel()
                    cont.resume(returning: value)
                    return
                }
            }
        }
        return result ?? OtaResult.timeout.rawValue
    }
}
