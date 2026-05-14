// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/DataDownloadScreen.kt
//
// Five-stage flow driven by state.dataFilesStage:
//   .list         → ListStage         (target devices + saved file list)
//   .downloading  → DownloadingStage  (progress + cancel)
//   .complete     → CompleteStage     (success + view/share)
//   .view         → ViewStage         (chart + stats + share)
//   .error        → ErrorStage        (error + back)

import SwiftUI
import WWS2Core

private let downloadOrange = Color(hex: 0xFFA500)
private let downloadGray   = Color(hex: 0x666666)
private let downloadRed    = Color(hex: 0xE53935)

public struct DataDownloadScreen: View {
    @ObservedObject var vm: AppViewModel
    public var onPickCsv: () -> Void = {}
    public var onShare:   () -> Void = {}
    public var onSave:    () -> Void = {}

    public var body: some View {
        switch vm.state.dataFilesStage {
        case .list:        ListStage(vm: vm, onPickCsv: onPickCsv)
        case .downloading: DownloadingStage(vm: vm)
        case .complete:    CompleteStage(vm: vm, onShare: onShare, onSave: onSave)
        case .view:        ViewStage(vm: vm, onShare: onShare, onSave: onSave)
        case .error:       ErrorStage(vm: vm)
        }
    }
}

// MARK: - LIST

private struct ListStage: View {
    @ObservedObject var vm: AppViewModel
    let onPickCsv: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Download")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.3)
                    .foregroundStyle(AppColors.grayLabel)
                Spacer().frame(height: 10)

                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Target Device")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.grayLabel)
                        if vm.state.connectedDevices.isEmpty {
                            HStack(spacing: 8) {
                                Circle().fill(AppColors.weakText).frame(width: 9, height: 9)
                                Text("No device connected")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.grayLabel)
                            }
                            Button(action: {}) {
                                Text("Download")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(AppColors.border)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(true)
                            .buttonStyle(.plain)
                        } else {
                            ForEach(Array(vm.state.connectedDevices.enumerated()), id: \.element.id) { idx, dev in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Circle().fill(AppColors.success).frame(width: 9, height: 9)
                                        Text(dev.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(AppColors.darkText)
                                    }
                                    Button(action: { vm.activateAndDownload(dev.id) }) {
                                        Text("Download")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                            .background(AppColors.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                                if idx < vm.state.connectedDevices.count - 1 {
                                    Spacer().frame(height: 16)
                                }
                            }
                        }
                    }
                }

                Spacer().frame(height: 18)
                Text("Open")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.3)
                    .foregroundStyle(AppColors.grayLabel)
                Spacer().frame(height: 10)
                FileSelectArea(onTap: onPickCsv)

                Spacer().frame(height: 20)
                Text("SAVED FILES")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.3)
                    .foregroundStyle(AppColors.grayLabel)
                Spacer().frame(height: 10)

                if vm.state.savedDataFiles.isEmpty {
                    CardContainer {
                        Text("No saved files yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.grayLabel)
                    }
                } else {
                    ForEach(vm.state.savedDataFiles, id: \.name) { file in
                        FileCard(file: file, onTap: { vm.viewDataFile(file) })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - DOWNLOADING

private struct DownloadingStage: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        let progress = max(0.0, min(1.0, vm.state.dataDownloadProgress))
        let receivedRecords = vm.state.downloadRecords.count
        let file = vm.state.activeDataFile

        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)
                ZStack {
                    Circle().fill(AppColors.primary.opacity(0.08)).frame(width: 72, height: 72)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.primary)
                }
                Spacer().frame(height: 20)
                Text("Downloading...")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Text("Receiving log data from the device.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                Spacer().frame(height: 24)
                TargetDeviceCard(targetDevice: file?.targetDevice ?? vm.deviceLabelOrDefault)
                Spacer().frame(height: 14)
                ProgressCard(fileName: file?.name ?? "--",
                             subtitle: vm.state.trendExpectedRecords > 0
                                ? "\(receivedRecords) / \(vm.state.trendExpectedRecords) records received"
                                : "\(receivedRecords) records received",
                             progress: progress)
                Spacer().frame(height: 18)
                Button(action: { vm.cancelDataDownload() }) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(downloadRed)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - COMPLETE

private struct CompleteStage: View {
    @ObservedObject var vm: AppViewModel
    let onShare: () -> Void
    let onSave: () -> Void
    var body: some View {
        let file = vm.state.activeDataFile
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)
                ZStack {
                    Circle().fill(AppColors.success.opacity(0.08)).frame(width: 72, height: 72)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.success)
                }
                Spacer().frame(height: 20)
                Text("Download Complete")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Text("The CSV file is ready to view or share.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                Text("Auto-saved: Documents/WESSWARE/\(file?.name ?? "")")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.weakText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                Spacer().frame(height: 24)
                TargetDeviceCard(targetDevice: file?.targetDevice ?? vm.deviceLabelOrDefault)
                Spacer().frame(height: 14)
                ProgressCard(
                    fileName: file?.name ?? "--",
                    subtitle: "\(file?.recordCount ?? 0) records / \(formatBytes(file?.sizeBytes ?? 0))",
                    progress: 1.0
                )

                Spacer().frame(height: 18)
                Button(action: { if let f = file { vm.viewDataFile(f) } }) {
                    Text("View Data")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 10)
                ShareButton(onShare: onShare)
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - VIEW

private struct ViewStage: View {
    @ObservedObject var vm: AppViewModel
    let onShare: () -> Void
    let onSave: () -> Void
    var body: some View {
        let file = vm.state.activeDataFile
        let isInterface = (file?.targetDevice.uppercased().contains("ENV130") ?? false)
        if isInterface {
            InterfaceViewStage(file: file, tempUnit: vm.state.tempUnit, onShare: onShare)
        } else {
            DensityViewStage(file: file, densUnit: vm.state.densUnit, tempUnit: vm.state.tempUnit, onShare: onShare)
        }
    }
}

private struct DensityViewStage: View {
    let file: DataFileItem?
    let densUnit: Int
    let tempUnit: Int
    let onShare: () -> Void
    var body: some View {
        let records = file?.chartRecords ?? []
        let dUnit = DensityUnit.fromInt(densUnit)
        var minDst = 0.0, avgDst = 0.0, maxDst = 0.0
        if !records.isEmpty {
            minDst = records.map(\.dst).min() ?? 0
            maxDst = records.map(\.dst).max() ?? 0
            avgDst = records.map(\.dst).reduce(0, +) / Double(records.count)
        }
        return ScrollView {
            VStack(spacing: 6) {
                FileInfoCard(file: file)
                TrendChart(records: records, densUnit: densUnit, tempUnit: tempUnit)
                    .frame(maxWidth: .infinity, minHeight: 420)
                StatRow(items: [
                    StatItem(label: "Min",
                             value: records.isEmpty ? "--" : dUnit.format(raw: minDst),
                             color: AppColors.darkText),
                    StatItem(label: "Avg",
                             value: records.isEmpty ? "--" : dUnit.format(raw: avgDst),
                             color: AppColors.primary),
                    StatItem(label: "Max",
                             value: records.isEmpty ? "--" : dUnit.format(raw: maxDst),
                             color: AppColors.darkText)
                ])
                ShareButton(onShare: onShare)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
        }
    }
}

private struct InterfaceViewStage: View {
    let file: DataFileItem?
    let tempUnit: Int
    let onShare: () -> Void
    var body: some View {
        let records = file?.chartRecords ?? []
        let lightValues = records.map { $0.dst * 0.01 }
        let heavyValues = records.map { Double($0.eeaD) * 0.01 }
        return ScrollView {
            VStack(spacing: 6) {
                FileInfoCard(file: file)
                InterfaceTrendChart(records: records, tempUnit: tempUnit)
                    .frame(maxWidth: .infinity, minHeight: 420)
                downloadInterfaceStatCard(lightValues: lightValues, heavyValues: heavyValues)
                ShareButton(onShare: onShare)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
        }
    }
}

// Local interface stat card (3-col Light + 3-col Heavy with divider).
private func downloadInterfaceStatCard(lightValues: [Double], heavyValues: [Double]) -> some View {
    let light: (String, String, String) = lightValues.isEmpty
        ? ("--", "--", "--")
        : (String(format: "%.2f", lightValues.min()!),
           String(format: "%.2f", lightValues.max()!),
           String(format: "%.2f", lightValues.reduce(0,+) / Double(lightValues.count)))
    let heavy: (String, String, String) = heavyValues.isEmpty
        ? ("--", "--", "--")
        : (String(format: "%.2f", heavyValues.min()!),
           String(format: "%.2f", heavyValues.max()!),
           String(format: "%.2f", heavyValues.reduce(0,+) / Double(heavyValues.count)))

    return VStack(spacing: 0) {
        HStack(spacing: 0) {
            DownloadStatCell(label: "Light Level (Min)", value: light.0, color: downloadGray)
            DownloadStatCell(label: "Light Level (Max)", value: light.1, color: downloadGray)
            DownloadStatCell(label: "Light Level (Avg)", value: light.2, color: downloadGray)
        }
        Rectangle().fill(AppColors.background).frame(height: 1).padding(.horizontal, 12)
        HStack(spacing: 0) {
            DownloadStatCell(label: "Heavy Level (Min)", value: heavy.0, color: downloadOrange)
            DownloadStatCell(label: "Heavy Level (Max)", value: heavy.1, color: downloadOrange)
            DownloadStatCell(label: "Heavy Level (Avg)", value: heavy.2, color: downloadOrange)
        }
    }
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(AppColors.white)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
}

private struct DownloadStatCell: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppColors.grayLabel)
                .multilineTextAlignment(.center)
            Text(value).font(.system(size: 16, weight: .bold)).kerning(-0.4).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - ERROR

private struct ErrorStage: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)
                ZStack {
                    Circle().fill(downloadRed.opacity(0.08)).frame(width: 72, height: 72)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(downloadRed)
                }
                Spacer().frame(height: 20)
                Text("Download Failed")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Text(vm.state.trendError ?? "Unknown error")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer().frame(height: 28)
                Button(action: { vm.openDataFilesList() }) {
                    Text("Back")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Shared building blocks

private struct FileCard: View {
    let file: DataFileItem
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(AppColors.background).frame(width: 40, height: 40)
                    Image(systemName: "doc.text").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.darkText)
                        .lineLimit(1)
                    Text("\(file.recordCount) records / \(file.rangeLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.grayLabel)
                    Text(formatBytes(file.sizeBytes))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.weakText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(AppColors.grayLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }
}

private struct ProgressCard: View {
    let fileName: String
    let subtitle: String
    let progress: Double
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text(fileName).font(.system(size: 13, weight: .bold)).foregroundStyle(AppColors.darkText)
                Spacer().frame(height: 6)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(AppColors.grayLabel)
                Spacer().frame(height: 14)
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(AppColors.primary)
                    .frame(height: 10)
                    .clipShape(Capsule())
                Spacer().frame(height: 8)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct TargetDeviceCard: View {
    let targetDevice: String
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Target Device")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                Text(targetDevice)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.darkText)
            }
        }
    }
}

private struct FileInfoCard: View {
    let file: DataFileItem?
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(file?.name ?? "--")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                HStack(spacing: 12) {
                    Text("\(file?.recordCount ?? 0) records")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.grayLabel)
                    Text(file?.rangeLabel ?? "--")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.grayLabel)
                    Text(formatBytes(file?.sizeBytes ?? 0))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.grayLabel)
                }
            }
        }
    }
}

private struct ShareButton: View {
    let onShare: () -> Void
    var body: some View {
        Button(action: onShare) {
            Text("Share")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.success)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
