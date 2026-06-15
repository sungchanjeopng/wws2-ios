// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/ReportScreen.kt
//
// ENV130 리포트: 기기 선택 → BLE 수집 → 토스 스타일 리포트 + HTML 공유.

import SwiftUI
import WWS2Core

private let reportPurple = Color(hex: 0x7C3AED)
private let lightBlue = Color(hex: 0x3182F6)
private let heavyOrange = Color(hex: 0xFF8C00)

public struct ReportScreen: View {
    @ObservedObject var vm: AppViewModel
    let onShare: () -> Void
    let onShareWord: () -> Void
    let onShareImage: () -> Void
    let onShareCsv: () -> Void

    @State private var savedReports: [URL] = []
    @State private var titlePromptFor: String? = nil
    @State private var titleText = ""

    public init(vm: AppViewModel, onShare: @escaping () -> Void,
                onShareWord: @escaping () -> Void, onShareImage: @escaping () -> Void,
                onShareCsv: @escaping () -> Void) {
        self.vm = vm
        self.onShare = onShare
        self.onShareWord = onShareWord
        self.onShareImage = onShareImage
        self.onShareCsv = onShareCsv
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            switch vm.state.reportStage {
            case .select:     deviceSelect
            case .collecting: collecting
            case .error:      errorView
            case .done:
                if let data = vm.state.reportData {
                    ReportResult(data: data, onShare: onShare, onShareWord: onShareWord,
                                 onShareImage: onShareImage, onShareCsv: onShareCsv,
                                 onNew: { vm.backToReportSelect() },
                                 onSaveComment: { vm.updateReportComment($0) })
                } else {
                    errorViewWith("No report data")
                }
            }
        }
    }

    // ── 기기 선택 ──
    private var deviceSelect: some View {
        let devices = vm.state.connectedDevices.filter { $0.label.hasPrefix("ENV130") }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Report")
                    .font(.system(size: 26, weight: .heavy)).kerning(-0.5)
                    .foregroundStyle(AppColors.darkText)
                Text("Pick a device to capture its current state.")
                    .font(.system(size: 14)).foregroundStyle(AppColors.grayLabel)
                    .padding(.bottom, 8)

                if devices.isEmpty {
                    VStack(spacing: 10) {
                        Text("📋").font(.system(size: 40))
                        Text("No connected ENV130 devices")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.grayLabel)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 50)
                } else {
                    ForEach(devices, id: \.id) { device in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xEDE9FE)).frame(width: 42, height: 42)
                                Text("📊").font(.system(size: 20))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.label).font(.system(size: 17, weight: .bold)).foregroundStyle(AppColors.darkText)
                                Text("Sludge Level Meter").font(.system(size: 12)).foregroundStyle(AppColors.weakText)
                            }
                            Spacer()
                            Button(action: { titleText = ""; titlePromptFor = device.id }) {
                                Text("Create").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(reportPurple).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .background(AppColors.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: AppColors.cardShadow, radius: 3, y: 1)
                    }
                }

                if !savedReports.isEmpty {
                    Text("Saved Reports")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(AppColors.darkText)
                        .padding(.top, 16)
                    ForEach(savedReports, id: \.self) { url in
                        savedReportRow(url)
                    }
                }
            }
            .padding(20)
        }
        .onAppear { savedReports = vm.listSavedReports() }
        .alert("Report Title", isPresented: Binding(
            get: { titlePromptFor != nil },
            set: { if !$0 { titlePromptFor = nil } }
        )) {
            TextField("Title (optional)", text: $titleText)
            Button("Cancel", role: .cancel) { titlePromptFor = nil }
            Button("Create") {
                if let id = titlePromptFor {
                    titlePromptFor = nil
                    vm.selectReportDevice(id, title: titleText)
                }
            }
        } message: {
            Text("Leave empty to use the device name")
        }
    }

    private func savedReportRow(_ url: URL) -> some View {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let meta = df.string(from: date)
        return HStack(spacing: 10) {
            Text("📄").font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.darkText)
                    .lineLimit(1).truncationMode(.middle)
                Text(meta).font(.system(size: 11)).foregroundStyle(AppColors.weakText)
            }
            Spacer()
            Button {
                vm.deleteSavedReport(url)
                savedReports = vm.listSavedReports()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.weakText)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { vm.openReportSnapshot(url) }
    }

    private var collecting: some View {
        VStack(spacing: 8) {
            ProgressView().tint(reportPurple).scaleEffect(1.3)
            Spacer().frame(height: 12)
            Text("Collecting data…").font(.system(size: 16, weight: .bold)).foregroundStyle(AppColors.darkText)
            Text("Measurement · Settings · Waveforms").font(.system(size: 13)).foregroundStyle(AppColors.grayLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View { errorViewWith(vm.state.reportError ?? "Report failed") }

    private func errorViewWith(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("⚠️").font(.system(size: 36))
            Text(message).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.error)
            Button(action: { vm.backToReportSelect() }) {
                Text("Back").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(reportPurple).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
}

// ── 리포트 결과 ──
private struct ReportResult: View {
    let data: ReportData
    let onShare: () -> Void
    let onShareWord: () -> Void
    let onShareImage: () -> Void
    let onShareCsv: () -> Void
    let onNew: () -> Void
    let onSaveComment: (String) -> Void
    @State private var showExportChoice = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeaderCard(data: data)
                    Spacer().frame(height: 18)

                    let measurementRows: [(String, String, Color?)] = [
                        ("Light Level", String(format: "%.2f m", data.lightLevel), lightBlue),
                        ("Heavy Level", String(format: "%.2f m", data.heavyLevel), heavyOrange),
                        ("Temperature", String(format: "%.1f °C", data.temperatureC), nil),
                        ("Current", String(format: "%.2f mA", data.currentMA), nil),
                    ]
                    SectionLabel(title: "Measurement", accent: lightBlue)
                    Spacer().frame(height: 10)
                    GridTable2(rows: measurementRows)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in copyAsImage(GridTable2(rows: measurementRows)) })
                    Spacer().frame(height: 22)

                    let thrLightStr = data.thrLightMode == 1
                        ? String(format: "%.1f V", Double(data.thrLightSet) / 10.0)
                        : "\(data.thrLightSet) %"
                    let thrHeavyStr = data.thrHeavyMode == 1
                        ? String(format: "%.1f V", Double(data.thrHeavySet) / 10.0)
                        : "\(data.thrHeavySet) %"
                    let parameterRows: [(String, String, String, String)] = [
                        ("Echo Amp", "\(data.echoAmp)",
                         "Frequency", String(format: "%.0f kHz", data.freqMHz * 1000)),
                        ("Thr.Light", thrLightStr,
                         "Thr.Heavy", thrHeavyStr),
                        ("Offset", String(format: "%.2f m", data.offset),
                         "Empty", String(format: "%.2f m", data.emptyDistance)),
                        ("Dead Zone", String(format: "%.2f m", data.deadZone),
                         "Damping", "\(data.damping)"),
                        ("Set 4mA", String(format: "%.2f m", data.set4mA),
                         "Set 20mA", String(format: "%.2f m", data.set20mA)),
                    ]
                    SectionLabel(title: "Parameter", accent: lightBlue)
                    Spacer().frame(height: 10)
                    GridTable4(rows: parameterRows)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in copyAsImage(GridTable4(rows: parameterRows)) })
                    Spacer().frame(height: 22)

                    SectionLabel(title: "Echo", accent: lightBlue)
                    Spacer().frame(height: 14)
                    WaveBlock(tag: "Real", accent: lightBlue, reading: data.realEcho)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in copyWaveImage(data.realEcho) })
                    Spacer().frame(height: 14)
                    WaveBlock(tag: "Average", accent: heavyOrange, reading: data.avgEcho)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in copyWaveImage(data.avgEcho) })
                    Spacer().frame(height: 22)

                    SectionLabel(title: "Comment", accent: lightBlue)
                    Spacer().frame(height: 10)
                    CommentBox(comment: data.comment ?? "", onSave: onSaveComment)
                }
                .padding(16)
            }

            // 하단 액션 바
            HStack(spacing: 12) {
                Button(action: onNew) {
                    Text("New").font(.system(size: 16, weight: .bold)).foregroundStyle(AppColors.subText)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(AppColors.background).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                Button(action: { showExportChoice = true }) {
                    Text("Export").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(reportPurple).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(AppColors.white)
            .shadow(color: AppColors.cardShadow, radius: 6, y: -2)
        }
        .confirmationDialog("Export Report", isPresented: $showExportChoice, titleVisibility: .visible) {
            Button("PDF") { onShare() }
            Button("Word (.doc)") { onShareWord() }
            Button("Image (.jpg)") { onShareImage() }
            Button("CSV (.csv)") { onShareCsv() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // 꾹 누르면 해당 블록을 이미지로 클립보드에 복사 (카톡 등에 붙여넣기)
    private func copyAsImage<V: View>(_ view: V) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 700, height: nil)
        if let img = renderer.uiImage {
            UIPasteboard.general.image = img
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func copyWaveImage(_ reading: InterfaceEchoReading?) {
        UIPasteboard.general.image = ReportHtmlExporter.renderWaveformImage(reading)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct HeaderCard: View {
    let data: ReportData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0x4ADE80)).frame(width: 10, height: 10)
                Text((data.title?.isEmpty == false) ? data.title! : data.label)
                    .font(.system(size: 24, weight: .heavy)).kerning(-0.5).foregroundStyle(.white)
            }
            Spacer().frame(height: 10)
            Text("ENV130")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
            Text(data.timestamp).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x7C3AED), Color(hex: 0x3B82F6)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: AppColors.cardShadow, radius: 6, y: 2)
    }
}

private struct SectionLabel: View {
    let title: String
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4, height: 16)
            Text(title).font(.system(size: 17, weight: .heavy)).kerning(-0.3).foregroundStyle(AppColors.darkText)
        }
    }
}

private struct CommentBox: View {
    let comment: String
    let onSave: (String) -> Void
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        Button {
            text = comment
            editing = true
        } label: {
            HStack {
                Text(comment.isEmpty ? "Tap to write a comment" : comment)
                    .font(.system(size: 14, weight: comment.isEmpty ? .regular : .semibold))
                    .foregroundStyle(comment.isEmpty ? AppColors.weakText : AppColors.darkText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(AppColors.white)
            .border(tableBorderCol, width: 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            VStack(spacing: 16) {
                Text("Comment").font(.system(size: 20, weight: .bold)).padding(.top, 20)
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .frame(minHeight: 160)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.weakText, lineWidth: 1))
                HStack(spacing: 12) {
                    Button {
                        editing = false
                    } label: {
                        Text("Cancel").font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(AppColors.lightGray)
                            .foregroundStyle(AppColors.darkText)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    Button {
                        editing = false
                        onSave(text)
                    } label: {
                        Text("Save").font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(AppColors.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .presentationDetents([.medium])
        }
    }
}

// PDF 표와 동일한 격자 스타일 (ReportHtmlExporter CSS 미러)
private let tableBorderCol = Color(hex: 0xC9CFD6)
private let tableLineCol = Color(hex: 0xD8DDE3)
private let thBgCol = Color(hex: 0xFAFBFC)
private let thTextCol = Color(hex: 0x4E5968)

private struct TableTh: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(thTextCol)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(thBgCol)
            .border(tableLineCol, width: 0.5)
    }
}

private struct TableTd: View {
    let text: String
    var color: Color = AppColors.darkText
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(AppColors.white)
            .border(tableLineCol, width: 0.5)
    }
}

private struct GridTable2: View {
    let rows: [(String, String, Color?)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    TableTh(text: row.0)
                    TableTd(text: row.1, color: row.2 ?? AppColors.darkText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .border(tableBorderCol, width: 1.5)
    }
}

private struct GridTable4: View {
    let rows: [(String, String, String, String)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    TableTh(text: row.0)
                    TableTd(text: row.1)
                    TableTh(text: row.2)
                    TableTd(text: row.3)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .border(tableBorderCol, width: 1.5)
    }
}

private struct WaveBlock: View {
    let tag: String
    let accent: Color
    let reading: InterfaceEchoReading?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tag).font(.system(size: 12, weight: .heavy)).foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(accent.opacity(0.12)).clipShape(Capsule())
            // InterfaceEchoChart 자체가 흰 카드라 그대로 사용
            InterfaceEchoChart(echo: reading).frame(height: 420)
        }
    }
}
