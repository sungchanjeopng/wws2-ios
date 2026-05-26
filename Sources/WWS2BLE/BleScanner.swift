// Ported from app/src/main/java/com/wws2/densitymeter/ble/scanner/BleScanner.kt
//
// On Android the equivalent class wraps `BluetoothLeScanner`. On iOS we use
// `CBCentralManager`. The public surface is preserved as closely as possible
// (startScan / stopScan / scannedDevices / isScanning / signalLevel) but the
// underlying mechanics — power-state, delegate callbacks, peripheral retrieval —
// follow CoreBluetooth conventions.

import Foundation
import Combine
import CoreBluetooth
import WWS2Core

#if canImport(os)
import os
#endif

/// Receives connect/disconnect events from the scanner-owned CBCentralManager.
/// CoreBluetooth supports only one central delegate, so GattClient instances
/// register here instead of trying to become CBCentralManagerDelegate too.
@MainActor
public protocol BleCentralEventHandler: AnyObject {
    func centralDidConnect(_ peripheral: CBPeripheral)
    func centralDidDisconnect(_ peripheral: CBPeripheral, error: Error?)
    func centralDidFailToConnect(_ peripheral: CBPeripheral, error: Error?)
}

private final class WeakBleCentralEventHandler {
    weak var value: BleCentralEventHandler?
    init(_ value: BleCentralEventHandler) { self.value = value }
}

/// BLE device discovery. Filters for WESSWARE devices (W2/W3/ENV/CHIPSEN).
@MainActor
public final class BleScanner: NSObject, ObservableObject {

    @Published public private(set) var scannedDevices: [String: ScannedDevice] = [:]
    @Published public private(set) var isScanning: Bool = false
    /// 현재 CoreBluetooth 상태 — UI에서 권한/전원 안내를 띄우기 위해 노출
    @Published public private(set) var managerState: CBManagerState = .unknown

    /// Set of peripheral identifiers that the higher layer is currently trying
    /// to connect to (mirrors the Kotlin `connectingIds` synchronized set).
    public var connectingIds: Set<String> = []

    /// Lookup peripherals discovered so far — needed by GattClient.connect().
    public private(set) var peripheralsById: [String: CBPeripheral] = [:]

    private lazy var central: CBCentralManager = {
        CBCentralManager(delegate: self, queue: .main)
    }()

    private var centralEventHandlers: [ObjectIdentifier: WeakBleCentralEventHandler] = [:]
    private var pendingStart = false

    public override init() {
        super.init()
        _ = central   // force init so `centralManagerDidUpdateState` fires
    }

    public func startScan() {
        if isScanning { return }
        guard central.state == .poweredOn else {
            pendingStart = true
            return
        }
        scannedDevices.removeAll()
        peripheralsById.removeAll()
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    public func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
    }

    public func getRemoteDevice(_ identifier: String) -> CBPeripheral? {
        peripheralsById[identifier]
    }

    public func addCentralEventHandler(_ handler: BleCentralEventHandler) {
        reapCentralEventHandlers()
        centralEventHandlers[ObjectIdentifier(handler)] = WeakBleCentralEventHandler(handler)
    }

    public func removeCentralEventHandler(_ handler: BleCentralEventHandler) {
        centralEventHandlers.removeValue(forKey: ObjectIdentifier(handler))
    }

    private func reapCentralEventHandlers() {
        centralEventHandlers = centralEventHandlers.filter { $0.value.value != nil }
    }

    private func notifyCentralDidConnect(_ peripheral: CBPeripheral) {
        reapCentralEventHandlers()
        for box in centralEventHandlers.values {
            box.value?.centralDidConnect(peripheral)
        }
    }

    private func notifyCentralDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        reapCentralEventHandlers()
        for box in centralEventHandlers.values {
            box.value?.centralDidDisconnect(peripheral, error: error)
        }
    }

    private func notifyCentralDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        reapCentralEventHandlers()
        for box in centralEventHandlers.values {
            box.value?.centralDidFailToConnect(peripheral, error: error)
        }
    }

    /// 1=weak, 2=ok, 3=strong (matches Android's signalLevel mapping).
    public nonisolated func signalLevel(rssi: Int) -> Int {
        if rssi >= -55 { return 3 }
        if rssi >= -72 { return 2 }
        return 1
    }

    public func dispose() {
        stopScan()
    }

    /// Underlying central — exposed so `GattClient` can call `connect/disconnect`.
    public var centralManager: CBCentralManager { central }
}

extension BleScanner: CBCentralManagerDelegate {

    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = central.state
        Task { @MainActor in
            self.managerState = newState
            if newState == .poweredOn, self.pendingStart {
                self.pendingStart = false
                self.startScan()
            } else if newState != .poweredOn {
                self.isScanning = false
            }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in self.notifyCentralDidConnect(peripheral) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in self.notifyCentralDidDisconnect(peripheral, error: error) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in self.notifyCentralDidFailToConnect(peripheral, error: error) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advName: String? = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name

        guard let raw = advName, !raw.isEmpty else { return }
        let lower = raw.lowercased()

        let matches = lower.hasPrefix("w3")
            || lower.hasPrefix("w2")
            || lower.contains("we13")
            || lower.contains("we23")
            || lower.contains("env")
            || lower.contains("chipsen")
        guard matches else { return }

        let isInterface = lower.hasPrefix("w3")
            || lower.contains("we13")
            || lower.contains("env130")
        let productName = isInterface ? "ENV130" : "ENV230"

        let stripped: String = {
            if lower.hasPrefix("w3") || lower.hasPrefix("w2") {
                return String(raw.dropFirst(2))
            }
            return ""
        }()

        var ch1 = ""
        var ch2 = ""
        if stripped.count >= 6 {
            ch1 = String(stripped.prefix(3))
            ch2 = String(stripped.dropFirst(3).prefix(3))
        } else if stripped.count >= 3 {
            ch1 = String(stripped.prefix(3))
        }

        let displayName: String = {
            if !ch1.isEmpty {
                if !ch2.isEmpty { return "\(productName)  \(ch1) / \(ch2)" }
                return "\(productName)_\(ch1)"
            }
            return productName
        }()

        let address = peripheral.identifier.uuidString
        let scanned = ScannedDevice(
            address: address,
            name: displayName,
            rawName: raw,
            rssi: RSSI.intValue,
            ch1SiteName: ch1,
            ch2SiteName: ch2
        )

        Task { @MainActor in
            self.peripheralsById[address] = peripheral
            self.scannedDevices[address] = scanned
        }
    }
}
