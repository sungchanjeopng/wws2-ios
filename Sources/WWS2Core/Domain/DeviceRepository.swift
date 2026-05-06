// Ported from app/src/main/java/com/wws2/densitymeter/data/repository/DeviceRepository.kt
//
// Manages the set of connected device sessions and bookkeeping helpers.
// The Android original tracks `BleProtocolService` instances per device id.
// On iOS we have a cleaner split (Crc / FrameCodec / GattClient / OtaUploader),
// so this layer is generic over a `BleSession` protocol — concrete iOS code
// adopts it on `GattClient`.
//
// All session-tracking logic stays here; Android-only APIs (ConcurrentHashMap)
// are replaced with a simple dictionary that callers serialize externally
// (e.g. from a @MainActor view model).

import Foundation

/// Minimal protocol the repository needs from a per-device session.
/// `GattClient` (in WWS2BLE) adopts this — the repository itself doesn't
/// import CoreBluetooth.
public protocol BleSession: AnyObject {
    func disconnect()
}

public final class DeviceRepository {

    private var sessions: [String: BleSession] = [:]
    /// Lock guarding `sessions` so the repo is safe to call from the main actor
    /// or background tasks alike. Android relies on ConcurrentHashMap; we use
    /// an NSLock to keep API parity without forcing actor isolation.
    private let lock = NSLock()

    public init() {}

    public func getSession(deviceId: String) -> BleSession? {
        lock.lock(); defer { lock.unlock() }
        return sessions[deviceId]
    }

    public func setSession(deviceId: String, session: BleSession) {
        lock.lock(); defer { lock.unlock() }
        sessions[deviceId] = session
    }

    public func removeSession(deviceId: String) {
        lock.lock(); defer { lock.unlock() }
        sessions.removeValue(forKey: deviceId)
    }

    public func removeSessions(ids: [String]) {
        lock.lock(); defer { lock.unlock() }
        for id in ids { sessions.removeValue(forKey: id) }
    }

    public func disconnectAll() {
        lock.lock()
        let snapshot = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        for s in snapshot { s.disconnect() }
    }

    /// Allocate a label for a density meter: ENV230_A01 .. A04.
    public func allocateDensityLabel(usedLabels: Set<String>) -> String {
        for i in 1...4 {
            let label = String(format: "ENV230_A%02d", i)
            if !usedLabels.contains(label) { return label }
        }
        return "ENV230_A04"
    }

    /// Allocate a label pair for an interface meter:
    /// ENV130_A02/A03, A04/A05, A06/A07, A08/A09.
    public func allocateInterfaceLabels(usedLabels: Set<String>) -> (String, String) {
        let pairs = [(2, 3), (4, 5), (6, 7), (8, 9)]
        for (a, b) in pairs {
            let l1 = String(format: "ENV130_A%02d", a)
            let l2 = String(format: "ENV130_A%02d", b)
            if !usedLabels.contains(l1) && !usedLabels.contains(l2) {
                return (l1, l2)
            }
        }
        return ("ENV130_A02", "ENV130_A03")
    }

    /// Extract firmware version from a BLE advertisement name
    /// (e.g. "WESS_V0.1_ENV230_A01" → "V0.1"). Returns "" if not found.
    public func extractFirmwareVersion(bleName: String) -> String {
        // Equivalent to Kotlin's `Regex("V(\\d+\\.\\d+)", RegexOption.IGNORE_CASE)`.
        // We use NSRegularExpression for IGNORE_CASE support.
        guard let regex = try? NSRegularExpression(
            pattern: "V(\\d+\\.\\d+)",
            options: [.caseInsensitive]
        ) else { return "" }
        let range = NSRange(bleName.startIndex..., in: bleName)
        guard let match = regex.firstMatch(in: bleName, options: [], range: range),
              let r = Range(match.range, in: bleName) else { return "" }
        return String(bleName[r])
    }

    /// Detect device type from BLE name.
    public static func isInterfaceMeter(name: String) -> Bool {
        let upper = name.uppercased()
        return upper.hasPrefix("W3")
            || upper.contains("130")
            || upper.contains("WE13")
            || upper.contains("INTERFACE")
    }
}
