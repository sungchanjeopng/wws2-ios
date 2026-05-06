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

/// BLE device discovery. Filters for WESSWARE devices (W2/W3/ENV/CHIPSEN).
@MainActor
public final class BleScanner: NSObject, ObservableObject {

    @Published public private(set) var scannedDevices: [String: ScannedDevice] = [:]
    @Published public private(set) var isScanning: Bool = false

    /// Set of peripheral identifiers that the higher layer is currently trying
    /// to connect to (mirrors the Kotlin `connectingIds` synchronized set).
    public var connectingIds: Set<String> = []

    /// Lookup peripherals discovered so far — needed by GattClient.connect().
    public private(set) var peripheralsById: [String: CBPeripheral] = [:]

    private lazy var central: CBCentralManager = {
        CBCentralManager(delegate: self, queue: .main)
    }()

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
        Task { @MainActor in
            if central.state == .poweredOn, self.pendingStart {
                self.pendingStart = false
                self.startScan()
            } else if central.state != .poweredOn {
                self.isScanning = false
            }
        }
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
