// SwiftUI port of `viewmodel/MainViewModel.kt`.
//
// State + navigation + BLE wiring.
//
// - `MainUiState`: the @Published state surface that screens read.
// - `AppViewModel`: published-state holder + navigation + the per-device
//   BLE session lifecycle. Each connected device gets a `GattClient` whose
//   `notifications` stream is subscribed. Bytes accumulate in a per-device
//   rxBuffer; whenever a SOF/CRC-valid frame can be extracted, FrameParser
//   converts it into a `ParseResult` and the result is applied to state.
//
// Heartbeat / trend-stream / OTA upload flows wire on top of this skeleton.

import Foundation
import Combine
import SwiftUI
import CoreBluetooth
import WWS2Core
import WWS2BLE

// MARK: - UI state shape

public struct MainUiState: Equatable {
    public var tabIndex: Int = 0
    /// "pairing", "download", "upload", "calib" — or nil for a top-level tab.
    /// Optional assistant sub-pages are intentionally excluded from this port scope.
    public var subPage: String? = nil

    public var connectedDevices: [ConnectedBleDevice] = []
    public var visibleDeviceIds: Set<String> = []
    public var activeDeviceId: String = ""
    public var activeDeviceLabel: String = ""
    public var deviceReadings: [String: DeviceReading] = [:]
    public var deviceEchoReadings: [String: EchoReading] = [:]

    public var temperatureC: Double = 0.0
    public var currentMA: Double = 0.0
    public var damping: Int = 0
    public var set4mA: Double = 0.0
    public var set20mA: Double = 0.0
    public var pipeDia: Int = 0
    public var freqMHz: Double = 0.0
    public var tvg: Int = 0
    public var offset: Double = 0.0
    public var asf: Int = 0
    public var relay: Int = 0
    public var densUnit: Int = 0
    public var extIn1En: Int = 0
    public var extIn1State: Int = 0
    public var extIn2En: Int = 0
    public var extIn2State: Int = 0

    public var echoReading: EchoReading? = nil
    public var interfaceEchoReading: InterfaceEchoReading? = nil
    public var interfaceDiag: InterfaceDiagReading? = nil
    public var echoMode: EchoMode = .real
    public var rxBlink: Bool = false

    public var trendRecords: [TrendRecord] = []
    public var downloadRecords: [TrendRecord] = []
    public var trendExpectedRecords: Int = 0
    public var isTrendStreaming: Bool = false
    public var trendError: String? = nil

    // Upload
    public var pickedFileName: String? = nil
    public var pickedFileSize: Int? = nil
    public var isUploading: Bool = false
    public var uploadProgress: Double = 0.0
    public var uploadDone: Bool = false
    public var uploadElapsed: Int64 = 0
    public var firmwareTargetDeviceId: String = ""

    // Data files
    public var dataFilesStage: DataFilesStage = .list
    public var activeDataFile: DataFileItem? = nil
    public var dataDownloadProgress: Double = 0.0
    public var savedDataFiles: [DataFileItem] = []

    // Scan
    public var connectingIds: Set<String> = []

    public var deviceType: DeviceType = .density
    public var interfaceReading: InterfaceReading? = nil

    public var calibrationPoints: [CalibrationPoint] = []

    /// 0 = Celsius, 1 = Fahrenheit
    public var tempUnit: Int = 0
}

public struct BleErrorState: Equatable {
    public let message: String
    public let retryAddress: String
}

// MARK: - View model

@MainActor
public final class AppViewModel: ObservableObject {

    @Published public var state = MainUiState()
    @Published public var showPinForPairing: Bool = false
    @Published public var bleError: BleErrorState? = nil

    /// Lazily create CoreBluetooth only when the pairing flow actually needs it.
    ///
    /// Creating `CBCentralManager` during app launch can make iOS kill the app
    /// immediately if the built target is missing the Bluetooth usage string in
    /// its final Info.plist. Deferring creation keeps the app shell launchable
    /// and makes Bluetooth permission failures easier to diagnose from the
    /// Pairing screen.
    public private(set) lazy var scanner = BleScanner()

    /// Per-device BLE sessions and their support state. All accessed on
    /// MainActor since the class is @MainActor and CBCentralManager's
    /// delegate queue is set to .main inside BleScanner.
    private var gattClients: [String: GattClient] = [:]
    private var rxBuffers: [String: [UInt8]] = [:]
    private var notificationSubs: [String: AnyCancellable] = [:]
    private var pickedFirmwareBytes: [UInt8]? = nil

    /// 1Hz heartbeat task — sends the current page-index frame to the
    /// active device so it knows what data to push back. Created on
    /// first connect, cancelled on the last disconnect.
    private var heartbeatTask: Task<Void, Never>? = nil

    /// Active trend-stream parser (shared across devices since only one
    /// download flow is active at a time, matching Kotlin behaviour).
    private var trendParser: TrendStreamParser? = nil
    private let interfaceEchoParser = InterfaceEchoParser()

    private var pendingPairingContinuations: [String: CheckedContinuation<PairingResult?, Never>] = [:]
    private var pendingPairingTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var uploadTask: Task<Void, Never>? = nil
    private var uploadGeneration: UInt64 = 0
    private var pendingOtaStartAckContinuation: CheckedContinuation<Bool, Never>?
    private var pendingOtaStartAckTimeoutTask: Task<Void, Never>?
    private var pendingOtaStartAckGeneration: UInt64?

    /// Pending pairing attempt — set when the user taps a scanned device,
    /// consumed when the PIN screen completes.
    private var pendingPairingAddress: String? = nil

    public init() {}

    // MARK: Top-level navigation (matches Kotlin MainViewModel surface)

    public var isConnected: Bool {
        !state.connectedDevices.isEmpty
    }

    public var statusLabel: String {
        let count = state.connectedDevices.count
        return count > 0 ? "\(count) Connected" : "Disconnected"
    }

    public var currentTitle: String {
        switch (state.tabIndex, state.subPage) {
        case (4, "pairing"):  return "BLE Pairing"
        case (4, "calib"):    return "Calibration"
        case (4, "upload"):   return "Firmware Update"
        case (4, "download"): return "Data Files"
        case (4, _):          return "Menu"
        case (0, _):          return "Main"
        case (1, _):          return "Echo"
        case (2, _):          return "Trend"
        case (3, _):          return "Parameter"
        default:              return "WESSWARE"
        }
    }

    public func setTab(_ index: Int) {
        if state.isTrendStreaming || state.isUploading { return }
        if state.tabIndex == 4 && state.subPage == "pairing" {
            scanner.stopScan()
        }
        if index != 2 {
            trendParser?.reset()
            trendParser = nil
            state.isTrendStreaming = false
        }
        state.tabIndex = index
        state.subPage = nil
        if index == 2 { state.trendError = nil }
    }

    public func openPairing()  { state.tabIndex = 4; state.subPage = "pairing" }
    public func openCalib()    { state.tabIndex = 4; state.subPage = "calib" }
    public func openUpload()   { state.tabIndex = 4; state.subPage = "upload" }
    public func openDownload() { state.tabIndex = 4; state.subPage = "download" }

    /// Aliases used by the menu screen — keep call sites identical to the
    /// Kotlin original until we converge on a single navigation API.
    public func openDataFilesList() {
        state.tabIndex = 4
        state.subPage = "download"
        state.dataFilesStage = .list
        state.trendError = nil
        state.savedDataFiles = loadSavedDataFileItems()
    }

    public func openFirmwareFlow() {
        state.tabIndex = 4
        state.subPage = "upload"
        if state.isUploading { return }
        resetFirmwareSelection(clearTarget: true)
    }

    /// Tap a device in the strip-bar header / pairing list:
    /// - if it's an already-connected device, just promote it to active;
    /// - otherwise, treat it as a scanned address and kick off a pairing
    ///   PIN entry flow (consumed by `onPairingPinResult`).
    public func requestConnectDevice(_ deviceId: String) {
        if let connected = state.connectedDevices.first(where: { $0.id == deviceId }) {
            state.activeDeviceId = deviceId
            state.activeDeviceLabel = connected.label
            state.deviceType = connected.deviceType == 1 ? .interface_ : .density
            return
        }
        // Treat as a scan-result address: prompt PIN, then connect.
        pendingPairingAddress = deviceId
        state.connectingIds.insert(deviceId)
        showPinForPairing = true
    }

    // MARK: BLE error handling

    public func dismissBleError() { bleError = nil }
    public func retryBleError() {
        guard let err = bleError else { return }
        bleError = nil
        pendingPairingAddress = err.retryAddress
        showPinForPairing = true
    }

    // MARK: Pairing PIN

    /// PIN entry result (-1 = cancel). On accept, perform the actual
    /// CoreBluetooth connect on the peripheral that was tapped.
    public func onPairingPinResult(_ pin: Int) {
        showPinForPairing = false
        guard let addr = pendingPairingAddress else { return }
        pendingPairingAddress = nil
        if pin < 0 {
            state.connectingIds.remove(addr)
            return
        }
        Task { @MainActor in
            await self.connectScannedAddress(addr, pin: pin)
        }
    }

    private func connectScannedAddress(_ address: String, pin: Int) async {
        guard let peripheral = scanner.getRemoteDevice(address) else {
            state.connectingIds.remove(address)
            bleError = BleErrorState(message: "Device not found in scan results.",
                                     retryAddress: address)
            return
        }

        let gatt = GattClient(scanner: scanner)
        gattClients[address] = gatt

        let ok = await gatt.connect(peripheral: peripheral)
        state.connectingIds.remove(address)
        if !ok {
            gattClients[address] = nil
            bleError = BleErrorState(
                message: "Failed to connect to the BLE device.",
                retryAddress: address
            )
            return
        }

        // Subscribe to notifications before sending the device-info request so
        // the pairing response cannot race past us.
        let sub = gatt.notifications.sink { [weak self] bytes in
            Task { @MainActor in self?.handleNotification(deviceId: address, bytes: bytes) }
        }
        notificationSubs[address] = sub

        var pairingResult = await requestPairing(gatt: gatt, deviceId: address, pin: pin)
        if pairingResult == nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
            pairingResult = await requestPairing(gatt: gatt, deviceId: address, pin: pin)
        }

        var pairingDeviceInfo: DeviceInfo? = nil
        switch pairingResult {
        case .pinFailed:
            notificationSubs[address]?.cancel()
            notificationSubs[address] = nil
            gatt.disconnect()
            gattClients[address] = nil
            bleError = BleErrorState(message: "PIN code incorrect.", retryAddress: address)
            return
        case .success(let info):
            pairingDeviceInfo = info
        case nil:
            // Android falls back to BLE advertisement parsing on timeout.
            break
        }

        let scanned = scanner.scannedDevices[address]
        let usedLabels = Set(state.connectedDevices.map(\.label))
        let routed = DeviceRouting.buildConnectedDevices(
            address: address,
            scanned: scanned,
            pairingDeviceInfo: pairingDeviceInfo,
            usedLabels: usedLabels
        )

        state.connectedDevices.append(contentsOf: routed.devices)
        state.visibleDeviceIds.formUnion(routed.visibleDeviceIds)
        state.activeDeviceId = routed.activeDeviceId
        state.activeDeviceLabel = routed.activeDeviceLabel
        state.deviceType = routed.deviceType

        // Store the same physical BLE session under Android-compatible virtual
        // IDs so heartbeat/download/upload paths can address CH1/CH2 directly.
        for device in routed.devices {
            gattClients[device.id] = gatt
        }

        // Spin up the 1Hz heartbeat once we have at least one device.
        ensureHeartbeatRunning()
    }

    private func requestPairing(
        gatt: GattClient,
        deviceId: String,
        pin: Int,
        timeout: TimeInterval = 5.0
    ) async -> PairingResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PairingResult?, Never>) in
            pendingPairingContinuations[deviceId] = continuation
            pendingPairingTimeoutTasks[deviceId]?.cancel()
            pendingPairingTimeoutTasks[deviceId] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.completePendingPairing(deviceId: deviceId, result: nil)
            }

            Task { @MainActor in
                let wrote = await gatt.write(
                    data: FrameCodec.buildDeviceInfoRequest(pin: pin),
                    withoutResponse: true
                )
                if !wrote {
                    self.completePendingPairing(deviceId: deviceId, result: nil)
                }
            }
        }
    }

    private func completePendingPairing(deviceId: String, result: PairingResult?) {
        pendingPairingTimeoutTasks[deviceId]?.cancel()
        pendingPairingTimeoutTasks[deviceId] = nil
        guard let continuation = pendingPairingContinuations.removeValue(forKey: deviceId) else { return }
        continuation.resume(returning: result)
    }

    private func waitForOtaStartAck(timeout: TimeInterval, generation: UInt64) async -> Bool {
        completePendingOtaStartAck(false)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pendingOtaStartAckContinuation = continuation
            pendingOtaStartAckGeneration = generation
            pendingOtaStartAckTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.completePendingOtaStartAck(false, generation: generation)
            }
        }
    }

    private func completePendingOtaStartAck(_ value: Bool, generation: UInt64? = nil) {
        if let generation, pendingOtaStartAckGeneration != generation { return }
        pendingOtaStartAckTimeoutTask?.cancel()
        pendingOtaStartAckTimeoutTask = nil
        pendingOtaStartAckGeneration = nil
        guard let continuation = pendingOtaStartAckContinuation else { return }
        pendingOtaStartAckContinuation = nil
        continuation.resume(returning: value)
    }

    // MARK: Heartbeat

    /// Map current tab + sub-page → page index used by the heartbeat
    /// frame (matches firmware Comm_ProcBle PAGE_* constants and the
    /// CH2 offsets for interface-meter virtual devices).
    private var currentPageIndex: UInt16 {
        DeviceRouting.heartbeatPageIndex(
            tabIndex: state.tabIndex,
            subPage: state.subPage,
            activeDeviceId: state.activeDeviceId,
            deviceType: state.deviceType,
            echoMode: state.echoMode
        )
    }

    private var shouldSuppressHeartbeat: Bool {
        if state.isUploading || state.isTrendStreaming || uploadTask != nil {
            return true
        }
        if let parser = trendParser, parser.isActive {
            return true
        }
        return state.dataFilesStage == .downloading
    }

    private func ensureHeartbeatRunning() {
        if heartbeatTask != nil { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self.state.connectedDevices.isEmpty { break }
                if self.shouldSuppressHeartbeat { continue }
                guard let activeId = self.state.connectedDevices.first(where: { $0.id == self.state.activeDeviceId })?.id
                        ?? self.state.connectedDevices.first?.id,
                      let gatt = self.gattClients[activeId] else { continue }
                let frame = FrameCodec.buildHeartbeat(
                    pageIndex: Int(self.currentPageIndex),
                    expectedLen: 0
                )
                _ = await gatt.write(data: frame, withoutResponse: true)
            }
            // Loop exited — if devices reconnect, restart on next connect call.
            self?.heartbeatTask = nil
        }
    }

    // MARK: Notification handling — frame extraction + dispatch

    private func handleNotification(deviceId: String, bytes: [UInt8]) {
        // Per-device rxBuf
        var buf = rxBuffers[deviceId, default: []]
        buf.append(contentsOf: bytes)
        state.rxBlink.toggle()

        // If a trend download is in progress, the parser owns the byte
        // stream — it walks header → 24-byte records → CRC trailer and
        // calls our onRecordsParsed/onComplete callbacks.
        if let parser = trendParser, parser.isActive {
            parser.tryParse(rxBuf: &buf, downloadedCount: state.downloadRecords.count)
            rxBuffers[deviceId] = buf
            return
        }

        if interfaceEchoParser.isCollecting {
            if let echo = interfaceEchoParser.tryParseChunks(rxBuf: &buf) {
                let targetId = DeviceRouting.logicalDeviceId(
                    physicalId: deviceId,
                    cmd: interfaceEchoParser.cmd,
                    connectedDeviceIds: Set(state.connectedDevices.map(\.id))
                )
                applyInterfaceEcho(deviceId: targetId, echo: echo)
            }
            rxBuffers[deviceId] = buf
            if interfaceEchoParser.isCollecting { return }
        }

        // Greedy frame extraction: walk the buffer looking for a SOF, then
        // try every length up to buf.count − sof. parseFrame() validates
        // CRC; if it fails for the current length, advance and try again.
        var consumedAll = false
        while !consumedAll {
            consumedAll = true
            // Drop leading garbage before SOF
            if let sofIdx = buf.firstIndex(of: FrameCodec.sof) {
                if sofIdx > 0 { buf.removeFirst(sofIdx); consumedAll = false }
            } else {
                buf.removeAll(keepingCapacity: true)
                break
            }
            // Need at least 5 bytes (SOF + cmd + crc)
            guard buf.count >= 5 else { break }

            let cmd = (UInt16(buf[1]) << 8) | UInt16(buf[2])
            let connectedIds = Set(state.connectedDevices.map(\.id))
            let targetDeviceId = DeviceRouting.logicalDeviceId(
                physicalId: deviceId,
                cmd: cmd,
                connectedDeviceIds: connectedIds
            )
            let targetIsInterface = state.connectedDevices.first { $0.id == targetDeviceId }?.deviceType == 1
            if DeviceRouting.isInterfaceEchoCommand(cmd), targetIsInterface {
                guard buf.count >= 33 else { break }
                let headerPkt = Array(buf[0..<33])
                buf.removeFirst(33)
                interfaceEchoParser.beginCollection(headerPkt: headerPkt, parsedCmd: cmd)
                if let echo = interfaceEchoParser.tryParseChunks(rxBuf: &buf) {
                    applyInterfaceEcho(deviceId: targetDeviceId, echo: echo)
                    consumedAll = false
                    continue
                }
                consumedAll = false
                break
            }

            // Try increasing frame lengths until parseFrame validates CRC.
            // Cap the search to avoid pathological scans.
            var matched = false
            let maxLen = min(buf.count, 256)
            for len in 5...maxLen {
                let candidate = Array(buf[0..<len])
                if let frame = FrameCodec.parseFrame(candidate) {
                    dispatchFrame(deviceId: deviceId, frame: frame)
                    buf.removeFirst(len)
                    matched = true
                    consumedAll = false
                    break
                }
            }
            if !matched { break } // wait for more bytes
        }

        rxBuffers[deviceId] = buf
    }

    private func applyInterfaceEcho(deviceId: String, echo: InterfaceEchoReading) {
        let echoReading = echo.toEchoReading()
        state.interfaceEchoReading = echo
        state.echoReading = echoReading
        state.deviceEchoReadings[deviceId] = echoReading
        state.temperatureC = Double(echo.temperature) * 0.1
    }

    private func dispatchFrame(deviceId physicalDeviceId: String, frame: ParsedFrame) {
        if frame.cmd == Command.cmdOtaStart {
            completePendingOtaStartAck(true)
            return
        }

        if let pairing = FrameCodec.parsePairingResponse(cmd: frame.cmd, data: frame.data) {
            completePendingPairing(deviceId: physicalDeviceId, result: pairing)
            return
        }

        let deviceId = DeviceRouting.logicalDeviceId(
            physicalId: physicalDeviceId,
            cmd: frame.cmd,
            connectedDeviceIds: Set(state.connectedDevices.map(\.id))
        )

        if frame.cmd == Command.cmdCalib {
            if let points = CalibrationPoint.fromBytes(frame.data) {
                state.calibrationPoints = points
            }
            return
        }

        let isInterface = state.connectedDevices.first { $0.id == deviceId }?.deviceType == 1
        guard let result = FrameParser.parse(cmd: frame.cmd, data: frame.data, isInterface: isInterface)
        else { return }

        switch result {
        case .status4B(let reading):
            state.deviceReadings[deviceId] = reading
        case .densityStatus(let reading, let trend, let relay, let densUnit,
                            let e1En, let e1St, let e2En, let e2St):
            state.deviceReadings[deviceId] = reading
            state.temperatureC = reading.temperature
            state.currentMA = reading.currentMA
            state.damping = reading.damping
            state.set4mA = reading.set4mA
            state.set20mA = reading.set20mA
            state.pipeDia = reading.pipeDia
            state.freqMHz = reading.freqMHz
            state.relay = relay
            state.densUnit = densUnit
            state.extIn1En = e1En; state.extIn1State = e1St
            state.extIn2En = e2En; state.extIn2State = e2St
            // Append a real-time trend record tagged with this device id.
            let tagged = TrendRecord(
                dateTime: trend.dateTime,
                eeaD: trend.eeaD,
                dst: trend.dst,
                temperature: trend.temperature,
                step: trend.step, vca: trend.vca, status: trend.status,
                deviceId: deviceId
            )
            state.trendRecords.append(tagged)
        case .interfaceStatus(let reading, let temperature, let currentMA, let damping,
                              let set4, let set20, let freq, let tvg, let offset, let asf,
                              let relay, let trend):
            state.deviceReadings[deviceId] = reading
            state.temperatureC = temperature
            state.currentMA = currentMA
            state.damping = damping
            state.set4mA = set4; state.set20mA = set20
            state.freqMHz = freq; state.tvg = tvg; state.offset = offset
            state.asf = asf; state.relay = relay
            let tagged = TrendRecord(
                dateTime: trend.dateTime,
                eeaD: trend.eeaD, dst: trend.dst,
                temperature: trend.temperature,
                deviceId: deviceId
            )
            state.trendRecords.append(tagged)
        case .densityEcho(let echo, let temperature, _, let densUnit):
            state.echoReading = echo
            state.deviceEchoReadings[deviceId] = echo
            state.temperatureC = temperature
            state.densUnit = densUnit
        case .densityDiag(let diag):
            state.temperatureC = diag.temperature
            state.currentMA = diag.currentMA
            state.damping = diag.damping
            state.set4mA = diag.set4mA
            state.set20mA = diag.set20mA
            state.pipeDia = diag.pipeDia
            state.freqMHz = diag.freqMHz
        case .interfaceDiag(let diag):
            state.interfaceDiag = diag
            state.temperatureC = diag.temperature
            state.currentMA = diag.currentMA
            state.freqMHz = Double(diag.freq) * 0.001
            state.offset = diag.offset
            state.set4mA = diag.set4mA
            state.set20mA = diag.set20mA
            state.tvg = diag.tvg
            state.damping = diag.damp
            state.asf = diag.asf
            state.relay = diag.relayOn ? 1 : 0
        }
    }

    // MARK: Pairing / scan

    public func startScan() { scanner.startScan() }
    public func stopScan()  { scanner.stopScan() }

    public func toggleDeviceVisibility(_ deviceId: String) {
        if state.visibleDeviceIds.contains(deviceId) {
            if state.visibleDeviceIds.count > 1 {
                state.visibleDeviceIds.remove(deviceId)
            }
        } else {
            state.visibleDeviceIds.insert(deviceId)
        }
    }

    public func cycleDensityUnit() {
        state.densUnit = DensityUnit.fromInt(state.densUnit).next().rawValue
    }

    public func cycleTemperatureUnit() {
        state.tempUnit = TemperatureUnit.fromInt(state.tempUnit).next().rawValue
    }

    public func disconnectDevice(_ deviceId: String) {
        let physicalId = DeviceRouting.physicalDeviceId(for: deviceId)
        let relatedIds = state.connectedDevices
            .map(\.id)
            .filter { $0 == physicalId || DeviceRouting.physicalDeviceId(for: $0) == physicalId }
        let idsToRemove = Set(relatedIds + [physicalId])

        notificationSubs[physicalId]?.cancel()
        notificationSubs[physicalId] = nil
        gattClients[physicalId]?.disconnect()

        for id in idsToRemove {
            gattClients[id] = nil
            rxBuffers[id] = nil
            state.deviceReadings[id] = nil
            state.deviceEchoReadings[id] = nil
            pendingPairingTimeoutTasks[id]?.cancel()
            pendingPairingTimeoutTasks[id] = nil
            pendingPairingContinuations.removeValue(forKey: id)?.resume(returning: nil)
        }
        rxBuffers[physicalId] = nil
        interfaceEchoParser.reset()

        state.connectedDevices.removeAll { idsToRemove.contains($0.id) }
        state.visibleDeviceIds.subtract(idsToRemove)
        if idsToRemove.contains(state.activeDeviceId) {
            state.activeDeviceId = state.connectedDevices.first?.id ?? ""
            state.activeDeviceLabel = state.connectedDevices.first?.label ?? ""
            state.deviceType = state.connectedDevices.first?.deviceType == 1 ? .interface_ : .density
        }
    }

    // MARK: Firmware upload

    public var firmwareTargetLabel: String? {
        state.connectedDevices.first { $0.id == state.firmwareTargetDeviceId }?.label
    }

    public func selectFirmwareTarget(_ deviceId: String) {
        if let connected = state.connectedDevices.first(where: { $0.id == deviceId }) {
            state.activeDeviceId = connected.id
            state.activeDeviceLabel = connected.label
            state.deviceType = connected.deviceType == 1 ? .interface_ : .density
        }
        state.subPage = "upload"
        state.firmwareTargetDeviceId = deviceId
        resetFirmwareSelection(clearTarget: false)
    }

    private func resetFirmwareSelection(clearTarget: Bool) {
        if clearTarget { state.firmwareTargetDeviceId = "" }
        state.pickedFileName = nil
        state.pickedFileSize = nil
        state.isUploading = false
        state.uploadProgress = 0.0
        state.uploadDone = false
        state.uploadElapsed = 0
        pickedFirmwareBytes = nil
    }

    public func setPickedFile(name: String, size: Int, bytes: [UInt8]) {
        state.pickedFileName = name
        state.pickedFileSize = size
        state.uploadDone = false
        state.uploadProgress = 0.0
        state.uploadElapsed = 0
        pickedFirmwareBytes = bytes
    }

    /// Begin an OTA upload against the picked firmware target device.
    public func startUpload() {
        guard let bytes = pickedFirmwareBytes,
              let gatt = gattClients[state.firmwareTargetDeviceId] else { return }
        // Android parity/bootloader offset: trim the 0x8000 bootloader
        // region before passing firmware bytes into OTA payload upload.
        let uploadBytes = OtaUploader.payloadForUpload(bytes)

        state.isUploading = true
        state.uploadProgress = 0.0
        state.uploadDone = false
        let startedAt = Date()
        uploadGeneration &+= 1
        let generation = uploadGeneration
        completePendingOtaStartAck(false)
        uploadTask?.cancel()
        uploadTask = Task { @MainActor in
            let uploader = OtaUploader(gatt: gatt)
            let resultCode = await uploader.upload(
                data: uploadBytes,
                awaitStartAck: { [weak self] timeout in
                    guard let self else { return false }
                    return await self.waitForOtaStartAck(timeout: timeout, generation: generation)
                },
                onProgress: { [weak self] p in
                    Task { @MainActor in
                        self?.state.uploadProgress = p
                        self?.state.uploadElapsed = Int64(Date().timeIntervalSince(startedAt) * 1000)
                    }
                }
            )
            self.completePendingOtaStartAck(false, generation: generation)
            guard generation == self.uploadGeneration, !Task.isCancelled else { return }
            self.state.isUploading = false
            self.state.uploadDone = (resultCode == OtaResult.ok.rawValue)
            self.state.uploadProgress = 1.0
            self.uploadTask = nil
        }
    }

    public func cancelUpload() {
        uploadGeneration &+= 1
        uploadTask?.cancel()
        uploadTask = nil
        completePendingOtaStartAck(false)
        state.isUploading = false
        state.uploadProgress = 0.0
    }

    // MARK: Echo

    public func setEchoMode(_ mode: EchoMode) { state.echoMode = mode }

    // MARK: Data download

    public var deviceLabelOrDefault: String {
        if !state.activeDeviceLabel.isEmpty { return state.activeDeviceLabel }
        return state.deviceType == .interface_ ? "ENV130_A02" : "ENV230_A01"
    }

    public func activateAndDownload(_ deviceId: String) {
        requestConnectDevice(deviceId)
        state.dataFilesStage = .downloading
        state.activeDataFile = nil
        state.downloadRecords = []
        state.trendExpectedRecords = 0
        state.dataDownloadProgress = 0
        state.trendError = nil
        state.isTrendStreaming = true

        // Build a parser that funnels into download state.
        let parser = TrendStreamParser(
            onRecordsParsed: { [weak self] records in
                Task { @MainActor in
                    guard let self else { return }
                    let tagged = records.map {
                        TrendRecord(
                            dateTime: $0.dateTime,
                            eeaD: $0.eeaD, dst: $0.dst, temperature: $0.temperature,
                            step: $0.step, vca: $0.vca, status: $0.status,
                            deviceId: deviceId
                        )
                    }
                    self.state.downloadRecords.append(contentsOf: tagged)
                    let total = max(self.state.trendExpectedRecords, 1)
                    self.state.dataDownloadProgress =
                        min(Double(self.state.downloadRecords.count) / Double(total), 1.0)
                }
            },
            onHeaderParsed: { [weak self] total in
                Task { @MainActor in self?.state.trendExpectedRecords = total }
            },
            onComplete: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.state.isTrendStreaming = false
                    self.state.dataFilesStage = .complete
                    self.state.dataDownloadProgress = 1.0
                    self.persistDownloadedFile(deviceId: deviceId)
                }
            },
            onCrcFail: { _ in false },     // no auto-retry yet
            onError: { [weak self] msg in
                Task { @MainActor in
                    guard let self else { return }
                    self.state.isTrendStreaming = false
                    self.state.dataFilesStage = .error
                    self.state.trendError = msg
                }
            }
        )
        parser.startStream()
        trendParser = parser

        // Send the trend download command so the device starts streaming.
        Task { @MainActor in
            guard let gatt = self.gattClients[deviceId] else { return }
            let cmd = DeviceRouting.isCh2DeviceId(deviceId) ? Command.cmdDownloadCh2 : Command.cmdDownload
            let frame = FrameCodec.buildHeartbeat(pageIndex: Int(cmd))
            _ = await gatt.write(data: frame, withoutResponse: true)
        }
    }

    private func persistDownloadedFile(deviceId: String) {
        let useCase = ExportCsvUseCase()
        let label = state.connectedDevices.first { $0.id == deviceId }?.label ?? deviceLabelOrDefault
        let stamp = useCase.formatDateStamp(Date())
        let filename = "\(label)_\(stamp).csv"
        let isInterface = label.uppercased().contains("ENV130") || state.deviceType == .interface_
        let savedPath = useCase.saveCsvToDocuments(
            fileName: filename,
            records: state.downloadRecords,
            isInterface: isInterface
        )
        let size: Int
        if let path = savedPath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let number = attrs[.size] as? NSNumber {
            size = number.intValue
        } else {
            size = 0
        }
        let item = DataFileItem(
            name: filename,
            recordCount: state.downloadRecords.count,
            rangeLabel: rangeLabel(for: state.downloadRecords),
            sizeBytes: size,
            targetDevice: label,
            chartRecords: state.downloadRecords,
            allRecords: state.downloadRecords
        )
        state.activeDataFile = item
        state.savedDataFiles = ([item] + state.savedDataFiles.filter { $0.name != item.name }).prefix(8).map { $0 }
    }

    public func cancelDataDownload() {
        let deviceId = state.activeDeviceId
        if let gatt = gattClients[deviceId] {
            let cmd = DeviceRouting.isCh2DeviceId(deviceId)
                ? Command.cmdDownloadCancelCh2
                : Command.cmdDownloadCancel
            Task { @MainActor in
                _ = await gatt.write(data: FrameCodec.buildHeartbeat(pageIndex: Int(cmd)), withoutResponse: true)
            }
        }
        trendParser?.reset()
        trendParser = nil
        state.isTrendStreaming = false
        state.dataFilesStage = .list
    }

    public func viewDataFile(_ file: DataFileItem) {
        let loaded: DataFileItem
        if file.chartRecords.isEmpty, let content = savedCsvContent(named: file.name) {
            loaded = makeDataFile(
                name: file.name,
                size: file.sizeBytes,
                content: content,
                targetDeviceFallback: file.targetDevice
            )
        } else {
            loaded = file
        }
        state.activeDataFile = loaded
        state.dataFilesStage = .view
    }

    public func handleTopBarBack() {
        guard let subPage = state.subPage else { return }
        switch subPage {
        case "pairing":
            scanner.stopScan()
            state.subPage = nil
        case "download":
            if state.dataFilesStage != .list {
                openDataFilesList()
            } else {
                state.subPage = nil
            }
        case "upload":
            if state.isUploading { return }
            if !state.firmwareTargetDeviceId.isEmpty || state.uploadDone {
                resetFirmwareSelection(clearTarget: true)
            } else {
                state.subPage = nil
            }
        default:
            state.subPage = nil
        }
    }

    // MARK: CSV import / export

    public func importCsvFile(name: String, size: Int) {
        if let content = savedCsvContent(named: name) {
            importCsvFile(name: name, size: size, content: content)
            return
        }
        let file = DataFileItem(
            name: name,
            recordCount: 0,
            rangeLabel: "--",
            sizeBytes: size,
            targetDevice: targetDeviceName(forCsvName: name, fallback: deviceLabelOrDefault),
            chartRecords: [],
            allRecords: []
        )
        state.subPage = "download"
        state.activeDataFile = file
        state.savedDataFiles = ([file] + state.savedDataFiles.filter { $0.name != file.name }).prefix(8).map { $0 }
        state.dataFilesStage = .view
    }

    public func importCsvFile(name: String, size: Int, content: String) {
        let file = makeDataFile(
            name: name,
            size: size,
            content: content,
            targetDeviceFallback: deviceLabelOrDefault
        )
        let useCase = ExportCsvUseCase()
        _ = useCase.saveCsvText(fileName: name, content: content)
        state.tabIndex = 4
        state.subPage = "download"
        state.activeDataFile = file
        state.savedDataFiles = ([file] + state.savedDataFiles.filter { $0.name != file.name }).prefix(8).map { $0 }
        state.dataFilesStage = .view
    }

    public func getCsvContentForSave() -> (String, String)? {
        guard let file = state.activeDataFile else { return nil }
        let records = file.allRecords.isEmpty ? file.chartRecords : file.allRecords
        guard !records.isEmpty else { return nil }
        let useCase = ExportCsvUseCase()
        let csv = useCase.buildCsvContent(records: records, isInterface: isInterfaceDataFile(file))
        return (file.name, csv)
    }

    public func shareDataFile() -> URL? {
        guard let (filename, content) = getCsvContentForSave() else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WESSWARE_share")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try? content.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }

    private func loadSavedDataFileItems() -> [DataFileItem] {
        ExportCsvUseCase().loadSavedFiles().prefix(8).map { info in
            DataFileItem(
                name: info.name,
                recordCount: info.recordCount,
                rangeLabel: info.rangeLabel,
                sizeBytes: info.sizeBytes,
                targetDevice: info.targetDevice,
                chartRecords: [],
                allRecords: []
            )
        }
    }

    private func savedCsvContent(named name: String) -> String? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = documents
            .appendingPathComponent(ExportCsvUseCase.documentsSubfolder, isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func makeDataFile(
        name: String,
        size: Int,
        content: String,
        targetDeviceFallback: String
    ) -> DataFileItem {
        let targetDevice = targetDeviceName(forCsvName: name, fallback: targetDeviceFallback)
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let header = lines.first else {
            return DataFileItem(name: name, recordCount: 0, rangeLabel: "--", sizeBytes: size,
                                targetDevice: targetDevice, chartRecords: [], allRecords: [])
        }
        let isInterface = header.lowercased().contains("light")
            || header.lowercased().contains("heavy")
            || targetDevice.uppercased().contains("ENV130")
        let parser = csvDateFormatter("yyyy-MM-dd HH:mm:ss")
        let allRecords: [TrendRecord] = lines.dropFirst().compactMap { line in
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cols.count >= 4, let date = parser.date(from: cols[0]) else { return nil }
            if isInterface {
                guard let light = Double(cols[1]),
                      let heavy = Double(cols[2]),
                      let temp = Double(cols[3]) else { return nil }
                return TrendRecord(
                    dateTime: date,
                    eeaD: Int((heavy / 0.01).rounded()),
                    dst: light,
                    temperature: temp
                )
            }
            guard let eea = Int(cols[1]),
                  let density = Double(cols[2]),
                  let temp = Double(cols[3]) else { return nil }
            let step = cols.count > 4 ? (Int(cols[4]) ?? 0) : 0
            let vca = cols.count > 5 ? parseVcaRaw(cols[5]) : 0
            let status = cols.count > 6 ? (Int(cols[6]) ?? 0) : 0
            return TrendRecord(
                dateTime: date,
                eeaD: eea,
                dst: density,
                temperature: temp,
                step: step,
                vca: vca,
                status: status
            )
        }

        var seenDates = Set<Date>()
        let chartRecords = allRecords.filter { record in
            if seenDates.contains(record.dateTime) { return false }
            seenDates.insert(record.dateTime)
            return true
        }

        return DataFileItem(
            name: name,
            recordCount: allRecords.count,
            rangeLabel: rangeLabel(for: allRecords),
            sizeBytes: size,
            targetDevice: targetDevice,
            chartRecords: chartRecords,
            allRecords: allRecords
        )
    }

    private func parseVcaRaw(_ text: String) -> Int {
        if let value = Int(text) { return value }
        if let scaled = Double(text) { return Int((scaled * 100.0).rounded()) }
        return 0
    }

    private func targetDeviceName(forCsvName name: String, fallback: String) -> String {
        if let range = name.range(of: #"ENV\d+_A\d{2}"#, options: [.regularExpression, .caseInsensitive]) {
            return String(name[range]).uppercased()
        }
        let upper = name.uppercased()
        if upper.contains("ENV130") { return "ENV130" }
        if upper.contains("ENV230") { return "ENV230" }
        return fallback
    }

    private func isInterfaceDataFile(_ file: DataFileItem) -> Bool {
        let upper = "\(file.targetDevice) \(file.name)".uppercased()
        return upper.contains("ENV130") || state.deviceType == .interface_
    }

    private func rangeLabel(for records: [TrendRecord]) -> String {
        guard records.count >= 2 else { return "--" }
        let formatter = csvDateFormatter("MM/dd HH:mm:ss")
        return "\(formatter.string(from: records.first!.dateTime)) ~ \(formatter.string(from: records.last!.dateTime))"
    }

    private func csvDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
