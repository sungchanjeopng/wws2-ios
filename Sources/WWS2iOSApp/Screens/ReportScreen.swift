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

    public init(vm: AppViewModel, onShare: @escaping () -> Void) {
        self.vm = vm
        self.onShare = onShare
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
                    ReportResult(data: data, onShare: onShare, onNew: { vm.backToReportSelect() })
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
                            Button(action: { vm.selectReportDevice(device.id) }) {
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
            }
            .padding(20)
        }
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
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeaderCard(data: data)
                    Spacer().frame(height: 18)

                    SectionLabel(title: "Measurement", accent: lightBlue)
                    Spacer().frame(height: 10)
                    HStack(spacing: 12) {
                        HeroStat(label: "Light Level", value: String(format: "%.2f", data.lightLevel), unit: "m", color: lightBlue)
                        HeroStat(label: "Heavy Level", value: String(format: "%.2f", data.heavyLevel), unit: "m", color: heavyOrange)
                    }
                    Spacer().frame(height: 12)
                    HStack(spacing: 12) {
                        MiniStat(label: "Temperature", value: String(format: "%.1f °C", data.temperatureC))
                        MiniStat(label: "Current", value: String(format: "%.2f mA", data.currentMA))
                    }
                    Spacer().frame(height: 22)

                    let thrLightStr = data.thrLightMode == 1
                        ? String(format: "%.1f V", Double(data.thrLightSet) / 10.0)
                        : "\(data.thrLightSet) %"
                    let thrHeavyStr = data.thrHeavyMode == 1
                        ? String(format: "%.1f V", Double(data.thrHeavySet) / 10.0)
                        : "\(data.thrHeavySet) %"
                    SettingsCard4(pairs: [
                        (("Echo Amp", "\(data.echoAmp)"),
                         ("Frequency", String(format: "%.0f kHz", data.freqMHz * 1000))),
                        (("Offset", String(format: "%.2f m", data.offset)),
                         ("Empty Distance", String(format: "%.2f m", data.emptyDistance))),
                        (("Dead Zone", String(format: "%.2f m", data.deadZone)),
                         ("Damping", "\(data.damping)")),
                        (("Current 4mA", String(format: "%.2f m", data.set4mA)),
                         ("Current 20mA", String(format: "%.2f m", data.set20mA))),
                        (("Temperature", String(format: "%.1f °C", data.temperatureC)),
                         ("Current", String(format: "%.2f mA", data.currentMA))),
                        (("Relay", String(format: "0x%02X", data.relay)), nil),
                    ])
                    Spacer().frame(height: 22)

                    SectionLabel(title: "Echo", accent: lightBlue)
                    Spacer().frame(height: 10)
                    SettingsCard(rows: [
                        ("Thr.Light", thrLightStr),
                        ("Thr.Heavy", thrHeavyStr),
                    ])
                    Spacer().frame(height: 14)
                    WaveBlock(tag: "Real", accent: lightBlue, reading: data.realEcho)
                    Spacer().frame(height: 14)
                    WaveBlock(tag: "Average", accent: heavyOrange, reading: data.avgEcho)
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
                Button(action: onShare) {
                    Text("Export PDF").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(reportPurple).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(AppColors.white)
            .shadow(color: AppColors.cardShadow, radius: 6, y: -2)
        }
    }
}

private struct HeaderCard: View {
    let data: ReportData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0x4ADE80)).frame(width: 10, height: 10)
                Text(data.label).font(.system(size: 24, weight: .heavy)).kerning(-0.5).foregroundStyle(.white)
            }
            Spacer().frame(height: 10)
            Text("Sludge Level Meter  ·  FW \(data.firmwareVersion.isEmpty ? "—" : data.firmwareVersion)")
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

private struct HeroStat: View {
    let label: String
    let value: String
    let unit: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            HStack(alignment: .bottom, spacing: 3) {
                Text(value).font(.system(size: 30, weight: .heavy)).kerning(-1).foregroundStyle(AppColors.darkText)
                Text(unit).font(.system(size: 15, weight: .bold)).foregroundStyle(AppColors.grayLabel).padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.white).clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: AppColors.cardShadow, radius: 3, y: 1)
    }
}

private struct MiniStat: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(AppColors.subText)
            Spacer()
            Text(value).font(.system(size: 16, weight: .heavy)).foregroundStyle(AppColors.darkText)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(AppColors.white).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
    }
}

private struct TossGroupLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppColors.grayLabel)
            .tracking(0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 6)
    }
}

private struct SettingsCard4: View {
    typealias Pair = (String, String)
    let pairs: [(Pair, Pair?)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 16) {
                    Text(row.0.0).font(.system(size: 13)).foregroundStyle(AppColors.subText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.0.1).font(.system(size: 14, weight: .bold)).foregroundStyle(AppColors.darkText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if let second = row.1 {
                        Text(second.0).font(.system(size: 13)).foregroundStyle(AppColors.subText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(second.1).font(.system(size: 14, weight: .bold)).foregroundStyle(AppColors.darkText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Spacer()
                        Spacer()
                    }
                }
                .padding(.vertical, 13)
                if idx < pairs.count - 1 {
                    Rectangle().fill(AppColors.background).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(AppColors.white).clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: AppColors.cardShadow, radius: 3, y: 1)
    }
}

private struct SettingsCard: View {
    let rows: [(String, String)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.0).font(.system(size: 14)).foregroundStyle(AppColors.subText)
                    Spacer()
                    Text(row.1).font(.system(size: 15, weight: .bold)).foregroundStyle(AppColors.darkText)
                }
                .padding(.vertical, 13)
                if idx < rows.count - 1 {
                    Rectangle().fill(AppColors.background).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(AppColors.white).clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: AppColors.cardShadow, radius: 3, y: 1)
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
