// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/MainShellScreen.kt
//
// Top-level container: TopBar + active tab/sub-page + BottomNavBar.
// Sub-page priority over the tab itself (matches the Compose `when` ladder).
// Optional assistant UI is intentionally excluded from this iOS port scope.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct MainShellView: View {
    @StateObject private var vm = AppViewModel()

    @State private var showFileImporter = false
    @State private var activeFileImportKind: FileImportKind? = nil
    @State private var showCsvExporter = false
    @State private var csvExportFileName = "WESSWARE.csv"
    @State private var csvExportDocument = CsvDocument()
    @State private var sharePayload: SharePayload? = nil
    @State private var fileImportError: FileImportError? = nil

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(
                    isConnected: vm.isConnected,
                    statusLabel: vm.statusLabel,
                    title: vm.currentTitle,
                    showBack: vm.state.tabIndex == 4 && vm.state.subPage != nil,
                    rxBlink: vm.state.rxBlink,
                    isReconnecting: vm.isReconnecting,
                    onBackTap: { vm.handleTopBarBack() },
                    onBleTap: { vm.openPairing() }
                )

                bodyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.background)

                BottomNavBar(
                    currentIndex: vm.state.tabIndex,
                    onTap: { vm.setTab($0) }
                )
            }

            // Full-screen PIN overlay for pairing
            if vm.showPinForPairing {
                PinScreen(
                    showBack: true,
                    onPinEntered: { vm.onPairingPinResult($0) },
                    onBack: { vm.onPairingPinResult(-1) }
                )
                .transition(.opacity)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: activeFileImportKind == .csv ? [.commaSeparatedText, .plainText, .data] : [.data, .item],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .fileExporter(
            isPresented: $showCsvExporter,
            document: csvExportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: csvExportFileName,
            onCompletion: { _ in }
        )
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: [payload.url])
        }
        .alert(item: $vm.bleError) { err in
            Alert(
                title: Text("BLE Error"),
                message: Text(err.message),
                primaryButton: .default(Text("Retry"), action: { vm.retryBleError() }),
                secondaryButton: .cancel(Text("Dismiss"), action: { vm.dismissBleError() })
            )
        }
        .alert(item: $fileImportError) { err in
            Alert(
                title: Text("File Error"),
                message: Text(err.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if vm.state.tabIndex == 4, let sub = vm.state.subPage {
            switch sub {
            case "pairing":  PairingScreen(vm: vm)
            case "calib":    CalibScreen(vm: vm)
            case "upload":
                UploadScreen(vm: vm, onPickFile: { presentFileImporter(.firmware) })
            case "download":
                DataDownloadScreen(
                    vm: vm,
                    onPickCsv: { presentFileImporter(.csv) },
                    onShare: presentShareSheet,
                    onSave: presentCsvExporter
                )
            default:         MenuTabScreen(vm: vm)
            }
        } else {
            switch vm.state.tabIndex {
            case 0: MainTabScreen(vm: vm)
            case 1: EchoTabScreen(vm: vm)
            case 2: TrendTabScreen(vm: vm)
            case 3: DiagnosticsTabScreen(vm: vm)
            case 4: MenuTabScreen(vm: vm)
            default: MainTabScreen(vm: vm)
            }
        }
    }

    private func presentFileImporter(_ kind: FileImportKind) {
        activeFileImportKind = kind
        showFileImporter = true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let kind = activeFileImportKind
        activeFileImportKind = nil

        switch kind {
        case .firmware:
            handleFirmwareImport(result)
        case .csv:
            handleCsvImport(result)
        case .none:
            fileImportError = FileImportError(message: "File picker state was lost. Please tap Open again.")
        }
    }

    private func handleFirmwareImport(_ result: Result<[URL], Error>) {
        guard let url = selectedUrl(from: result) else { return }
        guard let data = readSecurityScopedData(from: url) else {
            fileImportError = FileImportError(message: "Unable to read firmware file: \(url.lastPathComponent)")
            return
        }
        vm.setPickedFile(name: url.lastPathComponent, size: data.count, bytes: Array(data))
    }

    private func handleCsvImport(_ result: Result<[URL], Error>) {
        guard let url = selectedUrl(from: result) else { return }
        let name = url.lastPathComponent
        guard name.lowercased().hasSuffix(".csv") else {
            fileImportError = FileImportError(message: "CSV files only: \(name)")
            return
        }
        guard isSupportedWessCsvName(name) else {
            fileImportError = FileImportError(message: "ENV130 or ENV230 CSV files only: \(name)")
            return
        }
        guard let data = readSecurityScopedData(from: url) else {
            fileImportError = FileImportError(message: "Unable to read CSV file: \(name)")
            return
        }
        guard let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            fileImportError = FileImportError(message: "Unsupported CSV text encoding: \(name)")
            return
        }
        vm.importCsvFile(name: name, size: data.count, content: content)
    }

    private func presentShareSheet() {
        guard let url = vm.shareDataFile() else {
            fileImportError = FileImportError(message: "No CSV data available to share.")
            return
        }
        sharePayload = SharePayload(url: url)
    }

    private func presentCsvExporter() {
        guard let (fileName, content) = vm.getCsvContentForSave() else {
            fileImportError = FileImportError(message: "No CSV data available to save.")
            return
        }
        csvExportFileName = fileName
        csvExportDocument = CsvDocument(text: content)
        showCsvExporter = true
    }

    private func selectedUrl(from result: Result<[URL], Error>) -> URL? {
        switch result {
        case .success(let urls):
            return urls.first
        case .failure(let error):
            fileImportError = FileImportError(message: error.localizedDescription)
            return nil
        }
    }

    private func readSecurityScopedData(from url: URL) -> Data? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try? Data(contentsOf: url)
    }

    private func isSupportedWessCsvName(_ name: String) -> Bool {
        let upper = name.uppercased()
        if upper.contains("ENV130") || upper.contains("ENV230") { return true }
        return name.range(of: #"ENV\d+_A\d{2}"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// Make BleErrorState identifiable for SwiftUI .alert(item:)
extension BleErrorState: Identifiable {
    public var id: String { retryAddress + message }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct FileImportError: Identifiable {
    let id = UUID()
    let message: String
}

private enum FileImportKind {
    case firmware
    case csv
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct CsvDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let content = String(data: data, encoding: .utf8) {
            text = content
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
