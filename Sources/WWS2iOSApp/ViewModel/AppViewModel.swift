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
    /// "pairing", "download", "upload", "chatbot", "calib" — or nil for a top-level tab.
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

    public let scanner = BleScanner()

    /// Per-device BLE sessions and their support state. All accessed on
    /// MainActor since the class is @MainActor and CBCentralManager's
    /// delegate queue is set to .main inside BleScanner.
    private var gattClients: [String: GattClient] = [:]
    private var rxBuffers: [String: [UInt8]] = [:]
    private var notificationSubs: [String: AnyCancellable] = [:]
    private var pickedFirmwareBytes: [UInt8]? = nil

    /// Pending pairing attempt — set when the user taps a scanned device,
    /// consumed when the PIN screen completes.
    private var pendingPairingAddress: String? = nil

    public init() {}

    // MARK: Top-level navigation (matches Kotlin MainViewModel surface)

    public var isConnected: Bool {
        !state.connectedDevices.isEmpty
    }

    public var statusLabel: String {
        isConnected ? state.activeDeviceLabel.isEmpty
            ? "Connected" : state.activeDeviceLabel
            : "Disconnected"
    }

    public var currentTitle: String {
        switch (state.tabIndex, state.subPage) {
        case (4, "pairing"):  return "Pairing"
        case (4, "calib"):    return "Calibration"
        case (4, "upload"):   return "Firmware Upload"
        case (4, "chatbot"):  return "AI Chatbot"
        case (4, "download"): return "Data Files"
        case (4, _):          return "Menu"
        case (0, _):          return "Main"
        case (1, _):          return "Echo"
        case (2, _):          return "Trend"
        case (3, _):          return "Diagnostics"
        default:              return "WESSWARE"
        }
    }

    public func setTab(_ index: Int) {
        if state.isTrendStreaming { return }
        if state.tabIndex == 4 && state.subPage == "pairing" {
            scanner.stopScan()
        }
        state.tabIndex = index
        state.subPage = nil
    }

    public func openPairing()  { state.tabIndex = 4; state.subPage = "pairing" }
    public func openCalib()    { state.tabIndex = 4; state.subPage = "calib" }
    public func openUpload()   { state.tabIndex = 4; state.subPage = "upload" }
    public func openChatbot()  { state.tabIndex = 4; state.subPage = "chatbot" }
    public func openDownload() { state.tabIndex = 4; state.subPage = "download" }

    /// Aliases used by the menu screen — keep call sites identical to the
    /// Kotlin original until we converge on a single navigation API.
    public func openDataFilesList() { openDownload() }
    public func openFirmwareFlow()  { openUpload() }

    /// Tap a device in the strip-bar header / pairing list:
    /// - if it's an already-connected device, just promote it to active;
    /// - otherwise, treat it as a scanned address and kick off a pairing
    ///   PIN entry flow (consumed by `onPairingPinResult`).
    public func requestConnectDevice(_ deviceId: String) {
        if state.connectedDevices.contains(where: { $0.id == deviceId }) {
            state.activeDeviceId = deviceId
            state.activeDeviceLabel = state.connectedDevices.first { $0.id == deviceId }?.label ?? ""
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

        // Subscribe to notifications and keep the cancellable alive on self.
        let sub = gatt.notifications.sink { [weak self] bytes in
            Task { @MainActor in self?.handleNotification(deviceId: address, bytes: bytes) }
        }
        notificationSubs[address] = sub

        // Send the device-info pairing request as the first frame so the
        // device knows we're authenticated.
        _ = await gatt.write(data: FrameCodec.buildDeviceInfoRequest(pin: pin),
                             withoutResponse: false)

        // Decide density vs interface from the BLE name (matches Kotlin
        // DeviceRepository.isInterfaceMeter).
        let scanned = scanner.scannedDevices[address]
        let isInterface = DeviceRepository.isInterfaceMeter(name: scanned?.rawName ?? "")
        let label: String = scanned?.name ?? (isInterface ? "ENV130" : "ENV230")

        let connected = ConnectedBleDevice(
            id: address,
            label: label,
            firmwareVersion: "",
            deviceType: isInterface ? 1 : 0
        )
        state.connectedDevices.append(connected)
        state.activeDeviceId = address
        state.activeDeviceLabel = label
        state.deviceType = isInterface ? .interface_ : .density
    }

    // MARK: Notification handling — frame extraction + dispatch

    private func handleNotification(deviceId: String, bytes: [UInt8]) {
        // Per-device rxBuf
        var buf = rxBuffers[deviceId, default: []]
        buf.append(contentsOf: bytes)
        state.rxBlink.toggle()

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

    private func dispatchFrame(deviceId: String, frame: ParsedFrame) {
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

    public func disconnectDevice(_ deviceId: String) {
        notificationSubs[deviceId]?.cancel()
        notificationSubs[deviceId] = nil
        gattClients[deviceId]?.disconnect()
        gattClients[deviceId] = nil
        rxBuffers[deviceId] = nil
        state.connectedDevices.removeAll { $0.id == deviceId }
        state.deviceReadings[deviceId] = nil
        state.deviceEchoReadings[deviceId] = nil
        if state.activeDeviceId == deviceId {
            state.activeDeviceId = state.connectedDevices.first?.id ?? ""
            state.activeDeviceLabel = state.connectedDevices.first?.label ?? ""
        }
    }

    // MARK: Firmware upload

    public var firmwareTargetLabel: String? {
        state.connectedDevices.first { $0.id == state.firmwareTargetDeviceId }?.label
    }

    public func selectFirmwareTarget(_ deviceId: String) {
        state.firmwareTargetDeviceId = deviceId
    }

    public func setPickedFile(name: String, size: Int, bytes: [UInt8]) {
        state.pickedFileName = name
        state.pickedFileSize = size
        pickedFirmwareBytes = bytes
    }

    /// Begin an OTA upload against the picked firmware target device.
    public func startUpload() {
        guard let bytes = pickedFirmwareBytes,
              let gatt = gattClients[state.firmwareTargetDeviceId] else { return }
        state.isUploading = true
        state.uploadProgress = 0.0
        state.uploadDone = false
        let startedAt = Date()
        Task { @MainActor in
            let uploader = OtaUploader(gatt: gatt)
            let resultCode = await uploader.upload(
                data: bytes,
                awaitStartAck: { _ in true },          // ACK is implicit on iOS path
                onProgress: { [weak self] p in
                    Task { @MainActor in
                        self?.state.uploadProgress = p
                        self?.state.uploadElapsed = Int64(Date().timeIntervalSince(startedAt) * 1000)
                    }
                }
            )
            self.state.isUploading = false
            self.state.uploadDone = (resultCode == OtaResult.ok.rawValue)
            self.state.uploadProgress = 1.0
        }
    }

    public func cancelUpload() {
        // OtaUploader.upload is a single async function — a true cancel
        // requires a Task handle. Mark UI state for now; full cooperative
        // cancellation lands in a follow-up.
        state.isUploading = false
        state.uploadProgress = 0.0
    }

    // MARK: Echo

    public func setEchoMode(_ mode: EchoMode) { state.echoMode = mode }

    // MARK: Data download

    public var deviceLabelOrDefault: String {
        if !state.activeDeviceLabel.isEmpty { return state.activeDeviceLabel }
        return "--"
    }

    public func activateAndDownload(_ deviceId: String) {
        requestConnectDevice(deviceId)
        state.dataFilesStage = .downloading
        // TODO: drive TrendStreamParser via GattClient notifications.
    }

    public func cancelDataDownload() { state.dataFilesStage = .list }

    public func viewDataFile(_ file: DataFileItem) {
        state.activeDataFile = file
        state.dataFilesStage = .view
    }

    public func handleTopBarBack() {
        if state.subPage != nil { state.subPage = nil }
    }

    // MARK: CSV picker stubs (file picker UI is platform-specific; landed later)

    public func importCsvFile(name: String, size: Int) { /* TODO */ }

    public func getCsvContentForSave() -> (String, String)? {
        // Build a CSV from the current trend records of the active device.
        let active = state.activeDeviceId
        let records = state.trendRecords.filter { $0.deviceId == active }
        guard !records.isEmpty else { return nil }
        let useCase = ExportCsvUseCase()
        let isInterface = state.deviceType == .interface_
        let csv = useCase.buildCsvContent(records: records, isInterface: isInterface)
        let stamp = useCase.formatDateStamp(records.first?.dateTime ?? Date())
        let label = state.activeDeviceLabel.isEmpty ? "WESSWARE" : state.activeDeviceLabel
        return ("\(label)_\(stamp).csv", csv)
    }

    public func shareDataFile() -> URL? {
        guard let (filename, content) = getCsvContentForSave() else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WESSWARE_share")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try? content.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }
}
