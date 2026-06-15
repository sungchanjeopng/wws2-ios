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
import UIKit
import PDFKit
import WebKit
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
    public var emptyDistance: Double = 0.0
    public var deadZone: Double = 0.0
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
    /// 링크가 끊겨 자동 재연결 중인 기기들. connectedDevices에는 그대로 남아 있고(목록에서
    /// 안 빠짐) UI는 "Reconnecting…"으로 표시한다. 사용자가 수동(✕) 해제 전까지 무한 재시도.
    public var reconnectingIds: Set<String> = []

    // Report (ENV130) — 기기 선택 → BLE 수집 → 리포트 표시
    public var reportStage: ReportStage = .select
    public var reportTargetId: String = ""
    public var reportData: ReportData? = nil
    public var reportError: String? = nil

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
    /// Transient user-visible message (snackbar). Mirrors Kotlin
    /// MainViewModel._snackbarMessage. Set to nil after the UI consumes it.
    @Published public var snackbarMessage: String? = nil

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

    /// Per-device `isConnected` subscriptions. CoreBluetooth fires
    /// `didDisconnectPeripheral` on out-of-range / power loss; this maps that
    /// into removing the device from the UI list (Android does this via its
    /// connectionState collector).
    private var connectionSubs: [String: AnyCancellable] = [:]

    /// Heartbeat 응답 워치독: 연속으로 응답(RX)이 없는 워치독 대상 heartbeat 수.
    /// RX가 오면 0으로 리셋된다. supervision timeout(최대 ~20초)보다 빠르게 끊김 감지.
    private var missedHeartbeats = 0
    // Timestamp of last response notification — used by sendAppSetting to wait
    // for an idle window before writing a setting frame.
    private var lastHeartbeatAckAt: Date = .distantPast
    private let maxMissedHeartbeats = 5
    /// 펌웨어가 매 heartbeat마다 확실히 응답하는 page만 워치독 대상으로 삼는다.
    /// Status(Main/Diag/Trend): 0x00/0x10, Echo(CH1/CH2·AVG): 0x01/0x05/0x11/0x15.
    /// Calib/Pairing/Menu/Chatbot 등 무응답·미통신 화면은 제외 → 오탐 방지.
    private let watchdogPages: Set<UInt16> = [0x00, 0x10, 0x01, 0x05, 0x11, 0x15]

    /// 물리주소별 자동 재연결 루프 Task. 3초 고정 간격으로 무한 재시도.
    private var reconnectJobs: [String: Task<Void, Never>] = [:]
    private let reconnectIntervalNs: UInt64 = 3_000_000_000

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
    private var interfaceEchoCollectionDeviceId: String? = nil
    private var interfaceEchoCollectionLastProgressAt: Date? = nil
    // Keep this longer than one heartbeat period. On iOS, CoreBluetooth can deliver
    // the 203B header + waveform burst over several callbacks while SwiftUI is drawing.
    private let interfaceEchoCollectionTimeout: TimeInterval = 5.0

    /// Pending pairing attempt — set when the user taps a scanned device,
    /// consumed when the PIN screen completes.
    private var pendingPairingAddress: String? = nil

    public init() {}

    // MARK: Top-level navigation (matches Kotlin MainViewModel surface)

    public var isConnected: Bool {
        !state.connectedDevices.isEmpty
    }

    /// 재연결 중인 기기가 하나라도 있으면 true → TopBar 알약을 주황+깜빡임으로 표시.
    public var isReconnecting: Bool {
        state.connectedDevices.contains { state.reconnectingIds.contains($0.id) }
    }

    public var statusLabel: String {
        let reconnecting = state.connectedDevices.filter { state.reconnectingIds.contains($0.id) }.count
        let live = state.connectedDevices.count - reconnecting
        if reconnecting > 0 && live > 0 { return "\(reconnecting) Reconnecting · \(live) Connected" }
        if reconnecting > 0 { return "\(reconnecting) Reconnecting" }
        if live > 0 { return "\(live) Connected" }
        return "Disconnected"
    }

    public var currentTitle: String {
        switch (state.tabIndex, state.subPage) {
        case (4, "pairing"):  return "BLE Pairing"
        case (4, "calib"):    return "Calibration"
        case (4, "upload"):   return "Firmware Update"
        case (4, "download"): return "Data Files"
        case (4, "report"):   return "Report"
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
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        if index != 2 {
            trendParser?.reset()
            trendParser = nil
            state.isTrendStreaming = false
        }
        state.tabIndex = index
        state.subPage = nil
        if index == 2 { state.trendError = nil }
    }

    public func openPairing()  {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        state.tabIndex = 4
        state.subPage = "pairing"
    }
    public func openCalib()    {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        state.tabIndex = 4
        state.subPage = "calib"
    }
    public func openReport()   {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        state.tabIndex = 4
        state.subPage = "report"
        state.reportStage = .select
        state.reportTargetId = ""
        state.reportData = nil
        state.reportError = nil
    }
    public func backToReportSelect() {
        state.reportStage = .select
        state.reportTargetId = ""
        state.reportData = nil
        state.reportError = nil
    }
    public func openUpload()   {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        state.tabIndex = 4
        state.subPage = "upload"
    }
    public func openDownload() {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        state.tabIndex = 4
        state.subPage = "download"
    }

    /// Aliases used by the menu screen — keep call sites identical to the
    /// Kotlin original until we converge on a single navigation API.
    public func openDataFilesList() {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
        state.tabIndex = 4
        state.subPage = "download"
        state.dataFilesStage = .list
        state.trendError = nil
        state.savedDataFiles = loadSavedDataFileItems()
    }

    public func openFirmwareFlow() {
        stopScanIfPairingActive()
        resetInterfaceEchoStreamState(clearAllBuffers: true)
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
            resetInterfaceEchoStreamState(clearAllBuffers: true)
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

        // OS 레벨 끊김(거리 멀어짐·전원 등) 시 자동 재연결을 시작한다.
        // (초기값 true 는 dropFirst 로 무시)
        let connSub = gatt.$isConnected
            .dropFirst()
            .sink { [weak self] connected in
                guard let self, !connected else { return }
                Task { @MainActor in self.beginReconnect(address) }
            }
        connectionSubs[address] = connSub

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
        // Data Files uses CMD 0x0007 / 0x0017 only as an explicit download-start
        // request. Do not send it as a 1 Hz page heartbeat while the user is just
        // looking at the Data Files list, viewing a saved CSV, or after completion.
        if state.tabIndex == 4 && state.subPage == "download" {
            return true
        }
        // 리포트 화면에선 자체 수집 시퀀스가 명령을 직접 보내므로 자동 heartbeat 정지.
        if state.tabIndex == 4 && state.subPage == "report" {
            return true
        }
        return false
    }

    private func stopScanIfPairingActive() {
        if state.tabIndex == 4 && state.subPage == "pairing" {
            scanner.stopScan()
        }
    }

    private func clearRxBuffers(deviceId: String? = nil, clearAll: Bool = false) {
        if clearAll {
            for key in Array(rxBuffers.keys) {
                rxBuffers[key]?.removeAll(keepingCapacity: true)
            }
            return
        }

        guard let deviceId else { return }
        let physicalId = DeviceRouting.physicalDeviceId(for: deviceId)
        let relatedIds = state.connectedDevices
            .map(\.id)
            .filter { $0 == physicalId || DeviceRouting.physicalDeviceId(for: $0) == physicalId }
        for id in Set(relatedIds + [deviceId, physicalId]) {
            rxBuffers[id]?.removeAll(keepingCapacity: true)
        }
    }

    private func resetInterfaceEchoStreamState(deviceId: String? = nil, clearAllBuffers: Bool = false) {
        interfaceEchoParser.reset()
        interfaceEchoCollectionDeviceId = nil
        interfaceEchoCollectionLastProgressAt = nil
        clearRxBuffers(deviceId: deviceId, clearAll: clearAllBuffers)
    }

    private func ensureHeartbeatRunning() {
        if heartbeatTask != nil { return }
        missedHeartbeats = 0  // 새 heartbeat 세션 기준으로 워치독 초기화
        heartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self.state.connectedDevices.isEmpty { break }
                if self.shouldSuppressHeartbeat { continue }
                guard let activeId = self.state.connectedDevices.first(where: { $0.id == self.state.activeDeviceId })?.id
                        ?? self.state.connectedDevices.first?.id,
                      let gatt = self.gattClients[activeId] else { continue }
                let page = self.currentPageIndex
                let frame = FrameCodec.buildHeartbeat(
                    pageIndex: Int(page),
                    expectedLen: 0
                )
                _ = await gatt.write(data: frame, withoutResponse: true)
                // 응답 워치독: 펌웨어가 매초 응답하는 page를 보냈는데도 RX가
                // maxMissedHeartbeats회 연속 없으면(=거리 멀어져 링크 끊김) 재연결을 시작한다.
                if self.watchdogPages.contains(page) {
                    self.missedHeartbeats += 1
                    if self.missedHeartbeats >= self.maxMissedHeartbeats {
                        self.missedHeartbeats = 0
                        self.beginReconnect(activeId)
                    }
                }
            }
            // Loop exited — if devices reconnect, restart on next connect call.
            self?.heartbeatTask = nil
        }
    }

    // MARK: Notification handling — frame extraction + dispatch

    private func handleNotification(deviceId: String, bytes: [UInt8]) {
        // 어떤 데이터든 수신되면 장비가 살아있다는 뜻 → 워치독 카운터 리셋
        if !bytes.isEmpty {
            missedHeartbeats = 0
            lastHeartbeatAckAt = Date()
        }
        // Per-device rxBuf
        var buf = rxBuffers[deviceId, default: []]
        buf.append(contentsOf: bytes)
        let maxBufferedBytes = (trendParser?.isActive == true) ? 120_000 : 8_000
        if buf.count > maxBufferedBytes {
            buf.removeFirst(buf.count - maxBufferedBytes / 2)
        }
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
            guard interfaceEchoCollectionDeviceId == nil || interfaceEchoCollectionDeviceId == deviceId else {
                // Android only drains notifications for the currently active link
                // during interface-echo collection. Buffer other devices, but do
                // not let them corrupt the shared waveform parser mid-capture.
                rxBuffers[deviceId] = buf
                return
            }

            if let lastProgressAt = interfaceEchoCollectionLastProgressAt,
               Date().timeIntervalSince(lastProgressAt) > interfaceEchoCollectionTimeout {
                // Timeout on idle progress, not on total collection age. A valid
                // waveform can span many callbacks while still moving forward.
                resetInterfaceEchoStreamState(deviceId: deviceId)
                buf.removeAll(keepingCapacity: true)
            } else {
                let initialCount = buf.count
                if let echo = interfaceEchoParser.tryParseChunks(rxBuf: &buf) {
                    let targetId = DeviceRouting.logicalDeviceId(
                        physicalId: deviceId,
                        cmd: interfaceEchoParser.cmd,
                        connectedDeviceIds: Set(state.connectedDevices.map(\.id))
                    )
                    applyInterfaceEcho(deviceId: targetId, echo: echo)
                }
                if buf.count != initialCount || !interfaceEchoParser.isCollecting {
                    interfaceEchoCollectionLastProgressAt = Date()
                }
                rxBuffers[deviceId] = buf
                if interfaceEchoParser.isCollecting { return }
                interfaceEchoCollectionDeviceId = nil
                interfaceEchoCollectionLastProgressAt = nil
            }
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
                let headerPacketSize = InterfaceEchoParser.headerPacketSize
                guard buf.count >= headerPacketSize else { break }
                let headerPkt = Array(buf[0..<headerPacketSize])
                buf.removeFirst(headerPacketSize)
                interfaceEchoParser.beginCollection(headerPkt: headerPkt, parsedCmd: cmd)
                interfaceEchoCollectionDeviceId = deviceId
                interfaceEchoCollectionLastProgressAt = Date()
                let initialCount = buf.count
                if let echo = interfaceEchoParser.tryParseChunks(rxBuf: &buf) {
                    applyInterfaceEcho(deviceId: targetDeviceId, echo: echo)
                    interfaceEchoCollectionDeviceId = nil
                    interfaceEchoCollectionLastProgressAt = nil
                    consumedAll = false
                    continue
                }
                if buf.count != initialCount {
                    interfaceEchoCollectionLastProgressAt = Date()
                }
                if !interfaceEchoParser.isCollecting {
                    interfaceEchoCollectionDeviceId = nil
                    interfaceEchoCollectionLastProgressAt = nil
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
            if !matched {
                // Android reference does not wait forever on a CRC-invalid SOF.
                // If we have already scanned beyond the largest normal frame size
                // (status/diag/density echo are all < 256B; interface echo header is
                // handled above), the leading SOF is stale waveform/noise. Drop one
                // byte and continue searching so a later real 203B echo header can recover.
                if buf.count >= 256 {
                    buf.removeFirst()
                    consumedAll = false
                    continue
                }
                break // wait for more bytes
            }
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
                              let relay, let emptyDistance, let deadZone, let trend):
            state.deviceReadings[deviceId] = reading
            state.temperatureC = temperature
            state.currentMA = currentMA
            state.damping = damping
            state.set4mA = set4; state.set20mA = set20
            state.freqMHz = freq; state.tvg = tvg; state.offset = offset
            state.asf = asf; state.relay = relay
            // Mirror Kotlin MainViewModel.kt:870-871 — only overwrite when
            // the firmware actually sent the extended payload; otherwise
            // preserve the previously-known value.
            if let emptyDistance { state.emptyDistance = emptyDistance }
            if let deadZone      { state.deadZone      = deadZone      }
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

    /// Mirror Kotlin `appSettingCmd` (MainViewModel.kt:294-296). The active
    /// device's `_CH2` suffix shifts the command base by +1000 so the peer
    /// firmware routes the write to the second logical channel.
    private func appSettingCmd(baseCmd: Int) -> Int {
        return state.activeDeviceId.hasSuffix("_CH2") ? baseCmd + 1000 : baseCmd
    }

    /// Ported from MainViewModel.kt:298-309. Sends an app-setting write
    /// frame (SOF=0x03) to the currently active device. Returns immediately;
    /// the result is surfaced through `snackbarMessage`.
    /// Sends a setting frame and returns true only after the matching state
    /// field changes within 10s — proves the firmware actually applied it.
    /// Waits for a heartbeat-response idle window first (avoids racing an
    /// in-flight waveform reply).
    @discardableResult
    public func sendAppSetting(baseCmd: Int, value: Int) async -> Bool {
        let activeId = state.activeDeviceId
        guard !activeId.isEmpty else { return false }
        let physicalId = DeviceRouting.physicalDeviceId(for: activeId)
        guard let gatt = gattClients[physicalId] else { return false }

        // Snapshot the relevant field BEFORE writing.
        let before = readSettingFieldKey(baseCmd)

        // Wait for the next heartbeat ack (1.5s timeout) to land in idle window.
        let waitStart = lastHeartbeatAckAt
        let waitDeadline = Date().addingTimeInterval(1.5)
        while Date() < waitDeadline {
            if lastHeartbeatAckAt > waitStart { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Idle margin: firmware finishes its post-response bookkeeping.
        try? await Task.sleep(nanoseconds: 150_000_000)

        let cmd = appSettingCmd(baseCmd: baseCmd)
        let frame = FrameCodec.buildSettingFrame(cmd: cmd, data: value)
        let sent = await gatt.write(data: frame, withoutResponse: false)
        if !sent { return false }

        // Poll the same field for up to 10s — change == success.
        let pollDeadline = Date().addingTimeInterval(10.0)
        while Date() < pollDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if readSettingFieldKey(baseCmd) != before { return true }
        }
        return false
    }

    private func readSettingFieldKey(_ baseCmd: Int) -> String {
        let ifReading = state.interfaceEchoReading
        switch baseCmd {
        case 1:    return "1:\(ifReading?.echoAmp ?? -1)"
        case 2, 4: return "24:\(ifReading?.thrLightSet ?? -1)"
        case 3, 5: return "35:\(ifReading?.thrHeavySet ?? -1)"
        case 6:    return "6:\(state.freqMHz)"
        case 7:    return "7:\(state.offset)"
        case 8:    return "8:\(state.set4mA)"
        case 9:    return "9:\(state.set20mA)"
        case 11:   return "11:\(state.damping)"
        // Echo 탭은 Status가 아닌 파형만 폴링하므로 파형 헤더 값도 함께 감시
        case 12:   return "12:\(ifReading?.empty ?? -1):\(state.emptyDistance)"
        case 13:   return "13:\(ifReading?.deadzone ?? -1):\(state.deadZone)"
        default:   return "unknown"
        }
    }

    /// Reconnect is disabled — when the BLE link drops we tear down the device
    /// entry immediately and surface a "Signal too weak" dialog so the user
    /// can manually re-pair via the BleErrorDialog.
    private func beginReconnect(_ deviceId: String) {
        let address = DeviceRouting.physicalDeviceId(for: deviceId)
        let ids = state.connectedDevices.map(\.id).filter { DeviceRouting.physicalDeviceId(for: $0) == address }
        if ids.isEmpty { return }
        bleError = BleErrorState(message: "Signal too weak. Connection closed.", retryAddress: address)
        if let firstId = ids.first {
            disconnectDevice(firstId)
        }
    }

    /// 재연결 1회 시도: BLE 링크만 다시 연결하고(페어링 생략) 기존 기기 id에 새 세션을 매핑한다.
    private func attemptReconnect(_ address: String) async -> Bool {
        guard let peripheral = scanner.getRemoteDevice(address) else { return false }
        let gatt = GattClient(scanner: scanner)
        let ok = await gatt.connect(peripheral: peripheral)
        if !ok { gatt.disconnect(); return false }

        // 도중에 수동 해제됐을 수 있으니 현재 목록 기준으로 다시 계산
        let ids = state.connectedDevices.map(\.id).filter { DeviceRouting.physicalDeviceId(for: $0) == address }
        if ids.isEmpty { gatt.disconnect(); return false }

        let sub = gatt.notifications.sink { [weak self] bytes in
            Task { @MainActor in self?.handleNotification(deviceId: address, bytes: bytes) }
        }
        notificationSubs[address] = sub
        let connSub = gatt.$isConnected
            .dropFirst()
            .sink { [weak self] connected in
                guard let self, !connected else { return }
                Task { @MainActor in self.beginReconnect(address) }
            }
        connectionSubs[address] = connSub

        gattClients[address] = gatt
        for id in ids { gattClients[id] = gatt }
        state.reconnectingIds.subtract(ids)
        ensureHeartbeatRunning()
        return true
    }

    public func disconnectDevice(_ deviceId: String) {
        let physicalId = DeviceRouting.physicalDeviceId(for: deviceId)
        let relatedIds = state.connectedDevices
            .map(\.id)
            .filter { $0 == physicalId || DeviceRouting.physicalDeviceId(for: $0) == physicalId }
        let idsToRemove = Set(relatedIds + [physicalId])

        // 수동 해제 시 진행 중인 재연결 루프도 취소하고 재연결 표시도 정리
        reconnectJobs[physicalId]?.cancel()
        reconnectJobs[physicalId] = nil
        state.reconnectingIds.subtract(idsToRemove)

        notificationSubs[physicalId]?.cancel()
        notificationSubs[physicalId] = nil
        // 구독을 먼저 해제해야 아래 disconnect() → didDisconnect 콜백이 다시
        // disconnectDevice 를 부르는 재진입을 막는다.
        connectionSubs[physicalId]?.cancel()
        connectionSubs[physicalId] = nil
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
        resetInterfaceEchoStreamState(deviceId: physicalId)

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

    public func setEchoMode(_ mode: EchoMode) {
        guard state.echoMode != mode else { return }
        if state.deviceType == .interface_ {
            resetInterfaceEchoStreamState(deviceId: state.activeDeviceId)
            state.interfaceEchoReading = nil
            state.echoReading = nil
        }
        state.echoMode = mode
    }

    // MARK: Data download

    public var deviceLabelOrDefault: String {
        if !state.activeDeviceLabel.isEmpty { return state.activeDeviceLabel }
        return state.deviceType == .interface_ ? "ENV130_A02" : "ENV230_A01"
    }

    public func activateAndDownload(_ deviceId: String, title: String = "") {
        guard let connected = state.connectedDevices.first(where: { $0.id == deviceId }),
              let gatt = gattClients[deviceId]
        else {
            state.trendError = "Device not connected."
            state.dataFilesStage = .error
            return
        }

        // Match the Android reference: the Download button first promotes the
        // selected connected device to active, creates the placeholder CSV item,
        // clears RX, arms the trend parser, waits briefly, then sends CMD 0x0007
        // / 0x0017 exactly once. The normal 1 Hz heartbeat is suppressed while
        // the Data Files subpage is open, so simply viewing this screen cannot
        // start a transfer.
        state.activeDeviceId = connected.id
        state.activeDeviceLabel = connected.label
        state.deviceType = connected.deviceType == 1 ? .interface_ : .density

        let useCase = ExportCsvUseCase()
        let stamp = useCase.formatDateStamp(Date())
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
        let label = trimmedTitle.isEmpty ? connected.label : trimmedTitle
        let filename = "\(label)_\(stamp).csv"
        let placeholder = DataFileItem(
            name: filename,
            recordCount: 0,
            rangeLabel: "--",
            sizeBytes: 0,
            targetDevice: label,
            chartRecords: [],
            allRecords: []
        )

        state.dataFilesStage = .downloading
        state.activeDataFile = placeholder
        state.downloadRecords = []
        state.trendExpectedRecords = 0
        state.dataDownloadProgress = 0
        state.trendError = nil
        state.isTrendStreaming = true

        let physicalId = DeviceRouting.physicalDeviceId(for: deviceId)
        rxBuffers[deviceId]?.removeAll(keepingCapacity: true)
        rxBuffers[physicalId]?.removeAll(keepingCapacity: true)

        // Build a parser that funnels into download state.
        let parser = TrendStreamParser(
            isInterface: connected.deviceType == 1,
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

        Task { @MainActor in
            // Android waits 1 second after clearing stale RX before unmuting and
            // sending the explicit download command.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.rxBuffers[deviceId]?.removeAll(keepingCapacity: true)
            self.rxBuffers[physicalId]?.removeAll(keepingCapacity: true)
            guard self.state.isTrendStreaming,
                  self.state.activeDeviceId == deviceId
            else { return }
            let cmd = DeviceRouting.downloadCommand(for: deviceId)
            let frame = FrameCodec.buildHeartbeat(pageIndex: Int(cmd))
            _ = await gatt.write(data: frame, withoutResponse: true)
        }
    }

    private func persistDownloadedFile(deviceId: String) {
        let useCase = ExportCsvUseCase()
        let label = state.activeDataFile?.targetDevice
            ?? state.connectedDevices.first { $0.id == deviceId }?.label
            ?? deviceLabelOrDefault
        let filename = state.activeDataFile?.name ?? "\(label)_\(useCase.formatDateStamp(Date())).csv"
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
        let gatt = gattClients[deviceId]
        let cmd = DeviceRouting.isCh2DeviceId(deviceId)
            ? Command.cmdDownloadCancelCh2
            : Command.cmdDownloadCancel

        Task { @MainActor in
            // Android retransmits cancel a few times because the firmware can
            // miss a frame while sending a burst chunk.
            if let gatt {
                let frame = FrameCodec.buildHeartbeat(pageIndex: Int(cmd))
                for _ in 0..<5 {
                    _ = await gatt.write(data: frame, withoutResponse: true)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            self.trendParser?.reset()
            self.trendParser = nil
            self.state.isTrendStreaming = false
            self.state.dataFilesStage = .list
            self.state.dataDownloadProgress = 0
            self.state.downloadRecords = []
        }
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
        case "report":
            // 리포트 결과 화면이면 기기 선택으로, 선택 화면이면 메뉴로
            if state.reportStage != .select { backToReportSelect() }
            else { state.subPage = nil }
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

    // MARK: Report (ENV130)

    /// 선택한 채널에 대해 리포트를 생성한다.
    /// 캐시가 아니라 BLE로 직접 STATUS(측정+설정) → ECHO 실시간 → ECHO 평균을 수집한다.
    public func selectReportDevice(_ id: String, title: String = "") {
        state.reportTargetId = id
        state.reportStage = .collecting
        state.reportData = nil
        state.reportError = nil

        Task { @MainActor in
            // 대상 채널을 활성화 (echo 파싱이 이 기기로 라우팅되도록)
            if let dev = state.connectedDevices.first(where: { $0.id == id }) {
                state.activeDeviceId = id
                state.activeDeviceLabel = dev.label
                state.deviceType = dev.deviceType == 1 ? .interface_ : .density
            }
            resetInterfaceEchoStreamState(clearAllBuffers: true)
            try? await Task.sleep(nanoseconds: 400_000_000)

            let physicalId = DeviceRouting.physicalDeviceId(for: id)
            guard let gatt = gattClients[id] ?? gattClients[physicalId] else {
                state.reportStage = .error
                state.reportError = "No connection"
                return
            }
            let isCh2 = id.hasSuffix("_CH2")
            let statusPage: UInt16 = isCh2 ? 0x10 : 0x00
            let realPage: UInt16 = isCh2 ? 0x11 : 0x01
            let avgPage: UInt16 = isCh2 ? 0x15 : 0x05

            // ① STATUS (측정값 + 설정값 동시)
            for _ in 0..<3 {
                let f = FrameCodec.buildHeartbeat(pageIndex: Int(statusPage), expectedLen: 0)
                _ = await gatt.write(data: f, withoutResponse: true)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            // ② ECHO 실시간 → ③ ECHO 평균
            let realEcho = await requestEchoWaveform(gatt, page: realPage)
            let avgEcho = await requestEchoWaveform(gatt, page: avgPage)

            let dev = state.connectedDevices.first(where: { $0.id == id })
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let data = ReportData(
                deviceId: id,
                label: dev?.label ?? id,
                firmwareVersion: dev?.firmwareVersion ?? "",
                timestamp: fmt.string(from: Date()),
                lightLevel: realEcho?.lightLevel ?? avgEcho?.lightLevel ?? 0.0,
                heavyLevel: realEcho?.heavyLevel ?? avgEcho?.heavyLevel ?? 0.0,
                temperatureC: state.temperatureC,
                currentMA: state.currentMA,
                freqMHz: state.freqMHz,
                offset: state.offset,
                emptyDistance: state.emptyDistance,
                deadZone: state.deadZone,
                set4mA: state.set4mA,
                set20mA: state.set20mA,
                damping: state.damping,
                thrLightSet:  realEcho?.thrLightSet  ?? avgEcho?.thrLightSet  ?? 0,
                thrLightMode: realEcho?.thrLightMode ?? avgEcho?.thrLightMode ?? 0,
                thrHeavySet:  realEcho?.thrHeavySet  ?? avgEcho?.thrHeavySet  ?? 0,
                thrHeavyMode: realEcho?.thrHeavyMode ?? avgEcho?.thrHeavyMode ?? 0,
                echoAmp:      realEcho?.echoAmp      ?? avgEcho?.echoAmp      ?? 0,
                relay:        state.relay,
                realEcho: realEcho,
                avgEcho: avgEcho,
                title: title.trimmingCharacters(in: .whitespaces)
            )
            state.reportData = data
            state.reportStage = .done
            saveReportSnapshot(data)
        }
    }

    /// echo page를 보내고 새 interfaceEchoReading 을 timeout 동안 기다린다.
    private func requestEchoWaveform(_ gatt: GattClient, page: UInt16, timeout: TimeInterval = 4.0) async -> InterfaceEchoReading? {
        let before = state.interfaceEchoReading
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let frame = FrameCodec.buildHeartbeat(pageIndex: Int(page), expectedLen: 0)
            _ = await gatt.write(data: frame, withoutResponse: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let cur = state.interfaceEchoReading, cur != before { return cur }
        }
        let cur = state.interfaceEchoReading
        return (cur != before) ? cur : nil
    }

    /// 현재 리포트를 PDF 로 렌더링해 공유용 URL 을 반환한다. UIPrintPageRenderer
    /// + UIGraphicsPDFRenderer 표준 파이프라인으로 페이지 분할/이미지 임베드를
    /// 자동 처리한다.
    @MainActor
    public func shareReportHtml() async -> URL? {
        guard let data = state.reportData else { return nil }
        let html = ReportHtmlExporter.buildHtml(data)

        // A4 portrait at 72 DPI: 595.2 x 841.8 points.
        let pageSize = CGSize(width: 595.2, height: 841.8)
        let pageRect = CGRect(origin: .zero, size: pageSize)

        // Render through an offscreen WKWebView. UIMarkupTextPrintFormatter does
        // NOT render base64 data: URL images, so the waveform PNGs were silently
        // dropped from the PDF (only text/tables came through). WKWebView's print
        // formatter renders the live page, images included.
        let webView = WKWebView(frame: pageRect)
        webView.loadHTMLString(html, baseURL: nil)
        try? await Task.sleep(nanoseconds: 100_000_000) // let navigation start
        var tries = 0
        while webView.isLoading && tries < 60 {          // wait up to ~3s for load
            try? await Task.sleep(nanoseconds: 50_000_000); tries += 1
        }
        try? await Task.sleep(nanoseconds: 350_000_000)  // let images decode/paint

        let formatter = webView.viewPrintFormatter()
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: pageRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: pageRect), forKey: "printableRect")

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        for i in 0..<max(renderer.numberOfPages, 1) {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        _ = webView // keep alive until PDF rendering completes

        // Documents/exports = Files 앱(WESSWARE 폴더)에서 보이는 영구 저장 위치
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdfName = (data.title?.isEmpty == false) ? data.title! : data.label
        let safe = pdfName.replacingOccurrences(of: "[\\\\/:*?\"<>| ]", with: "_", options: .regularExpression)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let url = dir.appendingPathComponent("Report_\(safe)_\(df.string(from: Date())).pdf")
        pdfData.write(to: url, atomically: true)
        return url
    }

    /// 리포트를 JPG 이미지 한 장으로 저장해 공유용 URL 반환.
    /// (PDF 페이지들을 PDFKit으로 렌더해 세로로 이어 붙임)
    @MainActor
    public func shareReportImage() async -> URL? {
        guard let pdfUrl = await shareReportHtml(), let doc = PDFDocument(url: pdfUrl), doc.pageCount > 0 else { return nil }
        let scale: CGFloat = 2
        var pages: [UIImage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            pages.append(page.thumbnail(of: size, for: .mediaBox))
        }
        guard let first = pages.first else { return nil }
        let totalSize = CGSize(width: first.size.width,
                               height: pages.reduce(0) { $0 + $1.size.height })
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        let combined = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: totalSize))
            var y: CGFloat = 0
            for img in pages {
                img.draw(at: CGPoint(x: 0, y: y))
                y += img.size.height
            }
        }
        guard let jpg = combined.jpegData(compressionQuality: 0.9) else { return nil }
        let url = pdfUrl.deletingPathExtension().appendingPathExtension("jpg")
        try? jpg.write(to: url, options: .atomic)
        return url
    }

    /// 리포트를 CSV로 저장해 공유용 URL 반환. 파형은 raw 데이터(Index,Real,Avg)로 포함.
    public func shareReportCsv() -> URL? {
        guard let data = state.reportData else { return nil }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (data.title?.isEmpty == false) ? data.title! : data.label
        let safe = name.replacingOccurrences(of: "[\\\\/:*?\"<>| ]", with: "_", options: .regularExpression)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let url = dir.appendingPathComponent("Report_\(safe)_\(df.string(from: Date())).csv")
        // BOM — 엑셀에서 한글 깨짐 방지
        let csv = "\u{FEFF}" + buildReportCsv(data)
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private func buildReportCsv(_ data: ReportData) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = ""
        out += "Title,\(q((data.title?.isEmpty == false) ? data.title! : data.label))\n"
        out += "Device,\(q(data.label))\n"
        out += "Model,ENV130\n"
        out += "Timestamp,\(q(data.timestamp))\n\n"
        out += "[Measurement]\n"
        out += "Light Level (m),\(String(format: "%.2f", data.lightLevel))\n"
        out += "Heavy Level (m),\(String(format: "%.2f", data.heavyLevel))\n"
        out += "Temperature (C),\(String(format: "%.1f", data.temperatureC))\n"
        out += "Current (mA),\(String(format: "%.2f", data.currentMA))\n\n"
        out += "[Parameter]\n"
        out += "Echo Amp,\(data.echoAmp)\n"
        out += "Frequency (kHz),\(String(format: "%.0f", data.freqMHz * 1000))\n"
        let thrL = data.thrLightMode == 1
            ? String(format: "%.1f V", Double(data.thrLightSet) / 10.0) : "\(data.thrLightSet) %"
        let thrH = data.thrHeavyMode == 1
            ? String(format: "%.1f V", Double(data.thrHeavySet) / 10.0) : "\(data.thrHeavySet) %"
        out += "Thr.Light,\(q(thrL))\n"
        out += "Thr.Heavy,\(q(thrH))\n"
        out += "Offset (m),\(String(format: "%.2f", data.offset))\n"
        out += "Empty (m),\(String(format: "%.2f", data.emptyDistance))\n"
        out += "Dead Zone (m),\(String(format: "%.2f", data.deadZone))\n"
        out += "Damping,\(data.damping)\n"
        out += "Set 4mA (m),\(String(format: "%.2f", data.set4mA))\n"
        out += "Set 20mA (m),\(String(format: "%.2f", data.set20mA))\n\n"
        out += "[Comment]\n"
        out += q(data.comment ?? "") + "\n\n"
        out += "[Waveform]\n"
        out += "Index,Real,Avg\n"
        let real = data.realEcho?.wave ?? []
        let avg = data.avgEcho?.wave ?? []
        for i in 0..<max(real.count, avg.count) {
            let r = i < real.count ? "\(real[i])" : ""
            let a = i < avg.count ? "\(avg[i])" : ""
            out += "\(i),\(r),\(a)\n"
        }
        return out
    }

    /// 리포트를 Word가 열 수 있는 MHTML(.doc)로 저장해 공유용 URL 반환.
    /// HTML + 파형 PNG 2장을 multipart/related 한 파일에 포장 — mirrors Kotlin ReportWordExporter.
    public func shareReportWord() -> URL? {
        guard let data = state.reportData else { return nil }
        // Documents/exports = Files 앱(WESSWARE 폴더)에서 보이는 영구 저장 위치
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (data.title?.isEmpty == false) ? data.title! : data.label
        let safe = name.replacingOccurrences(of: "[\\\\/:*?\"<>| ]", with: "_", options: .regularExpression)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let url = dir.appendingPathComponent("Report_\(safe)_\(df.string(from: Date())).doc")
        guard let bytes = buildReportMhtml(data).data(using: .utf8) else { return nil }
        try? bytes.write(to: url, options: .atomic)
        return url
    }

    private func buildReportMhtml(_ data: ReportData) -> String {
        let boundary = "----=_NextPart_WWS2_REPORT"
        let (realB64, avgB64) = ReportHtmlExporter.waveImagesBase64(data)
        let html = ReportHtmlExporter.buildHtml(data, realSrc: "wave_real.png", avgSrc: "wave_avg.png", forWord: true)
        let htmlB64 = Data(html.utf8).base64EncodedString(
            options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])

        func wrap76(_ s: String) -> String {
            var out = ""
            var idx = s.startIndex
            while idx < s.endIndex {
                let end = s.index(idx, offsetBy: 76, limitedBy: s.endIndex) ?? s.endIndex
                out += s[idx..<end]
                out += "\r\n"
                idx = end
            }
            return out
        }

        var m = ""
        m += "MIME-Version: 1.0\r\n"
        m += "Content-Type: multipart/related; boundary=\"\(boundary)\"; type=\"text/html\"\r\n\r\n"
        m += "--\(boundary)\r\n"
        m += "Content-Type: text/html; charset=\"utf-8\"\r\n"
        m += "Content-Transfer-Encoding: base64\r\n"
        m += "Content-Location: report.html\r\n\r\n"
        m += htmlB64 + "\r\n\r\n"
        m += "--\(boundary)\r\n"
        m += "Content-Type: image/png\r\n"
        m += "Content-Transfer-Encoding: base64\r\n"
        m += "Content-Location: wave_real.png\r\n\r\n"
        m += wrap76(realB64) + "\r\n"
        m += "--\(boundary)\r\n"
        m += "Content-Type: image/png\r\n"
        m += "Content-Transfer-Encoding: base64\r\n"
        m += "Content-Location: wave_avg.png\r\n\r\n"
        m += wrap76(avgB64) + "\r\n"
        m += "--\(boundary)--\r\n"
        return m
    }

    // ── Report snapshot (ReportResult 화면 다시 열기) — mirrors Kotlin ReportSnapshotStore ──

    public func savedReportsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("report_snapshots")
    }

    // 현재 표시 중인 리포트의 스냅샷 파일 (comment 수정 시 갱신 대상)
    private var currentReportSnapshotURL: URL? = nil

    private func saveReportSnapshot(_ data: ReportData) {
        let dir = savedReportsDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (data.title?.isEmpty == false) ? data.title! : data.label
        let safe = name.replacingOccurrences(of: "[\\\\/:*?\"<>| ]", with: "_", options: .regularExpression)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let url = dir.appendingPathComponent("Report_\(safe)_\(df.string(from: Date())).json")
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: url, options: .atomic)
            currentReportSnapshotURL = url
        }
    }

    /// 리포트 화면에서 의견 입력/수정 — state + 스냅샷 파일 동시 갱신.
    public func updateReportComment(_ comment: String) {
        guard var data = state.reportData else { return }
        data.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        state.reportData = data
        if let url = currentReportSnapshotURL, let json = try? JSONEncoder().encode(data) {
            try? json.write(to: url, options: .atomic)
        }
    }

    public func listSavedReports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: savedReportsDir(),
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da > db
            }
    }

    public func openReportSnapshot(_ url: URL) {
        guard let json = try? Data(contentsOf: url),
              let data = try? JSONDecoder().decode(ReportData.self, from: json) else {
            state.reportError = "Failed to open saved report"
            state.reportStage = .error
            return
        }
        currentReportSnapshotURL = url
        state.reportData = data
        state.reportStage = .done
    }

    public func deleteSavedReport(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
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
