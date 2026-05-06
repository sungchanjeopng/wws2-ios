// SwiftUI port of `viewmodel/MainViewModel.kt`.
//
// The Android original is a 1989-line `AndroidViewModel` that fuses BLE I/O,
// frame parsing, and view state. We split it cleanly:
//
//   - `MainUiState` (this file): the @Published state surface that screens read
//   - `AppViewModel` (this file): the published-state holder + navigation + the
//     entry points screens call (e.g. setTab, openPairing, …).
//
// BLE wiring (BleScanner / GattClient / OtaUploader from WWS2BLE) and frame
// parsing (FrameParser / TrendStreamParser / InterfaceEchoParser from
// WWS2Core) plug into the view model in subsequent commits — the current
// version stubs those entry points so the shell builds and runs.

import Foundation
import Combine
import SwiftUI
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

    /// Aliases used by the menu screen — keep call sites identical to the Kotlin
    /// original until we converge on a single navigation API.
    public func openDataFilesList() { openDownload() }
    public func openFirmwareFlow()  { openUpload() }

    /// Tap a device in the strip-bar header. Brings that device to the front
    /// and updates the active label. BLE-side reconnect logic plugs in later.
    public func requestConnectDevice(_ deviceId: String) {
        state.activeDeviceId = deviceId
        if let dev = state.connectedDevices.first(where: { $0.id == deviceId }) {
            state.activeDeviceLabel = dev.label
        }
    }

    public func handleTopBarBack() {
        if state.subPage != nil { state.subPage = nil }
    }

    // MARK: BLE error handling

    public func dismissBleError() { bleError = nil }
    public func retryBleError() {
        guard bleError != nil else { return }
        bleError = nil
        showPinForPairing = true
    }

    // MARK: Pairing PIN

    /// PIN entry result (-1 = cancel).
    public func onPairingPinResult(_ pin: Int) {
        showPinForPairing = false
        // TODO: hook into BLE pairing flow once GattClient.connect path is wired.
    }

    // MARK: Upload / CSV stubs (filled in later commits)

    public func setPickedFile(name: String, size: Int, bytes: [UInt8]) {
        state.pickedFileName = name
        state.pickedFileSize = size
        // TODO: stash bytes for upload
    }

    public func importCsvFile(name: String, size: Int) {
        // TODO: wire into ExportCsvUseCase + DataDownload screen
    }

    public func getCsvContentForSave() -> (String, String)? {
        // TODO: build CSV from current trend records
        return nil
    }

    public func shareDataFile() -> URL? {
        // TODO: prepare a temp file URL for share-sheet integration
        return nil
    }
}
