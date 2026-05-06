// Ported from app/src/main/java/com/wws2/densitymeter/ble/gatt/GattClient.kt
//
// On Android this class wraps `BluetoothGatt` and a custom `BluetoothGattCallback`.
// On iOS the equivalent surface is `CBCentralManager` + `CBPeripheral` + their
// delegates. The class keeps zero knowledge of protocol framing — it deals only
// in raw `[UInt8]`. The public API mirrors the Kotlin original where possible:
//
//   connect(...) async -> Bool
//   write(data: , withoutResponse: ) async -> Bool
//   disconnect()
//   forceReconnect(maxRetries:) async -> Bool
//   setNotifyEnabled(_:)
//   payloadFromMtu() -> Int
//   notifications  : PassthroughSubject<[UInt8], Never>
//   isConnected    : @Published Bool

import Foundation
import Combine
import CoreBluetooth
import WWS2Core

@MainActor
public final class GattClient: NSObject, ObservableObject, BleSession {

    @Published public private(set) var isConnected: Bool = false

    /// Multi-subscriber stream of inbound notifications.
    public let notifications = PassthroughSubject<[UInt8], Never>()

    /// Default MTU is 23 (BLE spec); negotiated value on iOS is reported via
    /// `peripheral.maximumWriteValueLength(for:)`. We track the peripheral and
    /// compute payload length on demand.
    public var currentMtu: Int {
        // iOS doesn't expose MTU directly; for .withoutResponse type that the
        // firmware uses, 'maximumWriteValueLength' returns MTU - 3.
        guard let p = peripheral else { return 23 }
        let len = p.maximumWriteValueLength(for: .withoutResponse)
        return len + 3
    }

    public private(set) weak var peripheral: CBPeripheral?
    private let central: CBCentralManager
    private weak var scanner: BleScanner?

    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var useWriteNoResponse: Bool = false

    private var connectContinuation: CheckedContinuation<Bool, Never>?
    private var writeContinuation: CheckedContinuation<Bool, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var writeTimeoutTask: Task<Void, Never>?

    /// Create a client bound to a scanner-owned central manager.
    public init(scanner: BleScanner) {
        self.scanner = scanner
        self.central = scanner.centralManager
        super.init()
        scanner.addCentralEventHandler(self)
    }

    /// Connect to a peripheral (already discovered via the scanner).
    /// Returns true on full setup (services + notifications enabled).
    public func connect(peripheral: CBPeripheral, timeout: TimeInterval = 10.0) async -> Bool {
        if let existing = self.peripheral, existing !== peripheral {
            disconnect()
        }
        self.peripheral = peripheral
        peripheral.delegate = self

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.connectContinuation = cont
            self.connectTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run { self.completeConnect(false) }
            }
            central.connect(peripheral, options: nil)
        }
    }

    public func disconnect() {
        if let nc = notifyChar, let p = peripheral, p.state == .connected {
            p.setNotifyValue(false, for: nc)
        }
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isConnected = false
    }

    public func setNotifyEnabled(_ enabled: Bool) {
        guard let nc = notifyChar, let p = peripheral else { return }
        p.setNotifyValue(enabled, for: nc)
    }

    /// Reconnect with backoff. Returns true on success.
    public func forceReconnect(maxRetries: Int = 5) async -> Bool {
        guard let p = peripheral else { return false }
        for attempt in 0..<maxRetries {
            central.cancelPeripheralConnection(p)
            try? await Task.sleep(nanoseconds: 100_000_000)
            let ok = await connect(peripheral: p)
            if ok { return true }
            try? await Task.sleep(nanoseconds: UInt64(300_000_000 * (attempt + 1)))
        }
        return false
    }

    /// Write raw bytes to the writable characteristic.
    /// `withoutResponse=true` uses fire-and-forget; otherwise we await the
    /// `peripheral(_:didWriteValueFor:error:)` callback.
    public func write(data: [UInt8], withoutResponse: Bool = false) async -> Bool {
        guard let p = peripheral, let wc = writeChar else { return false }
        let payload = Data(data)

        let useNoResponse = withoutResponse && useWriteNoResponse
        if useNoResponse {
            // Yield momentarily so we don't overflow the BLE TX queue.
            p.writeValue(payload, for: wc, type: .withoutResponse)
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms (matches Android's 5L delay)
            return true
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.writeContinuation = cont
            self.writeTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { self.completeWrite(false) }
            }
            p.writeValue(payload, for: wc, type: .withResponse)
        }
    }

    /// Re-scan services to find a fresh writable characteristic (mirrors the
    /// Kotlin `refreshWriteChar`). Returns true if a write characteristic
    /// was found (and adopted).
    public func refreshWriteChar() async -> Bool {
        guard let p = peripheral else { return false }
        var found: CBCharacteristic?
        var foundNoResp = false
        for service in p.services ?? [] {
            for c in service.characteristics ?? [] {
                if c.properties.contains(.writeWithoutResponse) {
                    found = c
                    foundNoResp = true
                    break
                }
                if c.properties.contains(.write), found == nil {
                    found = c
                }
            }
            if foundNoResp { break }
        }
        if let f = found {
            writeChar = f
            useWriteNoResponse = foundNoResp
            return true
        }
        return false
    }

    /// Effective per-write payload after MTU negotiation (matches Android).
    public func payloadFromMtu() -> Int {
        var p = currentMtu - 3
        if p < 20 { p = 20 }
        if p > 244 { p = 244 }
        return p
    }

    // MARK: - Internal completion helpers

    private func completeConnect(_ value: Bool) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(returning: value)
        }
    }

    private func completeWrite(_ value: Bool) {
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        if let cont = writeContinuation {
            writeContinuation = nil
            cont.resume(returning: value)
        }
    }

    fileprivate func handleConnect(_ peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    fileprivate func handleDisconnect() {
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isConnected = false
        completeConnect(false)
    }

    fileprivate func handleServicesDiscovered(_ peripheral: CBPeripheral, error: Error?) {
        guard error == nil, let services = peripheral.services else {
            completeConnect(false)
            return
        }
        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    fileprivate func handleCharacteristicsDiscovered(_ peripheral: CBPeripheral, _ service: CBService, error: Error?) {
        guard error == nil else { completeConnect(false); return }

        var nc: CBCharacteristic? = notifyChar
        var wnr: CBCharacteristic? = useWriteNoResponse ? writeChar : nil
        var wr: CBCharacteristic? = useWriteNoResponse ? nil : writeChar

        for c in service.characteristics ?? [] {
            let p = c.properties
            if (p.contains(.notify) || p.contains(.indicate)) && nc == nil { nc = c }
            if p.contains(.writeWithoutResponse) && wnr == nil { wnr = c }
            if p.contains(.write) && wr == nil { wr = c }
        }

        let wc = wnr ?? wr
        nc = nc ?? wc

        // Wait until we've covered all services
        let allServicesScanned = (peripheral.services ?? []).allSatisfy { ($0.characteristics ?? []).count > 0 }
        if !allServicesScanned { return }

        guard let writeC = wc, let notifyC = nc else {
            completeConnect(false)
            return
        }

        writeChar = writeC
        notifyChar = notifyC
        useWriteNoResponse = (wnr != nil)

        if notifyC.properties.contains(.notify) || notifyC.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: notifyC)
            // completion fires from didUpdateNotificationStateFor
        } else {
            isConnected = true
            completeConnect(true)
        }
    }

    fileprivate func handleNotificationStateChanged(_ characteristic: CBCharacteristic, error: Error?) {
        // Treat enable as "ready"
        if characteristic === notifyChar {
            isConnected = true
            completeConnect(true)
        }
    }

    fileprivate func handleNotificationValue(_ characteristic: CBCharacteristic) {
        guard characteristic === notifyChar, let value = characteristic.value else { return }
        notifications.send([UInt8](value))
    }

    fileprivate func handleWriteValueDone(error: Error?) {
        completeWrite(error == nil)
    }
}

// MARK: - Scanner-owned CBCentralManager forwarding

extension GattClient: BleCentralEventHandler {
    public func centralDidConnect(_ peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        handleConnect(peripheral)
    }

    public func centralDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        handleDisconnect()
    }

    public func centralDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        handleDisconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension GattClient: CBPeripheralDelegate {

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in self.handleServicesDiscovered(peripheral, error: error) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in self.handleCharacteristicsDiscovered(peripheral, service, error: error) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in self.handleNotificationStateChanged(characteristic, error: error) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in self.handleNotificationValue(characteristic) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in self.handleWriteValueDone(error: error) }
    }
}
